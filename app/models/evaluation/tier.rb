module Evaluation
  # The four outcomes, ordered worst first: CONFLICT > POSSIBLE_CONFLICT > UNKNOWN > NONE.
  # Tiers compare with each other (CONFLICT > UNKNOWN) but expose only a name,
  # never a number: there are no scores or percentages.
  class Tier
    include Comparable

    attr_reader :name

    def initialize(name, severity)
      @name = name
      @severity = severity
      freeze
    end

    CONFLICT = new(:conflict, 3)
    POSSIBLE_CONFLICT = new(:possible_conflict, 2)
    UNKNOWN = new(:unknown, 1)
    NONE = new(:none, 0)

    ALL = [ CONFLICT, POSSIBLE_CONFLICT, UNKNOWN, NONE ].freeze
    private_class_method :new

    class << self
      # Accepts a Tier or its name (:conflict, "possible_conflict").
      def fetch(value)
        return value if value.is_a?(Tier)

        ALL.find { |tier| tier.name == value.to_s.to_sym } or raise ArgumentError, "unknown tier: #{value.inspect}"
      end
      alias_method :[], :fetch

      # The worst of the given tiers; NONE when there are none.
      def worst(*tiers)
        tiers.flatten.compact.map { |tier| fetch(tier) }.max || NONE
      end
    end

    def <=>(other)
      return unless other.is_a?(Tier)

      severity <=> other.severity
    end

    def none? = equal?(NONE)
    def to_sym = name
    def to_s = name.to_s
    def inspect = "#<Evaluation::Tier #{name}>"

    protected

    attr_reader :severity
  end
end
