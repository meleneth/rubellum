require "rails_helper"

RSpec.describe "App metadata history", type: :request do
  let(:project) { create(:app) }

  it "compares escaped historical metadata and restores a new revision" do
    initial = project.head_revision
    post_title = '<script>alert("title")</script>'
    patch app_path(project), params: { expected_revision: initial.id, title: post_title, description: "Later description", summary: "Rename project" }
    expect(response).to have_http_status(:see_other)
    later = project.reload.head_revision
    get history_app_path(project, revision: initial.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Selected revision compared with current", "Rename project")
    document = Nokogiri::HTML5(response.body)
    expect(document.css('tr[data-changed="true"]').size).to eq(2)
    expect(document.css("main script")).to be_empty
    expect(document.text).to include(post_title)
    post restore_app_path(project), params: { revision_id: initial.id, expected_revision: later.id }
    expect(response).to redirect_to(history_app_path(project))
    expect(project.reload.title).to eq(initial.title)
    expect(project.head_revision.parent_id).to eq(later.id)
    expect(project.head_revision.provenance).to eq("restored_from" => initial.id)
    expect(project.revisions.count).to eq(3)
  end

  it "rejects stale restore and update requests without losing the current metadata" do
    initial = project.head_revision
    patch app_path(project), params: { expected_revision: initial.id, title: "Winner" }
    post restore_app_path(project), params: { revision_id: initial.id, expected_revision: initial.id }
    expect(response).to have_http_status(:conflict)
    patch app_path(project), params: { expected_revision: initial.id, title: "Stale", archived: "true" }
    expect(response).to have_http_status(:conflict)
    expect(project.reload.title).to eq("Winner")
    expect(project.archived_at).to be_nil
  end

  it "does not disclose or restore another app's metadata" do
    other = create(:app)
    get history_app_path(project, revision: other.head_revision_id)
    expect(response).to have_http_status(:not_found)
    post restore_app_path(project), params: { revision_id: other.head_revision_id, expected_revision: project.head_revision_id }
    expect(response).to have_http_status(:not_found)
    expect(project.revisions.count).to eq(1)
  end

  it "keeps an archived app archived unless explicitly unarchived" do
    patch app_path(project), params: { expected_revision: project.head_revision_id, archived: "true" }
    archived_at = project.reload.archived_at
    expect(archived_at).not_to be_nil
    patch app_path(project), params: { expected_revision: project.head_revision_id, title: "Still archived" }
    expect(project.reload.archived_at).to eq(archived_at)
    patch app_path(project), params: { expected_revision: project.head_revision_id, archived: "not false" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(project.reload.archived_at).to eq(archived_at)
    patch app_path(project), params: { expected_revision: project.head_revision_id, archived: "false" }
    expect(project.reload.archived_at).to be_nil
  end

  it "rejects a landing notebook from another app" do
    other = create(:notebook)
    patch app_path(project), params: { expected_revision: project.head_revision_id, landing_notebook_id: other.id }
    expect(response).to have_http_status(:not_found)
    expect(project.reload.head_revision.landing_notebook_id).to be_nil
  end

  it "gives each library form unique input IDs and correctly associated labels" do
    project
    create(:app)
    get root_path
    document = Nokogiri::HTML5(response.body)
    ids = document.css("[id]").map { |node| node["id"] }
    expect(ids.uniq).to eq(ids)
    document.css("label[for]").each do |label|
      expect(document.css("[id='#{label['for']}']").size).to eq(1)
    end
  end
end
