import Foundation
import Testing
@testable import TokenWatch

@Suite("IncrementalJSONLFileState")
struct IncrementalJSONLFileStateTests {
    private let identity = JSONLFileIdentity(deviceID: 7, fileID: 11)

    @Test func transitionMatrixIsDeterministic() {
        let old = JSONLFileMetadata(
            identity: identity,
            size: 100,
            modificationDate: Date(timeIntervalSince1970: 10)
        )
        let state = IncrementalJSONLFileState<Int, String>(
            metadata: old,
            committedOffset: 80,
            stableCandidates: [1],
            provisionalTail: Data([0x7B]),
            provisionalCandidates: [],
            continuityAnchor: JSONLContinuityAnchor(
                offset: 76,
                bytes: Data("tail".utf8)
            ),
            checkpointAtCommittedOffset: "checkpoint"
        )

        #expect(IncrementalJSONLTransition.decide(previous: state, newMetadata: old) == .reuse)
        #expect(IncrementalJSONLTransition.decide(
            previous: state,
            newMetadata: JSONLFileMetadata(identity: identity, size: 120, modificationDate: .init(timeIntervalSince1970: 11))
        ) == .append(fromOffset: 80))
        #expect(IncrementalJSONLTransition.decide(
            previous: state,
            newMetadata: JSONLFileMetadata(identity: identity, size: 90, modificationDate: .init(timeIntervalSince1970: 12))
        ) == .rebuild)
        #expect(IncrementalJSONLTransition.decide(
            previous: state,
            newMetadata: JSONLFileMetadata(identity: identity, size: 100, modificationDate: .init(timeIntervalSince1970: 12))
        ) == .rebuild)
        #expect(IncrementalJSONLTransition.decide(
            previous: state,
            newMetadata: JSONLFileMetadata(identity: .init(deviceID: 7, fileID: 12), size: 120, modificationDate: .init(timeIntervalSince1970: 11))
        ) == .rebuild)
        #expect(IncrementalJSONLTransition.decide(
            previous: state,
            newMetadata: JSONLFileMetadata(identity: nil, size: 120, modificationDate: .init(timeIntervalSince1970: 11))
        ) == .rebuild)
    }

    @Test func continuityAnchorKeepsOnlyTheCommittedSuffix() {
        let first = Data(repeating: 0x41, count: 800)
        let second = Data(repeating: 0x42, count: 800)
        let firstAnchor = JSONLContinuityAnchor.make(
            previous: .empty,
            newlyCommittedBytes: first,
            committedOffset: 800
        )
        let secondAnchor = JSONLContinuityAnchor.make(
            previous: firstAnchor,
            newlyCommittedBytes: second,
            committedOffset: 1_600
        )

        #expect(secondAnchor.bytes == Data(
            (first + second).suffix(JSONLContinuityAnchor.maximumByteCount)
        ))
        #expect(secondAnchor.offset == 576)
    }

    @Test func continuityAnchorHandlesCommittedOffsetBoundaries() {
        let cases: [(committedOffset: UInt64, sourceByteCount: Int)] = [
            (1_023, 1_023),
            (1_024, 1_200),
            (0, 1),
        ]

        for boundary in cases {
            let source = Data(repeating: 0x41, count: boundary.sourceByteCount)
            let expectedByteCount = min(
                JSONLContinuityAnchor.maximumByteCount,
                source.count,
                Int(boundary.committedOffset)
            )
            let anchor = JSONLContinuityAnchor.make(
                previous: .empty,
                newlyCommittedBytes: source,
                committedOffset: boundary.committedOffset
            )

            #expect(anchor.bytes == Data(source.suffix(expectedByteCount)))
            #expect(anchor.offset == boundary.committedOffset - UInt64(expectedByteCount))
        }
    }

    @Test func continuityAnchorDoesNotUnderflowWhenNewBytesExceedCommittedOffset() {
        let source = Data("abcd".utf8)
        let anchor = JSONLContinuityAnchor.make(
            previous: .empty,
            newlyCommittedBytes: source,
            committedOffset: 2
        )

        #expect(anchor.bytes == Data("cd".utf8))
        #expect(anchor.offset == 0)
    }

    @Test func continuityAnchorMatchesAndRejectsOpenedStreamBytes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContinuityAnchor-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("0123456789abcdef".utf8).write(to: url)
        let snapshot = try SystemJSONLFileReader().openSnapshot(for: url)
        defer { snapshot.stream.close() }

        let matching = JSONLContinuityAnchor(
            offset: 4,
            bytes: Data("4567".utf8)
        )
        let mismatching = JSONLContinuityAnchor(
            offset: 4,
            bytes: Data("4568".utf8)
        )

        #expect(try matching.matches(in: snapshot.stream))
        #expect(try mismatching.matches(in: snapshot.stream) == false)
    }

    @Test("完整增量状态可编码并恢复")
    func stateRoundTripsThroughCodable() throws {
        let metadata = JSONLFileMetadata(
            identity: identity,
            size: 640,
            modificationDate: Date(timeIntervalSince1970: 42)
        )
        let state = IncrementalJSONLFileState<String, String>(
            metadata: metadata,
            committedOffset: 600,
            stableCandidates: ["stable"],
            provisionalTail: Data("partial".utf8),
            provisionalCandidates: ["provisional"],
            continuityAnchor: JSONLContinuityAnchor(
                offset: 344,
                bytes: Data(repeating: 0x41, count: 256)
            ),
            checkpointAtCommittedOffset: "checkpoint"
        )

        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(
            IncrementalJSONLFileState<String, String>.self,
            from: data
        )

        #expect(restored.metadata == state.metadata)
        #expect(restored.committedOffset == state.committedOffset)
        #expect(restored.stableCandidates == state.stableCandidates)
        #expect(restored.provisionalTail == state.provisionalTail)
        #expect(restored.provisionalCandidates == state.provisionalCandidates)
        #expect(restored.continuityAnchor == state.continuityAnchor)
        #expect(restored.checkpointAtCommittedOffset == state.checkpointAtCommittedOffset)
    }

    @Test("返回候选覆盖稳定、临时与组合状态")
    func returnedCandidatesCoverAllBufferShapes() {
        func state(
            stable: [Int],
            provisional: [Int]
        ) -> IncrementalJSONLFileState<Int, String> {
            IncrementalJSONLFileState(
                metadata: JSONLFileMetadata(
                    identity: identity,
                    size: 0,
                    modificationDate: .distantPast
                ),
                committedOffset: 0,
                stableCandidates: stable,
                provisionalTail: Data(),
                provisionalCandidates: provisional,
                continuityAnchor: .empty,
                checkpointAtCommittedOffset: "checkpoint"
            )
        }

        #expect(state(stable: [1, 2], provisional: []).returnedCandidates == [1, 2])
        #expect(state(stable: [], provisional: [3]).returnedCandidates == [3])
        #expect(state(stable: [1, 2], provisional: [3]).returnedCandidates == [1, 2, 3])
    }
}
