# pir-tester

This is a command-line tool which purpose is to test a PIR service for Apple's
[URL filtering API][urlfilteringdoc].

[urlfilteringdoc]: https://developer.apple.com/documentation/networkextension/filtering-traffic-by-url

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

## Multiple lookups

When launched with the following arguments, `PirTester` will send multiple PIR
queries one by one.

```sh
PirTester query \
    --pir-server-url <pir-server-url> \
    --privacy-pass-url <privacy-pass-url> \
    --pir-usecase <pir-usecase> \
    --user-token <user-token> \
    --input <input-file>
```

Where `<input-file>` is a file containing one keyword per line.

The tool will run the PIR query for each keyword and print the result to the
standard output.
