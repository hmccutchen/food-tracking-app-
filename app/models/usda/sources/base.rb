module Usda
  module Sources
    # Maps one food.csv row of this source's data_type to Food attributes.
    class Base
      def name = raise(NotImplementedError)
      def data_type = raise(NotImplementedError)
      def label = raise(NotImplementedError)

      # Called once per CSV folder before rows are mapped, for sources that need
      # side files (branded_food.csv). Foundation and SR Legacy don't.
      def prepare(_dir) = nil

      def attributes(row, categories:)
        {
          fdc_id: Integer(row["fdc_id"], 10),
          source: name,
          data_type: row["data_type"],
          description: row["description"].to_s.strip,
          category: categories[row["food_category_id"].to_s.strip],
          ingredients_text: ingredients_text(row),
          publication_date: publication_date(row["publication_date"]),
          raw: row.to_h
        }
      end

      # Verbatim ingredient text when the source has one; nil means the record
      # has no ingredient list (never an empty one).
      def ingredients_text(_row) = nil

      private

      def publication_date(value)
        value = value.to_s.strip
        return if value.empty?

        Date.iso8601(value)
      rescue Date::Error
        begin
          Date.strptime(value, "%m/%d/%Y")
        rescue Date::Error
          nil
        end
      end
    end
  end
end
