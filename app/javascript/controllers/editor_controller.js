import { Controller } from "@hotwired/stimulus";
import { basicSetup, EditorView } from "codemirror";
import { StreamLanguage } from "@codemirror/language";
import { ruby } from "@codemirror/legacy-modes/mode/ruby";
import { javascript } from "@codemirror/lang-javascript";
import { json } from "@codemirror/lang-json";
import { markdown } from "@codemirror/lang-markdown";

export default class extends Controller {
  static targets = ["source", "mount", "identity", "status", "recover"];
  static values = {language: String, draftUrl: String};
  connect() {
    this.identityTarget.value = sessionStorage.getItem("rubellum:editor") || crypto.randomUUID();
    sessionStorage.setItem("rubellum:editor", this.identityTarget.value);
    this.cacheKey = `${this.draftUrlValue}:${this.identityTarget.value}`;
    const languages = {ruby: () => StreamLanguage.define(ruby), markdown, d3: javascript, data: json, parameters: json};
    let language = languages[this.languageValue]?.() || [];
    try { if (JSON.parse(this.element.elements.configuration.value).format === "csv") language = []; } catch (_) {}
    this.view = new EditorView({doc: this.sourceTarget.value, parent: this.mountTarget, extensions: [basicSetup, language,
      EditorView.updateListener.of(update => { if (update.docChanged) this.changed(); }),
      EditorView.contentAttributes.of({"aria-label": "Cell source"})]});
    this.sourceTarget.hidden = true;
    this.onInput = event => { if (!event.target.closest(".cm-editor")) this.changed(); };
    this.element.addEventListener("input", this.onInput);
    this.onSubmitEnd = event => {
      if (event.detail.success) sessionStorage.removeItem(this.cacheKey);
    };
    this.element.addEventListener("turbo:submit-end", this.onSubmitEnd);
    this.beforeCache = () => this.teardown();
    document.addEventListener("turbo:before-cache", this.beforeCache);
    this.loadDraft();
  }
  snapshot() {
    this.sourceTarget.value = this.view.state.doc.toString();
    return Object.fromEntries(new FormData(this.element));
  }
  changed() {
    this.dirty = true;
    this.statusTarget.textContent = "Unsaved changes";
    const draft = this.snapshot();
    sessionStorage.setItem(this.cacheKey, JSON.stringify(draft));
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.saveDraft(draft), 600);
  }
  async saveDraft(draft) {
    // Serialize writes so an older response can never overwrite a newer draft.
    this.pending = draft;
    if (this.saving) return;
    this.saving = true;
    while (this.pending && this.element.isConnected) {
      const next = this.pending;
      this.pending = null;
      try {
        const response = await fetch(this.draftUrlValue, {method: "PUT", headers: {"Content-Type": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""}, body: JSON.stringify(next)});
        if (!response.ok) throw new Error(await response.text());
        if (!this.pending) this.statusTarget.textContent = "Draft saved · not a committed revision";
      } catch (_) { this.statusTarget.textContent = "Draft kept in this tab · server save failed"; }
    }
    this.saving = false;
  }
  async loadDraft() {
    try {
      const cached = sessionStorage.getItem(this.cacheKey);
      const response = await fetch(`${this.draftUrlValue}?editor_id=${this.identityTarget.value}`);
      const draft = cached ? JSON.parse(cached) : (response.ok ? await response.json() : {});
      const configuration = typeof draft.configuration === "string" ? JSON.parse(draft.configuration) : draft.configuration;
      if (!this.dirty && draft.source !== undefined && (draft.source !== this.sourceTarget.value || draft.title !== this.element.elements.title.value || draft.cell_type !== this.element.elements.cell_type.value || JSON.stringify(configuration) !== JSON.stringify(JSON.parse(this.element.elements.configuration.value)))) {
        this.draft = draft;
        this.recoverTarget.classList.remove("hidden");
        this.statusTarget.textContent = "A recoverable draft is available";
      }
    } catch (_) { this.statusTarget.textContent = "Draft recovery unavailable; editing still works"; }
  }
  recover() {
    const draft = this.draft;
    for (const name of ["title", "cell_type"]) this.element.elements[name].value = draft[name];
    this.element.elements.configuration.value = typeof draft.configuration === "string" ? draft.configuration : JSON.stringify(draft.configuration, null, 2);
    this.element.elements.expected_revision.value = draft.base_revision_id || draft.expected_revision;
    this.view.dispatch({changes: {from: 0, to: this.view.state.doc.length, insert: draft.source}});
    this.changed();
    this.recoverTarget.classList.add("hidden");
  }
  prepare() { this.snapshot(); clearTimeout(this.timer); }
  teardown() {
    if (!this.view) return;
    this.sourceTarget.value = this.view.state.doc.toString();
    this.view.destroy(); this.view = null;
    this.sourceTarget.hidden = false;
    clearTimeout(this.timer);
  }
  disconnect() { this.teardown(); this.element.removeEventListener("input", this.onInput); this.element.removeEventListener("turbo:submit-end", this.onSubmitEnd); document.removeEventListener("turbo:before-cache", this.beforeCache); }
}
