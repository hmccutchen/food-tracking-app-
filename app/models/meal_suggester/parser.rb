class MealSuggester
  # Turns a provider's reply text into Suggestions, or raises
  # Ai::MalformedResponseError. Strict: anything off-shape is rejected rather
  # than guessed at. Only JSON.parse touches the text; nothing is evaluated.
  class Parser
    MAX_TEXT = 200_000
    MEALS = 1..5
    INGREDIENTS = 1..40
    MAX_PREP_NOTES = 10
    MAX_STRING = 120

    Invalid = Class.new(StandardError)

    def initialize(provider)
      @provider = provider.to_s
    end

    def call(text)
      data = JSON.parse(extract_json(text.to_s))
      meals = data.is_a?(Hash) ? data["meals"] : nil
      check(meals.is_a?(Array) && MEALS.cover?(meals.size))
      meals.map { |meal| suggestion(meal) }
    rescue JSON::ParserError, Invalid
      raise Ai::MalformedResponseError.new(@provider), cause: nil
    end

    private

    # Strips ``` fences and any prose around the outermost {...}.
    def extract_json(text)
      check(text.length <= MAX_TEXT)
      fenced = text[/```[a-z]*\s*\n?(.*?)```/mi, 1]
      body = fenced || text
      first = body.index("{")
      last = body.rindex("}")
      check(first && last && last > first)
      body[first..last]
    end

    def suggestion(meal)
      check(meal.is_a?(Hash))
      MealSuggester::Suggestion.new(
        dish: string(meal["dish"]),
        ingredients: ingredients(meal["ingredients"]),
        prep_notes: prep_notes(meal["prep_notes"])
      )
    end

    def ingredients(value)
      check(value.is_a?(Array))
      list = value.map { |item| string(item) }.uniq
      check(INGREDIENTS.cover?(list.size))
      list
    end

    def prep_notes(value)
      check(value.is_a?(Array) && value.size <= MAX_PREP_NOTES && value.all?(String))
      value.map(&:strip).compact_blank
    end

    def string(value)
      check(value.is_a?(String))
      stripped = value.strip
      check(!stripped.empty? && stripped.length <= MAX_STRING)
      stripped
    end

    def check(condition)
      raise Invalid unless condition
    end
  end
end
