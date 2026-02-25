# pir-tester changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][keepachangelog], and this project
adheres to [Semantic Versioning][semver].

[keepachangelog]: https://keepachangelog.com/en/1.0.0/

[semver]: https://semver.org/spec/v2.0.0.html

## [Unreleased]

### Added

- `DEVELOPMENT.md` — comprehensive development guide covering prerequisites,
  setup, build/test commands, contribution workflow, and troubleshooting.
- Oblivious HTTP (OHTTP) relay support via `--ohttp-config-url` and
  `--ohttp-gateway-url` CLI arguments. When enabled, all HTTP requests (PIR
  and Privacy Pass) are encrypted using Binary HTTP + HPKE and sent through
  an OHTTP gateway, preventing the target servers from identifying the client.
    - New dependency: `swift-nio-oblivious-http` (0.3.x).
    - Generic `OHTTPClient` extracted from `OHTTPClientTransport` for
      standalone OHTTP requests independent of `TestClientProtocol`.
    - BHTTP request serialisation now uses known-length encoding (framing
      indicator 0) instead of indeterminate-length encoding (framing indicator
      2). The ohttp-go reference gateway only accepts known-length requests.

### Changed

- `README.md` rewritten as a user manual: added concepts, capabilities,
  inputs/outputs, behavioral guarantees, and documentation map; removed
  installation and build content.

[unreleased]: https://github.com/ameshkov/pir-tester/compare/v1.0.0...HEAD

## [v1.0.0] - 2025-10-20

### Added

- Initial release

[v1.0.0]: https://github.com/ameshkov/pir-tester/releases/tag/v1.0.0
