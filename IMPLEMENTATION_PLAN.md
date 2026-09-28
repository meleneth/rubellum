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

## Verification ledger

- 2026-09-28: read the full brief and applicable guidance; verified clean tree
  and Docker daemon access. No application acceptance tests exist yet.
