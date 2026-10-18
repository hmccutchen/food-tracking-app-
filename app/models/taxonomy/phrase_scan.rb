module Taxonomy
  # Finds known node names and aliases inside a longer phrase. The phrase is
  # split on spaces and hyphens into n-grams of up to MAX_TOKENS tokens; each
  # n-gram (and its singular) is looked up exactly, never fuzzily. Longest
  # matches win and matches never overlap, so "peanut butter cookies" finds
  # peanut butter (→ peanut) and not butter.
  module PhraseScan
    MAX_TOKENS = 4
    TOKEN = /[^\s-]+/

    module_function

    # Every string the scan may look up, for batching into the resolver's queries.
    def terms(normalized)
      grams(tokens(normalized)).flat_map { |gram| gram[:terms] }.uniq
    end

    # [[node, phrase], ...] in phrase order, one entry per node. nodes is
    # { name => node }, aliases is { term => alias with taxonomy_node loaded }.
    def find(normalized, nodes, aliases) = scan(normalized, nodes, aliases).first

    # [found, leftover]: found as in #find; leftover is the runs of tokens no
    # match covered, in order ("diced chicken breast in sauce" → [["diced"],
    # ["in", "sauce"]]).
    def scan(normalized, nodes, aliases)
      tokens = tokens(normalized)
      taken = Array.new(tokens.size, false)
      found = []

      grams(tokens).each do |gram|
        next if taken[gram[:range]].any?

        node = lookup(gram[:terms], nodes, aliases) or next
        taken.fill(true, gram[:range])
        found << [ gram[:range].begin, node, gram[:phrase] ]
      end

      found = found.sort_by(&:first).map { |_, node, phrase| [ node, phrase ] }.uniq(&:first)
      [ found, leftover(tokens, taken) ]
    end

    def leftover(tokens, taken)
      tokens.each_with_index.chunk_while { |(_, a), (_, b)| b == a + 1 && taken[a] == taken[b] }
        .reject { |run| taken[run.first.last] }
        .map { |run| run.map { |match, _| match[0] } }
    end

    def tokens(normalized)
      normalized.to_s.to_enum(:scan, TOKEN).map { Regexp.last_match }
    end

    # Longest first, then left to right.
    def grams(tokens)
      MAX_TOKENS.downto(1).flat_map do |size|
        (0..tokens.size - size).map do |start|
          slice = tokens[start, size]
          phrase = slice.first.string[slice.first.begin(0)...slice.last.end(0)]
          joined = slice.map { |match| match[0] }.join(" ")
          terms = [ joined, phrase ].uniq.flat_map { |term| Normalizer.candidates(term) }.uniq
          { range: start...(start + size), phrase:, terms: }
        end
      end
    end

    def lookup(terms, nodes, aliases)
      terms.each { |term| return nodes[term] if nodes.key?(term) }
      terms.each { |term| return aliases[term].taxonomy_node if aliases.key?(term) }
      nil
    end
  end
end
