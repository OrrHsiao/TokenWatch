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
        let first = Data(repeating: 0x41, count: 200)
        let second = Data(repeating: 0x42, count: 200)
        let firstAnchor = JSONLContinuityAnchor.make(
            previous: .empty,
            newlyCommittedBytes: first,
            committedOffset: 200
        )
        let secondAnchor = JSONLContinuityAnchor.make(
            previous: firstAnchor,
            newlyCommittedBytes: second,
            committedOffset: 400
        )

        #expect(secondAnchor.bytes == Data((first + second).suffix(256)))
        #expect(secondAnchor.offset == 144)
    }

    @Test func continuityAnchorHandlesCommittedOffsetBoundaries() {
        let cases: [(committedOffset: UInt64, sourceByteCount: Int)] = [
            (255, 255),
            (256, 300),
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
}
