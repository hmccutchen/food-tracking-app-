# A food imported from USDA FoodData Central. Foundation and SR Legacy records
# carry no ingredient list (ingredients_text is nil); Branded will.
class Food < ApplicationRecord
  SEARCH_LIMIT = 25
  # pg_trgm word_similarity cut-off for search. Low enough that "almnd" finds
  # "Nuts, almonds" (~0.5); the index-backed <% operator reads it per query.
  SEARCH_THRESHOLD = 0.3
  MATCH_TYPES = %w[exact alias phrase fuzzy unresolved].freeze

  belongs_to :taxonomy_node, optional: true

  validates :fdc_id, presence: true, uniqueness: true
  validates :description, :source, :data_type, :imported_at, presence: true
  validates :match_type, inclusion: { in: MATCH_TYPES }

  # Typo-tolerant trigram search over descriptions, best match first.
  # Returns an Array (the similarity threshold is set for this query only).
  def self.search(query, limit: SEARCH_LIMIT)
    term = normalize_query(query)
    return [] if term.blank?

    transaction do
      connection.select_value(
        sanitize_sql_array([ "SELECT set_config('pg_trgm.word_similarity_threshold', ?, true)", SEARCH_THRESHOLD.to_s ])
      )
      includes(:taxonomy_node)
        .where("foods.description ILIKE :like OR :term <% foods.description",
          like: "%#{sanitize_sql_like(term)}%", term:)
        .order(Arel.sql(sanitize_sql_array([
          "word_similarity(:term, foods.description) DESC, similarity(:term, foods.description) DESC, " \
          "length(foods.description), foods.id", { term: }
        ])))
        .limit(limit)
        .to_a
    end
  end

  def self.normalize_query(query)
    query.to_s.downcase.gsub(/[^\p{L}\p{N}\s'-]/, " ").squish.first(100)
  end

  def source_label = Usda::Sources.label_for(source)

  def fuzzy_link? = match_type == "fuzzy"
  def linked? = taxonomy_node_id.present? && %w[exact alias phrase].include?(match_type)
end
