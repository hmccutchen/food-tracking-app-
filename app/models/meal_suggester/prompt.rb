class MealSuggester
  # The one prompt every provider gets. It carries restriction terms, the
  # nurse's request (with patient names scrubbed) and anything a previous
  # attempt was dropped for. Never names, never ids, and no promise about
  # suitability: the engine checks every ingredient afterwards.
  class Prompt
    MAX_MEALS = 5
    MAX_REQUEST_LENGTH = 1_000

    # Sent as structured output where RubyLLM supports it (all three of ours).
    # Lengths and counts are enforced by Parser, not here: not every
    # provider's schema dialect accepts them.
    SCHEMA = {
      name: "meal_suggestions",
      schema: {
        type: "object",
        properties: {
          meals: {
            type: "array",
            items: {
              type: "object",
              properties: {
                dish: { type: "string" },
                ingredients: { type: "array", items: { type: "string" } },
                prep_notes: { type: "array", items: { type: "string" } }
              },
              required: %w[dish ingredients prep_notes],
              additionalProperties: false
            }
          }
        },
        required: %w[meals],
        additionalProperties: false
      }
    }.freeze

    SHAPE = '{"meals":[{"dish":"...","ingredients":["..."],"prep_notes":["..."]}]}'.freeze

    attr_reader :terms, :request, :rejected, :count

    def initialize(terms:, request:, rejected: [], count: 3, redact: [])
      @terms = clean_list(terms, redact)
      @rejected = clean_list(rejected, redact) - @terms
      @request = Redactor.call(request.to_s.squish.first(MAX_REQUEST_LENGTH), redact)
      @count = count.to_i.clamp(1, MAX_MEALS)
    end

    def schema = SCHEMA

    def text
      [ ask, avoid_section, rejected_section, format_section ].compact.join("\n\n") + "\n"
    end
    alias to_s text

    private

    def ask
      meals = count == 1 ? "1 meal" : "#{count} different meals"
      request.empty? ? "Suggest #{meals}." : "Suggest #{meals} for this request: #{request}"
    end

    def avoid_section
      return if terms.empty?

      "Leave these out entirely. Do not use them, or any ingredient that contains them or is made from them:\n" +
        bullets(terms)
    end

    def rejected_section
      return if rejected.empty?

      "An earlier suggestion was dropped because it used these. Do not use them either:\n" + bullets(rejected)
    end

    def format_section
      <<~TEXT.chomp
        Reply with JSON only, no other text, in exactly this shape:
        #{SHAPE}

        - "dish" is the meal's name.
        - "ingredients" lists every ingredient, one per array element. Name each one specifically, for example "low-sodium soy sauce", not "sauce".
        - "prep_notes" are short preparation tips. Use [] if there are none.
      TEXT
    end

    def bullets(items) = items.map { |item| "- #{item}" }.join("\n")

    def clean_list(items, redact)
      Array(items).map { |item| Redactor.call(item.to_s.squish, redact) }.compact_blank.uniq
    end
  end
end
