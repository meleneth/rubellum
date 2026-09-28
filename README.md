# Rubellum

A personal Ruby notebook appliance, under active construction. The intended
deployment is one container with Rails, PostgreSQL, GoAWS, and persistent notebook
runners, storing all durable data in one `/data` volume.

The [build brief](ruby-notebook-appliance-codex-prompt.md) defines the full product.
The [implementation plan](IMPLEMENTATION_PLAN.md) tracks verified progress, and
[core invariants](CORE_INVARIANTS.md) record the guarantees tests must protect.

Build/run/test commands will be added with the working slices that implement
them. There is not yet a runnable appliance.
