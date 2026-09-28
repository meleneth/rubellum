import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["filter", "status", "content"];
  static values = {url: String};
  connect() { this.page = 0; this.reload = this.reload.bind(this); window.addEventListener("rubellum:data", this.reload); this.reload(); }
  disconnect() { this.request?.abort(); window.removeEventListener("rubellum:data", this.reload); }
  async reload() {
    this.request?.abort(); this.request = new AbortController();
    try {
      const response = await fetch(this.urlValue, {signal: this.request.signal});
      if (!response.ok) throw new Error(await response.text());
      const result = await response.json();
      if (!Array.isArray(result.data) || result.data.some(row => row === null || typeof row !== "object")) throw new Error("Tables need an array of rows (objects or arrays).");
      this.rows = result.data;
      this.columns = [...new Set(this.rows.flatMap(Object.keys))];
      this.provenance = `${result.stale ? "Stale result · " : ""}Revision ${result.provenance.revision_id.slice(0, 8)}${result.provenance.execution_id ? ` · execution ${result.provenance.execution_id.slice(0, 8)}` : ""}`;
      this.render();
    } catch (error) { if (error.name !== "AbortError") { this.statusTarget.textContent = error.message; this.contentTarget.replaceChildren(); this.rows = []; } }
  }
  filtered() {
    const query = this.filterTarget.value.toLowerCase();
    const rows = (this.rows || []).filter(row => JSON.stringify(row).toLowerCase().includes(query));
    if (this.sortKey !== undefined) rows.sort((a, b) => (typeof a[this.sortKey] === "number" && typeof b[this.sortKey] === "number" ? a[this.sortKey] - b[this.sortKey] : String(a[this.sortKey] ?? "").localeCompare(String(b[this.sortKey] ?? ""), undefined, {numeric: true})) * this.direction);
    return rows;
  }
  render() {
    const rows = this.filtered(); this.page = Math.min(this.page, Math.max(0, Math.ceil(rows.length / 50) - 1));
    const table = document.createElement("table"), head = table.createTHead().insertRow();
    for (const column of this.columns || []) {
      const th = document.createElement("th"), button = document.createElement("button");
      button.textContent = column; button.type = "button";
      button.onclick = () => { this.direction = this.sortKey === column ? -this.direction : 1; this.sortKey = column; this.render(); };
      th.append(button); head.append(th);
    }
    const body = table.createTBody();
    for (const row of rows.slice(this.page * 50, (this.page + 1) * 50)) {
      const tr = body.insertRow();
      for (const column of this.columns) { const value = row[column]; tr.insertCell().textContent = typeof value === "object" ? JSON.stringify(value) : String(value ?? ""); }
    }
    this.contentTarget.replaceChildren(table);
    this.statusTarget.textContent = `${rows.length} rows · page ${this.page + 1} of ${Math.max(1, Math.ceil(rows.length / 50))} · ${this.provenance}`;
  }
  filter() { this.page = 0; this.render(); }
  previous() { this.page = Math.max(0, this.page - 1); this.render(); }
  next() { this.page++; this.render(); }
  download(content, type, name) { const url = URL.createObjectURL(new Blob([content], {type})); const link = document.createElement("a"); link.href = url; link.download = name; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000); }
  json() { this.download(JSON.stringify(this.filtered(), null, 2), "application/json", "table.json"); }
  csv() {
    const quote = value => `"${String(typeof value === "object" ? JSON.stringify(value) : value ?? "").replaceAll('"', '""')}"`;
    const rows = [this.columns || [], ...this.filtered().map(row => this.columns.map(column => row[column]))];
    this.download(rows.map(row => row.map(quote).join(",")).join("\r\n"), "text/csv", "table.csv");
  }
}
