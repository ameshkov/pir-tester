# pir-tester

A command-line tool for testing a [Private Information Retrieval][pir-wiki] (PIR)
service used by Apple's [URL filtering API][urlfilteringdoc]. It performs
end-to-end PIR lookups — acquiring Privacy Pass tokens, fetching configuration,
generating and uploading evaluation keys, and executing PIR queries — against a
running PIR service instance.

[pir-wiki]: https://en.wikipedia.org/wiki/Private_information_retrieval
[urlfilteringdoc]: https://developer.apple.com/documentation/networkextension/filtering-traffic-by-url

## Concepts

`PirTester` interacts with two services and ties them together into a single
lookup flow:

- **PIR server** — hosts the encrypted database and answers PIR queries. Each
  database is identified by a **use case** name.
- **Privacy Pass service** — issues anonymous authentication tokens
  ([Privacy Pass][privacypass-rfc]) that the PIR server requires with every
  request. Tokens are obtained using a **user token** as the credential.
- **Evaluation key** — a homomorphic encryption key derived from the PIR
  configuration. The client generates it locally and uploads it to the PIR
  server before the first query. The key is reused across subsequent queries
  in the same session.
- **Oblivious HTTP (OHTTP)** — an optional privacy relay
  ([RFC 9458][ohttp-rfc]) that prevents the target servers from learning the
  client's identity. When enabled, every request is encrypted and routed
  through an OHTTP gateway.

[privacypass-rfc]: https://www.rfc-editor.org/rfc/rfc9577.html
[ohttp-rfc]: https://www.rfc-editor.org/rfc/rfc9458.html

## Capabilities

- **Single keyword lookup** — query the PIR service for one keyword and print
  the result.
- **Batch lookup** — read keywords from a file (one per line) and query them
  sequentially, reusing the same client session.
- **OHTTP relay** — optionally encrypt and route all traffic (PIR and
  Privacy Pass) through an Oblivious HTTP gateway.
- **Automatic key management** — fetches configuration, generates evaluation
  keys, and acquires Privacy Pass tokens transparently on the first query.

## Using PirTester

### Single keyword query

```sh
PirTester query \
    --pir-server-url <pir-server-url> \
    --privacy-pass-url <privacy-pass-url> \
    --pir-usecase <pir-usecase> \
    --user-token <user-token> \
    <keyword>
```

The tool performs the full lookup flow and prints the result:

1. Fetches the Privacy Pass token directory and public key.
2. Obtains Privacy Pass tokens for the given user token.
3. Fetches the PIR configuration for the specified use case.
4. Generates an evaluation key and uploads it to the PIR server.
5. Executes the PIR query for the keyword.
6. Prints the decrypted result to standard output.

### Batch query from file

```sh
PirTester query \
    --pir-server-url <pir-server-url> \
    --privacy-pass-url <privacy-pass-url> \
    --pir-usecase <pir-usecase> \
    --user-token <user-token> \
    --input <input-file>
```

`<input-file>` is a text file with one keyword per line. The tool queries each
keyword sequentially and prints all results to standard output. Provide either
a positional `<keyword>` or `--input <file>`, not both.

### Routing through OHTTP

```sh
PirTester query \
    --pir-server-url <pir-server-url> \
    --privacy-pass-url <privacy-pass-url> \
    --pir-usecase <pir-usecase> \
    --user-token <user-token> \
    --ohttp-config-url <ohttp-config-url> \
    --ohttp-gateway-url <ohttp-gateway-url> \
    <keyword>
```

Both `--ohttp-config-url` and `--ohttp-gateway-url` must be provided together.
When set, the tool fetches the gateway's OHTTP key configuration, then encrypts
every subsequent HTTP request using Binary HTTP and HPKE before sending it
through the gateway. All traffic — PIR queries and Privacy Pass token
requests — is routed through the relay.

## Inputs and outputs

### Required arguments

| Argument | Description |
| --- | --- |
| `--pir-server-url` | Base URL of the PIR server |
| `--privacy-pass-url` | Base URL of the Privacy Pass service |
| `--pir-usecase` | Use case identifier for the PIR database |
| `--user-token` | Credential for obtaining Privacy Pass tokens |
| `<keyword>` | Keyword to look up (positional, mutually exclusive with `--input`) |

### Optional arguments

| Argument | Description |
| --- | --- |
| `--input <file>` | Path to a file containing keywords, one per line |
| `--ohttp-config-url` | URL of the OHTTP key configuration resource |
| `--ohttp-gateway-url` | URL of the OHTTP gateway resource |

### Output

Results are printed to standard output. For each keyword, the tool prints:

```text
Result for '<keyword>': <value>
```

If a keyword has no corresponding entry in the PIR database, the result is
`No value found`. Progress messages and diagnostics are printed inline during
execution.

## Behavior and guarantees

- **Stateless** — the tool does not persist any data between runs. Every
  invocation starts fresh: fetching tokens, configuration, and keys.
- **Session reuse** — within a single run, the PIR client instance is created
  once and reused for all keywords. Configuration, evaluation keys, and
  Privacy Pass tokens are cached in memory for the duration of the session.
- **Sequential queries** — when processing multiple keywords, queries are
  executed one at a time in order.
- **Automatic key rotation** — if the PIR configuration changes between
  queries (e.g. after a server-side rotation), the client fetches the new
  configuration and generates a new evaluation key automatically.
- **OHTTP scope** — when OHTTP is enabled, *all* HTTP requests are routed
  through the gateway, including both PIR and Privacy Pass traffic.

## Documentation

- [Development](DEVELOPMENT.md)
- [Changelog](CHANGELOG.md)
- [LLM agent rules](AGENTS.md)
- [Feature specifications](specs/)
