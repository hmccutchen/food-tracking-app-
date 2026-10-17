module Usda
  # One importer class per FoodData Central data type. Branded foods can be
  # added later as another subclass of Sources::Base that reads ingredients
  # from branded_food.csv.
  module Sources
    module_function

    def all = [ Foundation, SrLegacy ].map(&:new)

    def fetch(name)
      all.find { |source| source.name == name.to_s } or
        raise ArgumentError, "unknown USDA source #{name.inspect} (known: #{names.join(', ')})"
    end

    def names = all.map(&:name)

    def label_for(name) = all.find { |source| source.name == name.to_s }&.label || name.to_s
  end
end
