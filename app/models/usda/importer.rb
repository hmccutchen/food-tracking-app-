require "csv"

module Usda
  # Imports a FoodData Central bulk CSV download into foods.
  #
  #   Usda::Importer.new("db/usda", sources: %w[foundation sr_legacy]).call
  #
  # dir is a folder holding food.csv (and food_category.csv), or a folder whose
  # immediate subfolders each hold one — so the separately unzipped Foundation
  # and SR Legacy downloads can sit side by side under db/usda/. food.csv is
  # streamed row by row and upserted by fdc_id in batches, so re-running is
  # idempotent and refreshes imported_at. Rows of other data types are skipped.
  class Importer
    class MissingFileError < StandardError; end

    BATCH_SIZE = 1_000
    CSV_OPTIONS = { headers: true, encoding: "bom|utf-8" }.freeze

    Summary = Struct.new(:folders, :by_source, :inserted, :updated, :skipped, :links, keyword_init: true) do
      def total = by_source.values.sum

      def lines
        [
          "Imported #{total} USDA foods from #{folders.size} folder(s):",
          *by_source.map { |source, count| "  #{Sources.label_for(source)}: #{count}" },
          "  inserted #{inserted}, updated #{updated}",
          "Skipped #{skipped.values.sum} rows#{skipped_detail}",
          "Taxonomy links: #{links[:linked]} linked, #{links[:fuzzy]} fuzzy (please check), " \
          "#{links[:unresolved]} unresolved"
        ]
      end

      def to_s = lines.join("\n")

      private

      def skipped_detail
        return "" if skipped.empty?

        " (#{skipped.sort_by { |type, _| type.to_s }.map { |type, count| "#{type}: #{count}" }.join(', ')})"
      end
    end

    def initialize(dir, sources: Sources.names, matcher: DescriptionMatcher.new)
      @dir = Pathname(dir.to_s)
      @sources = Array(sources).map { |name| Sources.fetch(name) }.index_by(&:data_type)
      @matcher = matcher
    end

    def call
      folders = food_folders
      @summary = Summary.new(folders: folders.map(&:to_s), by_source: @sources.values.to_h { |s| [ s.name, 0 ] },
        inserted: 0, updated: 0, skipped: Hash.new(0), links: { linked: 0, fuzzy: 0, unresolved: 0 })
      folders.each { |folder| import_folder(folder) }
      @summary.skipped = @summary.skipped.to_h
      @summary
    end

    private

    attr_reader :matcher

    def food_folders
      raise MissingFileError, "USDA folder not found: #{@dir}" unless @dir.directory?
      return [ @dir ] if @dir.join("food.csv").file?

      folders = @dir.children.select { |child| child.directory? && child.join("food.csv").file? }.sort
      if folders.empty?
        raise MissingFileError, "No food.csv in #{@dir} or its subfolders. Unzip the FoodData Central " \
                                "Foundation and SR Legacy CSV downloads there."
      end
      folders
    end

    def import_folder(folder)
      categories = load_categories(folder)
      @sources.each_value { |source| source.prepare(folder) }
      batch = []

      CSV.foreach(folder.join("food.csv"), **CSV_OPTIONS) do |row|
        attributes = map_row(row, categories) or next
        batch << attributes
        if batch.size >= BATCH_SIZE
          write(batch)
          batch = []
        end
      end
      write(batch)
    end

    # { "1" => "Dairy and Egg Products" }. The file is small, so it's read whole.
    def load_categories(folder)
      path = folder.join("food_category.csv")
      return {} unless path.file?

      CSV.foreach(path, **CSV_OPTIONS).to_h { |row| [ row["id"].to_s.strip, row["description"].to_s.strip ] }
    end

    def map_row(row, categories)
      data_type = row["data_type"].to_s.strip
      source = @sources[data_type]
      return skip(data_type.presence || "blank data_type") unless source
      return skip("missing description") if row["description"].blank?
      return skip("bad fdc_id") unless row["fdc_id"].to_s.strip.match?(/\A\d+\z/)

      source.attributes(row, categories:)
    end

    def skip(reason)
      @summary.skipped[reason] += 1
      nil
    end

    def write(batch)
      return if batch.empty?

      rows = batch.index_by { |attributes| attributes[:fdc_id] }.values # last row wins within a batch
      existing = Food.where(fdc_id: rows.map { |row| row[:fdc_id] }).count
      now = Time.current
      links = matcher.match_all(rows.map { |row| row[:description] })

      records = rows.zip(links).map do |row, link|
        count_link(link)
        row.merge(imported_at: now, taxonomy_node_id: link.node&.id, match_type: link.match_type,
          match_reason: link.reason)
      end
      Food.upsert_all(records, unique_by: :fdc_id)

      rows.each { |row| @summary.by_source[row[:source]] += 1 }
      @summary.updated += existing
      @summary.inserted += rows.size - existing
    end

    def count_link(link)
      key = if link.linked? then :linked elsif link.fuzzy? then :fuzzy else :unresolved end
      @summary.links[key] += 1
    end
  end
end
