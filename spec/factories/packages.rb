require "rubellum/package_manifest"

FactoryBot.define do
  factory :package_revision, class: Hash do
    id { SecureRandom.uuid }
    parent_id { nil }
    title { "Portable app" }
    configuration { {} }
    author { "Owner" }
    summary { "" }
    provenance { {} }
    created_at { "2026-09-28T12:00:00.000000Z" }
    description { "" }
    landing_notebook_id { nil }
    initialize_with do
      value = attributes.transform_keys(&:to_s)
      value.merge("digest" => Rubellum::PackageManifest.digest(value))
    end
  end

  factory :package_manifest, class: Hash do
    format_version { 1 }
    cell_api_version { 1 }
    mode { "full" }
    app do
      revision = build(:package_revision)
      { "id" => SecureRandom.uuid, "head" => revision["id"], "revisions" => [revision] }
    end
    notebooks { [] }
    cells { [] }
    assets { [] }
    files { {} }
    initialize_with { attributes.transform_keys(&:to_s) }
  end
end
