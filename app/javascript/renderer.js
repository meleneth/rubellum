import * as d3 from "d3";

const token = new URLSearchParams(location.search).get("token");
let generation = 0, cleanup;
const dispose = () => { generation++; const previous = cleanup; cleanup = undefined; previous?.(); document.getElementById("chart").replaceChildren(); };
window.addEventListener("message", async event => {
  if (event.source !== parent || !token || event.data?.token !== token || !["render", "dispose"].includes(event.data.type)) return;
  try {
    dispose();
    if (event.data.type === "dispose") return;
    const {source, data, inputs, width, height, theme} = event.data;
    if (typeof source !== "string" || !Number.isFinite(width) || !Number.isFinite(height) || !theme || typeof theme !== "object") throw new Error("Invalid renderer message");
    const current = generation, element = document.createElement("div");
    element.style.color = theme.foreground; element.style.background = theme.background;
    document.getElementById("chart").replaceChildren(element);
    const render = new Function(`${source}\n;return render;`)();
    if (typeof render !== "function") throw new Error("Define async function render(context)");
    const release = await render({element, d3, data, inputs, width, height, theme});
    if (release !== undefined && typeof release !== "function") throw new Error("render must return a cleanup function or nothing");
    if (current !== generation) release?.(); else cleanup = release;
  } catch (error) { parent.postMessage({type: "error", token, message: String(error.message || error)}, "*"); }
});
window.addEventListener("pagehide", dispose);
parent.postMessage({type: "ready", token}, "*");
