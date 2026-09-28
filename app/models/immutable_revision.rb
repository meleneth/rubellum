require "digest"
require "json"

class ImmutableRevision < ApplicationRecord
  self.abstract_class = true
  before_validation :assign_digest, on: :create
  validates :content_digest, :author, presence: true
  def readonly? = persisted?

  private

  def assign_digest
    data = attributes.except("id", "created_at", "content_digest")
    self.content_digest = Digest::SHA256.hexdigest(JSON.generate(canonical(data)))
  end

  def canonical(value)
    case value
    when Hash then value.sort.to_h.transform_values { |item| canonical(item) }
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end
end
