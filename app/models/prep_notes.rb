# Advisory preparation notes for a dish: "Fryer oil is often shared with
# breaded or shellfish items. Lower-risk method: bake or pan-sear in fresh oil —
# still check shared pans and utensils."
#
# Advisory only. PrepNotes never sees an Evaluation::GroupResult and returns
# nothing the engine reads, so it can never lower, raise or clear a tier
# (docs/EVALUATION_RULES.md, "Things that can never change a tier").
#
#   PrepNotes.for(patients:, dish: "Fried shrimp", ingredients: [ "shrimp" ], prep_notes: [ "deep-fried" ])
#   PrepNotes.cross_contact_line(patients)
class PrepNotes
  TRIGGER_KINDS = %w[allergy intolerance cannot condition].freeze
  CROSS_CONTACT_LINE = "Check shared pans, oil, and cutting boards".freeze

  # terms: the restriction terms the note is relevant to. Never patient names.
  # key: stable for the same method, method text and terms, for dismissal.
  Note = Data.define(:key, :method_name, :risk, :terms, :lower_risk_line)

  def self.for(patients:, dish:, ingredients:, prep_notes: [])
    new(patients).notes(dish:, ingredients:, prep_notes:)
  end

  # One line for any group with an allergy; nil otherwise.
  def self.cross_contact_line(patients)
    CROSS_CONTACT_LINE if Restriction.where(patient_id: patient_ids(patients), kind: "allergy").exists?
  end

  def self.patient_ids(patients)
    Array(patients).map { |patient| patient.is_a?(Patient) ? patient.id : Integer(patient) }.uniq
  end

  def initialize(patients)
    @patient_ids = self.class.patient_ids(patients)
  end

  def notes(dish:, ingredients:, prep_notes: [])
    texts = [ dish, *Array(prep_notes), *Array(ingredients) ].map(&:to_s).compact_blank
    return [] if texts.empty? || @patient_ids.empty?

    detected = PrepMethod.active.ordered.includes(:risk_nodes).select { |method| method.detected_in?(texts) }
    return [] if detected.empty?

    restrictions = trigger_restrictions
    return [] if restrictions.empty?

    # Same coverage as the engine (tree + group membership), one graph for all.
    graph = Evaluation::Engine::Coverage.new(detected.flat_map(&:risk_nodes).uniq)
    detected.filter_map { |method| note_for(method, restrictions, graph) }
  end

  private

  # Restrictions with a taxonomy node only. A restriction the resolver could
  # not map has no node to compare with a method's risk nodes.
  def trigger_restrictions
    Restriction.where(patient_id: @patient_ids, kind: TRIGGER_KINDS).where.not(taxonomy_node_id: nil)
      .includes(:taxonomy_node).sort_by { |restriction| [ restriction.created_at, restriction.id ] }
  end

  def note_for(method, restrictions, graph)
    relevant = restrictions.select do |restriction|
      method.risk_nodes.any? { |node| related?(graph, restriction.taxonomy_node, node) }
    end
    return if relevant.empty?

    terms = relevant.map { |restriction| Taxonomy::Normalizer.call(restriction.term) }.compact_blank.uniq
    Note.new(key: key_for(method, terms), method_name: method.name, risk: method.risk, terms:,
      lower_risk_line: method.lower_risk_line)
  end

  # Either way round, with the engine's coverage (tree + group membership):
  # the restriction covers the risk (gluten → wheat, low sodium → stock), or the
  # risk covers the restriction (a shrimp allergy and fryer oil shared with
  # shellfish). Advisory, so the wider reading costs nothing.
  def related?(graph, restriction_node, risk_node)
    graph.relation(restriction_node, risk_node) || graph.relation(risk_node, restriction_node)
  end

  # A dismissed note comes back when the method's text or the terms change.
  # Hashed, so localStorage never holds restriction terms.
  def key_for(method, terms)
    digest = Digest::SHA256.hexdigest([ method.name, method.risk, method.lower_risk_line, *terms.sort ].join("\u0000"))
    "prep-#{method.id}-#{digest.first(16)}"
  end
end
