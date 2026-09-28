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

## Verified SQS transport

`Rubellum::SqsTransport` uses aws-sdk-sqs 1.119.0 against GoAWS 0.5.4 with its
JSON protocol. It creates standard queues with a 30-second visibility timeout,
uses explicit local dummy credentials, and receives one envelope at a time.
Receive validates the envelope but never deletes it. The durable consumer must
explicitly delete after recording acceptance; invalid messages raise and remain
unacknowledged. Poison-message handling belongs to the future consumer.

Real integration tests verify create/send/receive/delete, visibility redelivery,
the 64 KiB envelope budget, duplicate application identities, and queue/message
loss across GoAWS restart. Broker IDs are not application message identities.
No FIFO, durability, ordering, or hosted AWS guarantees are assumed. Recreating
queues and republishing retained messages works; durable retention/reconciliation
is still to be implemented.

Use `config/goaws.yml`. Keep GoAWS's `Region` empty: a nonempty value is prefixed
to `Host` in queue URLs, making a loopback IP invalid. The Ruby SDK uses
`us-east-1` separately for signing. This follows the pinned
[GoAWS configuration code](https://github.com/Admiral-Piett/goaws/blob/v0.5.4/app/conf/config.go)
and is checked by the real queue contract test. The pinned
[router](https://github.com/Admiral-Piett/goaws/blob/v0.5.4/app/router/router.go)
implements JSON alongside the older query protocol.
