# One kind of restriction (allergies, cannot have, ...) for one patient, edited
# as a set of picked taxonomy nodes. Each picked node is still stored as its
# own Restriction (a manual match, "set by you"), so the engine and every
# flag's reason stay exactly as they are for restrictions added one by one.
#
# Restrictions of the kind that have no node (typed terms the resolver didn't
# recognize) are not part of the set and are never touched here.
class RestrictionSelection
  Result = Data.define(:added, :removed) do
    def changed? = added.any? || removed.any?
  end

  attr_reader :patient, :kind

  def initialize(patient, kind)
    raise ArgumentError, "unknown restriction kind #{kind.inspect}" unless Restriction.kinds.key?(kind.to_s)

    @patient = patient
    @kind = kind.to_s
  end

  # "Allergies", "Can have" (without the list heading's "(you marked these OK)").
  def heading = Restriction::KIND_LABELS.fetch(kind).first.sub(/ \(.*\)\z/, "")

  def restrictions = patient.restrictions.where(kind:)

  def selected_node_ids = restrictions.where.not(taxonomy_node_id: nil).distinct.pluck(:taxonomy_node_id).to_set

  # Typed terms with no match; shown on the page so the nurse knows they stay.
  def unmatched = restrictions.where(taxonomy_node_id: nil).order(:created_at, :id)

  # Node ids that carry a note somewhere in this kind, so the page can warn
  # that unticking one also removes its note.
  def noted_node_ids
    restrictions.where.not(taxonomy_node_id: nil).select { |r| r.note.present? }.to_set(&:taxonomy_node_id)
  end

  # Makes the picked nodes of this kind exactly `node_ids`: removes the
  # restrictions whose node was unticked, adds one per newly ticked node.
  # Unknown ids are ignored.
  def update(node_ids)
    wanted = TaxonomyNode.where(id: Array(node_ids).compact_blank).pluck(:id).to_set
    picked = restrictions.where.not(taxonomy_node_id: nil).to_a
    to_remove = picked.reject { |restriction| wanted.include?(restriction.taxonomy_node_id) }
    to_add = TaxonomyNode.where(id: (wanted - picked.to_set(&:taxonomy_node_id)).to_a).order(:name)

    Restriction.transaction do
      to_remove.each(&:destroy!)
      to_add.each { |node| patient.restrictions.create!(kind:, term: node.name, manual_node_id: node.id) }
    end
    Result.new(added: to_add.map(&:name), removed: to_remove.map(&:term).uniq.sort)
  end
end
