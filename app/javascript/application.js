import "@hotwired/turbo-rails";
import { Application, Controller } from "@hotwired/stimulus";
import EditorController from "./controllers/editor_controller";
import TableController from "./controllers/table_controller";
import ChartController from "./controllers/chart_controller";

const app = Application.start();
app.register("editor", EditorController);
app.register("table", TableController);
app.register("chart", ChartController);
export const dataChanged = () => window.dispatchEvent(new Event("rubellum:data"));

app.register("theme", class extends Controller {
  connect() { document.documentElement.dataset.theme = localStorage.getItem("rubellum:theme") || "light"; }
  toggle() {
    const theme = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
    document.documentElement.dataset.theme = theme;
    localStorage.setItem("rubellum:theme", theme);
    dataChanged();
  }
});
app.register("presentation", class extends Controller {
  toggle() { this.element.classList.toggle("presenting"); window.dispatchEvent(new Event("resize")); }
});
app.register("parameters", class extends Controller {
  static targets = ["status"];
  async update(event) {
    event.preventDefault();
    this.request?.abort();
    this.request = new AbortController();
    try {
      const response = await fetch(this.element.action, {method: "PATCH", body: new FormData(this.element), signal: this.request.signal});
      if (!response.ok) throw new Error(await response.text());
      this.statusTarget.textContent = "Inputs updated. Ruby runs only when requested.";
      dataChanged();
    } catch (error) { if (error.name !== "AbortError") this.statusTarget.textContent = error.message; }
  }
  disconnect() { this.request?.abort(); }
});
app.register("output", class extends Controller {
  static values = {url: String};
  connect() {
    this.refresh = this.refresh.bind(this);
    this.timer = setInterval(this.refresh, 2000);
    window.addEventListener("online", this.refresh);
    this.refresh();
  }
  async refresh() {
    if (this.loading || !this.element.isConnected) return;
    this.loading = true;
    this.request = new AbortController();
    try {
      const response = await fetch(this.urlValue, {signal: this.request.signal});
      if (!response.ok) return;
      const html = await response.text();
      if (this.previous !== html) {
        this.element.innerHTML = html;
        this.previous = html;
        dataChanged();
      }
    } catch (error) { if (error.name !== "AbortError") this.element.dataset.disconnected = "true"; }
    finally { this.loading = false; }
  }
  disconnect() { clearInterval(this.timer); this.request?.abort(); window.removeEventListener("online", this.refresh); }
});

document.addEventListener("turbo:before-stream-render", event => {
  const original = event.detail.render;
  event.detail.render = async stream => { await original(stream); dataChanged(); };
});
