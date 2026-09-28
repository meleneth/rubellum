# Message contract v1

`Rubellum::Message` is the shared, Rails-independent wire envelope. It validates
incoming and outgoing JSON, rejects duplicate/unknown envelope keys, copies and
deeply freezes data, and limits encoded envelopes to 64 KiB. Payloads permit only
JSON values with string object keys, finite numbers, and at most 32 levels of
nesting. Execute payloads up to 32 KiB travel inline; larger payloads (maximum
8 MiB encoded JSON) travel as app-scoped immutable blob references. Every SQS
envelope remains within the same tested 64 KiB limit.

Required fields: `schema_version` (1), `message_id`, `kind`, `app_installation_id`,
`notebook_id`, `session_id`, `generation`, `sequence`, `payload` (object).
All IDs use canonical lowercase UUID strings; generation/sequence are positive
integers. `execution_id` is required on execution commands/events and optional
on lifecycle messages. `command_id` optionally correlates facts to commands.

Commands: `start`, `execute`, `interrupt`, `restart`, `stop`, `acknowledge`.
Facts: `runner_ready`, `runner_stopped`, `execution_accepted`, `execution_started`, `stdout`,
`stderr`, `structured_output`, `display`, `output_truncated`, `artifact`, `execution_completed`,
`execution_failed`, `execution_interrupted`, `execution_cancelled`,
`execution_unknown`, `heartbeat`.

Ownership: the lifecycle manager owns allocation/restart and generations; the
runner accepts sequenced execution commands and emits facts; Rails durably
ingests facts and acknowledges contiguous event sequences. Envelope validation
alone does not establish ordering, deduplication, durability, or fencing.
Standalone stop and heartbeat are declared envelope kinds but not complete
application workflows yet.

## Payload and artifact references

An inline execute payload contains cell/revision UUIDs, source and its SHA-256,
input/dataset snapshots, and optional Run all `batch_id`. A referenced payload is
`{"payload_ref":{"sha256":"64-lowercase-hex","size":12345},"batch_id":null}`.
The agent resolves it in the envelope's app storage, verifies digest/size and
batch metadata before durable acceptance, and revalidates before evaluation.
The journal retains the small reference, not a second large source copy. A
missing/corrupt accepted payload cancels before evaluation, never runs altered
source. These files hold bytes; the execute signal still crosses SQS.

`artifact` events contain `filename`, a declared/inferred `mime`, and a `blob`
digest/size reference. Blob publication is fsynced before the evaluator emits the
event. Rails verifies the bytes, determines the served MIME, and commits immutable
asset metadata and the event acknowledgment in the same transaction. Database
constraints tie asset content and app/execution ownership to the recorded event.
Duplicate facts do not create duplicate asset metadata.

Storage lives under `/data/apps/<installation UUID>/blobs/<SHA-256>`. Individual
blobs are capped at 25 MiB, all app blobs at 512 MiB; artifacts are additionally
capped at 32 files/100 MiB per execution. No history-referenced data is evicted.
Uncommitted temporary writes are cleaned under the writer lock. A published blob
left by a later transaction failure is retained and counted toward quota; safe
garbage collection and administrative retention tooling remain unfinished.

## Verified SQS transport

`Rubellum::SqsTransport` uses aws-sdk-sqs 1.119.0 against GoAWS 0.5.4 with its
JSON protocol. It creates standard queues with a 30-second visibility timeout,
uses explicit local dummy credentials, and receives one envelope at a time.
Receive validates the envelope but never deletes it. The durable consumer must
explicitly delete after recording acceptance; invalid messages raise and remain
unacknowledged. Dedicated poison-message quarantine remains unfinished.

Real integration tests verify create/send/receive/delete, visibility redelivery,
the 64 KiB envelope budget, duplicate application identities, and queue/message
loss across GoAWS restart. Broker IDs are not application message identities.
No FIFO, durability, ordering, or hosted AWS guarantees are assumed. Recreating
queues and republishing retained commands/events is implemented through a
PostgreSQL outbox, bounded fsynced runner journals, and contiguous acknowledgments.
Complete disk-pressure/retention and control-reconciliation cases remain unfinished.

Use `config/goaws.yml`. Keep GoAWS's `Region` empty: a nonempty value is prefixed
to `Host` in queue URLs, making a loopback IP invalid. The Ruby SDK uses
`us-east-1` separately for signing. This follows the pinned
[GoAWS configuration code](https://github.com/Admiral-Piett/goaws/blob/v0.5.4/app/conf/config.go)
and is checked by the real queue contract test. The pinned
[router](https://github.com/Admiral-Piett/goaws/blob/v0.5.4/app/router/router.go)
implements JSON alongside the older query protocol.
