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
- Pinned Ruby 4.0.6, Rails 8.1.4 (declares Ruby >= 3.2), AWS SDK SQS 1.119.0.
  Real SDK/broker interoperability and Rails boot remain to be verified.

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
