require "net/http"
require "open3"

module Usda
  # Downloads the official FoodData Central CSV archives (Foundation Foods and
  # SR Legacy) and unzips them, for Usda::Importer. Used by
  # `rake usda:fetch_import`, which production runs once (see
  # bin/docker-entrypoint and USDA_IMPORT).
  #
  # These are USDA's bulk download files, not their API; nothing is crawled.
  # Only fdc.nal.usda.gov is ever contacted, over HTTPS.
  #
  # The newest Foundation file name changes with each release, so it is read
  # from the download page. If the page can't be read, a known release is
  # used. USDA_FOUNDATION_URL / USDA_SR_LEGACY_URL override either one.
  class Downloader
    class Error < StandardError; end

    HOST = "fdc.nal.usda.gov".freeze
    PAGE_URL = "https://#{HOST}/download-datasets".freeze
    BASE = "https://#{HOST}/fdc-datasets/".freeze
    FALLBACKS = {
      "foundation" => "#{BASE}FoodData_Central_foundation_food_csv_2024-10-31.zip",
      "sr_legacy" => "#{BASE}FoodData_Central_sr_legacy_food_csv_2018-04.zip"
    }.freeze
    PATTERNS = {
      "foundation" => /FoodData_Central_foundation_food_csv_(\d{4}-\d{2}(?:-\d{2})?)\.zip/,
      "sr_legacy" => /FoodData_Central_sr_legacy_food_csv_(\d{4}-\d{2}(?:-\d{2})?)\.zip/
    }.freeze
    MAX_REDIRECTS = 3
    MAX_BYTES = 200 * 1024 * 1024 # Foundation is ~3 MB zipped, SR Legacy ~7 MB

    def initialize(env: ENV, log: ->(line) { puts line })
      @env = env
      @log = log
    end

    # { "foundation" => url, "sr_legacy" => url }
    def urls
      page = fetch_page
      PATTERNS.to_h do |name, pattern|
        override = @env["USDA_#{name.upcase}_URL"].presence
        [ name, override || (page && newest(page, pattern)) || FALLBACKS.fetch(name) ]
      end
    end

    # Downloads and unzips each archive into its own folder under `dir`.
    # Returns the folders that hold a food.csv.
    def download(dir)
      urls.map do |name, url|
        target = Pathname(dir).join(name).tap(&:mkpath)
        zip = target.join("#{name}.zip")
        @log.call("Downloading #{url}")
        get(url, to: zip)
        unzip(zip, target)
        folder_with_food_csv(target) or raise Error, "#{File.basename(url)} has no food.csv"
      end
    end

    # The newest file name on the page matching `pattern`, as a full URL.
    def newest(page, pattern)
      file = page.scan(/[\w.-]+\.zip/).grep(pattern).max_by { |name| name[pattern, 1] }
      "#{BASE}#{file}" if file
    end

    private

    def fetch_page
      body = +""
      get(PAGE_URL, to: nil) { |chunk| body << chunk }
      body
    rescue Error, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
      @log.call("Couldn't read the USDA download page (#{e.message}); using known release files.")
      nil
    end

    # Streams `url` to the file `to` (or to the block). Follows a few
    # redirects, but never off fdc.nal.usda.gov or off HTTPS.
    def get(url, to:, redirects: 0, &block)
      uri = URI(url)
      raise Error, "refusing #{url}: only https://#{HOST} is allowed" unless uri.scheme == "https" && uri.host == HOST

      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) do |http|
        http.request(Net::HTTP::Get.new(uri)) do |response|
          case response
          when Net::HTTPRedirection
            raise Error, "too many redirects for #{url}" if redirects >= MAX_REDIRECTS

            return get(URI.join(url, response["location"]).to_s, to:, redirects: redirects + 1, &block)
          when Net::HTTPSuccess
            write_body(response, to, &block)
          else
            raise Error, "#{url} answered #{response.code}"
          end
        end
      end
    end

    def write_body(response, to)
      size = 0
      file = to && File.open(to, "wb")
      response.read_body do |chunk|
        size += chunk.bytesize
        raise Error, "download larger than #{MAX_BYTES / 1024 / 1024} MB" if size > MAX_BYTES

        file ? file.write(chunk) : yield(chunk)
      end
    ensure
      file&.close
    end

    def unzip(zip, target)
      _out, err, status = Open3.capture3("unzip", "-q", "-o", zip.to_s, "-d", target.to_s)
      raise Error, "couldn't unzip #{zip.basename}: #{err.strip}" unless status.success?
    end

    def folder_with_food_csv(target)
      Pathname.glob(target.join("**/food.csv")).min_by { |path| path.to_s.length }&.dirname
    end
  end
end
