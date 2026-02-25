# Development Guide

This document explains how to set up the development environment, build, test,
and contribute to pir-tester.

## Prerequisites

### Required Tools

- **Swift 6.2+** / **Xcode 26+** — the project uses `swift-tools-version: 6.2`
  with strict concurrency enabled
- **[SwiftLint](https://github.com/realm/SwiftLint)** — Swift linting
- **[Periphery](https://github.com/peripheryapp/periphery)** — unused code
  detection
- **[markdownlint-cli](https://github.com/igorshubovych/markdownlint-cli)**
  (via `npx`) — Markdown linting
- **Node.js / npm** — required for `npx markdownlint`

### Platform Requirements

- **macOS 15+** — constrained by the `swift-homomorphic-encryption` dependency
- **Linux** — supported via conditional compilation

### Installing Tools on macOS

```sh
# Xcode (install from the App Store or Apple Developer portal)
xcode-select --install

# SwiftLint and Periphery via Homebrew
brew install swiftlint periphery

# markdownlint-cli via npm (or use npx directly)
npm install -g markdownlint-cli
```

### Verifying Tool Installation

Run `make tools` to verify all required tools are installed and available:

```sh
make tools
```

This checks that `swift`, `swiftlint`, `periphery`, and `npx markdownlint` are
on your `PATH`.

## Getting Started

### Clone and Initialize

```sh
git clone https://github.com/ameshkov/pir-tester.git
cd pir-tester
make init
```

`make init` sets the Git hooks path to `./scripts/hooks` so the pre-commit hook
runs automatically.

### Resolve Dependencies

Swift Package Manager resolves dependencies automatically on first build. To
resolve explicitly:

```sh
swift package resolve
```

The project depends on:

- `swift-homomorphic-encryption` (release/1.1)
- `swift-crypto` (3.10+)
- `swift-asn1` (1.0+)
- `hummingbird` (2.0+)
- `swift-argument-parser` (1.5+)
- `swift-nio-oblivious-http` (0.3+)

### Build

```sh
make build
```

This runs `swift build` in debug mode. For a release build:

```sh
make release
```

### Run Tests

```sh
make test
```

To run a specific test:

```sh
swift test --filter <test_name>
```

## Development Workflow

### Pre-commit Hook

After running `make init`, a pre-commit hook is active in
`scripts/hooks/pre-commit`. When you commit:

- If `.md` files are staged → runs `make md-lint`
- If `.swift` files are staged → runs `make swift-lint` and `make test`

The hook also warns about unstaged changes and temporary `TODO`/`FIXME` markers.

### Branching and Pull Requests

1. Create a feature branch from `main`.
2. Make your changes and ensure `make lint` and `make test` pass.
3. Update `CHANGELOG.md` with your changes under the `[Unreleased]` section.
4. Open a pull request. CI runs lint → test → build automatically.

### CI Pipeline

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs on every push and
pull request:

1. **lint** — installs tools and runs `make lint`
2. **test** — runs `make test`
3. **build** — runs `make build` (depends on lint and test passing)

Tagged pushes (`v*`) additionally create a GitHub release.

## Available Make Targets

| Target                  | Command                                                         | Description                        |
| ----------------------- | --------------------------------------------------------------- | ---------------------------------- |
| `make init`             | Sets git hooks path                                             | Initialize repo after cloning      |
| `make tools`            | Verifies tool availability                                      | Check required tools are installed |
| `make build`            | `swift build`                                                   | Debug build                        |
| `make release`          | `swift build -c release`                                        | Release build                      |
| `make test`             | `swift test --quiet`                                            | Run all tests                      |
| `make lint`             | Runs `md-lint` + `swift-lint`                                   | Run all linters                    |
| `make md-lint`          | `npx markdownlint .`                                            | Lint Markdown files                |
| `make swift-lint`       | Runs swiftlint + swift-format + periphery                       | Run all Swift linters              |
| `make swiftlint-lint`   | `swiftlint lint --strict --quiet`                               | Run SwiftLint only                 |
| `make swiftformat-lint` | `swift format lint --recursive --strict .`                      | Run swift-format only              |
| `make periphery-lint`   | `periphery scan --retain-public --quiet --strict --clean-build` | Run Periphery only                 |

All linters run in **strict** mode — warnings are treated as errors.

## Common Tasks

### Adding a New Source File

Place it in the appropriate target directory under `Sources/`:

- `Sources/PirTester/` — CLI executable logic
- `Sources/PIRServiceTesting/` — core PIR client logic
- `Sources/PrivacyPass/` — Privacy Pass token protocol
- `Sources/Util/` — shared utilities

Swift Package Manager automatically discovers new `.swift` files in target
directories.

### Adding a New Test

Add test files to `Tests/PirTesterTests/`. Use the Swift Testing framework:

```swift
import Testing

@Suite("Description of test suite")
struct MyTests {
    @Test("Description of behavior")
    func testSomething() throws {
        #expect(1 + 1 == 2)
    }
}
```

Stub external dependencies via protocol conformance (e.g.,
`StubTestClient: TestClientProtocol`) rather than mocking frameworks.

### Adding a New Dependency

1. Add the package to the `dependencies` array in `Package.swift`.
2. Add the product to the relevant target's `dependencies`.
3. Run `swift package resolve` to update `Package.resolved`.
4. Document the new dependency in `AGENTS.md` under Technical Context.

### Opening the Project in Xcode

```sh
open Package.swift
```

Xcode will resolve dependencies and index the project automatically.

## Configuration Files

| File                 | Purpose                                                           |
| -------------------- | ----------------------------------------------------------------- |
| `Package.swift`      | Swift package manifest (targets, dependencies)                    |
| `.swift-format`      | swift-format configuration (4-space indent, 100-char line length) |
| `.swiftlint.yml`     | SwiftLint rules and configuration                                 |
| `.markdownlint.json` | markdownlint configuration                                        |
| `.gitignore`         | Git ignore rules                                                  |

## Troubleshooting

### `make init` fails

Ensure you are in the repository root and Git is initialized. The command
sets `core.hooksPath` to `./scripts/hooks`.

### Dependencies fail to resolve

The `swift-homomorphic-encryption` package uses a branch dependency
(`release/1.1`). If resolution fails:

```sh
swift package reset
swift package resolve
```

### Build fails on Linux

Ensure you have Swift 6.2+ installed. The project uses conditional compilation
(`#if canImport(Darwin)`) for platform-specific code. The macOS 15+ platform
constraint only applies on Darwin.

### Periphery reports false positives

Periphery runs with `--retain-public`, so public symbols are not flagged.
If a symbol is only used in tests, consider making it `package` or `internal`
scope, or verify the test target depends on the module.

### SwiftLint or swift-format conflicts

The project uses 4-space indentation and a 100-character line length. Ensure
your editor is configured to match. See `.swift-format` and `.swiftlint.yml`
for the full configuration.

## Additional Resources

- [README.md](README.md) — user manual and CLI usage
- [AGENTS.md](AGENTS.md) — LLM agent guidance, architecture, and code
  guidelines
- [CHANGELOG.md](CHANGELOG.md) — project changelog
- [Swift Package Manager docs](https://www.swift.org/documentation/package-manager/)
- [Swift Testing framework](https://developer.apple.com/documentation/testing/)
- [swift-homomorphic-encryption](https://github.com/apple/swift-homomorphic-encryption)
