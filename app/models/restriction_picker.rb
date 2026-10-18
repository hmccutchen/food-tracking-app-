# The checklist on the "choose items" page: every taxonomy node (so saving an
# unchanged page can never drop a restriction it didn't show), grouped into
# sections a nurse can scan (allergens, nutrients, common food categories,
# everything else). Entries nest like the taxonomy: a group's entry holds the
# entries under it, and `linked` names the foods listed elsewhere that it
# also covers through a membership (wheat → soy sauce, gluten → oats), the
# same links Evaluation::Engine follows. Together that is what ticking it
# covers.
class RestrictionPicker
  Section = Data.define(:title, :entries)
  Entry = Data.define(:node, :children, :linked) do
    def covers_children = children.any?

    def each_entry(&block)
      block.call(self)
      children.each { |child| child.each_entry(&block) }
    end
  end

  COMMON_FOOD = "common food".freeze

  def initialize(nodes = TaxonomyNode.all.to_a, memberships = TaxonomyMembership.pluck(:node_id, :group_id))
    @names = nodes.to_h { |node| [ node.id, node.name ] }
    @children = nodes.group_by(&:parent_id)
    @children.each_value { |list| list.sort_by!(&:name) }
    @members = memberships.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(node_id, group_id), map|
      map[group_id] << node_id
    end
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

    sections = allergens.map { |root| section(title_for(root), [ tree(root) ]) }
    sections << section("Nutrients", nutrients.map { |root| tree(root) }) if nutrients.any?
    sections.concat(groups.map { |root| section(title_for(root), [ tree(root) ]) })
    common.each do |root|
      # The umbrella itself rarely makes sense, but "Match to" allows it.
      sections << section("All common foods", [ Entry.new(node: root, children: [], linked: []) ])
      sections.concat(@children.fetch(root.id, []).map { |category| section(title_for(category), [ tree(category) ]) })
    end
    sections << section("Other foods", single.map { |root| tree(root) }) if single.any?
    sections
  end

  private

  def section(title, entries) = Section.new(title:, entries:)

  def title_for(node) = node.name.delete_prefix("common ").upcase_first

  def tree(node)
    Entry.new(node:, children: @children.fetch(node.id, []).map { |child| tree(child) }, linked: linked(node))
  end

  # Names of foods outside this node's subtree that belong to it, or to
  # anything under it, through a membership (the engine then covers what is
  # under those foods too).
  def linked(node)
    inside = subtree_ids(node.id)
    inside.flat_map { |id| @members.fetch(id, []) }.uniq.reject { |id| inside.include?(id) }.map { |id| @names[id] }.sort
  end

  def subtree_ids(id)
    (@subtrees ||= {})[id] ||= Set[id] + @children.fetch(id, []).flat_map { |child| subtree_ids(child.id).to_a }
  end
end
