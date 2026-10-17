# Asks the nurse's chosen AI provider for meal ideas and returns them as
# plain data. It never decides whether a meal suits a patient: the caller runs
# every suggestion through Evaluation::Engine, which alone sets tiers.
#
#   result = MealSuggester.new(credential).suggest(
#     terms: avoid_list.to_terms,          # restriction terms only
#     request: "warm dinner, soft foods",  # the nurse's own words
#     redact: avoid_list.patient_names,    # scrubbed from the request
#     rejected: [ "butter" ]               # what got a previous attempt dropped
#   )
#   result.suggestions # => [#<data Suggestion dish=..., ingredients=[...], prep_notes=[...]>]
#
# Raises an Ai::Error subclass on any failure, including an unreadable reply
# (Ai::MalformedResponseError), which the caller counts as a failed attempt.
class MealSuggester
  Suggestion = Data.define(:dish, :ingredients, :prep_notes)
  Result = Data.define(:suggestions)

  def initialize(credential, adapter: nil)
    @credential = credential
    @adapter = adapter || Ai::Adapters.for(credential)
  end

  def suggest(terms:, request:, rejected: [], count: 3, redact: [])
    prompt = Prompt.new(terms:, request:, rejected:, count:, redact:)
    Result.new(suggestions: Parser.new(@credential.provider).call(@adapter.complete(prompt)))
  end
end
