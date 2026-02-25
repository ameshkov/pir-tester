# AGENTS.md

## Project Overview

A command-line tool for testing a Private Information Retrieval (PIR) service
used by Apple's URL filtering API. It performs end-to-end PIR lookups including
Privacy Pass token acquisition, configuration fetching, evaluation key
generation/upload, and PIR query execution.

## Technical Context

- **Language**: Swift 6.2 (swift-tools-version 6.2, strict concurrency enabled)
- **Primary Dependencies**:
    - `swift-homomorphic-encryption` (release/1.1) — PIR protocol and protobuf
    - `swift-crypto` (3.10+) / `swift-asn1` (1.0+) — cryptographic primitives
    - `hummingbird` (2.0+) — HTTP testing client protocol
    - `swift-argument-parser` (1.5+) — CLI argument parsing
    - `swift-nio-oblivious-http` (0.3+) — OHTTP encapsulation
- **Storage**: None (stateless CLI tool)
- **Testing**: Swift Testing framework (`@Test`, `@Suite`, `#expect`)
- **Target Platform**: macOS 15+ (constrained by swift-homomorphic-encryption);
  Linux is also supported via conditional compilation
- **Project Type**: Single-package Swift CLI tool with supporting libraries

## Project Structure

```text
Sources/
├── PirTester/             # CLI executable (entry point: main.swift)
├── PIRServiceTesting/     # Core PIR client logic (config, key rotation,
│                          #   privacy pass integration, protobuf helpers,
│                          #   OHTTP transport)
├── PrivacyPass/           # Privacy Pass token protocol implementation
│                          #   (issuer, verifier, token request/response)
└── Util/                  # Shared utilities (Platform, OsType, OsVersion)
Tests/
└── PirTesterTests/        # Unit tests for PIRClient
scripts/
└── hooks/                 # Git hooks (pre-commit runs linters and tests)
.github/
└── workflows/             # CI pipeline (lint → test → build → release)
```

## Build and Test Commands

- `make init` — initialize the repo (set git hooks path, verify tools).
- `make build` — build debug (`swift build`).
- `make release` — build release (`swift build -c release`).
- `make test` — run all tests (`swift test --quiet`).
- `make lint` — run **all** linters (markdown + Swift).
- `make md-lint` — run markdownlint (`npx markdownlint .`).
- `make swift-lint` — run all Swift linters (swiftlint, swift-format,
  periphery).
- `make swiftlint-lint` — run SwiftLint (`swiftlint lint --strict --quiet`).
- `make swiftformat-lint` — run swift-format
  (`swift format lint --recursive --strict .`).
- `make periphery-lint` — run Periphery for unused code detection.
- `swift test --filter <test_name>` — run a specific test.

### Required Tools

- Swift 6.2+ / Xcode 26+
- [SwiftLint](https://github.com/realm/SwiftLint)
- [Periphery](https://github.com/peripheryapp/periphery)
- [markdownlint-cli](https://github.com/igorshubovych/markdownlint-cli)
  (via `npx`)

## Contribution Instructions

You MUST follow the following rules for EVERY task that you perform:

- You MUST verify it with linter, formatter, and compiler.

  Use the following commands:
    - `make build` to run the build
    - `make lint` to run the linter
    - `make test` to run the tests

- You MUST update the unit tests for changed code.

- When making changes to the project structure, ensure the Project structure
  section in `AGENTS.md` is updated and remains valid.

- When the task is finished update `CHANGELOG.md` file and explain changes in
  the `Unreleased` section. Add entries to the appropriate subsection (`Added`,
  `Changed`, or `Fixed`) if it already exists; do not create duplicate
  subsections.

- If the prompt essentially asks you to refactor or improve existing code, check
  if you can phrase it as a code guideline. If it's possible, add it to
  the relevant Code Guidelines section in `AGENTS.md`.

- After completing the task you MUST verify that the code you've written
  follows the Code Guidelines in this file.

## Code Guidelines

### General Code Style and Formatting

1. Use standard Swift formatting and style guidelines.
2. Use 4 spaces for indentation.
3. When writing class and function comments, prefer `///` style comments. In
   this case, you should use proper markdown formatting.
4. When writing inline comments, prefer `//` style comments.
5. In the case of comments, try to keep line length under 80 characters. In
   the case of code, it should be under 100.
6. Avoid comments on the same line as the code; place them on a previous line.

### Architecture

- The CLI executable (`PirTester`) is thin — it parses arguments, creates an
  `HTTPClient` conforming to `TestClientProtocol`, and delegates to
  `PIRClient`.
- `PIRClient` is generic over `IndexPirClient` and manages configuration
  caching, secret key storage, privacy pass tokens, and query execution.
- `PrivacyPass` is a standalone module implementing the Privacy Pass token
  protocol (RSA Blind Signatures).
- `Util` provides platform/OS abstractions shared across modules.

### Testing

- Use the Swift Testing framework (`import Testing`, `@Test`, `@Suite`,
  `#expect`).
- Stub external dependencies via protocol conformance (e.g.,
  `StubTestClient: TestClientProtocol`) rather than mocking frameworks.
- Test names should be descriptive: `@Test("Description of behavior")`.
