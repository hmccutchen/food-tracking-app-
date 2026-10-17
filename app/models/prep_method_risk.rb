# Links a preparation method to a taxonomy node it can bring in.
class PrepMethodRisk < ApplicationRecord
  belongs_to :prep_method, inverse_of: :prep_method_risks
  belongs_to :taxonomy_node

  validates :taxonomy_node_id, uniqueness: { scope: :prep_method_id }
end
