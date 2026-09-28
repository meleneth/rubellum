# Rubellum

A personal Ruby notebook appliance, under active construction. The image boots
Rails, PostgreSQL, GoAWS, and Redis in one container with one `/data` volume.
Notebook authoring and the connected runner workflow are still in progress.

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

## Appliance

```sh
docker build -t rubellum:dev .
docker run -d --name rubellum -p 127.0.0.1:3001:3000 -v rubellum-data:/data rubellum:dev
curl -f http://127.0.0.1:3001/up
```

The current page is an authoring placeholder. `/up` checks actual PostgreSQL,
GoAWS, and Redis connectivity. Only port 3000 is exposed. Redis 8.0.2 listens on
container loopback, writes AOF/RDB under `/data/redis`, and has a 128 MiB
`noeviction` limit. AOF fsync runs every second, so a crash can lose recent Redis
writes; notebook history belongs to PostgreSQL, and runner transport remains SQS.

```sh
bin/test spec/unit spec/integration spec/models spec/requests
bin/test spec/appliance
```

Database tests require PostgreSQL 17 server binaries (`POSTGRES_BIN` optionally
sets their directory). Redis tests require `redis-server` (`REDIS_BIN` optionally
sets its path). Both use isolated temporary stores; they never use your normal
database or Redis instance. Appliance specs require Docker and the built image,
and remove only their own generated test containers/volumes.

Service definitions and operational guarantees are in [operations](docs/operations.md).
