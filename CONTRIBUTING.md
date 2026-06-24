# Contributing

Thanks for helping improve TokenWatch.

## Before You Start

- Keep changes focused on one issue or behavior at a time.
- Avoid committing private usage records, prompts, responses, local project paths, or credentials.
- Prefer existing AppKit and Swift patterns in the project over adding dependencies.

## Development

Build the app:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -configuration Debug build
```

Run unit tests:

```bash
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch -destination 'platform=macOS' -only-testing:TokenWatchTests test
```

## Pull Requests

Please include:

- A short summary of the change
- The test command you ran
- Any privacy or local-data considerations

For parser, pricing, aggregation, or UI behavior changes, add or update focused tests.
