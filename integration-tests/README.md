# Integration Tests

Here lives the integration tests for chainlink, utilizing our [chainlink-testing-framework](https://github.com/smartcontractkit/chainlink-testing-framework).

## NOTE: Move to Testcontainers

If you have previously run these smoke tests using GitHub Actions or some sort of Kubernetes setup, that method is no longer necessary. We have moved the majority of our tests to utilize plain Docker containers (with the help of [Testcontainers](https://golang.testcontainers.org/)). This should make tests faster, more stable, and enable you to run them on your local machine without much hassle.

## Requirements

1. [Go](https://go.dev/)
2. [Docker](https://www.docker.com/)
3. You'll probably want to [increase the resources available to Docker](https://stackoverflow.com/questions/44533319/how-to-assign-more-memory-to-docker-container) as most tests require quite a few containers (e.g. OCR requires 6 Chainlink nodes, 6 databases, a simulated blockchain, and a mock server).

## Configure

We have finished first pass at moving the configuration from env vars to TOML files. Currently all product-related configuration is already in TOML files, but env vars still are used to control things like log level, Slack notifications and Kubernetes-related settings. See the [example.env](./example.env) file for environment variables.

We have added what we think are sensible defaults for all products, you can find them in `./testconfig/<product>/<product>.toml` files. Each product folder contains also an `example.toml` file with all possible TOML keys and some description. Detailed description of TOML configuration can be found in [README.md](./testconfig/README.md), but if you want to run some tests using default value all you need to do is provide Chainlink image and version:
```toml
# ./testconfig/overrides.toml

[ChainlinkImage]
image = "your image name"
version = "your tag"
```

You could also think about that config this way:
```toml
# ./testconfig/overrides.toml
[ChainlinkImage]
image = "${CHAINLINK_IMAGE}"
version = "${CHAINLINK_VERSION}"
```

Of course above just and example, in real world no substitution will take place unless you use some templating tool, but it should give you an idea on how to move from env vars to TOML files. **Remember** your runtime configuration needs to be placed in `./testconfig/overrides.toml` file **that should never be committed**.

## Build

If you'd like to run the tests on a local build of Chainlink, you can point to your own docker image, or build a fresh one with `make`.

`make build_docker_image image=<image-name> tag=<tag>`

e.g.

`make build_docker_image image=chainlink tag=test-tag`

## Run

Make sure you have `./testconfig/overrides.toml` file with your Chainlink image and version.

`go test ./smoke/<product>_test.go`

Most test files have a couple of tests, it's recommended to look into the file and focus on a specific one if possible. 90% of the time this will probably be the `Basic` test. See [ocr_test.go](./smoke/ocr_test.go) for example, which contains the `TestOCRBasic` test.

`go test ./smoke/ocr_test.go -run TestOCRBasic`

It's generally recommended to run only one test at a time on a local machine as it needs a lot of docker containers and can peg your resources otherwise. You will see docker containers spin up on your machine for each component of the test where you can inspect logs.

## Analyze

You can see the results of each test in the terminal with normal `go test` output. If a test fails, logs of each Chainlink container will dump into the `smoke/logs/` folder for later analysis. You can also see these logs in CI uploaded as GitHub artifacts.

## Running Soak, Performance, Benchmark, and Chaos Tests

These tests remain bound to a Kubernetes run environment, and require more complex setup and running instructions not documented here. We endeavor to make these easier to run and configure, but for the time being please seek a member of the QA/Test Tooling team if you want to run these.
