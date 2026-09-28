class AppRevision < ImmutableRevision
  belongs_to :app
  validates :title, presence: true
  before_validation(on: :create) { AssetReferences.validate!(app_id:, configuration:) }
end
