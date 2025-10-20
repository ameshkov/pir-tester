# pir-tester

This is a command-line tool which purpose is to test a PIR service for Apple's
[URL filtering API][urlfilteringdoc].

The implementation is based on PIRClient from Apple's
[PIRServiceTesting][pirservicetesting].

[urlfilteringdoc]: https://developer.apple.com/documentation/networkextension/filtering-traffic-by-url
[pirservicetesting]: https://github.com/apple/pir-service-example/tree/main/Sources/PIRServiceTesting

## Full lookup

When launched with the following arguments, `PirTester` will do the following:

1. Fetch tokens directory.
2. Fetch public key for the user token.
3. Fetch privacy pass tokens for that public key and user token.
4. Fetch configuration from the PIR service for the specified usecase.
5. Generate and upload the evaluation key.
6. Run the PIR query for the specified keyword.

```sh
PirTester query \
    --pir-server-url <pir-server-url> \
    --privacy-pass-url <privacy-pass-url> \
    --pir-usecase <pir-usecase> \
    --user-token <user-token> \
    <keyword>
```

## Fetch privacy pass tokens

When launched with the following arguments, `PirTester` will do the following:

1. Fetch tokens directory.
2. Fetch public key for the user token.
3. Fetch `<tokens-count>` privacy pass tokens for that public key and user token.
4. Save the tokens to a JSON file specified by the `--output` argument.

```sh
PirTester fetch-tokens \
    --privacy-pass-url <privacy-pass-url> \
    --user-token <user-token> \
    --tokens-count <tokens-count> \
    --output <output-file>
```

## Upload evaluation key

When launched with the following arguments, `PirTester` will do the following:

1. Fetch configuration from the PIR service for the specified usecase.
2. Generate and upload the evaluation key.
3. Save the configuration and the evaluation key to a JSON file specified by the
   `--output` argument.

```sh
PirTester upload-evaluation-key \
    --pir-server-url <pir-server-url> \
    --privacy-pass-url <privacy-pass-url> \
    --pir-usecase <pir-usecase> \
    --user-token <user-token> \
    --output <output-file>
```

## Lookup with pre-generated tokens and configuration

When launched with the following arguments, `PirTester` will do the following:

1. Load the configuration and the evaluation key from a JSON file specified by
   the `--input-config` argument.
2. Use the token specified by the `--token` argument.
3. Run the PIR query for the specified keyword.

```sh
PirTester query-with-pregenerated \
    --pir-server-url <pir-server-url> \
    --input-config <input-config-file> \
    --token <token> \
    <keyword>
```
