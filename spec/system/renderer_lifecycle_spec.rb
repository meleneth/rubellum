require "rails_helper"
require_relative "../support/chrome"

RSpec.describe "D3 lifecycle in Chrome", type: :system do
  before { driven_by :rubellum_chrome }
  let(:notebook) { create(:notebook) }

  def add(type, source: CellTemplates.source(type), configuration: {})
    History.new(notebook).add_cell(cell_type: type, source:, configuration:,
      expected_notebook_revision: notebook.reload.head_revision_id)
  end

  def activate(source)
    producer = add("data")
    add("parameters")
    chart = add("d3", source:, configuration: { "input" => { "cell_id" => producer.id } })
    visit app_notebook_path(notebook.app, notebook)
    within("#cell-#{chart.id}") { click_button "Render chart" }
    @frame = find("#cell-#{chart.id} iframe")
    @chart_id = chart.id
    within_frame(@frame) { expect(page).to have_content("Scale 1") }
  end

  def scale(value)
    find('input[type="range"]').set(value)
    within_frame(@frame) { expect(page).to have_content("Scale #{value}") }
  end

  it "ignores obsolete asynchronous failures instead of overwriting a newer successful chart" do
    activate(<<~JS)
      async function render({element, inputs}) {
        element.textContent = `Scale ${inputs.scale}`;
        if (inputs.scale === 1) await new Promise((resolve, reject) => {
          (window.oldRejectors ||= []).push(reject);
        });
      }
    JS
    scale(2)
    page.execute_script(<<~JS)
      window.addEventListener("message", event => {
        if (event.data?.type === "test-checkpoint") document.body.dataset.rendererCheckpoint = "done";
      });
    JS
    within_frame(@frame) do
      page.execute_script(<<~JS)
        window.oldRejectors.forEach(reject => reject(new Error("Obsolete render failed")));
        // This task follows promise rejection handlers. Same-sender messages
        // arrive in order, so the parent checkpoint follows any error message.
        setTimeout(() => parent.postMessage({type: "test-checkpoint"}, "*"), 0);
      JS
    end
    expect(page).to have_css('body[data-renderer-checkpoint="done"]')
    within("#cell-#{@chart_id}") do
      expect(page).not_to have_content("Obsolete render failed")
      expect(page).to have_css('[data-chart-target="status"]', text: "Revision")
    end
    within_frame(@frame) { expect(page).to have_content("Scale 2") }
    expect(Execution.count).to eq(0)
  end

  it "releases late obsolete renders and cleans the current renderer before replacement" do
    activate(<<~JS)
      async function render({element, inputs}) {
        const value = inputs.scale;
        element.textContent = `Scale ${value}`;
        if (value === 1) await new Promise(resolve => (window.oldResolvers ||= []).push(resolve));
        return () => {
          const chart = document.getElementById("chart");
          chart.dataset[`released${value}`] = Number(chart.dataset[`released${value}`] || 0) + 1;
        };
      }
    JS
    scale(2)
    within_frame(@frame) do
      count = page.evaluate_script("window.oldResolvers.length")
      page.execute_script("window.oldResolvers.forEach(resolve => resolve())")
      expect(page).to have_css("#chart[data-released1='#{count}']")
      expect(page).to have_content("Scale 2")
    end
    scale(3)
    within_frame(@frame) { expect(page).to have_css("#chart[data-released2]") }
  end

  it "rejects wrong-frame/token/obsolete errors while showing current exceptions and recovering" do
    activate(<<~JS)
      async function render({element, inputs}) {
        element.textContent = `Scale ${inputs.scale}`;
        if (inputs.scale === 3) throw null;
      }
    JS
    within_frame(@frame) do
      page.execute_script('window.addEventListener("message", event => { if (event.data?.type === "render") window.latestRenderId = event.data.renderId; })')
    end
    scale(2)
    render_id = within_frame(@frame) { page.evaluate_script("window.latestRenderId") }
    page.execute_script(<<~JS, render_id)
      window.addEventListener("message", event => {
        if (event.data?.type === "test-checkpoint") document.body.dataset.rendererCheckpoint = "done";
      });
      const frame = document.querySelector("#cell-#{@chart_id} iframe");
      const token = new URL(frame.src).searchParams.get("token");
      window.postMessage({type: "error", token, renderId: arguments[0], message: "Wrong frame error"}, "*");
    JS
    within_frame(@frame) do
      page.execute_script(<<~JS)
        const token = new URLSearchParams(location.search).get("token");
        parent.postMessage({type: "error", token: "wrong-token", renderId: window.latestRenderId, message: "Wrong token error"}, "*");
        parent.postMessage({type: "error", token, renderId: window.latestRenderId - 1, message: "Old queued error"}, "*");
        parent.postMessage({type: "test-checkpoint"}, "*");
      JS
    end
    expect(page).to have_css('body[data-renderer-checkpoint="done"]')
    within("#cell-#{@chart_id}") do
      expect(page).not_to have_content("Wrong frame error")
      expect(page).not_to have_content("Wrong token error")
      expect(page).not_to have_content("Old queued error")
    end
    scale(3)
    expect(page).to have_content("Renderer error: null")
    scale(4)
    within("#cell-#{@chart_id}") { expect(page).to have_css('[data-chart-target="status"]', text: /\ARevision/) }
  end

  it "clears the old chart and runs its replacement even when authored cleanup throws" do
    activate(<<~JS)
      async function render({element, inputs}) {
        element.textContent = `Scale ${inputs.scale}`;
        return () => { if (inputs.scale === 1) throw new Error("Cleanup failed"); };
      }
    JS
    scale(2)
    expect(page).to have_content("Renderer error: Cleanup failed")
    within_frame(@frame) { expect(page).not_to have_content("Scale 1") }
    scale(3)
    within("#cell-#{@chart_id}") { expect(page).to have_css('[data-chart-target="status"]', text: /\ARevision/) }
  end

  it "refreshes dimensions and theme and releases authored resources on Turbo navigation" do
    activate(<<~JS)
      async function render({element, inputs, width, theme}) {
        element.textContent = `Scale ${inputs.scale}`;
        element.dataset.width = width;
        element.dataset.background = theme.background;
        const timer = setInterval(() => element.dataset.tick = Number(element.dataset.tick || 0) + 1, 20);
        return () => { clearInterval(timer); parent.postMessage({type: "test-cleanup"}, "*"); };
      }
    JS
    page.execute_script(<<~JS)
      document.documentElement.dataset.rendererCleanups = "0";
      window.addEventListener("message", event => {
        if (event.data?.type === "test-cleanup") {
          const root = document.documentElement;
          root.dataset.rendererCleanups = Number(root.dataset.rendererCleanups || 0) + 1;
        }
      });
      document.querySelector("#cell-#{@chart_id} iframe").style.width = "410px";
    JS
    background = within_frame(@frame) do
      expect(page).to have_css('#chart > div[data-width="410"]')
      find("#chart > div")["data-background"]
    end
    find('button[aria-label="Toggle light and dark theme"]').click
    within_frame(@frame) do
      next_background = background == "#ffffff" ? "#161b22" : "#ffffff"
      expect(page).to have_css("#chart > div[data-background='#{next_background}']")
    end
    released = page.evaluate_script("document.documentElement.dataset.rendererCleanups")
    click_link "App library"
    expect(page).to have_content("Your Ruby notebooks")
    expect(page).to have_css("html[data-renderer-cleanups]:not([data-renderer-cleanups='#{released}'])")
    expect(Execution.count).to eq(0)
  end
end
