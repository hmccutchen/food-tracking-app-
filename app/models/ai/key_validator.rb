require "net/http"

module Ai
  # Checks a key with the provider's free list-models endpoint (no tokens
  # spent) and returns the model ids it offers. Raises an Ai::Error.
  class KeyValidator
    TIMEOUT = 10 # seconds; validation should be quick or fail plainly

    def self.call(provider, api_key) = new(provider).call(api_key)

    def initialize(provider)
      @provider = Providers.fetch(provider)
    end

    def call(api_key)
      raise InvalidKeyError.new(@provider.key) if api_key.to_s.strip.empty?

      response = get(api_key.to_s.strip)
      unless response.is_a?(Net::HTTPSuccess)
        raise Error.from_response(@provider.key, status: response.code, body: response.body)
      end

      @provider.parse_models(JSON.parse(response.body))
    # `cause: nil` so the low-level exception never rides along to a log.
    rescue Timeout::Error
      raise TimeoutError.new(@provider.key), cause: nil
    rescue JSON::ParserError, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse,
           Net::ProtocolError
      raise ProviderError.new(@provider.key), cause: nil
    end

    private

    def get(api_key)
      uri = URI(@provider.models_url)
      request = Net::HTTP::Get.new(uri)
      @provider.auth_headers(api_key).each { |name, value| request[name] = value }
      Net::HTTP.start(uri.host, uri.port, use_ssl: true,
        open_timeout: TIMEOUT, read_timeout: TIMEOUT, write_timeout: TIMEOUT) { |http| http.request(request) }
    end
  end
end
