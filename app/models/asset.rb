class Asset < ApplicationRecord
  belongs_to :app
  belongs_to :execution, optional: true
  belongs_to :runner_event, optional: true
  validates :filename, presence: true, length: { maximum: 255 }, format: { without: %r{[/\\\x00-\x1f\x7f]} }
  validates :mime_type, format: { with: %r{\A[a-zA-Z0-9.+-]+/[a-zA-Z0-9.+-]+\z} }
  validates :sha256, format: { with: Rubellum::BlobStore::DIGEST }
  validates :byte_size, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: Rubellum::BlobStore::MAX_BYTES }
  def readonly? = persisted?
  def reference = { "sha256" => sha256, "size" => byte_size }
  def image? = %w[image/png image/jpeg image/gif image/webp image/avif].include?(mime_type)
end
