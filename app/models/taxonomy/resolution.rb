module Taxonomy
  # The outcome of resolving one ingredient term. Unresolved is an explicit
  # result with a reason, never nil.
  #
  # contained: [[node, phrase], ...] known names or aliases found inside the
  # text by Resolver's phrase scan ("low-sodium soy sauce" → soy sauce). Only
  # filled when the whole phrase was fuzzy or unresolved; empty otherwise.
  Resolution = Data.define(:input, :normalized, :node, :match_type, :similarity, :reason, :contained) do
    def initialize(contained: [], **attributes)
      super(contained: contained.freeze, **attributes)
    end

    def resolved? = !node.nil?
    def unresolved? = match_type == :unresolved
    def fuzzy? = match_type == :fuzzy
    def contained_nodes = contained.map(&:first)
  end
end
