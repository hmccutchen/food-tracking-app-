class TaxonomyAlias < ApplicationRecord
  belongs_to :taxonomy_node, inverse_of: :aliases

  normalizes :term, with: ->(term) { Taxonomy::Normalizer.call(term) }

  validates :term, presence: true, uniqueness: true
end
