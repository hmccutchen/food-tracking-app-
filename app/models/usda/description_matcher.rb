module Usda
  # Links a USDA food description ("Nuts, almonds") to a taxonomy node.
  #
  # USDA descriptions are inverted: the first comma segment is the general
  # kind, later segments narrow it ("Nuts, almonds"; "Cheese, cheddar").
  # Qualifier segments ("without salt", "low sodium", "with added vitamin D")
  # describe preparation, not the food, and are dropped first so "without salt"
  # never links a potato to sodium.
  #
  # Steps, first hit wins:
  #   1. exact/alias on the whole description, then the first two segments
  #      reversed ("Oil, sesame" → "sesame oil"), then segments 2..n
  #      ("Nuts, almonds" → "almonds")
  #   2. phrase scan of segments 2..n ("Nuts, pistachio nuts" → pistachio)
  #   3. exact/alias on the first segment ("Milk, whole, ..." → milk)
  #   4. phrase scan of the whole description ("Soy sauce made from soy and
  #      wheat (shoyu)" → soy sauce, also mentions soy and wheat)
  #   5. the best fuzzy match of the whole, reversed pair or first segment,
  #      marked fuzzy so the UI asks the nurse to check it. Never on lone
  #      later segments: "whole" or "raw" would fuzzy-match anything.
  #   6. unresolved.
  class DescriptionMatcher
    QUALIFIER = /\A(?:with|without|no|not|low|reduced|added|less|free)\b/i

    Match = Data.define(:node, :match_type, :reason) do
      def linked? = %w[exact alias phrase].include?(match_type)
      def fuzzy? = match_type == "fuzzy"
      def unresolved? = match_type == "unresolved"
    end

    # The shared resolver with its trigram step switched off, for the cheap
    # first pass over every candidate. Taxonomy::Resolver itself is untouched;
    # a fuzzy-or-unresolved term comes back unresolved, still with its phrase scan.
    class ExactResolver < Taxonomy::Resolver
      private

      def fuzzy(_text, _normalized) = nil
    end

    def initialize(resolver: Taxonomy::Resolver.new, exact_resolver: ExactResolver.new)
      @resolver = resolver
      @exact_resolver = exact_resolver
    end

    def match(description) = match_all([ description ]).first

    def match_all(descriptions)
      plans = descriptions.map { |description| [ description, candidates(description) ] }
      direct = resolve(plans.flat_map { |_, terms| terms.all }, allow_fuzzy: false)

      pending = []
      matches = plans.map do |description, terms|
        found = direct_match(terms.specific, direct) ||
          terms.later.lazy.filter_map { |term| phrase_match(term, direct) }.first ||
          direct_match([ terms.head ], direct) ||
          phrase_match(terms.whole, direct)
        pending << [ description, terms ] unless found
        found
      end

      fuzzy = resolve(pending.flat_map { |_, terms| terms.fuzzy }, allow_fuzzy: true)
      fuzzy_matches = pending.to_h { |description, terms| [ description, fuzzy_match(description, terms.fuzzy, fuzzy) ] }

      matches.zip(descriptions).map { |found, description| found || fuzzy_matches.fetch(description) }
    end

    # Normalized candidate strings for one description.
    Candidates = Data.define(:whole, :reversed, :later, :head) do
      def specific = [ whole, reversed, *later ].compact.uniq
      def fuzzy = [ whole, reversed, head ].compact.uniq
      def all = [ *specific, head ].compact.uniq
    end

    def candidates(description)
      segments = description.to_s.split(",").map { |segment| Taxonomy::Normalizer.call(segment) unless qualifier?(segment) }
      segments = segments.compact_blank
      return Candidates.new(whole: nil, reversed: nil, later: [], head: nil) if segments.empty?

      Candidates.new(
        whole: segments.join(" "),
        reversed: (segments.size >= 2 ? "#{segments[1]} #{segments[0]}" : nil),
        later: segments.drop(1).uniq,
        head: segments.first
      )
    end

    private

    attr_reader :resolver, :exact_resolver

    def qualifier?(segment) = segment.strip.match?(QUALIFIER)

    # { normalized term => Resolution }
    def resolve(terms, allow_fuzzy:)
      terms = terms.uniq
      return {} if terms.empty?

      terms.zip((allow_fuzzy ? resolver : exact_resolver).resolve_all(terms)).to_h
    end

    def direct_match(terms, resolutions)
      terms.each do |term|
        resolution = resolutions[term]
        next unless resolution && %i[exact alias].include?(resolution.match_type)

        return Match.new(node: resolution.node, match_type: resolution.match_type.to_s,
          reason: "matched to #{resolution.node.name} via '#{term}'")
      end
      nil
    end

    def phrase_match(term, resolutions)
      contained = resolutions[term]&.contained.presence or return

      node, phrase = contained.first
      reason = "matched to #{node.name} via '#{phrase}' in the description"
      others = contained.drop(1).map { |other, _| other.name }
      reason += " (also mentions #{others.to_sentence})" if others.any?
      Match.new(node:, match_type: "phrase", reason:)
    end

    def fuzzy_match(description, terms, resolutions)
      best = terms.filter_map { |term| resolutions[term] }.select(&:fuzzy?).max_by(&:similarity)
      unless best
        return Match.new(node: nil, match_type: "unresolved",
          reason: "no ingredient match for '#{description.to_s.strip}'")
      end

      Match.new(node: best.node, match_type: "fuzzy",
        reason: "fuzzy match to #{best.node.name} via '#{best.normalized}' " \
                "(similarity #{format('%.2f', best.similarity)}) — please check")
    end
  end
end
