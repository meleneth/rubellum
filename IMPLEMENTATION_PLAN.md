# Implementation plan

The complete contract is `ruby-notebook-appliance-codex-prompt.md`. Work proceeds
in small tested commits. Checkboxes mean verified behavior, not files created.

## Delivery checkpoints

- [ ] 1. Appliance foundation: pinned compatible dependencies, RSpec harness,
  versioned message contract, real GoAWS SDK verification, PostgreSQL and s6 boot,
  smallest Ruby command/result round trip through SQS.
- [ ] 2. App/notebook/cell model: storage-enforced immutable revisions and assets,
  optimistic editing, drafts, restore/history, exact execution provenance.
- [ ] 3. Runner lifecycle: manager ownership, durable outbox/spools, sequence and
  generation fencing, interruption, broker/crash recovery, persisted streaming.
- [ ] 4. Authoring: Hotwire/Tailwind, locally bundled editors, six complete cell
  types, programmable iframe D3, stable dataflow and reconnect behavior.
- [ ] 5. Portability/operations: app library and switching, archive schema and
  validation, copy/import/export, explicit dependency preparation, backup/restore.
- [ ] 6. Acceptance: both public-path fixture apps, browser journeys, fault tests,
  fresh-volume restore, container replacement, offline built-in functionality.

## Working method

For each behavior: write the invariant/failure test, implement the smallest
coherent change, run the relevant checks, review the diff, and commit. Unit tests
run without infrastructure; separate integration tests exercise real PostgreSQL,
GoAWS, subprocesses, and browsers. Do not skip failed integration checks or mark
an incomplete checkpoint complete.

## Decisions and context

- Project name: Rubellum (repository name); personal, trusted-user appliance.
- Starting repository: one build brief, no application code; clean `main` at
  `b4ae31b` on 2026-09-28.
- Host: AMD64, Ruby 4.0.6, Bundler 4.0.16, Node 24.21.0, Docker available.
- No unresolved product decision blocks the first checkpoint.
- Pinned Ruby 4.0.6, Rails 8.1.4 (declares Ruby >= 3.2), AWS SDK SQS 1.119.0,
  GoAWS 0.5.4. Real SDK/broker interoperability is verified; Rails boot remains
  to be verified.

## Verification ledger

- 2026-09-28: read the full brief and applicable guidance; verified clean tree
  and Docker daemon access. No application acceptance tests exist yet.
- 2026-09-28: `bin/test spec/unit`: 66 examples, 0 failures. Shared message
  envelope and strict JSON copying cover invalid identities, unsupported schema,
  required fields, duplicate keys, size/depth bounds, and mutation protection.
  Line coverage 100%; branch coverage 92.86% for these two classes. This does not
  prove transport, durability, execution, or application acceptance behavior.
- 2026-09-28: added FactoryBot for reusable data and factory/trait linting using
  the build strategy; `bin/test spec/unit`: 67 examples, 0 failures.
- 2026-09-28: `bin/test spec/unit spec/integration/goaws_spec.rb`: 92 examples,
  0 failures (87 unit, 5 real broker). Verified JSON protocol, idempotent queue
  creation, 64 KiB envelopes, receipt deletion, visibility redelivery, duplicate
  application IDs, lost topology/messages after broker restart, recreation and
  explicit republication. Corrected GoAWS region-prefixed loopback URLs and
  protected that behavior with a regression assertion. Actual coverage: 100%
  lines, 93.75% branches for the current small library. This does not yet prove
  durable reconciliation, generation fencing, or a Ruby execution round trip.

## Next concrete work

- Owner preferences are persisted in `AGENTS.md`: Haml templates, RSpec with
  verifying doubles, FactoryBot, and small frequent commits. Haml Rails is pinned;
  all application templates use Haml and generator defaults match.
- `npm run build` passes for the local CodeMirror grammars, Turbo/Stimulus, D3
  iframe bootstrap and Tailwind. `bin/test spec/unit spec/models spec/requests
  spec/integration`: 199 examples, 0 failures. New coverage includes all six Haml
  cell views, source escaping, app/cell scoping, draft conflicts, exact Save-and-run
  revisions, inert historical renderers, and typed data/parameter validation.
  Browser lifecycle, renderer cleanup, reconnect and offline acceptance are not
  yet verified by these request tests.

- `bin/test spec/integration/full_execution_spec.rb`: 1 example, 0 failures.
  Real PostgreSQL request/outbox → GoAWS → manager-owned agent and clean Ruby
  evaluator → GoAWS → PostgreSQL result, including durable event acknowledgment
  and journal compaction. Manager service entry points are wired into s6; this
  expanded image still needs a fresh build/boot verification.

- AMD64 appliance image builds. `bin/test spec/appliance/boot_spec.rb`: 2 examples,
  0 failures: fresh boot, only one published HTTP port, PostgreSQL/Redis/secret
  persistence through restart and replacement, clean PostgreSQL shutdown, fatal
  critical-service exit. Redis added at owner's request with AOF/RDB persistence,
  loopback binding and 128 MiB noeviction limit. ARM64 remains unverified.
- `bin/test spec/unit spec/integration spec/models spec/requests`: 146 examples,
  0 failures. Includes 16 real PostgreSQL history invariants and raw SQL guards.

- Evaluator and helper API implemented and tested with real subprocesses:
  persistent variables/methods/requires, distinct contexts, separated stdout and
  protocol, bounded output, strict JSON helpers, cell-local errors and unknown
  abrupt exits. No application execution path is claimed yet.

- Rails 8.1.4 boots on Ruby 4.0.6. Three request specs pass against temporary
  PostgreSQL 17.11 and GoAWS processes, including dependency-failure readiness.
  PostgreSQL test fixtures never use an existing host database. The host lacked
  server binaries; an extracted Debian PostgreSQL package supplies them locally.

Continue checkpoint 1 with PostgreSQL/s6 appliance boot and the smallest Ruby
execution/result path, using the verified SDK and broker configuration. Keep
durable acceptance, clean evaluator exec, and explicit process ownership in scope
as the execution path develops. Do not interpret the transport tests as proof of
the reliability requirements or any complete application acceptance criterion.
