module Evaluation
  # One finding for one patient and one ingredient. Every flag carries a reason a
  # nurse can read. An overridden flag is kept (never dropped) and does not count
  # toward the patient's tier.
  Flag = Data.define(:tier, :ingredient, :reason, :source, :overridden, :override_reason) do
    const_set(:SOURCES, %i[allergy intolerance condition cannot fuzzy ambiguous unresolved missing_list].freeze)
    const_set(:MARKED_OK, "you marked this OK")

    def initialize(tier:, reason:, source:, ingredient: nil, overridden: false, override_reason: nil)
      raise ArgumentError, "a flag needs a human-readable reason" if reason.to_s.strip.empty?

      source = source.to_sym
      raise ArgumentError, "unknown flag source: #{source.inspect}" unless self.class::SOURCES.include?(source)

      super(tier: Tier.fetch(tier), ingredient:, reason: reason.to_s, source:, overridden: overridden ? true : false,
        override_reason:)
    end

    # Plain JSON-ready hash for storing a result (M11). from_h reverses it.
    def self.from_h(hash)
      hash = hash.to_h.symbolize_keys
      new(tier: hash.fetch(:tier), ingredient: hash[:ingredient], reason: hash.fetch(:reason),
        source: hash.fetch(:source), overridden: hash[:overridden], override_reason: hash[:override_reason])
    end

    def to_h
      { "tier" => tier.to_s, "ingredient" => ingredient, "reason" => reason, "source" => source.to_s,
        "overridden" => overridden, "override_reason" => override_reason }
    end

    def active? = !overridden

    # The same finding, kept visible but no longer counted ("you marked this OK").
    def override(reason = self.class::MARKED_OK)
      with(overridden: true, override_reason: reason)
    end
  end
end
