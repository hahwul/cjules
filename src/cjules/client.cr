require "http/client"
require "json"
require "openssl"
require "socket"
require "uri"
require "./version"
require "./config"

module Cjules
  class Client
    class APIError < Exception
      getter status : Int32
      getter body : String

      def initialize(@status : Int32, @body : String)
        super("HTTP #{@status}")
      end

      def detail : String
        return body if body.empty?
        begin
          parsed = JSON.parse(body)
          if err = parsed["error"]?
            msg = err["message"]?.try(&.as_s?) || body
            return msg
          end
        rescue JSON::ParseException
          # fallthrough
        end
        body
      end
    end

    CONNECT_TIMEOUT = 10.seconds
    READ_TIMEOUT    = 30.seconds

    # POST is excluded from 5xx retry: the create endpoint is non-idempotent
    # and `cjules new --reconcile-on-error` already handles ambiguous failures.
    # 429 is retried on every method since it signals server-side throttling.
    RETRYABLE_STATUSES = {429, 500, 502, 503, 504}
    MAX_ATTEMPTS       = 3
    BASE_BACKOFF       = 500.milliseconds
    MAX_BACKOFF        = 8.seconds

    def initialize(@config : Config)
    end

    private def full_path(path : String, query : Hash(String, String)? = nil) : String
      return path unless query && !query.empty?
      params = URI::Params.build do |form|
        query.each { |k, v| form.add(k, v) }
      end
      "#{path}?#{params}"
    end

    private def request(method : String, path : String, query : Hash(String, String)? = nil, body : String? = nil) : String
      uri = URI.parse(@config.api_base)
      headers = HTTP::Headers{
        "x-goog-api-key" => @config.require_api_key!,
        "Content-Type"   => "application/json",
        "Accept"         => "application/json",
        "User-Agent"     => "cjules/#{Cjules::VERSION}",
      }
      full = full_path(path, query)

      attempt = 0
      loop do
        attempt += 1
        client = HTTP::Client.new(uri)
        client.connect_timeout = CONNECT_TIMEOUT
        client.read_timeout = READ_TIMEOUT
        begin
          response = client.exec(method: method, path: full, headers: headers, body: body)
          if response.status_code >= 400
            if retry_status?(response.status_code, method) && attempt < MAX_ATTEMPTS
              sleep retry_after(response, attempt)
              next
            end
            raise APIError.new(response.status_code, response.body)
          end
          return response.body
        rescue ex : Socket::Error | IO::Error | OpenSSL::SSL::Error
          raise ex unless retry_method?(method) && attempt < MAX_ATTEMPTS
          sleep backoff(attempt)
        ensure
          client.close
        end
      end
    end

    # GET and DELETE are safe to retry on transport errors and 5xx.
    private def retry_method?(method : String) : Bool
      method == "GET" || method == "DELETE"
    end

    private def retry_status?(status : Int32, method : String) : Bool
      return false unless RETRYABLE_STATUSES.includes?(status)
      return true if status == 429
      retry_method?(method)
    end

    private def retry_after(response, attempt : Int32) : Time::Span
      if header = response.headers["Retry-After"]?
        if secs = header.to_i?
          return Math.min(secs, MAX_BACKOFF.total_seconds.to_i).seconds
        end
      end
      backoff(attempt)
    end

    private def backoff(attempt : Int32) : Time::Span
      base = BASE_BACKOFF * (1 << (attempt - 1))
      capped = base < MAX_BACKOFF ? base : MAX_BACKOFF
      capped + rand(0..200).milliseconds
    end

    def get(path : String, query : Hash(String, String)? = nil) : String
      request("GET", path, query, nil)
    end

    def post(path : String, body : String? = nil) : String
      request("POST", path, nil, body)
    end

    def delete(path : String) : String
      request("DELETE", path, nil, nil)
    end
  end
end
