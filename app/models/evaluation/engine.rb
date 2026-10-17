module Evaluation
  # Checks a list of ingredient strings against the selected patients'
  # restrictions and returns a GroupResult. Plain Ruby over the database: no
  # network, no AI. The rules live in docs/EVALUATION_RULES.md.
  #
  #   Evaluation::Engine.new(patients).evaluate([ "almond flour", "soy sauce" ])
  class Engine
    AMBIGUOUS_GROUP = "ambiguous ingredient".freeze
    FLAGGING_KINDS = %w[allergy intolerance condition cannot].freeze
    AMBIGUOUS_TRIGGER_KINDS = %w[allergy intolerance cannot].freeze

    def initialize(patients, resolver: Taxonomy::Resolver.new)
      @patient_ids = Array(patients).map { |patient| patient.is_a?(Patient) ? patient.id : Integer(patient) }.uniq
      @resolver = resolver
    end

    # ingredients: array of strings. nil or empty means "no ingredient list found".
    def evaluate(ingredients)
      list = Array(ingredients).map(&:to_s).reject { |text| text.strip.empty? }
      patients = load_patients
      resolutions = list.empty? ? [] : @resolver.resolve_all(list)
      graph = Coverage.new(resolutions.flat_map { |resolution| [ resolution.node, *resolution.contained_nodes ] }.compact)

      results = patients.map do |patient|
        flags = list.empty? ? [ missing_list_flag ] : patient_flags(patient, resolutions, graph)
        PatientResult.new(patient_id: patient.id, profile_version: patient.profile_version, flags:)
      end

      GroupResult.new(patient_results: results, ingredients: ingredients.nil? ? nil : list,
        profile_versions: patients.to_h { |patient| [ patient.id, patient.profile_version ] },
        missing_patient_ids: @patient_ids - patients.map(&:id), evaluated_at: Time.current)
    end

    private

    # Two queries in this order: patients (with profile_version), then their
    # restrictions. A concurrent edit can therefore only leave the stamp older
    # than the restrictions read, so the result reads stale (the cautious side).
    def load_patients
      by_id = Patient.where(id: @patient_ids).includes(restrictions: :taxonomy_node).index_by(&:id)
      @patient_ids.filter_map { |id| by_id[id] }
    end

    def missing_list_flag
      Flag.new(tier: Tier::UNKNOWN, ingredient: nil, reason: "no ingredient list found", source: :missing_list)
    end

    def patient_flags(patient, resolutions, graph)
      restrictions = patient.restrictions.sort_by { |restriction| [ restriction.created_at, restriction.id ] }
      watches_ambiguous = restrictions.any? { |restriction| AMBIGUOUS_TRIGGER_KINDS.include?(restriction.kind) }

      resolutions.flat_map do |resolution|
        IngredientCheck.new(resolution, restrictions, graph, watches_ambiguous).flags
      end
    end

    # In-memory view of the taxonomy for the nodes being evaluated, so coverage
    # costs a fixed number of queries however many patients and restrictions
    # there are. Mirrors TaxonomyNode#covers?: a restriction node covers an
    # ingredient node when it is the node or an ancestor (:tree), or when the
    # node or an ancestor is a member of the restriction node or one of its
    # descendants (:membership).
    class Coverage
      def initialize(ingredient_nodes)
        @coverers = {}
        return if ingredient_nodes.empty?

        rows = TaxonomyNode.pluck(:id, :parent_id, :name)
        @parents = rows.to_h { |id, parent_id, _| [ id, parent_id ] }
        @ambiguous_id = rows.find { |_, _, name| name == AMBIGUOUS_GROUP }&.first
        @groups = TaxonomyMembership.pluck(:node_id, :group_id)
          .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
      end

      # :tree, :membership or nil.
      def relation(restriction_node, ingredient_node)
        return if restriction_node.nil? || ingredient_node.nil?

        tree, membership = coverers(ingredient_node.id)
        if tree.include?(restriction_node.id) then :tree
        elsif membership.include?(restriction_node.id) then :membership
        end
      end

      # In the ambiguous group by tree or by membership (a custom item whose
      # ingredient text lists "natural flavors").
      def ambiguous?(ingredient_node)
        !@ambiguous_id.nil? && !ingredient_node.nil? && coverers(ingredient_node.id).any? { |set| set.include?(@ambiguous_id) }
      end

      private

      def coverers(node_id)
        @coverers[node_id] ||= begin
          tree = chain(node_id)
          groups = tree.flat_map { |id| @groups.fetch(id, []) }
          [ tree.to_set, groups.flat_map { |id| chain(id) }.to_set ]
        end
      end

      # [id, parent, grandparent, ...], bounded like ANCESTRY_SQL.
      def chain(node_id)
        ids = []
        id = node_id
        while id && ids.size <= 64 && !ids.include?(id)
          ids << id
          id = @parents[id]
        end
        ids
      end
    end

    # Applies the per-ingredient rules and the override precedence for one
    # patient and one resolved ingredient. The ingredient is checked through
    # its targets: the node it resolved to (direct or fuzzy), plus any nodes the
    # phrase scan found inside it (contained), plus text matching for
    # restrictions that have no node.
    class IngredientCheck
      Target = Data.define(:node, :via, :phrase) # via: :direct, :fuzzy, :contained
      Finding = Data.define(:flag, :restriction, :target)

      def initialize(resolution, restrictions, graph, watches_ambiguous)
        @resolution = resolution
        @restrictions = restrictions
        @graph = graph
        @watches_ambiguous = watches_ambiguous
        @ingredient = resolution.input.to_s.strip
      end

      def flags
        findings = targets.flat_map { |target| covered_findings(target) + ambiguous_findings(target) } + text_findings
        flags = findings.flat_map { |finding| apply_cans(finding) }
        (flags.sort_by { |flag| flag.overridden ? 1 : 0 } + unresolved_flags).uniq
      end

      private

      attr_reader :resolution, :ingredient, :graph

      def targets
        @targets ||= begin
          list = []
          list << Target.new(node: resolution.node, via: resolution.fuzzy? ? :fuzzy : :direct, phrase: nil) if resolution.node
          list + resolution.contained.map { |node, phrase| Target.new(node:, via: :contained, phrase:) }
        end
      end

      def with_node = @restrictions.select(&:taxonomy_node)
      def without_node = @restrictions.reject(&:taxonomy_node)

      # [restriction, relation] for node restrictions of these kinds covering the target.
      def covering(target, kinds)
        with_node.filter_map do |restriction|
          next unless kinds.include?(restriction.kind)

          relation = graph.relation(restriction.taxonomy_node, target.node)
          [ restriction, relation ] if relation
        end
      end

      def text_covering(kinds)
        without_node.select { |restriction| kinds.include?(restriction.kind) && TextMatch.match?(restriction.term, resolution) }
      end

      def covered_findings(target)
        covering(target, FLAGGING_KINDS).map do |restriction, relation|
          Finding.new(flag: covered_flag(restriction, relation, target), restriction:, target:)
        end
      end

      def covered_flag(restriction, relation, target)
        return fuzzy_flag(restriction, target) if target.via == :fuzzy

        reason =
          if target.via == :contained
            Reasons.contained(ingredient, target.phrase, restriction)
          else
            Reasons.covered(ingredient, restriction, relation, target.node)
          end
        Flag.new(tier: kind_tier(restriction), ingredient:, source: restriction.kind.to_sym, reason:)
      end

      def kind_tier(restriction) = restriction.condition? ? Tier::POSSIBLE_CONFLICT : Tier::CONFLICT

      def fuzzy_flag(restriction, target)
        Flag.new(tier: Tier::POSSIBLE_CONFLICT, ingredient:, source: :fuzzy,
          reason: Reasons.fuzzy(ingredient, restriction, target.node))
      end

      def text_findings
        text_covering(FLAGGING_KINDS).map do |restriction|
          flag = Flag.new(tier: kind_tier(restriction), ingredient:, source: restriction.kind.to_sym,
            reason: Reasons.text(ingredient, restriction))
          Finding.new(flag:, restriction:, target: nil)
        end
      end

      def ambiguous_findings(target)
        return [] unless @watches_ambiguous && graph.ambiguous?(target.node)

        reason = target.via == :contained ? "'#{target.phrase}' appears in '#{ingredient}'" : "'#{ingredient}' listed"
        flag = Flag.new(tier: Tier::POSSIBLE_CONFLICT, ingredient:, source: :ambiguous,
          reason: "#{reason} — may hide allergens")
        [ Finding.new(flag:, restriction: nil, target:) ]
      end

      # Unresolved phrases are UNKNOWN. So is a fuzzy phrase when the scan found
      # nothing known inside it: a loose match alone says what the phrase might
      # be, not what is in it, so it is never reported as no flags.
      def unresolved_flags
        return [] unless resolution.node.nil? || (resolution.fuzzy? && resolution.contained.empty?)

        reason =
          if resolution.fuzzy?
            "'#{ingredient}' only loosely matches #{resolution.node.name} — check the label"
          else
            resolution.reason.presence || "'#{ingredient}' not recognized"
          end
        [ Flag.new(tier: Tier::UNKNOWN, ingredient:, source: :unresolved, reason:) ]
      end

      # A "can" covering the flag's target clears intolerance, condition and
      # ambiguous flags (and fuzzy ones raised by those), keeping them as
      # overridden notes. It never clears an allergy or a cannot, never applies
      # once any cannot covers the ingredient, and never touches unknown. Where
      # it cannot clear a flag it adds a visible "you marked this OK" note.
      def apply_cans(finding)
        can = covering_can(finding) or return [ finding.flag ]

        if cannot_applies? || !clearable?(finding)
          [ finding.flag, marked_ok_note(finding, can) ]
        else
          [ finding.flag.override ]
        end
      end

      # A can only reaches the part of the ingredient it names. A flag on a
      # target (the whole phrase or one contained node) takes cans covering that
      # target. A text-match flag has no target, so it takes a can for the same
      # term, or one covering the whole ingredient. A text can that names only
      # part of a phrase never clears a flag raised by another part.
      def covering_can(finding)
        cans = finding.target ? covering(finding.target, %w[can]).map(&:first) : whole_ingredient_node_cans
        (cans + same_text_cans(finding.restriction)).first
      end

      def whole_ingredient_node_cans
        direct = targets.find { |target| target.via == :direct } or return []
        covering(direct, %w[can]).map(&:first)
      end

      def same_text_cans(restriction)
        wanted = [ normalized(resolution.input) ]
        wanted << normalized(restriction.term) if restriction && restriction.taxonomy_node.nil?
        without_node.select { |can| can.can? && wanted.include?(normalized(can.term)) }
      end

      def normalized(text) = Taxonomy::Normalizer.call(text)

      def cannot_applies?
        @cannot_applies ||= text_covering(%w[cannot]).any? || targets.any? { |target| covering(target, %w[cannot]).any? }
      end

      def clearable?(finding)
        finding.restriction.nil? || finding.restriction.intolerance? || finding.restriction.condition?
      end

      def marked_ok_note(finding, can)
        why = cannot_applies? ? "a cannot always wins" : "the #{finding.restriction.kind} still applies"
        Flag.new(tier: finding.flag.tier, ingredient:, source: finding.flag.source, overridden: true,
          override_reason: Flag::MARKED_OK, reason: "you marked '#{can.term}' as can, but #{why}")
      end
    end

    # Whole-word or whole-phrase match of a restriction term against an ingredient,
    # both normalized. Used only when the restriction has no taxonomy node.
    module TextMatch
      module_function

      def match?(term, resolution)
        haystack = resolution.normalized.to_s
        return false if haystack.empty?

        Taxonomy::Normalizer.candidates(Taxonomy::Normalizer.call(term)).compact_blank.any? do |needle|
          haystack.match?(/(?<![\p{L}\p{N}])#{Regexp.escape(needle)}(?![\p{L}\p{N}])/)
        end
      end
    end

    # Human-readable reasons. Restriction terms appear here; patient names never do.
    module Reasons
      module_function

      def covered(ingredient, restriction, relation, ingredient_node)
        node = restriction.taxonomy_node
        text =
          case restriction.kind
          when "cannot" then cannot_phrase(ingredient, restriction, ingredient_node)
          else "#{ingredient} #{link(ingredient, restriction, relation, node, ingredient_node)} (#{label(restriction)})"
          end
        text + entry_note(restriction)
      end

      def contained(ingredient, phrase, restriction)
        "'#{phrase}' appears in '#{ingredient}' (#{label(restriction)})" + entry_note(restriction)
      end

      def text(ingredient, restriction)
        "#{ingredient}: text match to '#{normalized_term(restriction)}' (#{label(restriction)})"
      end

      def fuzzy(ingredient, restriction, ingredient_node)
        node = restriction.taxonomy_node
        covered = node == ingredient_node ? "" : ", which is under #{node.name}"
        "#{ingredient}: fuzzy match to #{ingredient_node.name}#{covered} — check the label (#{label(restriction)})" +
          entry_note(restriction)
      end

      def cannot_phrase(ingredient, restriction, ingredient_node)
        node = restriction.taxonomy_node
        return "you marked #{ingredient} as cannot" if node == ingredient_node && normalized_term(restriction) == node.name

        "#{ingredient} is under #{node.name} — you marked '#{restriction.term}' as cannot"
      end

      def link(ingredient, restriction, relation, node, ingredient_node)
        return "is high in #{node.name}" if node.nutrient?
        if node == ingredient_node
          return Taxonomy::Normalizer.call(ingredient) == node.name ? "is listed" : "is #{node.name}"
        end
        return "is in the #{node.name} group" if relation == :membership

        restriction.allergy? && node.allergen? ? "is a #{node.name}" : "contains #{node.name}"
      end

      def label(restriction)
        term = normalized_term(restriction)
        case restriction.kind
        when "allergy" then "allergy"
        when "cannot" then "cannot"
        when "intolerance" then term.include?("intoleran") ? term : "#{term} intolerance"
        else term
        end
      end

      # A restriction that was fuzzy-matched when entered names what the nurse typed.
      def entry_note(restriction)
        return "" unless restriction.match_type == "fuzzy"

        " — you entered '#{restriction.term}', matched to #{restriction.taxonomy_node.name}"
      end

      def normalized_term(restriction) = Taxonomy::Normalizer.call(restriction.term)
    end
  end
end
