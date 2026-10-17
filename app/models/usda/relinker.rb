module Usda
  # Re-runs taxonomy linking over every imported food, for when the taxonomy
  # has grown since the import. Only rows whose link changed are written.
  class Relinker
    BATCH_SIZE = 1_000

    Summary = Struct.new(:checked, :changed, :linked, :fuzzy, :unresolved, keyword_init: true) do
      def to_s
        "Relinked #{checked} USDA foods: #{changed} changed. " \
          "#{linked} linked, #{fuzzy} fuzzy (please check), #{unresolved} unresolved"
      end
    end

    def initialize(matcher: DescriptionMatcher.new)
      @matcher = matcher
    end

    def call
      summary = Summary.new(checked: 0, changed: 0, linked: 0, fuzzy: 0, unresolved: 0)

      Food.select(:id, :description, :taxonomy_node_id, :match_type, :match_reason)
        .find_in_batches(batch_size: BATCH_SIZE) do |foods|
        links = @matcher.match_all(foods.map(&:description))
        foods.zip(links).each do |food, link|
          summary.checked += 1
          tally(summary, link)
          attributes = { taxonomy_node_id: link.node&.id, match_type: link.match_type, match_reason: link.reason }
          next if attributes.all? { |name, value| food[name] == value }

          Food.where(id: food.id).update_all(attributes.merge(updated_at: Time.current))
          summary.changed += 1
        end
      end

      summary
    end

    private

    def tally(summary, link)
      if link.linked? then summary.linked += 1
      elsif link.fuzzy? then summary.fuzzy += 1
      else summary.unresolved += 1
      end
    end
  end
end
