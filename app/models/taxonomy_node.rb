class TaxonomyNode < ApplicationRecord
  ANCESTRY_SQL = <<~SQL.freeze
    WITH RECURSIVE chain(id, parent_id, depth) AS (
      SELECT id, parent_id, 0 FROM taxonomy_nodes WHERE id = :id
      UNION ALL
      SELECT n.id, n.parent_id, chain.depth + 1
      FROM taxonomy_nodes n JOIN chain ON n.id = chain.parent_id
      WHERE chain.depth < 64
    )
    SELECT id, depth FROM chain
  SQL

  DESCENDANTS_SQL = <<~SQL.freeze
    WITH RECURSIVE tree(id) AS (
      SELECT id FROM taxonomy_nodes WHERE parent_id = :id
      UNION
      SELECT n.id FROM taxonomy_nodes n JOIN tree ON n.parent_id = tree.id
    )
    SELECT id FROM tree
  SQL

  enum :kind, { allergen: "allergen", intolerance: "intolerance", ingredient: "ingredient", category: "category",
                 nutrient: "nutrient" },
    validate: true

  belongs_to :parent, class_name: "TaxonomyNode", optional: true, inverse_of: :children
  has_many :children, class_name: "TaxonomyNode", foreign_key: :parent_id, inverse_of: :parent, dependent: :nullify
  has_many :aliases, class_name: "TaxonomyAlias", dependent: :delete_all, inverse_of: :taxonomy_node
  # Groups this node belongs to outside its tree (soy sauce → sodium).
  has_many :memberships, class_name: "TaxonomyMembership", foreign_key: :node_id, dependent: :delete_all,
    inverse_of: :node
  has_many :groups, through: :memberships
  # Nodes that belong to this group outside the tree (sodium → soy sauce).
  has_many :member_links, class_name: "TaxonomyMembership", foreign_key: :group_id, dependent: :delete_all,
    inverse_of: :group
  has_many :members, through: :member_links, source: :node

  normalizes :name, with: ->(name) { Taxonomy::Normalizer.call(name) }

  before_validation { self.slug = name.to_s.parameterize }

  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  validate :parent_is_not_self_or_descendant

  # Nearest first: [self, parent, grandparent, ...]
  def self_and_ancestors
    chain = self.class.sanitize_sql_array([ ANCESTRY_SQL, { id: } ])
    self.class.joins("JOIN (#{chain}) chain ON chain.id = taxonomy_nodes.id").order("chain.depth")
  end

  def ancestors
    self_and_ancestors.where("chain.depth > 0")
  end

  def descendants
    self.class.where("taxonomy_nodes.id IN (#{DESCENDANTS_SQL})", id:)
  end

  # A "tree nut" restriction covers "almond": other is this node or one of its descendants.
  # Group membership also counts: "sodium" covers "soy sauce" because soy sauce
  # (or one of its ancestors) is a member of sodium or of one of sodium's descendants.
  def covers?(other)
    return false if other.nil? || id.nil?
    return true if other.id == id

    chain = other.self_and_ancestors.unscope(:order)
    chain.where(id:).exists? ||
      TaxonomyMembership.where(node_id: chain.select(:id))
        .where("group_id = :id OR group_id IN (#{DESCENDANTS_SQL})", id:).exists?
  end

  private

  def parent_is_not_self_or_descendant
    return if parent_id.nil? || new_record?

    if parent_id == id || descendants.exists?(id: parent_id)
      errors.add(:parent, "can't be this node or one of its descendants")
    end
  end
end
