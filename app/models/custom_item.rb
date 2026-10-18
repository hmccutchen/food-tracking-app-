# The "not found" path: a food or ingredient that isn't in USDA or the seeded
# taxonomy, added by the nurse as a taxonomy node of her own (source "custom").
#
# - name and aliases resolve exactly like seeded names and aliases.
# - parent ("this is a kind of…") puts it in the tree, so a restriction on the
#   parent covers it.
# - ingredients_text is kept verbatim and resolved; every node found in it
#   becomes a group the item is a MEMBER of (node = item, group = found node).
#   TaxonomyNode#covers? and the engine's Coverage read a membership as "the
#   group covers its members", so a milk allergy covers an item whose text
#   says "milk", while a can or cannot on the item reaches only the item itself
#   (never every milk ingredient). Groups the found nodes themselves belong to
#   (milk → lactose) are added too, because coverage follows one membership hop.
#
# Saving re-resolves her unresolved restrictions (a term that now matches gets
# the node) and bumps every one of her patients' profile versions, since a
# taxonomy change can change any stored evaluation that listed the item.
class CustomItem
  include ActiveModel::Model
  include ActiveModel::Attributes

  INGREDIENT_SEPARATORS = /[\n,;()\[\]]/
  ALIAS_SEPARATORS = /[\n,;]/
  MARKS = %w[can cannot].freeze

  attribute :name, :string
  attribute :ingredients_text, :string
  attribute :parent_id, :integer
  attribute :aliases_text, :string

  attr_reader :node, :user

  validates :name, presence: true
  validate :parent_is_allowed
  validate :name_is_not_an_alias
  validate :aliases_are_free

  delegate :id, :persisted?, :to_param, :to_key, :created_at, :parent, :aliases, :groups, to: :node

  HUMAN_NAMES = { "aliases_text" => "Other names", "parent_id" => "Kind of", "ingredients_text" => "Ingredients" }.freeze

  def self.human_attribute_name(attribute, options = {}) = HUMAN_NAMES.fetch(attribute.to_s) { super }

  # Parent choices: any seeded node, or one of her own items (not this one).
  def self.parent_options(user, except: nil)
    TaxonomyNode.seeded.or(user.custom_items).where.not(id: except&.id).order(:name)
  end

  def self.split_ingredients(text) = text.to_s.split(INGREDIENT_SEPARATORS).map(&:strip).compact_blank

  def initialize(user:, node: nil, **attributes)
    @user = user
    @node = node || user.custom_items.build(source: "custom")
    super()
    self.name = @node.name
    self.ingredients_text = @node.ingredients_text
    self.parent_id = @node.parent_id
    self.aliases_text = @node.aliases.map(&:term).sort.join(", ")
    assign_attributes(attributes)
  end

  def alias_terms
    aliases_text.to_s.split(ALIAS_SEPARATORS).map { |term| Taxonomy::Normalizer.call(term) }.compact_blank.uniq -
      [ Taxonomy::Normalizer.call(name) ]
  end

  def save
    return false unless valid?

    TaxonomyNode.transaction do
      lock_patients!
      node.assign_attributes(name:, ingredients_text: ingredients_text.to_s.strip.presence, parent_id:,
        source: "custom", created_by: user)
      unless node.save
        node.errors.each { |error| errors.add(error.attribute == :slug ? :name : error.attribute, error.message) }
        raise ActiveRecord::Rollback
      end
      sync_aliases!
      sync_memberships!
      rename_marks!
      refresh_restrictions!(user.restrictions.where(taxonomy_node_id: node.id).where.not(match_type: "manual"))
    end
    errors.empty?
  end

  # Restrictions that pointed to it (including per-patient marks) go back to
  # the resolver; with the item gone they fall back to text matching.
  def destroy!
    TaxonomyNode.transaction do
      lock_patients!
      pointing = user.restrictions.where(taxonomy_node_id: node.id).pluck(:id)
      node.destroy!
      Restriction.where(id: pointing).find_each(&:re_resolve!)
      bump_patients!
    end
  end

  # { patient_id => "can" | "cannot" } for her patients marked from this item.
  def marks
    mark_restrictions.to_h { |restriction| [ restriction.patient_id, restriction.kind ] }
  end

  # choices: { patient_id => "can" | "cannot" | "" }. Writes ordinary
  # Restriction rows (term = item name, manual match to the item), so every
  # precedence rule applies unchanged and each change bumps that profile.
  def update_marks(choices)
    choices = choices.to_h.transform_keys(&:to_s)
    existing = mark_restrictions.group_by(&:patient_id)

    Restriction.transaction do
      lock_patients!
      user.patients.find_each do |patient|
        wanted = choices[patient.id.to_s].presence_in(MARKS)
        current, *extra = existing.fetch(patient.id, [])
        extra.each(&:destroy!)
        if wanted.nil?
          current&.destroy!
        elsif current
          current.update!(kind: wanted) unless current.kind == wanted
        else
          patient.restrictions.create!(kind: wanted, term: node.name, manual_node_id: node.id)
        end
      end
    end
  end

  # Parts of the ingredient text that matched nothing known, for the item page.
  def unrecognized_ingredients
    parts = self.class.split_ingredients(node.ingredients_text)
    Taxonomy::Resolver.new.resolve_all(parts).filter_map do |resolution|
      resolution.input if direct_node(resolution).nil? && resolution.contained.empty?
    end
  end

  private

  def mark_restrictions
    user.restrictions.where(taxonomy_node_id: node.id, match_type: "manual", kind: MARKS).order(:created_at, :id).to_a
  end

  def sync_aliases!
    wanted = alias_terms
    node.aliases.where.not(term: wanted).delete_all
    wanted.each { |term| node.aliases.find_or_create_by!(term:) }
  end

  def sync_memberships!
    groups = contained_groups
    node.memberships.where.not(group_id: groups).delete_all
    groups.each { |group_id| node.memberships.find_or_create_by!(group_id:) }
  end

  # Ids of the nodes named in the ingredient text, plus the groups those nodes
  # (or their ancestors) belong to. Fuzzy whole-phrase guesses are left out;
  # the phrase scan's exact finds inside a phrase are kept.
  def contained_groups
    parts = self.class.split_ingredients(node.ingredients_text)
    return [] if parts.empty?

    found = Taxonomy::Resolver.new.resolve_all(parts).flat_map do |resolution|
      [ direct_node(resolution), *resolution.contained_nodes ].compact
    end
    ids = found.map(&:id).uniq
    chains = ids.flat_map { |id| TaxonomyNode.find(id).self_and_ancestors.pluck(:id) }
    (ids + TaxonomyMembership.where(node_id: chains).pluck(:group_id)).uniq - [ node.id ]
  end

  def direct_node(resolution) = (resolution.node if %i[exact alias].include?(resolution.match_type))

  def rename_marks!
    return unless node.saved_change_to_name? && !node.previously_new_record?

    user.restrictions.where(taxonomy_node_id: node.id, match_type: "manual").find_each do |restriction|
      restriction.update!(term: node.name)
    end
  end

  # Unresolved restrictions may match now; ones that matched this item by its
  # name or an alias may not any more.
  def refresh_restrictions!(previous_matches)
    user.restrictions.where(match_type: "unresolved").or(previous_matches).find_each(&:re_resolve!)
    bump_patients!
  end

  # Restriction writers lock the patient rows first, in id order, before any
  # restriction row (as RestrictionSelection and RestrictionsController do),
  # so two writers can never wait on each other's locks.
  def lock_patients!
    user.patients.order(:id).lock.ids
  end

  def bump_patients!
    user.patients.update_all([ "profile_version = profile_version + 1, updated_at = ?", Time.current ])
  end

  def parent_is_allowed
    return if parent_id.nil?
    return if self.class.parent_options(user, except: node).exists?(id: parent_id)

    errors.add(:parent_id, "must be chosen from the list")
  end

  def name_is_not_an_alias
    taken = TaxonomyAlias.includes(:taxonomy_node).where.not(taxonomy_node_id: node.id)
      .find_by(term: Taxonomy::Normalizer.call(name))
    errors.add(:name, "is already another name for '#{taken.taxonomy_node.name}'") if taken
  end

  def aliases_are_free
    alias_terms.each do |term|
      if (other = TaxonomyNode.where.not(id: node.id).find_by(name: term))
        errors.add(:aliases_text, "'#{term}' is already the item '#{other.name}'")
      elsif (taken = TaxonomyAlias.includes(:taxonomy_node).where.not(taxonomy_node_id: node.id).find_by(term:))
        errors.add(:aliases_text, "'#{term}' is already another name for '#{taken.taxonomy_node.name}'")
      end
    end
  end
end
