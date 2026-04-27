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

    def initialize(@config : Config)
    end

    private def build_uri(path : String, query : Hash(String, String)? = nil) : URI
      uri = URI.parse(@config.api_base)
      uri.path = path
      if query && !query.empty?
        params = URI::Params.build do |form|
          query.each { |k, v| form.add(k, v) }
        end
        uri.query = params
      end
      uri
    end

    private def request(method : String, path : String, query : Hash(String, String)? = nil, body : String? = nil) : String
      uri = build_uri(path, query)
      headers = HTTP::Headers{
        "x-goog-api-key" => @config.require_api_key!,
        "Content-Type"   => "application/json",
        "Accept"         => "application/json",
        "User-Agent"     => "cjules/#{Cjules::VERSION}",
      }
      response = HTTP::Client.exec(method: method, url: uri, headers: headers, body: body)
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
