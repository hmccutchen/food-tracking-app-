module Taxonomy
  # The outcome of resolving one ingredient term. Unresolved is an explicit
  # result with a reason, never nil.
  Resolution = Data.define(:input, :normalized, :node, :match_type, :similarity, :reason) do
    def resolved? = !node.nil?
    def unresolved? = match_type == :unresolved
    def fuzzy? = match_type == :fuzzy
  end
end
