# The combined avoid list for the patients who are eating together. Plain Ruby
# over the database, no network. Each entry is traced to the patient(s) who
# need it.
#
#   list = AvoidList.build(Current.user.patients.where(id: ids))
#   list.sections   # Avoid, Limit, Marked OK (empty sections included)
#   list.to_terms   # restriction terms only, for an AI prompt (never names)
class AvoidList
  AVOID_KINDS = %w[allergy intolerance cannot].freeze
  LIMIT_KINDS = %w[condition].freeze
  KIND_ORDER = %w[allergy cannot intolerance condition can].freeze
  HINT_SIZE = 6

  SECTIONS = {
    avoid: [ "Avoid", nil ],
    limit: [ "Limit", nil ],
    ok: [ "Marked OK", "Shown so you can see them. A can never overrides an allergy." ]
  }.freeze

  # One patient's restriction behind an entry.
  Need = Data.define(:patient_id, :patient_name, :kind, :term, :match_type, :match_note)

  # label: node name, or the nurse's term when the restriction was not recognized.
  Entry = Data.define(:section, :label, :node, :needs, :hint) do
    def kinds = needs.map(&:kind).uniq.sort_by { |kind| KIND_ORDER.index(kind) }
    def patient_names = needs.map(&:patient_name).uniq
    def match_notes = needs.filter_map(&:match_note).uniq
    def resolved? = !node.nil?
  end

  Section = Data.define(:key, :title, :note, :entries) do
    def empty? = entries.empty?
  end

  attr_reader :entries, :profile_versions, :built_at

  def self.build(patients)
    ids = Array(patients).map { |patient| patient.is_a?(Patient) ? patient.id : Integer(patient) }.uniq
    # Patients first, then restrictions (like Evaluation::Engine), so a
    # concurrent edit can only make the stamp look older, never newer.
    by_id = Patient.where(id: ids).includes(restrictions: :taxonomy_node).index_by(&:id)
    new(ids.filter_map { |id| by_id[id] })
  end

  def initialize(patients)
    @patients = patients
    @profile_versions = patients.to_h { |patient| [ patient.id, patient.profile_version ] }.freeze
    @built_at = Time.current
    @entries = build_entries.freeze
  end

  def sections
    SECTIONS.map do |key, (title, note)|
      Section.new(key:, title:, note:, entries: entries.select { |entry| entry.section == key })
    end
  end

  def patient_names = @patients.map(&:display_name)
  def empty? = entries.empty?

  # Any selected patient has an allergy, so the cross-contact reminder applies.
  def cross_contact?
    @patients.any? { |patient| patient.restrictions.any?(&:allergy?) }
  end

  def stale? = Evaluation::GroupResult.stale_for?(profile_versions)

  # The Avoid and Limit restriction terms, sorted and de-duplicated: node names,
  # plus the nurse's own words when the match was fuzzy or not recognized. No
  # patient names, no ids. Marked-OK terms are left out.
  def to_terms
    entries.reject { |entry| entry.section == :ok }.flat_map do |entry|
      own_words = entry.needs.reject { |need| entry.resolved? && %w[exact alias manual].include?(need.match_type) }
      [ entry.node&.name, *own_words.map { |need| Taxonomy::Normalizer.call(need.term) } ]
    end.compact_blank.uniq.sort
  end

  private

  def build_entries
    grouped = Hash.new { |hash, key| hash[key] = [] }
    @patients.each do |patient|
      patient.restrictions.sort_by { |restriction| [ restriction.created_at, restriction.id ] }.each do |restriction|
        bucket = restriction.can? ? :ok : :restrict
        grouped[[ bucket, merge_key(restriction) ]] << [ restriction, need_for(patient, restriction) ]
      end
    end

    hints = Hints.new(grouped.values.filter_map { |pairs| pairs.first.first.taxonomy_node })
    grouped.map { |(bucket, _), pairs| entry_for(bucket, pairs, hints) }
      .sort_by { |entry| [ SECTIONS.keys.index(entry.section), entry.label.downcase ] }
  end

  # Same node → one entry; same unrecognized term (normalized) → one entry.
  # A node and its descendant stay separate entries.
  def merge_key(restriction)
    if restriction.taxonomy_node_id
      [ :node, restriction.taxonomy_node_id ]
    else
      [ :term, Taxonomy::Normalizer.call(restriction.term) ]
    end
  end

  def entry_for(bucket, pairs, hints)
    restrictions = pairs.map(&:first)
    node = restrictions.first.taxonomy_node
    section =
      if bucket == :ok then :ok
      elsif restrictions.any? { |restriction| AVOID_KINDS.include?(restriction.kind) } then :avoid
      else :limit
      end
    needs = pairs.map(&:last).sort_by { |need| [ need.patient_name.downcase, KIND_ORDER.index(need.kind) ] }
    Entry.new(section:, label: node ? node.name : restrictions.first.term.strip, node:, needs: needs.freeze,
      hint: node && hints.for(node))
  end

  def need_for(patient, restriction)
    Need.new(patient_id: patient.id, patient_name: patient.display_name, kind: restriction.kind,
      term: restriction.term, match_type: restriction.match_type, match_note: match_note(restriction))
  end

  def match_note(restriction)
    case restriction.match_type
    when "fuzzy" then "fuzzy match — please check (you entered '#{restriction.term.strip}')"
    when "unresolved" then "not recognized — checked by exact text only"
    when "manual" then "match set by you"
    end
  end

  # "includes almond, cashew, …": the first descendant names (nearest first,
  # then by name), then group members (sodium → soy sauce, …). One query each.
  class Hints
    def initialize(nodes)
      @cache = {}
      return if nodes.empty?

      rows = TaxonomyNode.pluck(:id, :parent_id, :name)
      @names = rows.to_h { |id, _, name| [ id, name ] }
      @children = rows.group_by { |_, parent_id, _| parent_id }
        .transform_values { |list| list.sort_by(&:last).map(&:first) }
      @members = TaxonomyMembership.pluck(:group_id, :node_id).group_by(&:first)
        .transform_values { |pairs| pairs.map(&:last).sort_by { |id| @names[id].to_s } }
    end

    def for(node)
      @cache[node.id] ||= begin
        names = (descendants(node.id) + @members.fetch(node.id, [])).filter_map { |id| @names[id] }.uniq
        "includes #{names.first(HINT_SIZE).join(', ')}#{names.size > HINT_SIZE ? ', …' : ''}" if names.any?
      end
    end

    private

    def descendants(root_id)
      found = []
      level = @children.fetch(root_id, [])
      while level.any? && found.size < 1_000
        found.concat(level)
        level = level.flat_map { |id| @children.fetch(id, []) } - found
      end
      found
    end
  end
end
