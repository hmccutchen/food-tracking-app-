class Patient < ApplicationRecord
  belongs_to :user
  has_many :restrictions, dependent: :delete_all, inverse_of: :patient

  encrypts :display_name
  encrypts :notes

  validates :display_name, presence: true

  # Any change to the patient's own fields bumps the profile once, in the same
  # transaction, with an atomic UPDATE ... SET profile_version = profile_version + 1.
  after_update :bump_profile_version!, if: -> { saved_changes.except("updated_at").any? }

  # Atomic +1 from anywhere (restrictions call this). Does not run callbacks,
  # so it can never trigger a second bump.
  def self.bump_profile_version!(patient_id)
    update_counters(patient_id, profile_version: 1, touch: true)
  end

  # { patient_id => profile_version }, stamped on evaluation results so a
  # later change to the profile can mark them stale.
  def profile_stamp
    { id => profile_version }
  end

  def restrictions_by_kind
    grouped = restrictions.includes(:taxonomy_node).order(:created_at, :id).group_by(&:kind)
    Restriction.kinds.keys.index_with { |kind| grouped.fetch(kind, []) }
  end

  private

  def bump_profile_version!
    increment!(:profile_version, touch: false)
  end
end
