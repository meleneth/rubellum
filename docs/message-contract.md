# Message contract v1

`Rubellum::Message` is the shared, Rails-independent wire envelope. It validates
incoming and outgoing JSON, rejects duplicate/unknown envelope keys, copies and
deeply freezes data, and limits encoded envelopes to 64 KiB. Payloads permit only
JSON values with string object keys, finite numbers, and at most 32 levels of
nesting. Large payload storage and kind-specific payload contracts are subsequent
implementation work.

Required fields: `schema_version` (1), `message_id`, `kind`, `app_installation_id`,
`notebook_id`, `session_id`, `generation`, `sequence`, `payload` (object).
All IDs use canonical lowercase UUID strings; generation/sequence are positive
integers. `execution_id` is required on execution commands/events and optional
on lifecycle messages. `command_id` optionally correlates facts to commands.

Commands: `execute`, `interrupt`, `restart`, `stop`, `acknowledge`.
Facts: `runner_ready`, `execution_accepted`, `execution_started`, `stdout`,
`stderr`, `structured_output`, `artifact`, `execution_completed`,
`execution_failed`, `execution_interrupted`, `execution_cancelled`,
`execution_unknown`, `heartbeat`.

Planned ownership: the lifecycle manager owns restart/stop and generations; the
runner accepts sequenced execution commands and emits facts; Rails durably
ingests facts and acknowledges contiguous event sequences. Envelope validation
alone does not establish ordering, deduplication, durability, or fencing.
