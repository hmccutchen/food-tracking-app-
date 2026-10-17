# Turns free text ("No Nuts!", "nut-free") into the canonical lowercase form
# that taxonomy names and aliases are stored and matched in.
module Taxonomy
  module Normalizer
    NEGATION_PREFIX = /\A(?:no|without|free of|free from|avoid|avoids|avoiding)\s+/
    FREE_SUFFIX = /[\s-]free\z/

    module_function

    def call(text)
      term = text.to_s.downcase.tr("’‘", "''")
      term = term.gsub(/[^\p{L}\p{N}\s'-]/, " ")
      term = term.gsub(/(?<![\p{L}\p{N}])['-]+|['-]+(?![\p{L}\p{N}])/, " ")
      term = term.squish
      term = term.sub(NEGATION_PREFIX, "") while term.match?(NEGATION_PREFIX)
      term.sub(FREE_SUFFIX, "").strip
    end

    # The normalized term plus, when it looks plural, a conservative singular.
    def candidates(normalized)
      [ normalized, singularize(normalized) ].compact.uniq
    end

    def singularize(term)
      head, _, last = term.rpartition(" ")
      singular =
        case last
        when /\A(.{2,})ies\z/ then "#{$1}y"
        when /\A(.{2,}(?:ss|sh|ch|x|z))es\z/ then $1
        when /\A(.{2,}[^su])s\z/ then $1
        end
      return unless singular

      head.empty? ? singular : "#{head} #{singular}"
    end
  end
end
