# pir-tester

This is a command-line tool which purpose is to test a PIR service for Apple's
[URL filtering API][urlfilteringdoc].

[urlfilteringdoc]: https://developer.apple.com/documentation/networkextension/filtering-traffic-by-url

## Implementation details

The tool uses `PIRClient` that is provided by the `PIRServiceTesting` library
from Apple's [pir-service-example][pir-service-example]. This library implements
all the necessary operations:

- `PIRClient.fetchTokens` for fetching the privacy pass tokens. It will
  internally call `fetchTokenDirectory` and `fetchPublicKeyForUserToken` so you
  don't need to do it yourself.
- `PIRClient.fetchKeyStatus` for fetching the key status from the PIR service
  for the specified usecase. It will save the configuration to `configCache`.
- `PIRClient.rotateKey` for generating and uploading the evaluation key.
- `PIRClient.request` for running the PIR query.

[pir-service-example]: https://github.com/apple/pir-service-example

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
