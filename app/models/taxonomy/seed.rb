module Taxonomy
  # Loads the structured tree in db/seeds/taxonomy.rb. Idempotent: running it
  # again changes nothing, and edits to the tree (new parent, kind, alias) apply.
  module Seed
    DATA_FILE = Rails.root.join("db/seeds/taxonomy.rb")

    module_function

    def load!(tree = data)
      TaxonomyNode.transaction { tree.each { |name, spec| upsert_node(name, spec, nil) } }
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
  end
end
