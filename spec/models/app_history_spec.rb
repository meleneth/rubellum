require "rails_helper"

RSpec.describe AppHistory, type: :model do
  let(:app) { create(:app) }
  subject(:history) { described_class.new(app) }

  def update(attributes = {}, **options)
    history.update(expected_revision: app.reload.head_revision_id, attributes:, **options)
  end

  it "versions metadata and restores all fields as a new revision" do
    first_page, second_page = create(:notebook, app:), create(:notebook, app:)
    asset = create(:asset, app:)
    original = update({ title: "Original", description: "Original notes", landing_notebook_id: first_page.id,
      configuration: { "asset_ids" => [asset.id], "theme" => "dark" } })
    later = update({ title: "Later", description: "Later notes", landing_notebook_id: second_page.id, configuration: {} })
    restored = history.restore(revision_id: original.id, expected_revision: later.id)
    expect(restored.id).not_to eq(original.id)
    expect(restored.parent_id).to eq(later.id)
    expect(restored.attributes.slice(*described_class::FIELDS)).to eq(original.attributes.slice(*described_class::FIELDS))
    expect(restored.provenance).to eq("restored_from" => original.id)
    expect(later.reload.title).to eq("Later")
    expect(app.revisions.count).to eq(4)
    expect(app.reload.head_revision_id).to eq(restored.id)
  end

  it "preserves archive state during ordinary metadata edits and restores" do
    initial = app.head_revision
    update({}, archived: true)
    archived_at = app.reload.archived_at
    update({ title: "Edited archived app" })
    expect(app.reload.archived_at).to eq(archived_at)
    history.restore(revision_id: initial.id, expected_revision: app.head_revision_id)
    expect(app.reload.archived_at).to eq(archived_at)
    update({}, archived: false)
    expect(app.reload.archived_at).to be_nil
  end

  it "rejects stale saves and restores without changing either metadata or archive state" do
    old = app.head_revision
    current = update({ title: "Other tab" })
    expect { history.update(expected_revision: old.id, attributes: { title: "Stale" }, archived: true) }.to raise_error(History::Conflict)
    expect { history.restore(revision_id: old.id, expected_revision: old.id) }.to raise_error(History::Conflict)
    expect(app.reload.head_revision_id).to eq(current.id)
    expect(app.archived_at).to be_nil
    expect(app.revisions.count).to eq(2)
  end

  it "rejects cross-app landing notebooks and restoration identities" do
    other = create(:notebook)
    original = app.head_revision_id
    expect { update({ landing_notebook_id: other.id }) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { history.restore(revision_id: other.app.head_revision_id, expected_revision: original) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(app.reload.head_revision_id).to eq(original)
    expect(app.revisions.count).to eq(1)
  end

  it "rejects invalid content and unknown fields atomically" do
    original = app.head_revision_id
    expect { update({ title: "" }, archived: true) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { update({ configuration: [] }) }.to raise_error(ArgumentError)
    expect { update({ configuration: { "asset_ids" => [SecureRandom.uuid] } }) }.to raise_error(ArgumentError)
    expect { update({ portable_id: SecureRandom.uuid }) }.to raise_error(ArgumentError, /Unknown/)
    expect { update({}, archived: "false") }.to raise_error(ArgumentError, /Archive state/)
    expect(app.reload.head_revision_id).to eq(original)
    expect(app.archived_at).to be_nil
    expect(app.revisions.count).to eq(1)
  end

  it "retains unspecified metadata and explicitly clears a landing notebook" do
    notebook = create(:notebook, app:)
    update({ title: "Retain me", description: "Notes", landing_notebook_id: notebook.id })
    revision = update({ landing_notebook_id: "" })
    expect(revision.title).to eq("Retain me")
    expect(revision.description).to eq("Notes")
    expect(revision.landing_notebook_id).to be_nil
  end
end
