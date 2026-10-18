namespace :usda do
  desc "Import USDA FoodData Central Foundation + SR Legacy CSVs (default folder: db/usda)"
  task :import, [ :path ] => :environment do |_task, args|
    path = args[:path].presence || Rails.root.join("db/usda")
    puts Usda::Importer.new(path).call
  rescue Usda::Importer::MissingFileError => e
    abort e.message
  end

  desc "Re-run taxonomy linking over imported USDA foods"
  task relink: :environment do
    puts Usda::Relinker.new.call
  end
end
