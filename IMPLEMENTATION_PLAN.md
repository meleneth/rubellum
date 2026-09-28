# Implementation plan

The complete contract is `ruby-notebook-appliance-codex-prompt.md`. Work proceeds
in small tested commits. Checkboxes mean verified behavior, not files created.

## Delivery checkpoints

- [x] 1. Appliance foundation: pinned compatible dependencies, RSpec harness,
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
- No unresolved product decision currently blocks implementation.
- Pinned Ruby 4.0.6, Rails 8.1.4 (declares Ruby >= 3.2), AWS SDK SQS 1.119.0,
  GoAWS 0.5.4. Real SDK/broker interoperability and Rails production boot are
  verified, including a real container-to-browser execution/reset path.

## Next concrete work

1. Close remaining history/authoring gaps: richer source/structure comparisons,
   editing affordances. Metadata editing/restore and Markdown split preview now
   works through the public app and notebook history controls.
2. Remaining lifecycle guarantees: heartbeat/hang detection, manager crash and
   descendant cleanup tests, durable control reconciliation, complete journal
   pressure handling, and explicit Restart-and-run-all.
3. Finish renderer lifecycle coverage and explicit dependency preparation. Portable
   app import/export/copy now works through the UI and CLI.
4. Coordinated backup/restore into a fresh volume, full offline acceptance, and
   remaining public-path fixture journeys. ARM64 remains unverified.

## Latest verification

- Reset admission fencing: `bin/test spec/models/session_reset_spec.rb
  spec/models/execution_transport_spec.rb spec/models/run_all_spec.rb`:
  18 examples, 0 failures (seed 59477). Pending resets are durable, reject
  duplicate resets/new ordinary executions, and survive old ready/stopped facts.
  Only manager readiness advances the generation and releases admission. The
  regression tests failed against the previous implementation before the fix.

- Post-interrupt full regression: `bin/test spec/unit spec/models spec/requests
  spec/integration spec/system`: 330 examples, 0 failures (seed 44834), tracked
  Ruby line coverage 95.26% / branch 80.08%. `docker build -t rubellum:dev .`
  succeeds, image `2e2cd85d433c`. This is a local development image; existing
  published registry tags have not been changed by this implementation work.
  `bin/test spec/appliance/boot_spec.rb`: 3 examples, 0 failures (seed 19985,
  94 seconds) against that rebuilt image, including persistence, fatal-service
  handling and the browser execution/reset/fresh-volume package-import journey.

- Queued interrupt cancellation: `bin/test spec/unit/session_agent_spec.rb
  spec/integration/session_agent_spec.rb spec/integration/interrupt_recovery_spec.rb
  spec/models/execution_transport_spec.rb`: 33 examples, 0 failures (seed 44719).
  The agent journals interrupt intent before deleting its notification, rejects
  conflicting execution identities, and cancels a later-arriving command without
  invoking Ruby. Real broker restart preserves this behavior; event assertions
  use protocol sequence rather than assuming SQS arrival order.

- Interrupt delivery regression: `bin/test spec/models/execution_transport_spec.rb
  spec/integration/interrupt_recovery_spec.rb`: 13 examples, 0 failures (seed
  50237). SendMessage no longer confirms interruption. A deterministic real
  agent pause/broker restart loses the first notification; retry interrupts the
  original evaluator without replaying its side effect or changing generation.
  Confirmation waits for contiguous durable terminal/stopped facts.

- History/D3/Markdown milestone: full non-appliance suite 321 examples, 0 failures
  (seed 63428), Ruby line coverage 94.85% / branch 79.21%. AMD64 development image
  rebuild succeeds; appliance suite 3 examples, 0 failures (seed 64899), including
  persistence, fatal-service handling, browser execution and fresh-volume package
  import. Registry tags still identify the previously published release candidate.

- Markdown draft edit/preview/split modes: `npm run build` and `bin/test
  spec/requests/markdown_preview_spec.rb spec/system/markdown_preview_spec.rb
  spec/system/authoring_spec.rb`: 8 examples, 0 failures (seed 23824). Real Chrome
  verifies live sanitized preview/highlighting, retained editor/undo across modes,
  and explicit-save semantics. Request tests cover empty/oversized/invalid source,
  app/asset scoping and no revision/draft/execution writes by the preview endpoint.

- D3 lifecycle regression reproduced an obsolete promise rejection overwriting a
  newer chart's status. Frame/controller now fence requests and errors by render
  identity, release late cleanup, and continue after cleanup exceptions.
  `npm run build` passes; `bin/test spec/system/renderer_lifecycle_spec.rb`:
  5 examples, 0 failures (seed 58824), including real-frame identity checks,
  null exceptions, resize/theme refresh and Turbo navigation cleanup. The first
  two lifecycle cases plus existing authoring passed together: 6 examples.

- `npm run build` and metadata regression suite: 34 examples, 0 failures (seed
  9463). Includes history/app-history model specs, app-history/notebook-metadata
  request specs, and both new Chrome metadata-history journeys. App metadata
  comparison/restore and versioned notebook settings are public Haml controls.
  Browser testing exposed duplicate library input IDs; forms now have unique
  namespaces with request coverage for label associations.

- `bin/test spec/models/app_history_spec.rb`: 6 examples, 0 failures. App metadata
  updates/restores append immutable revisions, preserve archive state unless
  explicitly changed, and reject stale edits and cross-app landing/restore IDs.

- Notebook restore regression reproduced metadata staying at the current head.
  Restore now appends historical title, description and configuration alongside
  restored cell revisions, retaining intervening history and restore provenance.
  `bin/test spec/models/history_spec.rb spec/models/app_package_import_spec.rb
  spec/models/app_package_export_spec.rb spec/requests/authoring_spec.rb`:
  38 examples, 0 failures (seed 18695).

- Release candidate source `393e3a15e1d2`: final non-appliance regression is
  294 examples, 0 failures (seed 6668), Ruby line coverage 94.26% / branch 77.94%.
  Built linux/amd64 image `b5a9229abe3b` with local tags
  `registry.deva.station/meleneth/rubellum:latest` and
  `registry.deva.station/meleneth/rubellum:393e3a15e1d2` (also `rubellum:dev`).
  Both tags were subsequently pushed at the owner's request; the registry returned
  `sha256:d2a32aa4a8ffc35a7bbda848658f31219d22dbbfb64dd24d23de1ad66d80fd53`
  for each successful push.

- Expanded appliance journey: `bin/test spec/appliance/boot_spec.rb`: 3 examples,
  0 failures (seed 7072, 94 seconds). Browser-authored Ruby and artifact history
  export through the real CLI, import into a second freshly initialized volume,
  preserve file ownership, remain stopped until explicitly run, then execute in
  a new context. Original persistence and fatal-service tests still pass.

- `bin/test spec/unit/package_manifest_spec.rb spec/unit/documentation_spec.rb`:
  14 examples, 0 failures. Strict integer schema versions, malformed owner shapes
  and embedded NUL metadata are rejected before staging/database insertion.

- Full regression after public package controls: `bin/test spec/unit spec/models
  spec/requests spec/integration spec/system`: 292 examples, 0 failures (seed
  17879), Ruby line coverage 94.24% / branch 77.75%. `npm run build` and rebuilt
  AMD64 image pass. Expanded fresh-appliance package journey is running next.

- `bin/test spec/requests/app_packages_spec.rb spec/integration/app_package_cli_spec.rb
  spec/system/app_packages_spec.rb`: 6 examples, 0 failures. Public full/current
  downloads, inert upload, explicit collision/copy, duplicate, actual CLI
  subprocesses and Chrome import/copy all pass. CLI refuses file overwrite.
  No imported Ruby/D3 execution or session allocation occurs. README documents
  commands and explicit named-volume/host-directory `/data` mounts.

- Inert package installation stages verified blobs, remaps local identities and
  references, preserves revision provenance, requires explicit copy on collision,
  and atomically publishes database state. Recovery retains committed files and
  removes abandoned installation namespaces. PostgreSQL advisory locking fences
  recovery against in-flight commit completion; startup runs recovery after
  migrations. `bin/test spec/models/app_package_import_spec.rb`: 8 examples,
  0 failures, including real database commit/rollback and a deterministic blocked
  advisory-lock race. Public controls and rebuilt-image verification remain next.

- `bin/test spec/unit/package_manifest_spec.rb spec/models/app_package_export_spec.rb`:
  12 examples, 0 failures. Versioned machine validation and full/current export
  preserve immutable history/assets, remap portable references and emit readable
  source files without sessions/executions. Public package import/export remains
  in progress; schema and limits are documented in `docs/app-packages.md`.

- `bin/test spec/unit/package_archive_spec.rb`: 9 examples, 0 failures. The
  inert tar/gzip container layer rejects traversal, links/devices/extensions,
  duplicate/conflicting paths, corrupt checksums, truncation and concatenated
  streams. Limits: 64 MiB compressed, 256 MiB expanded, 32 MiB per entry and
  10,000 entries. This is archive validation, not yet app import/export.

- Asset milestone regression: `bin/test spec/unit spec/models spec/requests
  spec/integration spec/system`: 256 examples, 0 failures (seed 22487), including
  Chrome image upload and Markdown import. Ruby line coverage 92.68%, branch
  coverage 75.43%. Rebuilt AMD64 image; `bin/test spec/appliance/boot_spec.rb`:
  3 examples, 0 failures (seed 20916). Browser-generated artifacts retain their
  original bytes after a later execution replaces the workspace file.

- Corrected a documentation-link check to recognize `asset://` examples and a
  real GoAWS fixture bind race. `bin/test spec/unit/documentation_spec.rb
  spec/integration/goaws_spec.rb`: 9 examples, 0 failures, including a deliberately
  occupied first-boot port. Restarts retain the original endpoint; only initial
  bind collisions are retried, not arbitrary broker errors.

- `bin/test spec/models/cell_files_spec.rb spec/requests/cell_files_spec.rb
  spec/requests/assets_spec.rb`: 10 examples, 0 failures. Public Markdown/data
  imports validate UTF-8, source size, format and document base revision; preserve
  original immutable file bytes; never enqueue execution; and export exact
  selected historical source. CSV parsing choices are stored with the revision.

- `bin/test spec/unit/execution_payload_spec.rb spec/unit/session_agent_spec.rb
  spec/integration/full_execution_spec.rb spec/models/execution_transport_spec.rb
  spec/models/run_all_spec.rb`: 26 examples, 0 failures. Large source and input
  snapshots now use digest-verified app blobs with an 8 MiB encoded limit and a
  32 KiB inline threshold. The real managed round trip executes >64 KiB source
  with a <2 KiB SQS envelope and persists an artifact. Corrupt accepted payloads
  cancel before evaluator invocation; duplicate acceptance does not reread bytes.

- `bin/test spec/unit/artifact_writer_spec.rb spec/unit/notebook_api_spec.rb
  spec/integration/evaluator_process_spec.rb spec/integration/full_execution_spec.rb
  spec/models/artifacts_spec.rb`: 27 examples, 0 failures. `Notebook.asset` now
  copies workspace files into durable blobs, returns metadata, and emits SQS
  artifact events. Real managed execution verifies scratch replacement does not
  alter artifact bytes and duplicate events do not duplicate metadata. SQL guards
  enforce artifact ownership and event/content identity. Limits: 32 files and
  100 MiB per execution, within the shared app storage quota.

- App uploads and immutable Markdown asset references: `bin/test
  spec/models/assets_spec.rb spec/requests/assets_spec.rb spec/models/history_spec.rb
  spec/requests/authoring_spec.rb`: 35 examples, 0 failures. Database triggers
  prevent asset mutation/deletion and cross-app revision references. Uploads
  version the app asset list; same-name replacements retain both identities.
  Downloads validate bytes; only raster images render inline, with nosniff and
  sandbox response headers. Active content remains an attachment.

- Immutable blob-store foundation: `bin/test spec/unit/blob_store_spec.rb`:
  10 examples, 0 failures. SHA-256 addresses, fsynced atomic publication,
  deduplication without overwrite, corruption/size validation, app namespaces,
  temporary-write recovery, 25 MiB per blob and 512 MiB per app defaults.
  No deletion/GC API; retained bytes are never evicted to make room.

- `docker build -t rubellum:dev .` and `bin/test spec/appliance/boot_spec.rb`:
  latest expanded AMD64 image builds; all 3 examples pass together (73 seconds).
  Fresh boot, PostgreSQL/Redis/secret persistence through restart and replacement,
  critical-service fatal exit, and browser-driven saved Ruby execution/context
  reset are verified. Generated test containers and volumes are cleaned up.

- `bin/test spec/unit spec/models spec/requests spec/integration spec/system`:
  209 examples, 0 failures. Line coverage 91.29%; branch coverage 73.74% for the
  tracked Ruby code in this run (not a browser JavaScript coverage claim).
- `bin/test spec/unit/documentation_spec.rb`: 3 examples, 0 failures. The README
  Ruby example runs and returns 36 with the documented structured output; the
  parameter example validates and local README links resolve.
- README now covers actual startup, persistence, Redis, first-notebook usage,
  editing/execution semantics, development/test prerequisites, safety boundaries,
  troubleshooting and concrete remaining limitations. Added cell/renderer docs;
  corrected stale operations/evaluator descriptions.

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

## Incremental verification history

- Run all now persists a shared immutable batch identity, captures one notebook/
  input snapshot, and cancels remaining batch cells after failure/interruption.
  Explicit later runs remain allowed; broker restart does not clear the failed
  batch. `bin/test spec/unit/session_agent_spec.rb spec/models/run_all_spec.rb
  spec/integration/session_agent_spec.rb`: 17 examples, 0 failures, including
  verifying-double boundaries and real broker/evaluator failure recovery.

- Expanded AMD64 image builds with Haml, local frontend assets and supervised
  workers. Appliance persistence/fatal-exit checks pass; the new real Chrome →
  Rails → SQS workers → Rails/Chrome execution and reset example passes separately
  (`bin/test spec/appliance/boot_spec.rb -e 'executes saved Ruby'`: 1 example).
  It verifies persistent Ruby values, stdout, a connected Cable subscription and
  reset into generation 2. Production boot exposed a missing Active Job railtie;
  `EAGER_LOAD=1 bin/test spec/requests/authoring_spec.rb`: 9 examples, 0 failures
  after the fix. The first browser fixture itself had a Ruby local-variable bug;
  correcting it allowed the execution journey to pass.

- `bin/test spec/models/execution_updates_spec.rb spec/system/authoring_spec.rb`:
  4 examples, 0 failures in real Chrome 154. Browser evidence: public create/edit/
  save/recover, local highlighted Markdown, table filtering, explicit iframe D3,
  slider refresh without Ruby, and output reconciliation retaining editor focus,
  source and undo. Broadcasts target only output/status nodes. External page
  requests are blocked. This does not yet prove all renderer cleanup races or
  the full container-to-browser execution acceptance path.

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
  and journal compaction. At this checkpoint the manager service entry points
  were wired into s6 but the expanded image had not yet been boot-tested.

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
  abrupt exits. At that checkpoint no application execution path was claimed.

- Rails 8.1.4 boots on Ruby 4.0.6. Three request specs pass against temporary
  PostgreSQL 17.11 and GoAWS processes, including dependency-failure readiness.
  PostgreSQL test fixtures never use an existing host database. The host lacked
  server binaries; an extracted Debian PostgreSQL package supplies them locally.

Passing individual transport tests is not proof of all reliability requirements.
Only checkpoint 1 is complete; the unchecked checkpoints retain the full scope
of the build brief, including missing asset, portability and operational work.
