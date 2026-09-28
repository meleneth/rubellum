# Rubellum

A personal Ruby notebook appliance for executable notes and small interactive
tools. Write Markdown and Ruby, keep a live Ruby context, and connect structured
data to tables, parameter controls, and editable D3 visualizations.

One Docker image. One container. One persistent `/data` volume. One HTTP port.
PostgreSQL, GoAWS, Redis, Rails, and notebook workers are bundled—no Compose,
external AWS account, hosted service, runtime CDN, or Docker socket required.

**Under active development.** The authoring and execution paths work, but the
full product contract is not complete. App import/export, custom gem environments,
and coordinated backup/restore are not ready.
Use disposable development data until backup/restore is implemented and verified.

## Quick start

You need Docker. Build from this checkout, then run:

```sh
docker build -t rubellum:dev .
docker run -d --name rubellum \
  --restart unless-stopped --stop-timeout 30 \
  -p 127.0.0.1:3001:3000 \
  -v rubellum-data:/data \
  rubellum:dev
```

Open **http://127.0.0.1:3001** once the container is healthy. Initial boot prepares
the data volume and migrates PostgreSQL; it takes longer than subsequent starts.

```sh
docker inspect --format '{{.State.Health.Status}}' rubellum
docker logs --tail 100 rubellum
curl --fail http://127.0.0.1:3001/up
```

`/up` checks actual PostgreSQL, GoAWS, and Redis connectivity. Critical web/worker
or database-service exits stop the appliance; the Docker restart policy restarts
it. A hung worker is not yet detected by readiness checks.

This is a **trusted, single-owner local tool**, not a hosted execution sandbox.
There is no login system. Keep the localhost binding; do not expose it directly
to an untrusted network. Notebook Ruby can access resources available to its
process. The D3 iframe separates renderer code from the editor but is not a
complete security boundary for hostile programs.

### Stop and restart

```sh
docker stop --time 30 rubellum
docker start rubellum
```

The named volume retains notebooks, revisions, outputs, Redis data, runtime
journals, and the instance secret. Browser navigation does not reset Ruby.
Container restart does lose live Ruby memory: reset a lost session explicitly;
Rubellum does not replay arbitrary code to reconstruct it.

Same-image container replacement with the same volume is tested. Cross-version
upgrades and whole-instance restore are not yet supported. Never copy a running
PostgreSQL data directory and call it a consistent backup.

## Your first notebook

1. Create an app in the app library. Each app contains its own notebooks; use the
   sidebar to add notebooks and switch projects.
2. Add a Ruby cell. Under **Edit source**, replace its source with:

   ```ruby
   rows = [{ "label" => "One", "value" => 12 }, { "label" => "Two", "value" => 24 }]
   Notebook.emit("rows", data: rows)
   rows.sum { |row| row.fetch("value") }
   ```

3. Choose **Save & run**. You should see the named `rows` output and return value
   `36`. A second Ruby cell can use `rows`; each notebook has a separate context.
4. Add a Table or D3 cell. In its **Configuration and input binding**, use the Ruby
   cell's identity (shown in its editor):

   ```json
   { "input": { "cell_id": "REPLACE-WITH-PRODUCER-CELL-UUID", "output": "rows" } }
   ```

5. Save the renderer revision. Tables load their data automatically; D3 requires
   **Render chart**. Its starter source is real, editable JavaScript using local
   D3—not a fixed chart picker. Add a Parameters cell to try its `scale` slider.

Bindings currently use configuration JSON; a dedicated input picker is still
needed. Missing bindings and missing successful outputs produce cell-local
errors. A Data cell can also be selected by `cell_id`, without an `output` name.

### Editing and execution semantics

- **Drafts are not revisions.** Edits autosave separately with tab-local recovery.
  Save revision creates immutable history. A stale concurrent save is rejected
  rather than overwriting the other tab's work.
- **Run saved revision** uses committed source. **Save & run** commits and queues
  that exact revision atomically. Outputs retain source revision, execution order,
  and session generation; edited source does not relabel old output as current.
- **Run all saved Ruby** captures one document/input snapshot and queues Ruby in
  document order using the existing context. Failure or interruption cancels the
  rest of that batch; a later explicit run is still allowed. There is no inferred
  dependency graph. A combined Restart-and-run-all action is not implemented.
- **Interrupt** uses a separate SQS control path. Unresponsive code is forcibly
  terminated after a grace period; an uncertain outcome is recorded honestly,
  never automatically retried. **Reset session** starts a fresh generation.
- **Parameters** refresh active browser renderers but never silently run Ruby.
  Every Ruby execution snapshots its parameter and dataset inputs.
- **History** provides old source, structural snapshots, comparison, and restore
  as a new revision. Removed cells remain available in retained history.

### Cell types

| Type | Current behavior |
| --- | --- |
| Markdown | Source editing, sanitized preview, GFM-style tables and highlighted fenced code |
| Ruby | Persistent notebook context, stdout/stderr, return values, named JSON outputs, errors and interrupt |
| Data | JSON or CSV source, parsing configuration, validation and preview |
| Parameters | Versioned text/number/boolean/select/slider definitions; separate current values |
| Table | Explicit data binding, column sorting, filtering, pagination, JSON/CSV download |
| D3 | Editable JavaScript in an explicitly activated iframe; structured data, inputs, sizing and theme |

Built-in helpers are `Notebook.inputs`, `Notebook.dataset(name)`,
`Notebook.emit(name, data:)`, `Notebook.display(text, mime: "text/plain")`, and
`Notebook.asset("workspace-file.png")`. Upload immutable files through **Files and
images**; reference them in Markdown with `![Image](asset://ASSET-UUID)`.
See the [Ruby helper reference](docs/evaluator.md) and
[cell/renderer reference](docs/cells.md) for contracts and limits.

## What's inside

The pinned stack is Ruby **4.0.6**, Rails **8.1.4**, PostgreSQL **17**,
GoAWS **0.5.4**, Redis **8.0.2**, and s6-overlay **3.2.3.2**. Views use **Haml**;
the browser uses Hotwire, Tailwind, CodeMirror 6, and D3. Lockfiles pin dependencies.
Node is used to build assets, not as a runtime frontend service.

Rails stores requests and an outgoing-message record in one PostgreSQL
transaction. The dispatcher sends commands through GoAWS SQS; manager-owned
agents journal them durably and invoke clean Ruby evaluator processes. Results
return through SQS and commit to PostgreSQL before acknowledgment. Turbo updates
only status/output nodes, while reconnect polling reconciles persisted results.

Duplicate delivery, sequence gaps, generation fencing, broker restart, and
unknown evaluator outcomes have automated coverage. These mechanisms do **not**
promise exactly-once external side effects.

### Redis

Redis is bundled and supervised, listening on **container loopback `127.0.0.1:6379`**.
It is not published on the host and does not replace SQS or PostgreSQL.

```sh
docker exec rubellum redis-cli PING
```

Data lives in `/data/redis`, with AOF persistence, periodic RDB snapshots, and a
**128 MiB `noeviction` limit**. AOF fsync runs every second, so a crash can lose
recent Redis writes. Notebook revision history belongs to PostgreSQL. Bundling
the server does not yet supply custom gems to the isolated notebook evaluator.

## Development and tests

Use Ruby 4.0.6, Bundler 4.0.16, and Node 24 for local development. Building the
Docker image does not require these tools on the host.

```sh
BUNDLE_PATH=vendor/bundle bundle install
npm ci
npm run build
bin/setup-goaws
```

All tests use **RSpec**. Mocks verify real interfaces; reusable test data uses
**FactoryBot**. Contributions should include meaningful unit/failure-path tests
and small, frequent commits. See [AGENTS.md](AGENTS.md) for coding preferences.

Run the layers independently:

```sh
# Fast library tests: no Rails, database, or broker
bin/test spec/unit

# Real PostgreSQL, Redis, GoAWS and evaluator subprocesses
bin/test spec/models spec/requests spec/integration

# Production-style loading catches missing framework dependencies
EAGER_LOAD=1 bin/test spec/requests

# Real Chrome authoring/rendering journeys; build assets first
bin/test spec/system

# Fresh Docker volumes, persistence, fatal exits and browser-to-runner execution
docker build -t rubellum:dev .
bin/test spec/appliance
```

Local service tests need PostgreSQL 17 server/client binaries and `redis-server`.
System tests and the appliance browser journey need Chrome. Override locations
with `POSTGRES_BIN` (directory), `REDIS_BIN`, `GOAWS_BIN`, or `CHROME_BIN`.
Chrome defaults to `/usr/bin/google-chrome`. `RUBELLUM_IMAGE` selects the appliance
test image; its default is `rubellum:dev`.

Tests create isolated temporary databases/brokers and never use your ordinary
database or Redis instance. Unset `DATABASE_URL` before running database tests;
the harness refuses it. Run local PostgreSQL tests as a non-root user. Appliance
specs clean up only their own generated containers/volumes. Browser tests block
external page requests. SimpleCov writes line/branch reports to `coverage/`.

AMD64 is tested. ARM64 build paths exist but are **not verified**. Runtime offline
acceptance is only partially covered: local assets work with external browser
requests blocked; a fully network-disabled appliance journey remains to be run.

## Remaining work and references

Still unfinished: portable app packages/import/export/duplicate,
individual Markdown import/export and split preview, custom
gem preparation, large payload references, coordinated backup/restore, richer
diffs and editor controls, complete journal retention/pressure handling, and the
remaining lifecycle/renderer/offline acceptance cases. No import/export or backup
CLI is advertised before it actually exists.

- [Implementation plan and verification ledger](IMPLEMENTATION_PLAN.md)
- [Core invariants](CORE_INVARIANTS.md)
- [Process supervision and operations](docs/operations.md)
- [Message contract](docs/message-contract.md)
- [Full product/build brief](ruby-notebook-appliance-codex-prompt.md)

If boot fails, inspect `docker logs --tail 100 rubellum` first. A PostgreSQL major
version mismatch is deliberately fatal—do not delete or reinitialize an existing
volume to get past it. For unknown Ruby outcomes, inspect the output and reset
explicitly before deciding whether a new run is safe.
