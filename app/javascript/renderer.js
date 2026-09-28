import * as d3 from "d3";

const token = new URLSearchParams(location.search).get("token");
let generation = 0, cleanup;
const dispose = () => {
  const previous = cleanup; cleanup = undefined;
  try { previous?.(); } finally { document.getElementById("chart").replaceChildren(); }
};
const report = (error, renderId) => {
  if (renderId === generation) parent.postMessage({type: "error", token, renderId, message: String(error?.message || error)}, "*");
};
window.addEventListener("message", async event => {
  if (event.source !== parent || !token || event.data?.token !== token || !["render", "dispose"].includes(event.data.type)) return;
  const current = event.data.renderId;
  if (!Number.isSafeInteger(current) || current <= generation) return;
  generation = current;
  try { dispose(); } catch (error) { report(error, current); }
  if (event.data.type === "dispose") return;
  try {
    const {source, data, inputs, width, height, theme} = event.data;
    if (typeof source !== "string" || !Number.isFinite(width) || !Number.isFinite(height) || !theme || typeof theme !== "object") throw new Error("Invalid renderer message");
    const element = document.createElement("div");
    element.style.color = theme.foreground; element.style.background = theme.background;
    document.getElementById("chart").replaceChildren(element);
    const render = new Function(`${source}\n;return render;`)();
    if (typeof render !== "function") throw new Error("Define async function render(context)");
    const release = await render({element, d3, data, inputs, width, height, theme});
    if (release !== undefined && typeof release !== "function") throw new Error("render must return a cleanup function or nothing");
    if (current !== generation) release?.(); else cleanup = release;
  } catch (error) { report(error, current); }
});
window.addEventListener("pagehide", () => { generation++; try { dispose(); } catch (_) { /* Frame is leaving. */ } });
parent.postMessage({type: "ready", token}, "*");
