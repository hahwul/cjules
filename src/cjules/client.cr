require "http/client"
require "json"
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
      client = HTTP::Client.new(uri)
      client.connect_timeout = CONNECT_TIMEOUT
      client.read_timeout = READ_TIMEOUT
      headers = HTTP::Headers{
        "x-goog-api-key" => @config.require_api_key!,
        "Content-Type"   => "application/json",
        "Accept"         => "application/json",
        "User-Agent"     => "cjules/#{Cjules::VERSION}",
      }
      begin
        response = client.exec(method: method, path: full_path(path, query), headers: headers, body: body)
      ensure
        client.close
      end
      if response.status_code >= 400
        raise APIError.new(response.status_code, response.body)
      end
      response.body
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
