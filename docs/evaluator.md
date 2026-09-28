# Ruby evaluator

The evaluator is a clean `exec` of the pinned Ruby interpreter in the notebook's
workspace. It does not boot Rails or Bundler, and inherits only an explicit PATH
and locale. An anonymous Ruby context retains locals, methods, and required
libraries across calls. Different evaluator processes own different contexts.

The agent's command and result pipes use separate file descriptors from actual
stdout/stderr. Output is read in 4 KiB chunks, capped at 1 MiB per execution, with
one visible truncation event. Return inspection is separate and capped at 16 KiB.
Abrupt evaluator exit raises an unknown-outcome error; it does not replay source.
Ruby exceptions and syntax errors include cell identities and local line numbers.

Implemented helper methods:

- `Notebook.inputs`: immutable JSON object snapshot.
- `Notebook.dataset(name)`: explicitly supplied immutable dataset; missing names
  raise `KeyError`.
- `Notebook.emit(name, data:)`: strict JSON-compatible named output, at most
  16 KiB per inline output. Arbitrary Ruby objects and nonfinite numbers fail.
- `Notebook.display(text, mime: "text/plain")`: bounded text display.
- `Notebook.asset(path, mime: nil)`: copy a regular relative workspace file into
  immutable app storage and emit a durable artifact reference. Returns a frozen
  object with filename, declared/inferred MIME, and SHA-256/size blob reference.
  Rails verifies bytes and determines the served MIME independently. Traversal,
  absolute paths and symlinks are rejected. Limits: 25 MiB/file, 32 files and
  100 MiB/execution; all app blobs share a 512 MiB quota. Rewriting a scratch
  filename does not change existing artifacts. No retained content is evicted.

The manager owns agents; an agent owns the clean evaluator and fsynced journal.
Commands/results cross SQS in both directions. Interrupts have a two-second grace
period before evaluator process-group termination. Lost state is not replayed.
Run all batches stop after failure/interruption; later explicit runs are separate.

Custom app bundles are not yet implemented. The clean evaluator can use Ruby's
available standard/default libraries; gems loaded
by Rails are not automatically available to notebook code.
