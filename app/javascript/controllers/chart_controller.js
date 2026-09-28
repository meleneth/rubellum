import { Controller } from "@hotwired/stimulus";
import palette from "../../../config/palettes/lospec500.json";

export default class extends Controller {
  static targets = ["frame", "status"];
  static values = {url: String, source: String};
  connect() {
    this.token = crypto.randomUUID(); this.active = false; this.ready = false; this.renderSequence = 0;
    this.receive = event => {
      if (!this.active || event.source !== this.frameTarget.contentWindow || event.data?.token !== this.token) return;
      if (event.data.type === "ready") { this.ready = true; this.refresh(); }
      if (event.data.type === "error" && event.data.renderId === this.renderSequence) this.statusTarget.textContent = `Renderer error: ${event.data.message}`;
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
    const renderId = ++this.renderSequence;
    this.request?.abort(); this.request = new AbortController();
    try {
      const response = await fetch(this.urlValue, {signal: this.request.signal});
      if (!response.ok) throw new Error(await response.text());
      const result = await response.json();
      if (!this.active || !this.ready || renderId !== this.renderSequence || !this.element.isConnected) return;
      const styles = getComputedStyle(document.documentElement);
      const color = token => styles.getPropertyValue(token).trim().toLowerCase()
        .replace(/^#([\da-f])([\da-f])([\da-f])$/, "#$1$1$2$2$3$3");
      const theme = {background: color("--panel"), foreground: color("--ink"), accent: color("--accent"), palette: palette.colors};
      this.frameTarget.contentWindow.postMessage({type: "render", token: this.token, renderId, source: this.sourceValue, data: result.data, inputs: result.inputs, width: this.frameTarget.clientWidth, height: this.frameTarget.clientHeight, theme}, "*");
      this.statusTarget.textContent = `${result.stale ? "Stale result · " : ""}Revision ${result.provenance.revision_id.slice(0, 8)}${result.provenance.execution_id ? ` · execution ${result.provenance.execution_id.slice(0, 8)}` : ""}`;
    } catch (error) { if (error.name !== "AbortError" && this.active && renderId === this.renderSequence) this.statusTarget.textContent = error.message; }
  }
  stop() { this.active = false; this.ready = false; this.request?.abort(); this.frameTarget.contentWindow?.postMessage({type: "dispose", token: this.token, renderId: ++this.renderSequence}, "*"); this.frameTarget.removeAttribute("src"); }
  disconnect() { this.stop(); this.observer.disconnect(); window.removeEventListener("message", this.receive); window.removeEventListener("rubellum:data", this.refresh); document.removeEventListener("turbo:before-cache", this.beforeCache); }
}
