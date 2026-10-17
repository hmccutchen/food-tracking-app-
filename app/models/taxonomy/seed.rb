module Taxonomy
  # Loads the structured tree in db/seeds/taxonomy.rb. Idempotent: running it
  # again changes nothing, and edits to the tree (new parent, kind, alias) apply.
  module Seed
    DATA_FILE = Rails.root.join("db/seeds/taxonomy.rb")

    module_function

    def load!(tree = data)
      TaxonomyNode.transaction do
        tree.each { |name, spec| upsert_node(name, spec, nil) }
        sync_memberships(tree)
        # An alias spelled like a node name can never match (names win), e.g.
        # "parmesan" after it became its own node. Drop such leftovers.
        TaxonomyAlias.where(term: TaxonomyNode.select(:name)).delete_all
      end
    end

    def data
      require DATA_FILE.to_s
      ::TaxonomySeedData::TREE
    end

    def upsert_node(name, spec, parent)
      node = TaxonomyNode.find_or_initialize_by(name:)
      node.assign_attributes(kind: spec.fetch(:kind, :ingredient), parent:)
      node.save! if node.changed?

      spec.fetch(:aliases, []).each do |term|
        record = TaxonomyAlias.find_or_initialize_by(term:)
        record.taxonomy_node = node
        record.save! if record.changed?
      end
      spec.fetch(:children, {}).each { |child_name, child_spec| upsert_node(child_name, child_spec, node) }
    end

    # Runs after every node exists. A group's memberships are exactly its
    # `members:` list; members removed from the list are unlinked.
    def sync_memberships(tree)
      each_spec(tree) do |name, spec|
        next unless spec.key?(:members)

        group = TaxonomyNode.find_by!(name:)
        members = spec[:members].map { |member| TaxonomyNode.find_by!(name: member) }
        group.member_links.where.not(node_id: members.map(&:id)).delete_all
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
