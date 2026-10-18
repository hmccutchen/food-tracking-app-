# Puts a node into a cross-cutting group (e.g. soy sauce into sodium) without
# changing its single tree parent.
class TaxonomyMembership < ApplicationRecord
  belongs_to :node, class_name: "TaxonomyNode", inverse_of: :memberships
  belongs_to :group, class_name: "TaxonomyNode", inverse_of: :member_links

  validates :node_id, uniqueness: { scope: :group_id }
  validate :not_own_group

  private

  def not_own_group
    errors.add(:group, "can't be the node itself") if node_id.present? && node_id == group_id
  end
end
