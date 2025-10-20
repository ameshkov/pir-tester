# AGENTS.md

## General Code Style & Formatting

1. Use standard Swift formatting and style guidelines.
2. Use 4 spaces for indentation.
3. When writing class and function comments, prefer `///` style comments. In
   this case, you should use proper markdown formatting.
4. When writing inline comments, prefer `//` style comments.
5. In the case of comments, try to keep line length under 80 characters. In the
   case of code, it should be under 100.
6. Avoid comments on the same line as the code; place them on a previous line.

## Testing instructions

- Run `make lint` to run all linters.
- Run `make test` to run all tests.
- Run `make build` to build the Swift package.

You can also use `swift test --filter <test_name>` to run a specific test.
