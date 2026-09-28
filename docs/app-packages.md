# App package format 1

The archive, full/current export and inert import services are implemented.
Public import/copy/export controls are still in progress; this is not a backup.

Packages use `.rubellum-app.tar.gz`: one gzip member containing regular USTAR
files. No directory entries, links, devices or extension headers are accepted.
Paths are canonical relative ASCII names (100 bytes maximum). The reader never
extracts paths to disk. It verifies header checksums, gzip integrity, terminators,
file padding, duplicate/conflicting paths and trailing data before returning.
Limits are 64 MiB compressed, 256 MiB expanded, 32 MiB per entry and 10,000 entries.
Validation is memory-bounded, not streaming installation; allow memory headroom
for the expanded archive, decoded manifest and Ruby object overhead.

`manifest.json` is UTF-8 JSON, at most 16 MiB, with no duplicate keys or unknown
fields. `Rubellum::PackageManifest` is the executable schema and reference
validator. Its top-level fields are:

| Field | Contract |
| --- | --- |
| `format_version`, `cell_api_version` | Both integer `1` |
| `mode` | `full` (default) or `current` |
| `app` | One owner object |
| `notebooks`, `cells` | Arrays of owner objects |
| `assets` | Asset metadata array |
| `files` | Path → `{sha256, size}` for every non-manifest file |

Owner objects contain `id` (portable UUID), `head` (revision UUID) and `revisions`.
Cells additionally contain `notebook_id` and `source_path`. Package identities
must be unique. A revision contains `id`, nullable `parent_id`, `title`,
`configuration`, `author`, `summary`, `provenance`, ISO-8601 `created_at`, and
`digest`. Cell revisions add `cell_type` and `source`; notebook revisions add
`description` and ordered `entries` (`cell_id`, `revision_id`); app revisions add
`description` and nullable `landing_notebook_id`.

Revision digests are SHA-256 over compact JSON with recursively sorted object
keys, excluding `digest` itself. These portable-content digests differ from
database digests, which incorporate local installation keys. Ancestry must be
acyclic and owner-local; heads, document entries, asset references, renderer
inputs and restore provenance must resolve. Invalid authored source remains
source: the validator does not run Ruby, JavaScript or a Gemfile.

Current source files live at `sources/<portable-cell-uuid>.<extension>` and must
match the selected revision's source exactly. Sources use `.md`, `.rb`, `.js`,
`.json` or `.csv`. Asset bytes live at `assets/<sha256>`; metadata includes `id`,
`filename`, `mime_type`, `sha256`, `byte_size` and `created_at`. Each asset is at
most 25 MiB. Equal bytes are stored once, even with multiple asset identities.
`asset://` and declared configuration references use portable UUIDs in packages.

Full export retains removed cells and every revision. Current-state export
contains only present cells and one parentless revision per owner; earlier
restore references become informational `source_revision` provenance. A current
renderer pointing at an excluded cell must be repaired before current export.
Both modes retain app assets, including unused uploads and artifact bytes.

Recorded executions are currently omitted. Artifacts export as ordinary immutable
assets without execution/event pointers. Sessions, queues, drafts, runtime
parameter values, journals, database files, instance secrets and dependency caches
are never serialized. Arbitrary secrets explicitly authored into source/config
remain authored content: review it before sharing. Custom dependency declarations
and explicit environment preparation are a separate, unfinished feature.

## Installation and recovery

The complete archive and manifest are validated before staging. A portable app
identity already present requires explicit import-as-copy; no merge or replacement
is performed. Each installation gets new local app/notebook/cell/revision/asset
IDs. Known asset, renderer, document and restore references are remapped. Imported
revisions retain timestamps, authors and summaries and record their source app
and revision in `provenance.imported_from`. Portable object identities survive.

Private staging is under `/data/apps/.imports/<new-installation-uuid>`. Import is
serialized by a local lock, publishes fsynced immutable files, and commits all
database records in one transaction. Only committed apps become visible. A
durable staging marker remains until commit; rollback removes only that new
installation. Startup (`bin/rails rubellum:prepare`) and subsequent imports recover
abandoned staging and remove uncommitted published files. Committed installations
are retained. A PostgreSQL transaction advisory lock fences recovery against a
commit still completing after its client dies. Installation must own its database
transaction; callers cannot nest it inside an uncommitted application transaction.

No import prepares dependencies, starts sessions, enqueues execution, renders
JavaScript or evaluates source. Recorded artifact bytes become ordinary assets.
