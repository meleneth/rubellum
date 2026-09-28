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

Artifact persistence, app bundles, lifecycle ownership, durable messaging,
interrupt escalation and browser rendering are still separate implementation work.
There is no artifact helper pretending to persist files before that facility exists.
