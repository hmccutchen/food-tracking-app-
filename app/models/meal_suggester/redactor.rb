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

    def self.call(text, names)
      words = Array(names).flat_map { |name| [ name.to_s.squish, *name.to_s.split(/[\s,]+/), *name.to_s.split(/[\s,-]+/) ] }
      words = words.map { |word| word.delete_suffix(".") }.reject(&:empty?).uniq
      words.sort_by { |word| -word.length }.reduce(text.to_s) do |result, word|
        result.gsub(/(?<![[:alnum:]])#{Regexp.escape(word)}(?![[:alnum:]])/i, REPLACEMENT)
      end
    end
  end
end
