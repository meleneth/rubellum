# Build a personal Ruby notebook appliance

Implement this project end to end in the current repository. This is a build request, not a request for a proposal or a scaffold. Read the repository and its applicable AGENTS.md first, preserve unrelated work, and adapt useful existing implementation. If the repository is empty, initialize the application here. Use the working name Ruby Notebook unless the repository already has a name.

Make a short implementation plan, record the core invariants, and then implement and verify working vertical slices until the acceptance criteria below pass. Make ordinary implementation decisions autonomously. Ask only when a genuine unresolved product decision blocks progress. Do not stop after planning or after the first slice. If the environment prevents a required build or verification, report that precisely; never substitute a passing mock for the blocked verification.

## 1. Product and deployment contract

Build a personal, trusted-user notebook appliance in Ruby on Rails, Hotwire, and Tailwind. It must feel like a polished local tool for authoring executable documents and small interactive applications.

The hard requirements are:

- One Docker image running as one Docker container, with PostgreSQL, GoAWS, the Rails application, background processes, and notebook runners inside it.
- One persistent `/data` volume and one published HTTP port. An ordinary `docker run` command must boot the complete appliance. Compose, external databases, external AWS, sibling runner containers, and a mounted Docker socket must not be deployment requirements.
- A personal instance can install multiple independently named apps, switch between them easily, and import/export each app independently.
- Wiki-style immutable revision history for notebook cells and notebook structure, with meaningful diffs and non-destructive restore.
- Real SQS signalling in both directions between the Rails application and the runner subsystem: commands toward runners; status, outputs, and results back toward Rails.
- Hotwire and Tailwind throughout, Markdown source editing, syntax highlighting, and a first-class editable D3 renderer cell type.
- Local operation without a hosted service, account signup, telemetry, cloud credentials, or runtime CDN dependency. Internet access by user-written notebook code is the user's choice, not a requirement of the appliance.

This is not a SaaS project. Do not build organizations, billing, invitations, multi-tenant authorization, a marketplace, or orchestration infrastructure. The owner trusts installed notebook code. Use sensible file permissions, normal Rails request protections, and a localhost-bound Docker example without turning the project into a hosted execution sandbox.

## 2. Stack and code organization

Use a currently supported, mutually compatible Ruby/Rails combination and pin it. Prefer Rails 8.x or newer if that is the supported baseline when implementing. Verify actual compatibility rather than assuming a specific Ruby/Rails pairing. Pin PostgreSQL's major version, GoAWS's release or commit, and important JavaScript dependencies. Commit lockfiles.

Use:

- Rails with server-rendered views and domain logic in small Ruby objects.
- Turbo Frames/Streams, Action Cable, and Stimulus for interaction.
- Tailwind for consistent light/dark styling, focus states, spacing, and responsive layout.
- CodeMirror 6 or a comparably suitable locally bundled editor, with actual Ruby, Markdown, JavaScript, JSON, and CSV/plain-text support as appropriate. Verify the grammar packages that exist; do not invent imports.
- Locally bundled D3, using normal JavaScript with a small renderer API.
- PostgreSQL for the durable application model and a PostgreSQL-backed Action Cable adapter such as Solid Cable.
- The AWS Ruby SDK's SQS client against the bundled GoAWS endpoint. Verify the selected SDK and GoAWS API protocol work together, and lock the working combination.
- s6-overlay as container init/service supervisor. Use its dependency-aware service definitions and foreground processes.
- RSpec, verifying doubles at real boundaries, and browser/system tests for critical user journeys.

One repository is enough. Rails web, the dispatcher/event consumer, and the runner manager are separate executable entry points. Keep shared message contracts in one small Ruby library used by both sides. Do not create duplicated protocol definitions, an internal microservice framework, or a plugin architecture merely to organize six cell types.

Use a small explicit cell-type registry with clear contracts for validation, source editing, rendering, execution where applicable, and import/export. Prefer direct calls within a clear owner and messages across the actual application/runner boundary.

## 3. Define the product objects precisely

An **instance** is the installed appliance and its persistent data.

An **app** is an independently portable project: metadata, notebooks/pages, revision history, assets/datasets, dependency declarations, and app configuration. An app is not another Rails application or a separately deployed server. Give it a stable portable identity plus a local installation identity.

A **notebook** is an ordered executable document within an app. An app may contain several notebooks and choose a landing notebook. Supply navigation between its notebooks.

A **cell** has stable identity, a type, title/label, source or structured configuration, and revisions. Position belongs to the notebook's versioned structure; array offsets must never be cell identities.

A **session** is a live execution context for one notebook. Start with one active session per notebook, shared by the owner's browser tabs. Different notebooks have separate Ruby processes. Changing the selected app or notebook does not itself restart existing sessions.

An **execution** records one invocation against an exact immutable cell revision, input snapshot, and session generation. Runtime state is not a cell revision.

Use clear app/notebook/cell/session identities in every relevant table and operation. Scope app data access and broadcasts explicitly so switching apps cannot display or mutate the wrong app. These boundaries prevent accidental contamination; do not claim adversarial isolation between arbitrary Ruby programs in one container.

## 4. Revision history is a first-class feature

Implement an explicit immutable revision model instead of treating a mutable source column plus timestamps as history.

For each committed cell revision retain:

- Stable revision identity and parent/base revision identity.
- Cell identity, cell type, source, title, and relevant configuration.
- Creation time, local author label, optional edit summary, and restore/import provenance when relevant.
- A content digest useful for integrity checks and comparisons.

The single owner is sufficient as the author; do not introduce an account system to populate that field.

Revision rules:

- Editing source/configuration creates a new revision. Old revisions are never rewritten.
- Restore copies historical content into a new revision with a new parent and explicit provenance. It must not move the current pointer backward and discard intervening history.
- Deleting, restoring, adding, or reordering cells is recorded in notebook-level revisions containing the ordered cell identities and the selected cell revision identities. Historical notebook views must reconstruct the actual document at that revision.
- Commit the changed cell head and notebook revision atomically. Concurrent saves from two tabs use an expected base revision and produce a visible conflict rather than silently overwriting edits.
- A type change is versioned and cannot silently reinterpret historical outputs as if they came from the new type.
- App titles, descriptions, landing-page selection, and relevant configuration have recoverable versioned changes. Avoid building a general event-sourcing framework for this.
- Preserve removed cells/revisions needed by history. Archive an app as an ordinary reversible operation; permanent deletion is a separate explicit action.

Provide a history drawer/page, revision timestamps and summaries, source diffs, side-by-side or unified comparison, historical preview, and Restore as new revision. Show structural changes such as cell reorder/removal intelligibly.

Editing should be pleasant: recoverable autosaved drafts, a visible saved/unsaved state, explicit Save revision, and an optional summary. Do not create a permanent wiki revision on every keystroke. Keep draft state distinct from committed revisions. Running edited code must first commit exactly that draft or explicitly use the current saved revision; never run one source while recording another.

An execution retains its cell revision, ordered notebook snapshot when part of Run all, parameter/dataset inputs, environment lock digest, session generation, and execution order. Label historical or stale outputs. Editing cell A must not relabel A's old output as current or pretend existing Ruby state has been recomputed. Clearly distinguish chronological execution order from document order.

Asset/dataset bytes referenced by revisions or executions must also be immutable. Uploading a replacement creates a new content identity; it cannot change a historical document through a reused mutable filename. Separate mutable scratch/workspace files from committed assets. Garbage collection must respect retained history and executions. Enforce revision immutability and reference integrity beyond controller conventions, and test the actual storage guarantees.

## 5. Implement these cell types

| Type | Required behavior |
| --- | --- |
| Markdown | Edit real `.md` source; render CommonMark/GFM-style headings, lists, links, tables, inline code, fenced code with syntax highlighting, and app-local images/assets. Provide edit, preview, and split views. Support importing/exporting individual `.md` cells. |
| Ruby | Highlighted Ruby source, Run/Run all, persistent notebook context, stdout/stderr, inspected return value, explicit structured outputs, errors with cell-local line references, interrupt, and restart. |
| D3 renderer | Editable highlighted JavaScript that uses bundled D3 to render an interactive SVG/HTML/canvas visualization from an explicitly selected data output or dataset and parameter values. |
| Data | Editable JSON or imported JSON/CSV with validation, preview, and a named structured dataset output. Preserve the original source/asset and the configured CSV parsing choices. |
| Table | A useful renderer for a named dataset/output: columns, sortable view, pagination for larger sets, basic filtering, and CSV/JSON export. Rendering does not execute Ruby. |
| Parameters | Versioned definitions of text/number/boolean/select/slider inputs with labels, defaults, and validation. Current values feed a named JSON-compatible input object for Ruby and renderers. |

Attach files/images through a shared asset facility; do not invent an executable type for every MIME type. Leave SQL, shell, and additional language kernels for later unless already required by the repository. The six types above must work completely before optional expansion.

Parameter definitions are versioned. Runtime values may be persisted separately for convenience, but each execution snapshots the values it used. Changing a slider can update a browser renderer immediately; it must not silently rerun side-effecting Ruby. Provide an explicit Run action or explicitly configured opt-in behavior with documented semantics.

Provide a small documented Ruby helper API, for example:

```ruby
Notebook.inputs                         # JSON-compatible input snapshot
Notebook.dataset("measurements")        # explicitly supplied dataset
Notebook.emit("summary", data: rows)    # named structured output
Notebook.display(value, mime: "text/plain")
Notebook.asset("plot.png")              # app-local output artifact reference
```

These names are a suggested coherent interface, not permission to leave methods unimplemented. Finalize and document one real API. Validate JSON values instead of silently stringifying arbitrary Ruby objects, NaN, or unsupported types. Keep ordinary Ruby return-value inspection separate from named machine-readable outputs. Images/files should become persisted artifacts with MIME type, size, and digest.

## 6. D3 and dataflow semantics

D3 is an actual programmable renderer, not a screenshot or a hard-coded chart picker. Include a minimal working renderer template.

Use a small versioned contract such as:

```javascript
async function render({ element, d3, data, inputs, width, height, theme }) {
  // Create a chart inside element.
  return () => {
    // Stop timers/simulations and release resources on replacement.
  };
}
```

Renderer source, selected input references, and configuration are revisioned. Bind inputs by stable cell/output identifiers within the app, never by cell position, ad hoc DOM selectors, or evaluation of Ruby variable names. A renderer can select a current successful output; record/display the specific execution and dataset revision actually rendered. Missing, stale, or incompatible data produces an informative cell-local state.

Keep runtime semantics deliberately explicit:

- Ruby cells run in document order for Run all, or in the order requested for individual execution, using one persistent Ruby context.
- No static analysis pretending to infer all Ruby dependencies. Re-running an earlier cell does not automatically fix downstream Ruby state.
- Renderer dependencies are declarative data references. Refresh a renderer when its selected successful input output or parameters change, without rerunning Ruby.
- A failed producer does not quietly turn a previous successful result into the output of the failed execution. Show the last successful result as stale if retained.
- Keep the first implementation's renderer inputs limited to structured data outputs/datasets/parameters, so it does not need a general reactive graph engine.

Run editable D3 JavaScript in a dedicated cell iframe, with the locally bundled renderer bootstrap and D3. Keep it separate from the editor's DOM. Pass only the intended structured data and events across a validated frame-message boundary, checking the sending frame and message identifiers. Do not evaluate renderer source in the main Rails page. Do not market this as a complete sandbox for hostile programs.

Handle resizing, rerendering, Turbo navigation/cache lifecycle, cancellation of obsolete asynchronous renders, cleanup of D3 timers/simulations/listeners, and renderer exceptions. A malformed chart must not break cell editing or app navigation. Supply theme colors to the renderer; do not depend on user-written Tailwind class strings being present in a precompiled stylesheet.

## 7. SQS is the application/runner transport in both directions

This requirement is intentional. Do not replace SQS with HTTP callbacks, a Redis bus, database polling as the normal transport, or direct Rails-to-evaluator pipes.

Use GoAWS to host:

- An execution-command queue per live session generation, avoiding arbitrary consumers stealing another session's work.
- A separate control queue per live session generation for interrupts, acknowledgments, and lifecycle controls that must remain responsive while code runs.
- A runner-events queue consumed by the Rails-side event ingestor.
- A manager-control queue if asynchronous allocation/restart commands need a distinct owner.

Choose consistent queue names and cleanup rules. Only use SQS features verified against the pinned GoAWS build. Do not assume FIFO ordering, deduplication, persistence, or a dead-letter feature exists merely because AWS SQS has it. Implement the required application guarantees explicitly and test the emulator/SDK pairing before investing in UI polish. SNS is available with GoAWS but does not need to be inserted without a real fan-out requirement.

A runner may consist of a lightweight agent and a child Ruby evaluator. This is useful for retaining a responsive SQS control path and separating the runner's SDK gems from each app's Bundler environment. Private agent/evaluator pipes are implementation details inside that runner. The Rails-to-runner and runner-to-Rails boundaries still use SQS for all commands and results; user stdout must not share a framing channel with protocol records.

Define one versioned message envelope including schema version, message ID, kind, app installation ID, notebook ID, session ID, generation, execution/command ID as applicable, sequence number where applicable, and payload. Validate it on both sides. Carry references plus digests for large immutable source/input payloads and artifacts in the shared volume; these files are payload storage, not a second signalling mechanism. Small payloads can travel inline within a tested size budget.

Events include runner ready, execution accepted/started, stdout/stderr chunks, structured output/artifact references, completion, failure, interruption, and heartbeat/status. Commands include execute, interrupt, restart/stop through the lifecycle owner, and persisted-event acknowledgments. Specify which messages are commands versus committed facts and which component owns each transition.

Reliability requirements:

1. Rails saves an execution request and outgoing message record in one Postgres transaction. A dispatcher publishes committed messages with retries. Recovery periodically reconciles outstanding requests even if a previous SendMessage succeeded before a GoAWS restart lost the notification.
2. The runner deduplicates commands by application identity and enforces sequence order per session. Redelivery must not execute the same command twice while the session survives. Out-of-order delivery cannot reorder Run all. Track gaps and cancellation explicitly.
3. Persist runner acceptance/start records and outgoing result events in a bounded, fsynced local journal/spool under `/data/runtime` before the corresponding transport acknowledgment. It must survive a GoAWS restart. Do not keep unacknowledged output solely in process memory.
4. Rails ingests events idempotently into Postgres with database uniqueness constraints. Preserve event identity and sequence across retries. Advance an acknowledgment only for a contiguous durably recorded event sequence; the runner can then compact its acknowledged spool. An SQS SendMessage response alone is not proof Rails recorded an event.
5. Recreate queue topology and republish outstanding command/event records after broker restart. The recovery owner must also replay durable result events left by dead runner agents without restarting their evaluators or re-executing source. Duplicate acknowledgments and events are safe. Set a concrete retention and disk-pressure policy for journals and output artifacts.
6. Fence every request and result by session generation. Old messages cannot execute in a replacement Ruby context or overwrite a newer session's displayed status. Preserve legitimate old results as historical records where applicable.
7. Never claim exactly-once external side effects. If the evaluator died after starting code and the outcome cannot be established, mark the execution unknown/interrupted and require a new explicit run. Never automatically replay arbitrary Ruby to recreate lost live state.
8. Visibility timeout/redelivery behavior is explicit. The agent acknowledges command delivery after durable acceptance, keeps its own pending-command state, and emits accepted/started/completed facts separately. A long-running cell must not cause a second evaluation merely because a queue visibility timeout elapsed.
9. Batch stdout/stderr into bounded chunks. Use backpressure and finite spool/output limits. If recording can no longer keep up, stop or truncate according to a visible documented policy; never consume memory/disk without bounds or silently discard output. Keep terminal status/control capacity available.

These are small domain protocols with concrete failure behavior, not a request for a universal distributed workflow engine. Keep them testable as plain Ruby objects with clocks, storage, and transport injected at their actual boundaries.

## 8. Runner ownership and execution lifecycle

The session manager is the sole owner of runner allocation, process groups, termination, and session generation changes. Enforce one owner and one live evaluator per session. Do not make Puma workers responsible for owning notebook subprocesses.

Each notebook evaluator has one persistent Ruby context and executes one cell at a time. App/notebook work directories and app dependency bundles are explicit. Different notebooks can execute concurrently within configured process and memory budgets. Loading an app does not automatically execute its notebooks.

Keep kernel lifetime separate from browser lifetime. Reloading or disconnecting the browser preserves the session. Reconnecting loads the persisted execution state and output cursor, subscribes to subsequent updates, and reconciles gaps/duplicates. It must not depend on replay from a transient Cable broadcast alone.

Implement normal completion, Ruby exception, syntax error, user interrupt, forced termination, runner crash, lost heartbeat, and appliance restart. Centralize valid state transitions; distinguish cancelled-before-start from interrupted-after-start and unknown outcome. Capture cell identity and sensible line numbers in backtraces.

Interruption has a bounded escalation path: request an interrupt, allow a short configurable grace period, then terminate the evaluator's process group if it does not respond. Native extensions or code trapping signals cannot be allowed to freeze the manager. Any interruption can leave Ruby objects partially mutated: display that state and offer Reset session. Forced termination loses the context and requires a fresh generation. Kill remaining descendants before declaring a replacement session ready.

On session reset, invalidate/cancel pending executions targeting the prior generation. Do not automatically retry them in a new, empty context. Run all starts from the documented state; offer a distinct Restart and run all action. If a Run all cell fails, stop subsequent Ruby execution by default and make the remaining state visible.

The evaluator must not inherit the Rails application's booted object graph, Bundler environment, database credentials, or unrelated secrets accidentally. Launch it through a clean exec environment with the app's declared bundle. The runner agent owns protocol transport. Arbitrary notebook code may deliberately access the user's chosen resources, but that is not an excuse for accidental application coupling.

## 9. App installation, switching, and portable packages

Provide an app library/home screen, persistent app switcher, per-app notebook navigation, create/rename/archive/duplicate, import, and export. Preserve navigation and recoverable drafts while switching. Show running sessions without forcing the owner to stop them to view another app.

Define and document a versioned app archive format, e.g. `.notebook-app.zip`, with a JSON manifest and a machine-validated schema. Include:

- Format version, app portable ID, metadata, compatible appliance/API versions, and landing notebook.
- Notebooks and ordered cell definitions with stable portable IDs and reference mappings.
- Current cell sources as readable `.md`, `.rb`, `.js`, `.json`, or `.csv` files where appropriate, not only opaque database dumps.
- Complete immutable cell/notebook/app revision history by default, including removal and restore provenance.
- Assets/datasets with relative paths, sizes, and digests.
- Gemfile/Gemfile.lock and declared environment requirements, if used.
- An explicit optional section for recorded executions/outputs. Live Ruby memory and live session/queue identities are never exported.

Support full-history export and a clearly labeled current-state-only export for sharing. If recorded outputs are omitted, do not leave dangling execution/artifact references. Rebuild all local database keys, paths, and references during import; portable UUIDs are not global database primary keys across independent installed copies.

App packages exclude instance secrets, local credential values, database files, runtime journals, and dependency caches. Represent app-specific local secrets as declarations/placeholders so portability does not silently copy the owner's credentials. Full appliance backups intentionally include the persistent configuration needed to restore that instance.

The first version must support installing an archive as a new app and importing a second copy safely. On identity collision, offer Import as copy or Cancel. Automatic merging/replacing of an existing edited app is outside this initial contract; never silently overwrite it. Preserve imported history with its provenance and distinguish local installation identity from source identity. Duplicating an app uses the same well-tested serialization/model mapping where sensible.

Validate the whole package before exposing an installed app: schema/version support, checksums, revision ancestry, unique identities, selected current revisions, renderer references, sizes, archive paths, and missing assets. Reject traversal, symlinks escaping the staging area, duplicate/conflicting archive entries, and unsupported format versions. Stage extraction and installation with cleanup/recovery so failures cannot leave a half-installed app or orphan files indefinitely.

Import and preview must not evaluate Ruby, renderer JavaScript, package hooks, or Gemfiles. Render recorded previews as inert content; run custom renderers only after an explicit render/run action. Install custom gem dependencies through an explicit Prepare environment action with visible progress/errors, separate from import. Record a changed dependency lock as an app revision and restart affected sessions deliberately.

Bundle caches/native extensions live outside the application bundle and are keyed by the actual runtime/platform/lock digest. Do not export or reuse incompatible compiled extensions across architectures. Standard built-in cell types must work offline after the appliance image is obtained. Document that a newly imported app with uncached external gems or missing OS libraries may need dependency preparation or an image extension; do not promise arbitrary gems work offline.

## 10. Hotwire/Tailwind interaction quality

Deliver a coherent, usable interface, not a collection of scaffold pages.

Required flows and details:

- App switcher and notebook sidebar with clear active selection.
- Notebook title/description, kernel state, run controls, edit/presentation mode, and import/export/history entry points.
- Cell toolbar: type, title, run/render where meaningful, edit/preview, move, duplicate, delete, history, and collapse source/output.
- Add a cell between existing cells; reorder with pointer support and an accessible keyboard alternative.
- Editor line numbers, indentation, search, keyboard shortcuts, syntax highlighting, and useful validation/error messages.
- Markdown preview and fenced-code highlighting use locally bundled assets.
- Real streaming execution status/output, visible execution order, source revision, stale state, elapsed duration, and terminal outcome.
- Reasonable presentation mode that hides editing controls and foregrounds the app's narrative, inputs, tables, and visualizations.
- Responsive layout, dark/light themes, accessible labels/focus, and usable empty/loading/error/conflict states.

Use targeted Turbo updates. Streaming output must not replace a focused editor, wipe undo history, move the caret, lose a draft, or rerender the entire notebook. Give Stimulus controllers clear connect/disconnect ownership and clean up editor instances and renderer resources on navigation. Reconcile persisted output after reconnect; treat broadcasts as update notifications, not the only copy of results.

Keep app code separate from author-written cell JavaScript. Bundle Tailwind, D3, editor grammars, fonts/icons if used, and Markdown/highlighting assets locally. No runtime frontend build service is required. Keep implementation jargon out of the normal authoring flow; protocol diagnostics can live in an explicit local diagnostics page.

## 11. Container, data, and operations

Use a multi-stage Dockerfile to build assets/gems and produce the appliance image. Node/Go tooling can be build-stage dependencies where feasible; do not add Python or Jupyter to the runtime. Install the actual PostgreSQL server and GoAWS binary in the final image.

Use one `/data` mount with clear ownership and directories such as:

| Directory | Purpose |
| --- | --- |
| `/data/postgres` | PostgreSQL data cluster |
| `/data/apps` | App workspaces and immutable payload/artifact content |
| `/data/bundles` | Per-app dependency caches by platform/runtime/lock digest |
| `/data/runtime` | Recoverable runner journals and message spools |
| `/data/config` | Generated persistent secrets and instance configuration |
| `/data/backups` | Explicit appliance backup outputs |

Keep disposable sockets and PID files under `/run`. Mutable user data must not live only in the image's writable layer. Use distinct service users where appropriate. Only the web port is published; PostgreSQL and GoAWS remain internal.

Boot must be repeatable: prepare directories, initialize an empty database only once, start dependencies, wait for real readiness, migrate schema, provision queues, recover durable protocol records, start consumers/managers/web, and report ready. A failed migration or critical startup step must stop the container with an actionable log. Detect a PostgreSQL major-version mismatch and require a documented upgrade path rather than initializing over existing data.

Shutdown must stop accepting work, stop or interrupt active sessions within a configured deadline, record what can be recorded, flush/retain durable spools, stop consumers, and stop PostgreSQL cleanly last. Critical service failure must not leave a deceptively healthy web shell. Health/readiness checks must include the services needed for actual execution. A healthcheck alone is not a restart policy; configure supervision/fatal-exit behavior explicitly.

Handle a runner process crash as a session failure. Handle GoAWS restart through queue recreation and message reconciliation while surviving evaluator contexts remain owned. If the manager itself fails, terminate/reconcile its owned runner groups before a replacement can allocate new generations. Do not leave orphan evaluators running untracked.

Send structured or clearly service-prefixed logs to container stdout/stderr. Correlate app/session/execution/message IDs without logging secrets or full arbitrary cell source by default. Include configured concurrency, output limits, disk pressure, and dependency readiness in local diagnostics.

Provide real documented CLI commands for build, start, test, app import/export, status/diagnostics, appliance backup, and restore. Distinguish individual app packages from whole-instance backups. Whole-instance backup must coordinate writes and collect PostgreSQL logical dumps, persistent configuration, and app assets consistently. Restore into a fresh volume is a required verification. Raw copying a running PostgreSQL directory is not an acceptable backup implementation.

Provide AMD64 and ARM64 build support where upstream components support it. Verify the architecture available in the environment and be explicit about any untested target. Do not copy host-specific binaries blindly between build platforms. Image replacement must reuse the existing data volume. Document supported upgrades and backup-before-upgrade procedure.

## 12. Testing and acceptance evidence

Use behavior-driven tests for meaningful invariants and failure paths. Small Ruby objects, injected transport/storage/clock boundaries, and verifying doubles should make unit tests straightforward. Keep most unit tests threadless. Use real subprocesses and real GoAWS/Postgres for integration contracts. Do not make every test boot the appliance, and do not claim a mocked SQS client proves real GoAWS interoperability.

Required evidence:

1. A clean image builds and a single container starts on a fresh volume; one HTTP port reaches the working app. Restart preserves committed data; replacing the container with the same image/volume also preserves it.
2. Create two apps with several notebooks, switch between them, and verify cells, drafts, datasets, outputs, and session state remain correctly scoped.
3. Save several revisions, diff them, restore an earlier revision as a new one, remove/reorder cells, reconstruct historical notebook state, and reject a stale concurrent edit without losing either draft.
4. Ruby variables and required libraries survive sequential cells within a session. They do not leak into another notebook. A run is tied to its actual saved source and parameter snapshot.
5. Trace a real execution command through GoAWS into the runner and real result/output events back through GoAWS into Rails and the browser. No direct callback bypass is used.
6. Exercise duplicate delivery, reordered events, sequence gaps, lost acknowledgment, and broker restart. Preserve a live runner's Ruby state across broker restart, reconcile outstanding messages, and prove a side-effecting test cell is not inadvertently executed again.
7. Kill a runner at a deliberately chosen execution boundary. Show an honest unknown/interrupted outcome; never silently rerun the operation. Reset cancels old-generation work, and delayed old messages cannot alter a replacement session.
8. Interrupt a long-running cell through the real control path. Verify bounded forced termination, descendant cleanup, responsive UI, and subsequent fresh-session execution. Bound excessive output and a renderer failure without breaking the application.
9. Edit/import/export Markdown with highlighted fenced code. Edit and run Ruby that emits a dataset; connect a D3 renderer, a table, and parameter controls; verify resize, refresh, cleanup, data provenance, and errors in a browser.
10. Export one app with its full history/assets, import it into a fresh instance, and compare semantic content, history, references, and assets. Import a second copy without collisions. Verify source-only export and malformed package rejection. No import automatically executes code.
11. Restart/reconnect the browser mid-execution and recover output without duplicates or gaps. Streaming must not disturb a focused editor or its draft.
12. Back up the appliance and restore into a fresh volume. Verify notebooks, revisions, settings, and assets. Live interpreter state correctly remains stopped/lost until explicitly run.
13. Load the built-in functionality with external networking disabled after image creation. Verify local D3/editor/Tailwind/Markdown assets still function.

Use deterministic synchronization/test hooks for races rather than brittle long sleeps. Test contracts across layers and significant state transitions, not incidental private implementation details or giant DOM snapshots. Add regression tests for actual defects found during implementation.

## 13. Delivery sequence and completion

Implement in reviewable increments, keeping the repository runnable:

1. Appliance boot, real PostgreSQL/GoAWS connectivity, message contracts, and the smallest real Ruby execution/result round trip.
2. App/notebook/cell model and immutable history, with correct revision/execution association.
3. Complete runner lifecycle, bidirectional reliable messaging, interruption/recovery, and persisted streaming output.
4. Full editor experience and all six required cell types, including real programmable D3 rendering.
5. Independent app packages, app switching, dependency preparation, and backup/restore.
6. Focused integration/browser verification and final usability fixes.

Create a minimal fixture app that exercises Markdown, parameters/data, Ruby output, a table, and D3, plus a second tiny fixture app for isolation/switching tests. These are acceptance fixtures that use the public authoring/import path, not a hard-coded substitute for the engine. A broader collection of polished demo apps will be a separate task; do not expand into building that catalog now.

Keep documentation concise but complete: README quick start and developer commands; CORE_INVARIANTS.md; architecture/process ownership and failure behavior; cell/helper/renderer API; versioned message contract; app package schema; backup/restore/upgrade instructions. Keep all docs aligned with implemented behavior, including real limits and unsupported cases.

Finish with the actual build/run commands, implementation summary, tests and browser journeys performed, concrete remaining limitations, and any verification the environment prevented. Do not describe a scaffold, mock transport, absent D3 editor, or missing history/import path as a complete implementation.

## Primary references to verify during implementation

Use current upstream documentation and the pinned source when selecting exact APIs:

- Docker multiple-process containers: https://docs.docker.com/engine/containers/multi-service_container/
- s6-overlay: https://github.com/just-containers/s6-overlay
- GoAWS and its actual supported API implementation: https://github.com/Admiral-Piett/goaws
- AWS SQS standard delivery/ordering semantics: https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/standard-queues.html
- Turbo Streams: https://turbo.hotwired.dev/handbook/streams
- Solid Cable: https://github.com/rails/solid_cable
- D3 installation and local bundling: https://d3js.org/getting-started
- CodeMirror: https://codemirror.net/
- PostgreSQL backup documentation: https://www.postgresql.org/docs/current/backup.html

AWS's hosted durability guarantees do not establish GoAWS's durability. The protocol above must be verified against the actual bundled emulator. Documentation examples using CDNs do not override this appliance's local-asset requirement.
