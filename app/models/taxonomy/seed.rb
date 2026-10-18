module Taxonomy
  # Loads the structured tree in db/seeds/taxonomy.rb. Idempotent: running it
  # again changes nothing, and edits to the tree (new parent, kind, alias) apply.
  #
  # Custom items (source "custom", added by the nurse) are never deleted or
  # changed: not their attributes, aliases or memberships. If the tree ever
  # uses a custom item's name or alias, the nurse's version is kept and a
  # warning is logged.
  module Seed
    DATA_FILE = Rails.root.join("db/seeds/taxonomy.rb")
    DESCRIPTOR_FILE = Rails.root.join("db/seeds/ingredient_descriptors.rb")

    module_function

    def load!(tree = data)
      TaxonomyNode.transaction do
        tree.each { |name, spec| upsert_node(name, spec, nil) }
        sync_memberships(tree)
        # An alias spelled like a node name can never match (names win), e.g.
        # "parmesan" after it became its own node. Drop such leftovers.
        TaxonomyAlias.where(term: TaxonomyNode.select(:name))
          .where.not(taxonomy_node_id: TaxonomyNode.custom.select(:id)).delete_all
        load_descriptors!
      end
    end

    # The default descriptor words the engine reads with the taxonomy (create-only).
    def load_descriptors!
      require DESCRIPTOR_FILE.to_s
      ::IngredientDescriptorSeedData.load!
    end

    def data
      require DATA_FILE.to_s
      ::TaxonomySeedData::TREE
    end

    def upsert_node(name, spec, parent)
      node = TaxonomyNode.find_or_initialize_by(name:)
      if node.custom?
        warn_custom("node", name)
      else
        node.assign_attributes(kind: spec.fetch(:kind, :ingredient), parent:)
        node.save! if node.changed?
        spec.fetch(:aliases, []).each { |term| upsert_alias(term, node) }
      end
      spec.fetch(:children, {}).each { |child_name, child_spec| upsert_node(child_name, child_spec, node) }
    end

    def upsert_alias(term, node)
      record = TaxonomyAlias.find_or_initialize_by(term:)
      return warn_custom("alias", term) if record.persisted? && record.taxonomy_node.custom?

      record.taxonomy_node = node
      record.save! if record.changed?
    end

    def warn_custom(what, name)
      Rails.logger.warn("Taxonomy seed: #{what} '#{name}' is a custom item; keeping the nurse's version")
    end

    # Runs after every node exists. A group's memberships are exactly its
    # `members:` list; members removed from the list are unlinked.
    def sync_memberships(tree)
      each_spec(tree) do |name, spec|
        next unless spec.key?(:members)

        group = TaxonomyNode.find_by!(name:)
        next if group.custom?

        members = spec[:members].map { |member| TaxonomyNode.find_by!(name: member) }
        # A custom item's own memberships ("contains milk") are hers, not the tree's.
        group.member_links.where.not(node_id: members.map(&:id))
          .where.not(node_id: TaxonomyNode.custom.select(:id)).delete_all
        members.each { |member| TaxonomyMembership.find_or_create_by!(group:, node: member) }
      end
    end

    def each_spec(tree, &block)
      tree.each do |name, spec|
        yield name, spec
        each_spec(spec.fetch(:children, {}), &block)
      end
    end
  end
end
