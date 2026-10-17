module Taxonomy
  # Maps free-text ingredient or restriction terms to taxonomy nodes:
  # exact node name, then exact alias, then trigram fuzzy match, else unresolved.
  class Resolver
    FUZZY_THRESHOLD = 0.4

    def resolve(text)
      resolve_all([ text ]).first
    end

    def resolve_all(texts)
      inputs = Array(texts).map { |text| [ text, Normalizer.call(text) ] }
      terms = inputs.flat_map { |_, normalized| Normalizer.candidates(normalized) }.uniq.compact_blank
      nodes = TaxonomyNode.where(name: terms).index_by(&:name)
      aliases = TaxonomyAlias.includes(:taxonomy_node).where(term: terms).index_by(&:term)

      inputs.map { |text, normalized| build(text, normalized, nodes, aliases) }
    end

    def covers?(restriction_node, ingredient_node)
      restriction_node.present? && restriction_node.covers?(ingredient_node)
    end

    private

    def build(text, normalized, nodes, aliases)
      return unresolved(text, normalized, "empty ingredient") if normalized.blank?

      candidates = Normalizer.candidates(normalized)
      exact(text, normalized, candidates, nodes) ||
        aliased(text, normalized, candidates, aliases) ||
        fuzzy(text, normalized) ||
        unresolved(text, normalized, "'#{text.to_s.strip}' not recognized")
    end

    def exact(text, normalized, candidates, nodes)
      term = candidates.find { |candidate| nodes.key?(candidate) } or return

      reason = "exact match to '#{term}'"
      reason += " (from '#{normalized}')" unless term == normalized
      result(text, normalized, nodes[term], :exact, nil, reason)
    end

    def aliased(text, normalized, candidates, aliases)
      term = candidates.find { |candidate| aliases.key?(candidate) } or return

      node = aliases[term].taxonomy_node
      result(text, normalized, node, :alias, nil, "alias '#{term}' → '#{node.name}'")
    end

    def fuzzy(text, normalized)
      match = [ fuzzy_by_name(normalized), fuzzy_by_alias(normalized) ].compact.max_by(&:similarity) or return
      return if match.similarity < FUZZY_THRESHOLD

      similarity = match.similarity.round(2)
      via = match.matched_term == match.name ? "" : " via alias '#{match.matched_term}'"
      reason = "fuzzy match to '#{match.name}'#{via} (similarity #{format('%.2f', similarity)})"
      result(text, normalized, match, :fuzzy, similarity, reason)
    end

    def fuzzy_by_name(term)
      TaxonomyNode
        .select("taxonomy_nodes.*", "taxonomy_nodes.name AS matched_term", sanitize([ "similarity(taxonomy_nodes.name, ?)::float AS similarity", term ]))
        .where("taxonomy_nodes.name % ?", term)
        .order(Arel.sql("similarity DESC, length(taxonomy_nodes.name)"))
        .first
    end

    def fuzzy_by_alias(term)
      TaxonomyNode.joins(:aliases)
        .select("taxonomy_nodes.*", "taxonomy_aliases.term AS matched_term", sanitize([ "similarity(taxonomy_aliases.term, ?)::float AS similarity", term ]))
        .where("taxonomy_aliases.term % ?", term)
        .order(Arel.sql("similarity DESC, length(taxonomy_aliases.term)"))
        .first
    end

    def sanitize(sql_and_binds) = TaxonomyNode.sanitize_sql_array(sql_and_binds)

    def result(text, normalized, node, match_type, similarity, reason)
      Resolution.new(input: text, normalized:, node:, match_type:, similarity:, reason:)
    end

    def unresolved(text, normalized, reason)
      result(text, normalized, nil, :unresolved, nil, reason)
    end
  end
end
