# Working on Rubellum

Read `ruby-notebook-appliance-codex-prompt.md`, `IMPLEMENTATION_PLAN.md`, and
`CORE_INVARIANTS.md` before changing behavior. The build brief is the product
contract; the plan records progress, not a reduced scope.

- Make small, frequent commits, each with a coherent, reviewable change.
- Prefer Haml over ERB for Rails views. Use Haml for new templates and preserve
  normal HTML escaping; do not mark user-authored content safe indiscriminately.
- All tests must use RSpec. Add meaningful unit tests alongside behavior changes;
  cover invalid inputs, boundary conditions, and failure/recovery behavior.
- All mocks/doubles must verify the real interface: use `instance_double`,
  `class_double`, or `object_double`, never unverified `double` or `spy`. Keep
  `verify_partial_doubles` and `verify_doubled_constant_names` enabled. Load the
  real class before doubling it. Do not use `allow_any_instance_of` or
  `expect_any_instance_of`. Prefer plain Ruby objects with injected boundaries.
- Use FactoryBot for reusable test data. Keep factories small and valid by
  default; use explicit traits for meaningful variants. Prefer `build` or
  `attributes_for` for unit tests; use `create` when persistence is under test.
  Avoid hidden database writes and large implicit association graphs.
- Run the relevant tests before committing. Keep unit tests independent of
  Rails, PostgreSQL, and GoAWS where possible; use real services to verify their
  contracts. Never describe mocks as integration evidence.
- Record commands, actual results, and unverified acceptance criteria in the
  implementation plan. Keep the repository runnable at each checkpoint.
- Preserve unrelated work. Do not change the system's default toolchains.

## Strict color requirement

- Use only the official **Lospec500** palette for every project-defined color in
  every theme (including light/dark), component, editor/highlighter, chart starter,
  illustration and UI state. Source: https://lospec.com/palette-list/lospec500.
- Reuse shared semantic theme tokens. Do not introduce arbitrary hex/RGB/HSL
  values, default Tailwind palettes, gradients, opacity blends, or third-party
  theme colors outside Lospec500. Transparent surfaces, inheritance and
  `currentColor` are permitted; antialiasing is not a new authored color.
- The canonical list is `config/palettes/lospec500.json`; semantic tokens live in
  `app/assets/stylesheets/application.css`. Charts receive them through `theme`.
- Override third-party UI defaults and add RSpec palette/contrast regression
  coverage when changing themes or components. Keep bundled charts on the same
  theme tokens. Do not rewrite the owner's imported assets or notebook source
  merely to recolor existing content.

## Optional C/C++ toolchains

Prefer the repository's requested compiler. Only opt into these for an explicit
compiler requirement or newer-compiler verification; never use update-alternatives:

- GCC 16.2: `/opt/devastation/toolchains/gcc-16.2/bin/{gcc,g++}`
- Clang 22.1.6: `/opt/devastation/toolchains/clang-22.1.6/bin/{clang,clang++}`
