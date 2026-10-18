class MealSuggester
  # Replaces patient names in free text with "the patient" before anything
  # reaches a provider. Case-insensitive, whole words only. Full names go
  # first, then each part of a name (split on spaces, commas and hyphens),
  # so "Ann", "Ann Lee" and "Mary" from "Mary-Jane Smith" all go. Single
  # letters count too: a patient entered as "Q" is still a name.
  #
  # Errs toward privacy: a patient called "Basil" also scrubs the herb from
  # the request. A worse suggestion beats a name leaving the app.
  module Redactor
    REPLACEMENT = "the patient".freeze
    # Scripts written without spaces between words, or with particles joined
    # straight onto names (Korean). Whole-word matching never fires there, so
    # names in these scripts are matched anywhere in the text.
    UNSPACED_SCRIPT = /[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}\p{Thai}\p{Lao}\p{Khmer}\p{Myanmar}]/

    def self.call(text, names)
      words = Array(names).flat_map { |name| [ name.to_s.squish, *name.to_s.split(/[\s,]+/), *name.to_s.split(/[\s,-]+/) ] }
      words = words.map { |word| word.delete_suffix(".") }.reject(&:empty?).uniq
      words.sort_by { |word| -word.length }.reduce(text.to_s) do |result, word|
        result.gsub(pattern(word), REPLACEMENT)
      end
    end

    # Straight, curly and backtick apostrophes all match each other, so
    # "O'Brien" on file still catches "O’Brien" typed on a phone.
    APOSTROPHES = "['’‘`ʼ]".freeze

    def self.pattern(word)
      body = Regexp.escape(word).gsub(/['’‘`ʼ]/, APOSTROPHES)
      return /#{body}/i if word.match?(UNSPACED_SCRIPT)

      /(?<![[:alnum:]])#{body}(?![[:alnum:]])/i
    end
  end
end
