require "json"
require "net/http"
require "uri"

module TokenWatchFastlane
  # Minimal JSON:API client for App Store Connect endpoints that Fastlane does not expose.
  class AppStoreConnectAPIClient
    BASE_URL = "https://api.appstoreconnect.apple.com".freeze
    MAX_GET_RETRIES = 2

    class Error < StandardError
      attr_reader :status

      def initialize(message, status: nil)
        super(message)
        @status = status
      end
    end

    def initialize(token:)
      @token = token
    end

    # Sends an authenticated GET request and returns the parsed JSON document.
    def get(path, query: nil)
      request(:get, path, query: query)
    end

    # Returns nil for a missing resource while preserving every other API error.
    def get_optional(path, query: nil)
      get(path, query: query)
    rescue Error => error
      raise unless error.status == 404

      nil
    end

    # Sends an authenticated JSON POST request and returns the parsed response.
    def post(path, body:)
      request(:post, path, body: body)
    end

    # Follows JSON:API pagination links and returns all resources from each page.
    def get_all(path, query: nil)
      resources = []
      response = get(path, query: query)

      loop do
        resources.concat(Array(response["data"]))
        next_url = response.dig("links", "next")
        break if next_url.nil? || next_url.empty?

        response = get(next_url)
      end

      resources
    end

    # Follows pagination while retaining both primary and included JSON:API resources.
    def get_paginated_document(path, query: nil)
      resources = []
      included = []
      response = get(path, query: query)

      loop do
        resources.concat(Array(response["data"]))
        included.concat(Array(response["included"]))
        next_url = response.dig("links", "next")
        break if next_url.nil? || next_url.empty?

        response = get(next_url)
      end

      {
        "data" => resources,
        "included" => included.uniq { |resource| [resource["type"], resource["id"]] }
      }
    end

    private

    def request(method, path, query: nil, body: nil)
      uri = build_uri(path, query)
      attempts = 0

      loop do
        @token.refresh! if @token.expired?
        http_request = request_class(method).new(uri)
        http_request["Authorization"] = "Bearer #{@token.text}"
        http_request["Accept"] = "application/json"
        http_request["Content-Type"] = "application/json" if body
        http_request.body = JSON.generate(body) if body

        begin
          response = Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: true,
            open_timeout: 30,
            read_timeout: 60
          ) { |http| http.request(http_request) }
        rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError => error
          if retry_get?(method, attempts)
            attempts += 1
            sleep attempts
            next
          end
          raise Error, "App Store Connect 网络请求失败：#{error.class}: #{error.message}"
        end

        status = response.code.to_i
        if retryable_status?(status) && retry_get?(method, attempts)
          attempts += 1
          sleep retry_delay(response, attempts)
          next
        end

        return parse_body(response.body) if response.is_a?(Net::HTTPSuccess)

        parsed_body = parse_error_body(response.body)

        raise Error.new(
          format_error(method, uri, status, parsed_body),
          status: status
        )
      end
    rescue JSON::ParserError => error
      raise Error, "App Store Connect 返回了无效 JSON：#{error.message}"
    end

    def build_uri(path, query)
      uri = path.start_with?("http://", "https://") ? URI(path) : URI.join(BASE_URL, path)
      unless uri.scheme == "https" && uri.host == "api.appstoreconnect.apple.com"
        raise Error, "拒绝向非 App Store Connect 地址发送 API Token：#{uri.host}"
      end

      uri.query = URI.encode_www_form(query) if query && !query.empty?
      uri
    end

    def request_class(method)
      case method
      when :get then Net::HTTP::Get
      when :post then Net::HTTP::Post
      else
        raise ArgumentError, "不支持的 HTTP 方法：#{method}"
      end
    end

    def parse_body(body)
      return {} if body.nil? || body.empty?

      JSON.parse(body)
    end

    def parse_error_body(body)
      parse_body(body)
    rescue JSON::ParserError
      detail = body.to_s.strip
      { "errors" => [{ "detail" => detail.empty? ? "非 JSON 错误响应" : detail }] }
    end

    def retry_get?(method, attempts)
      method == :get && attempts < MAX_GET_RETRIES
    end

    def retryable_status?(status)
      status.between?(500, 599)
    end

    def retry_delay(response, attempts)
      retry_after = response["Retry-After"].to_i
      [[retry_after, attempts].max, 5].min
    end

    def format_error(method, uri, status, body)
      details = Array(body["errors"]).map do |error|
        code = error["code"] || error["status"]
        detail = error["detail"] || error["title"]
        [code, detail].compact.join(": ")
      end.reject(&:empty?)
      suffix = details.empty? ? "" : "（#{details.join('；')}）"
      "App Store Connect API #{method.to_s.upcase} #{uri.path} 失败：HTTP #{status}#{suffix}"
    end
  end
end
