# Working on Rubellum

Read `ruby-notebook-appliance-codex-prompt.md`, `IMPLEMENTATION_PLAN.md`, and
`CORE_INVARIANTS.md` before changing behavior. The build brief is the product
contract; the plan records progress, not a reduced scope.

- Make small, frequent commits, each with a coherent, reviewable change.
- All tests must use RSpec. Add meaningful unit tests alongside behavior changes;
  cover invalid inputs, boundary conditions, and failure/recovery behavior.
- All mocks/doubles must verify the real interface: use `instance_double`,
  `class_double`, or `object_double`, never unverified `double` or `spy`. Keep
  `verify_partial_doubles` and `verify_doubled_constant_names` enabled. Load the
  real class before doubling it. Do not use `allow_any_instance_of` or
  `expect_any_instance_of`. Prefer plain Ruby objects with injected boundaries.
- Run the relevant tests before committing. Keep unit tests independent of
  Rails, PostgreSQL, and GoAWS where possible; use real services to verify their
  contracts. Never describe mocks as integration evidence.
- Record commands, actual results, and unverified acceptance criteria in the
  implementation plan. Keep the repository runnable at each checkpoint.
- Preserve unrelated work. Do not change the system's default toolchains.

## Optional C/C++ toolchains

Prefer the repository's requested compiler. Only opt into these for an explicit
compiler requirement or newer-compiler verification; never use update-alternatives:

- GCC 16.2: `/opt/devastation/toolchains/gcc-16.2/bin/{gcc,g++}`
- Clang 22.1.6: `/opt/devastation/toolchains/clang-22.1.6/bin/{clang,clang++}`
