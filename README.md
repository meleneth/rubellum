# Rubellum

A personal Ruby notebook appliance, under active construction. The intended
deployment is one container with Rails, PostgreSQL, GoAWS, and persistent notebook
runners, storing all durable data in one `/data` volume.

The [build brief](ruby-notebook-appliance-codex-prompt.md) defines the full product.
The [implementation plan](IMPLEMENTATION_PLAN.md) tracks verified progress, and
[core invariants](CORE_INVARIANTS.md) record the guarantees tests must protect.

## Development

Use Ruby 4.0.6 and Bundler 4.0.16:

```sh
BUNDLE_PATH=vendor/bundle bundle install
bin/test spec/unit
```

Tests use RSpec with verifying doubles and FactoryBot. Unit tests require no database, broker,
or Rails boot. SimpleCov writes line/branch coverage to `coverage/`.

Install the pinned, checksum-verified GoAWS release and run the real broker
contracts (requires local sockets and subprocesses):

```sh
bin/setup-goaws
bin/test spec/unit spec/integration
```

`bin/setup-goaws` supports Linux AMD64 and ARM64. AMD64 is verified; ARM64 is
not yet tested. Alternatively set `GOAWS_BIN` to a GoAWS 0.5.4 executable.
Integration examples start and stop their own broker with temporary storage.

There is not yet a runnable appliance. Build/run commands will be added with the
working slices that implement them.
