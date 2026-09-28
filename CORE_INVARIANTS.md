# Core invariants

These are requirements to enforce and test, not claims that every subsystem is
already implemented. See `IMPLEMENTATION_PLAN.md` for current evidence.

1. **One appliance.** One image/container, one `/data` volume, one HTTP port.
   PostgreSQL, GoAWS, Redis, Rails, consumers, and runners run under s6. Redis was
   explicitly added by the owner; SQS remains the runner transport. Normal use needs
   no external service, account, cloud credentials, Docker socket, or runtime CDN.
2. **Explicit identity.** Every operation scopes installation, notebook, session,
   generation, and execution as applicable. Portable IDs are distinct from local
   installation IDs. Different notebooks have different Ruby contexts.
3. **Immutable history.** Cell, notebook structure, app metadata, and committed
   asset bytes retain history. Storage enforces immutability and references.
   Save changes cell and document heads atomically with expected-base checking;
   restore appends a revision. Drafts are recoverable but are not revisions.
4. **Truthful execution.** A run names exact source, inputs, environment, document
   snapshot, generation, and order. Outputs retain that provenance. Editing does
   not recompute state or relabel old output. Failed runs do not claim old success.
5. **SQS in both directions.** Rails/runner commands, control, events, and durable
   acknowledgments cross real SQS queues. Shared files hold immutable payloads,
   not signals. Only the evaluator/agent use private pipes.
6. **Durability before acknowledgment.** Postgres request/outbox transactions,
   fsynced runner journals, unique event identities, contiguous acknowledgments,
   bounded buffers, and reconciliation tolerate duplicates and broker loss.
   Command sequence controls order independently of SQS delivery order.
7. **One lifecycle owner.** The manager owns process groups, allocation,
   termination, and generation changes. Stale generations cannot execute in or
   overwrite a replacement context. Lost outcomes remain unknown/interrupted;
   arbitrary Ruby is never automatically replayed to reconstruct memory.
8. **Bounded resources.** Interrupt escalation, descendant cleanup, concurrency,
   stdout/stderr chunks, durable spool, and artifacts have explicit limits.
   Terminal/control capacity survives output pressure. Truncation is visible.
9. **Clean evaluator.** Exec with an explicit environment and app bundle; do not
   inherit a booted Rails graph or application credentials. Validate structured
   JSON rather than coercing arbitrary Ruby values. Trust is not hostile isolation.
10. **Explicit dataflow.** Six cell types: Markdown, Ruby, D3, data, table, and
    parameters. Renderers use stable data references and record provenance.
    Parameter changes do not silently run Ruby. D3 runs in a dedicated iframe
    with validated messages and cleanup on cancellation, replacement, and navigation.
11. **Portable, inert import.** Validate complete archives before installation;
    preserve history, digest assets, rebuild local references, reject unsafe paths
    and collisions. Import/preview never evaluates code or prepares dependencies.
    Copy installation is explicit; secrets and live runtime state are excluded.
12. **Recoverable UI and operations.** Focused editors survive output updates;
    reconnect reconciles durable output. Startup checks dependencies; critical
    failures cannot leave a falsely healthy shell. Backups coordinate writes and
    use logical database dumps; restore is verified on a fresh volume.
