import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["frame", "status"];
  static values = {url: String, source: String};
  connect() {
    this.token = crypto.randomUUID(); this.active = false; this.ready = false;
    this.receive = event => {
      if (event.source !== this.frameTarget.contentWindow || event.data?.token !== this.token) return;
      if (event.data.type === "ready") { this.ready = true; this.refresh(); }
      if (event.data.type === "error") this.statusTarget.textContent = `Renderer error: ${event.data.message}`;
    };
    this.refresh = this.refresh.bind(this);
    window.addEventListener("message", this.receive);
    window.addEventListener("rubellum:data", this.refresh);
    this.observer = new ResizeObserver(this.refresh); this.observer.observe(this.frameTarget);
    this.beforeCache = () => this.stop(); document.addEventListener("turbo:before-cache", this.beforeCache);
  }
  activate() { if (this.active) { this.refresh(); return; } this.active = true; this.frameTarget.src = `/renderer?token=${this.token}`; }
  async refresh() {
    if (!this.active || !this.ready) return;
    this.request?.abort(); this.request = new AbortController();
    try {
      const response = await fetch(this.urlValue, {signal: this.request.signal});
      if (!response.ok) throw new Error(await response.text());
      const result = await response.json();
      const theme = document.documentElement.dataset.theme === "dark" ? {background: "#161b22", foreground: "#e9edf2", accent: "#f6a66b"} : {background: "#ffffff", foreground: "#242d3a", accent: "#b64f29"};
      this.frameTarget.contentWindow.postMessage({type: "render", token: this.token, source: this.sourceValue, data: result.data, inputs: result.inputs, width: this.frameTarget.clientWidth, height: this.frameTarget.clientHeight, theme}, "*");
      this.statusTarget.textContent = `${result.stale ? "Stale result · " : ""}Revision ${result.provenance.revision_id.slice(0, 8)}${result.provenance.execution_id ? ` · execution ${result.provenance.execution_id.slice(0, 8)}` : ""}`;
    } catch (error) { if (error.name !== "AbortError") this.statusTarget.textContent = error.message; }
  }
  stop() { this.active = false; this.ready = false; this.request?.abort(); this.frameTarget.contentWindow?.postMessage({type: "dispose", token: this.token}, "*"); this.frameTarget.removeAttribute("src"); }
  disconnect() { this.stop(); this.observer.disconnect(); window.removeEventListener("message", this.receive); window.removeEventListener("rubellum:data", this.refresh); document.removeEventListener("turbo:before-cache", this.beforeCache); }
}
