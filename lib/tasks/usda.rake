namespace :usda do
  desc "Import USDA FoodData Central Foundation + SR Legacy CSVs (default folder: db/usda)"
  task :import, [ :path ] => :environment do |_task, args|
    path = args[:path].presence || Rails.root.join("db/usda")
    puts Usda::Importer.new(path).call
  rescue Usda::Importer::MissingFileError => e
    abort e.message
  end

  desc "Download USDA's Foundation + SR Legacy CSV files and import them (used once in production)"
  task fetch_import: :environment do
    Dir.mktmpdir("usda") do |dir|
      Usda::Downloader.new.download(dir).each do |folder|
        puts Usda::Importer.new(folder).call
      end
    end
    puts "USDA import finished: #{Food.count} foods on file."
  rescue Usda::Downloader::Error, Usda::Importer::MissingFileError => e
    abort "USDA import failed: #{e.message}"
  end

  desc "Re-run taxonomy linking over imported USDA foods"
  task relink: :environment do
    puts Usda::Relinker.new.call
  end
end
