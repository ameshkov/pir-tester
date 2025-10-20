# Keep the Makefile POSIX-compliant.  We currently allow hyphens in
# target names, but that may change in the future.
#
# See https://pubs.opengroup.org/onlinepubs/9699919799/utilities/make.html.
.POSIX:

# Init the repo

init: tools
	git config core.hooksPath ./scripts/hooks

# Makes sure that the necessary tools are installed
tools:
	swift --version
	swiftlint --version
	periphery version
	npx markdownlint --version

# Building debug builds

build:
	swift build

swift-build:
	swift build

# Building release builds

release:
	swift build -c release

# Linter commands

lint: md-lint swift-lint

md-lint:
	npx markdownlint .

swift-lint: swiftlint-lint swiftformat-lint periphery-lint

swiftlint-lint:
	swiftlint lint --strict --quiet

swiftformat-lint:
	swift format lint --recursive --strict .

periphery-lint:
	periphery scan --retain-public --quiet --strict --clean-build

# Testing

test:
	swift test --quiet
