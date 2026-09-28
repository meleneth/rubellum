class AppRevision < ImmutableRevision
  belongs_to :app
  validates :title, presence: true
end
