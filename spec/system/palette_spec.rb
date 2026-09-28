require "rails_helper"
require_relative "../support/chrome"

RSpec.describe "Lospec500 themes in Chrome", type: :system do
  before { driven_by :rubellum_chrome }
  let(:notebook) { create(:notebook) }
  let(:palette) { JSON.parse(File.read(Rails.root.join("config/palettes/lospec500.json"))).fetch("colors") }

  def add(type, source: CellTemplates.source(type), configuration: {})
    History.new(notebook).add_cell(cell_type: type, source:, configuration:,
      expected_notebook_revision: notebook.reload.head_revision_id)
  end

  def palette_violations
    page.evaluate_script(<<~JS, palette)
      ((palette) => {
        const allowed = new Set(palette.map(hex => `rgb(${[1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16)).join(", ")})`));
        allowed.add("rgba(0, 0, 0, 0)");
        const violations = [];
        for (const element of document.body.querySelectorAll("*")) {
          if (!element.getClientRects().length || element.closest("svg")) continue;
          const style = getComputedStyle(element);
          const properties = ["color", "backgroundColor"];
          for (const edge of ["Top", "Right", "Bottom", "Left"]) {
            if (parseFloat(style[`border${edge}Width`]) > 0) properties.push(`border${edge}Color`);
          }
          if (parseFloat(style.outlineWidth) > 0) properties.push("outlineColor");
          if (element.isContentEditable) properties.push("caretColor");
          for (const property of properties) {
            if (!allowed.has(style[property])) violations.push(`${element.tagName}.${element.className} ${property}: ${style[property]}`);
          }
          if (style.backgroundImage !== "none") violations.push(`${element.className} backgroundImage: ${style.backgroundImage}`);
        }
        return [...new Set(violations)];
      })(arguments[0])
    JS
  end

  it "uses palette colors for light/dark UI, syntax, focused selections, search and chart rendering" do
    ruby = add("ruby", source: "# A comment\nvalue = 42\nputs \"hello\"\nvalue")
    add("markdown", source: "```ruby\n# A comment\nvalue = 42\nputs \"hello\"\n```")
    add("parameters")
    data = add("data")
    add("table", configuration: { "input" => { "cell_id" => data.id } })
    chart = add("d3", configuration: { "input" => { "cell_id" => data.id } })
    execution = ExecutionRequests.submit(notebook:, cell_id: ruby.id, expected_revision: ruby.head_revision_id)
    execution.update!(status: "failed", result: { "error_class" => "RuntimeError", "message" => "Visible error" })
    visit app_notebook_path(notebook.app, notebook)
    expect(page).to have_css(".error", text: "Visible error")
    within("#cell-#{chart.id}") { click_button "Render chart" }
    frame = find("#cell-#{chart.id} iframe")
    editor = find("#cell-#{ruby.id} .cm-content")
    editor.click
    editor.send_keys([:control, "a"])
    expect(page).to have_css(".cm-selectionBackground")
    editor.send_keys([:control, "f"])
    find('.cm-search input[name="search"]').set("value")
    expect(page).to have_css(".cm-searchMatch")
    page.execute_script("window.paletteEditor = document.querySelector('#cell-#{ruby.id} .cm-content')")

    %w[light dark light].each do |theme|
      if page.evaluate_script("document.documentElement.dataset.theme") != theme
        find('button[aria-label="Toggle light and dark theme"]').click
      end
      expect(page).to have_css("html[data-theme='#{theme}']")
      expect(palette_violations).to eq([])
      tokens = page.evaluate_script(<<~JS)
        ["--panel", "--ink", "--accent"].map(token => getComputedStyle(document.documentElement).getPropertyValue(token).trim())
      JS
      tokens.map! { |color| color.size == 4 ? "##{color.delete_prefix('#').chars.map { |char| char * 2 }.join}" : color }
      within_frame(frame) do
        expect(page).to have_css("svg rect[fill='#{tokens[2]}']")
        expect(page).to have_css("svg text[fill='#{tokens[1]}']")
        body_background = page.evaluate_script("getComputedStyle(document.body).backgroundColor")
        channels = tokens[0].delete_prefix("#").scan(/../).map { |value| value.to_i(16) }
        expect(body_background).to eq("rgb(#{channels.join(', ')})")
      end
      expect(page.evaluate_script("window.paletteEditor === document.querySelector('#cell-#{ruby.id} .cm-content')")).to be(true)
    end
  end

  it "themes the autocomplete popup and selected suggestion in both modes" do
    cell = add("d3", source: "const banana = 42;\nban")
    visit app_notebook_path(notebook.app, notebook)
    within("#cell-#{cell.id}") { find("summary", text: "Edit source", exact_text: true).click }
    editor = find("#cell-#{cell.id} .cm-content")
    %w[light dark].each do |theme|
      if page.evaluate_script("document.documentElement.dataset.theme") != theme
        find('button[aria-label="Toggle light and dark theme"]').click
      end
      editor.click
      editor.send_keys([:control, :end], [:control, :space])
      expect(page).to have_css(".cm-tooltip-autocomplete li[aria-selected='true']")
      expect(palette_violations).to eq([])
      editor.send_keys(:escape)
    end
  end
end
