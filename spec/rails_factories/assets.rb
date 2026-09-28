FactoryBot.define do
  factory :asset do
    association :app
    transient { bytes { "example bytes" } }
    filename { "example.txt" }
    mime_type { "text/plain" }
    sha256 { Digest::SHA256.hexdigest(bytes) }
    byte_size { bytes.bytesize }
    before(:create) { |asset, evaluator| AssetStorage.for_app(asset.app).put(StringIO.new(evaluator.bytes)) }
  end
end
