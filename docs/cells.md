# Cells and renderer API

Cell source, type, title, and configuration belong to immutable revisions.
Editing creates a recoverable draft; explicit Save revision commits it. History
restore copies historical content into a new revision and preserves provenance.

## Files and images

The app's **Files and images** page uploads immutable assets (25 MiB per file,
512 MiB shared app quota). A replacement upload has a new asset identity; old
references keep the old bytes. Markdown uses `![Alt text](asset://ASSET-UUID)`
or `[Download](asset://ASSET-UUID)`. References must belong to the current app;
both model validation and SQL triggers enforce this. Only raster images are
served inline; other files are sandboxed attachments with nosniff headers.

**Import Markdown or data** accepts UTF-8 `.md`, JSON, and CSV source up to 1 MiB.
The chosen format is explicit, data is validated before installation, and the
original upload is retained in the revision's `configuration.asset_ids` list.
CSV imports record delimiter/header/blank-line choices. Imports never evaluate
Ruby or JavaScript. **Export source** downloads the exact selected revision;
table cells export their configuration.

Markdown's **Edit source** section offers **Edit Markdown**, **Preview Markdown**
and **Split Markdown**. The split view stacks on narrow screens. Preview renders
the current draft with the same sanitization, highlighting and app-asset scoping
as saved Markdown. It does not create revisions or execute code; ordinary draft
autosave remains separate. The labeled saved rendering stays unchanged until
Save revision. Mode switches preserve CodeMirror and its undo history. Requests
are debounced, cancelled and fenced so obsolete responses cannot replace a newer
draft preview.

## Data and parameters

Data cells default to JSON. CSV configuration is explicit:

```json
{ "format": "csv", "name": "measurements", "delimiter": ",", "headers": true, "skip_blanks": true }
```

Header names must be present and unique and each row must match their width.
CSV values remain strings; Rubellum does not guess numeric types. With headers
disabled, the result is an array of arrays. `Notebook.dataset("measurements")`
receives the dataset captured when the Ruby run was requested. Without `name`,
the data cell's UUID is used as the dataset name. Names must be unique per notebook.

Parameter source is a JSON array, for example:

```json
[
  { "name": "scale", "type": "slider", "label": "Scale", "default": 1, "min": 0, "max": 5 },
  { "name": "caption", "type": "text", "default": "Measurements" },
  { "name": "visible", "type": "boolean", "default": true },
  { "name": "color", "type": "select", "options": ["orange", "blue"], "default": "orange" }
]
```

`number` also supports `min`/`max`; number and slider inputs must be finite.
Text is limited to 4 KiB. Names must match `[a-zA-Z_][a-zA-Z0-9_]*` and be unique
across the notebook. Current values are separate from definition revisions.
Changing values does not execute Ruby. Execution snapshots remain unchanged.

## Explicit renderer bindings

Table and D3 configuration names a stable producer cell identity within the app:

```json
{ "input": { "cell_id": "PRODUCER-UUID", "output": "rows" } }
```

For a Data producer, the selected current data revision is parsed. For Ruby,
`output` selects an emitted name from the latest successful execution; its default
is `rows`. A newer unsuccessful execution or edited source marks the retained
successful result stale. Provenance displays the actual revision and, for Ruby,
execution identity. Parameter changes alone do not mark Ruby outputs recomputed.
Missing/unavailable inputs are errors, not empty successful datasets.

Tables accept arrays of objects or arrays, show 50 rows per page, and support
sorting, text filtering, and download of the filtered view. CSV downloads contain
original values, including any spreadsheet formulas in user data; treat imported
data accordingly before opening it in a spreadsheet.

## D3 contract

```javascript
async function render({ element, d3, data, inputs, width, height, theme }) {
  const svg = d3.select(element).append("svg")
    .attr("viewBox", [0, 0, width, height]);
  svg.append("text").attr("x", 16).attr("y", 32)
    .attr("fill", theme.foreground).text(inputs.caption || "Hello");
  return () => svg.remove();
}
```

Source defines `render`; it may return nothing or a cleanup function. `theme`
contains `background`, `foreground`, and `accent` semantic colors, plus `palette`,
the complete 42-color Lospec500 array. Use these colors for built-in charts in
both light and dark themes. D3 and the bootstrap
are bundled locally. Renderer source is never evaluated in the main editor page.

The iframe has `sandbox="allow-scripts"`, without same-origin access. Messages
check the sending frame, a per-frame random token, and the current render request
identifier. It activates only through
Render chart; historical previews remain inert. Active charts refresh on inputs,
output notifications, resize, and theme changes. Cleanup runs on replacement or
navigation; obsolete async results release their cleanup when they finish.
Obsolete promise failures cannot overwrite a newer render's status. A cleanup
exception is shown locally but does not prevent rendering the replacement chart.
Authored timers/simulations/listeners must be stopped by the authored cleanup
function. Exceptions are shown at the cell, not injected as page HTML.

This boundary is intended for trusted-owner code, not hostile-code isolation.
Chrome tests cover obsolete async success/failure, message identity checks,
cleanup exceptions, resize/theme refresh and Turbo navigation cleanup. A hard
bound on renderer CPU is not implemented; user code must yield to the browser.
