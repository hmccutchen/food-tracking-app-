module Taxonomy
  # The outcome of resolving one ingredient term. Unresolved is an explicit
  # result with a reason, never nil.
  #
  # contained: [[node, phrase], ...] known names or aliases found inside the
  # text by Resolver's phrase scan ("low-sodium soy sauce" → soy sauce). Only
  # filled when the whole phrase was fuzzy or unresolved; empty otherwise.
  #
  # leftover: [["diced"], ["with", "sauce"]] runs of words the scan did not
  # cover, filled alongside contained. The engine checks them against the
  # descriptor words.
  Resolution = Data.define(:input, :normalized, :node, :match_type, :similarity, :reason, :contained, :leftover) do
    def initialize(contained: [], leftover: [], **attributes)
      super(contained: contained.freeze, leftover: leftover.freeze, **attributes)
    end

    def resolved? = !node.nil?
    def unresolved? = match_type == :unresolved
    def fuzzy? = match_type == :fuzzy
    def contained_nodes = contained.map(&:first)
  end
end
