require "rubellum/package_manifest"

RSpec.describe Rubellum::PackageManifest do
  let(:manifest) { build(:package_manifest) }
  let(:revision) { manifest["app"]["revisions"].first }

  def load_manifest(value = manifest, extra_files = {})
    described_class.load(extra_files.merge("manifest.json" => JSON.generate(value)))
  end

  def redigest(record = revision)
    record["digest"] = described_class.digest(record.reject { |key, _| key == "digest" })
  end

  it "validates and freezes an inert minimal package" do
    result = load_manifest
    expect(result).to eq(manifest)
    expect(result).to be_frozen
    expect(result["app"]["revisions"].first).to be_frozen
  end

  it "rejects missing manifests, invalid JSON and duplicate JSON keys" do
    expect { described_class.load({}) }.to raise_error(described_class::Invalid, /Missing/)
    ["{", '{"format_version":1,"format_version":1}', "\xff".b].each do |json|
      expect { described_class.load("manifest.json" => json) }.to raise_error(described_class::Invalid)
    end
  end

  it "rejects unsupported versions, unknown fields and oversized manifests" do
    [manifest.merge("format_version" => 2), manifest.merge("cell_api_version" => 2),
      manifest.merge("format_version" => 1.0), manifest.merge("mode" => "merge"), manifest.merge("secrets" => {})].each do |invalid|
      expect { load_manifest(invalid) }.to raise_error(described_class::Invalid)
    end
    expect { described_class.load("manifest.json" => " " * (described_class::MAX_BYTES + 1)) }
      .to raise_error(described_class::Invalid, /limit/)
  end

  it "checks immutable revision content digests" do
    revision["title"] = "Tampered"
    expect { load_manifest }.to raise_error(described_class::Invalid, /digest/)
  end

  it "rejects foreign heads, missing parents, duplicate identities and cycles" do
    manifest["app"]["head"] = SecureRandom.uuid
    expect { load_manifest }.to raise_error(described_class::Invalid, /head/)
    manifest["app"]["head"] = revision["id"]
    revision["parent_id"] = SecureRandom.uuid
    redigest
    expect { load_manifest }.to raise_error(described_class::Invalid, /parent/)
    revision["parent_id"] = revision["id"]
    redigest
    expect { load_manifest }.to raise_error(described_class::Invalid, /Cyclic/)
    revision["parent_id"] = nil
    redigest
    manifest["app"]["revisions"] << revision.dup
    expect { load_manifest }.to raise_error(described_class::Invalid, /Duplicate/)
  end

  it "rejects dangling asset, landing and restore references" do
    [{ "configuration" => { "asset_ids" => [SecureRandom.uuid] } },
      { "landing_notebook_id" => SecureRandom.uuid },
      { "provenance" => { "restored_from" => SecureRandom.uuid } }].each do |changes|
      original = revision.dup
      revision.merge!(changes)
      redigest
      expect { load_manifest }.to raise_error(described_class::Invalid, /Missing/)
      revision.replace(original)
    end
  end

  it "checks file inventories and excludes unclaimed secrets or runtime files" do
    expect { load_manifest(manifest, "config/secret" => "sensitive") }.to raise_error(described_class::Invalid, /files/)
    manifest["files"]["missing"] = { "sha256" => "0" * 64, "size" => 1 }
    expect { load_manifest }.to raise_error(described_class::Invalid, /files/)
  end

  it "rejects history in current-state packages and invalid scalar fields" do
    second = build(:package_revision, parent_id: revision["id"])
    manifest["app"]["revisions"] << second
    manifest["mode"] = "current"
    expect { load_manifest }.to raise_error(described_class::Invalid, /parentless/)
    manifest["mode"] = "full"
    revision["created_at"] = "yesterday"
    redigest
    expect { load_manifest }.to raise_error(described_class::Invalid)
  end

  it "rejects NUL metadata before staging or PostgreSQL JSONB insertion" do
    revision["configuration"] = { "settings" => [{ "name" => "bad\0value" }] }
    redigest
    expect { load_manifest }.to raise_error(described_class::Invalid, /NUL/)
  end

  it "reports malformed owner/revision shapes as validation errors" do
    [nil, true, 42, "text", [], {}].each do |bad|
      expect { load_manifest(manifest.merge("app" => bad)) }.to raise_error(described_class::Invalid)
      changed = Marshal.load(Marshal.dump(manifest))
      changed["mode"] = "current"
      changed["app"]["revisions"] = [bad]
      expect { load_manifest(changed) }.to raise_error(described_class::Invalid)
    end
  end
end
