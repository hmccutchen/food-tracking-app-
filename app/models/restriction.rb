class Restriction < ApplicationRecord
  MATCH_TYPES = %w[exact alias fuzzy unresolved manual].freeze
  MANUAL_REASON = "set by you".freeze

  # kind => [ group heading, select option ]
  KIND_LABELS = {
    "allergy" => [ "Allergies", "Allergy" ], "intolerance" => [ "Intolerances", "Intolerance" ],
    "condition" => [ "Conditions", "Condition" ], "cannot" => [ "Cannot have", "Cannot have" ],
    "can" => [ "Can have (you marked these OK)", "Can have" ]
  }.freeze

  enum :kind, { allergy: "allergy", intolerance: "intolerance", condition: "condition", cannot: "cannot", can: "can" },
    validate: true

  belongs_to :patient, inverse_of: :restrictions
  belongs_to :taxonomy_node, optional: true

  encrypts :term
  encrypts :note

  # The "match to" select on the form. Blank means "match automatically".
  attribute :manual_node_id, :integer

  validates :term, presence: true
  validates :match_type, inclusion: { in: MATCH_TYPES }
  validates :taxonomy_node, presence: { message: "must be chosen from the list" }, if: -> { match_type == "manual" }

  before_validation :assign_match

  after_create :bump_profile_version
  after_update :bump_profile_version, if: :saved_changes?
  after_destroy :bump_profile_version

  def manual? = match_type == "manual"

  # The form preselects the node only when the nurse picked it herself.
  def manual_node_id
    @manual_node_choice_given ? super : (taxonomy_node_id if manual?)
  end

  def manual_node_id=(value)
    @manual_node_choice_given = true
    super
  end

  private

  # Re-resolve rule:
  # - "Match to" set to a node: that node is stored as match_type "manual"
  #   ("set by you"). The resolver never overrides it, even when the term
  #   changes, for as long as the nurse keeps a node picked.
  # - "Match to" left blank: the resolver runs on create, whenever the term
  #   changes, and when the nurse clears a previous manual choice.
  # - Not mentioned at all (e.g. a note-only update from code): a manual match
  #   is kept as is; an automatic match is re-resolved only if the term changed.
  # Changing only the note or kind never re-resolves.
  def assign_match
    if @manual_node_choice_given && self[:manual_node_id].present?
      assign_manual(self[:manual_node_id])
    elsif @manual_node_choice_given && manual?
      assign_resolution
    elsif !manual? && (new_record? || will_save_change_to_term? || match_reason.blank?)
      assign_resolution
    end
  end

  def assign_manual(node_id)
    self.taxonomy_node = TaxonomyNode.find_by(id: node_id)
    self.match_type = "manual"
    self.match_reason = MANUAL_REASON
  end

  def assign_resolution
    resolution = Taxonomy::Resolver.new.resolve(term)
    self.taxonomy_node = resolution.node
    self.match_type = resolution.match_type.to_s
    self.match_reason = plain_reason(resolution)
  end

  # Feedback for the nurse, in plain words.
  def plain_reason(resolution)
    name = resolution.node&.name
    case resolution.match_type
    when :exact then "matched to #{name}"
    when :alias then "alias '#{resolution.reason[/\Aalias '(.+?)'/, 1] || resolution.normalized}' → #{name}"
    when :fuzzy then "fuzzy match to #{name} — please check"
    else "not recognized — will be checked by exact text only"
    end
  end

  def bump_profile_version
    Patient.bump_profile_version!(patient_id)
  end
end
