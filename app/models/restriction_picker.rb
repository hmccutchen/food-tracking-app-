# The checklist on the "choose items" page: every taxonomy node, grouped into
# sections a nurse can scan (allergens, nutrients, common food categories,
# everything else). A group comes first, followed by everything under it;
# ticking a group covers all of those.
class RestrictionPicker
  Section = Data.define(:title, :entries)
  Entry = Data.define(:node, :covers_children)

  COMMON_FOOD = "common food".freeze

  def initialize(nodes = TaxonomyNode.all.to_a)
    @children = nodes.group_by(&:parent_id)
    @children.each_value { |list| list.sort_by!(&:name) }
  end

  # Allergens (and intolerances) first, one section each; then nutrients;
  # then the other groups (gluten, cured meat, ...); then the common food
  # categories; last, single foods that belong to no group.
  def sections
    roots = @children.fetch(nil, [])
    allergens, rest = roots.partition { |root| root.allergen? || root.intolerance? }
    nutrients, rest = rest.partition(&:nutrient?)
    common, rest = rest.partition { |root| root.name == COMMON_FOOD }
    groups, single = rest.partition { |root| @children.key?(root.id) }

    sections = allergens.map { |root| section(title_for(root), tree(root)) }
    sections << section("Nutrients", nutrients.flat_map { |root| tree(root) }) if nutrients.any?
    sections.concat(groups.map { |root| section(title_for(root), tree(root)) })
    sections.concat(common.flat_map { |root| @children.fetch(root.id, []) }.map { |category| section(title_for(category), tree(category)) })
    sections << section("Other foods", single.flat_map { |root| tree(root) }) if single.any?
    sections
  end

  private

  def section(title, entries) = Section.new(title:, entries:)

  def title_for(node) = node.name.delete_prefix("common ").upcase_first

  def tree(node)
    children = @children.fetch(node.id, [])
    [ Entry.new(node:, covers_children: children.any?) ] + children.flat_map { |child| tree(child) }
  end
end
