require "rails_helper"
require "capybara/rspec"
require "capybara/cuprite"
require "base64"

Capybara.register_driver(:rubellum_chrome) do |application|
  Capybara::Cuprite::Driver.new(application, window_size: [1400, 1000], timeout: 10,
    browser_path: ENV.fetch("CHROME_BIN", "/usr/bin/google-chrome"),
    url_whitelist: [%r{\Ahttps?://(127\.0\.0\.1|localhost)(:|/)}])
end

RSpec.describe "Authoring in Chrome", type: :system do
  before { driven_by :rubellum_chrome }
  let(:notebook) { create(:notebook) }

  def add_cell(type, source: CellTemplates.source(type), configuration: {})
    History.new(notebook).add_cell(cell_type: type, source:, configuration:,
      expected_notebook_revision: notebook.reload.head_revision_id)
  end

  it "creates an app, edits real highlighted Ruby, saves and recovers a separate draft" do
    visit root_path
    fill_in "New app name", with: "Browser research"
    click_button "Create app"
    expect(page).to have_content("Welcome")
    select "Ruby", from: "Add a cell"
    click_button "+ Add cell"
    expect(page).to have_css(".cm-editor", count: 1)
    editor = find(".cm-content")
    editor.click
    editor.send_keys([:control, "a"], "answer = 42")
    expect(page).to have_content("Draft saved · not a committed revision")
    page.refresh
    click_button "Recover draft"
    expect(page).to have_css(".cm-content", text: "answer = 42")
    click_button "Save revision"
    expect(page).to have_css(".cm-content", text: "answer = 42")
    expect(Cell.last.head_revision.source).to eq("answer = 42")
    expect(Cell.last.revisions.count).to eq(2)
    expect(page).not_to have_button("Recover draft")
  end

  it "renders local Markdown, sortable data and programmable D3 with input refresh" do
    add_cell("markdown", source: "# Measurements\n\n```ruby\nputs 42\n```")
    producer = add_cell("data")
    add_cell("parameters")
    table = add_cell("table", configuration: { "input" => { "cell_id" => producer.id } })
    chart = add_cell("d3", configuration: { "input" => { "cell_id" => producer.id } })
    visit app_notebook_path(notebook.app, notebook)
    expect(page).to have_css(".prose h1", text: "Measurements")
    expect(page).to have_css(".highlight span")
    within("#cell-#{table.id}") do
      expect(page).to have_css("tbody tr", count: 2)
      fill_in "Filter rows", with: "Two"
      expect(page).to have_css("tbody tr", count: 1)
      expect(page).to have_css("tbody", text: "24")
    end
    within("#cell-#{chart.id}") { click_button "Render chart" }
    frame = find("#cell-#{chart.id} iframe")
    within_frame(frame) { expect(page).to have_css("svg rect", count: 2) }
    scale = find('input[type="range"]')
    scale.set(2)
    expect(page).to have_content("Inputs updated. Ruby runs only when requested.")
    within_frame(frame) do
      expect(page).to have_css("svg rect", count: 2)
      expect(find("svg rect", match: :first)["width"].to_f).to be > 500
    end
    expect(Execution.count).to eq(0)
    expect(page.driver.network_traffic.map { |exchange| exchange.request.url }.grep(%r{\Ahttps?://}).all? { |url| URI(url).host == "127.0.0.1" }).to be(true)
    page.driver.scroll_to(0, 0)
    page.save_screenshot(Rails.root.join("tmp/authoring.png"))
  end

  it "reconciles persisted output without replacing the focused editor or undo history" do
    cell = add_cell("ruby", source: "21 * 2")
    execution = ExecutionRequests.submit(notebook:, cell_id: cell.id, expected_revision: cell.head_revision_id)
    visit app_notebook_path(notebook.app, notebook)
    editor = find(".cm-content")
    editor.click
    editor.send_keys([:control, "a"], "my_unsaved_value = 99")
    expect(page).to have_content("Draft saved · not a committed revision")
    page.execute_script("window.originalEditor = document.querySelector('.cm-content')")
    execution.update!(status: "completed", result: { "inspection" => "42" })
    ExecutionUpdates.broadcast(execution.notebook_session)
    expect(page).to have_css(".return-value", text: "42", wait: 5)
    expect(page.evaluate_script("document.activeElement === window.originalEditor")).to be(true)
    expect(page.evaluate_script("document.querySelector('.cm-content') === window.originalEditor")).to be(true)
    expect(page).to have_css(".cm-content", text: "my_unsaved_value = 99")
    editor.send_keys([:control, "z"])
    expect(page).to have_css(".cm-content", text: "21 * 2")
    expect(cell.reload.head_revision.source).to eq("21 * 2")
  end

  it "uploads an image and imports Markdown referring to its immutable app asset" do
    visit app_notebook_path(notebook.app, notebook)
    click_link "Files and images"
    Tempfile.create(["plot", ".png"]) do |file|
      file.binmode
      file.write(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jWZkAAAAASUVORK5CYII="))
      file.flush
      attach_file "File or image", file.path
      click_button "Upload immutable asset"
      expect(page).to have_css("article pre", text: "asset://")
    end
    reference = find("article pre").text
    click_link "← App"
    find("summary", text: "Import Markdown or data").click
    Tempfile.create(["notes", ".md"]) do |file|
      file.write("# Imported picture\n\n#{reference}\n")
      file.flush
      attach_file "Source file", file.path
      click_button "Import as new cell"
      expect(page).to have_css(".prose h1", text: "Imported picture")
      expect(page).to have_css(".prose img")
    end
    image = find(".prose img")
    expect(image["src"]).to include("/apps/#{notebook.app_id}/assets/")
    expect(page).to have_link("Export source")
    expect(Execution.count).to eq(0)
  end
end
