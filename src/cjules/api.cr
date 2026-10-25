require "json"
require "./client"
require "./models"

module Cjules
  module API
    # Follows nextPageToken (100 items per page) until exhausted. Yields each
    # page's raw JSON body; the block returns that page's nextPageToken.
    def self.each_page(client : Client, path : String, extra : Hash(String, String)? = nil, &)
      token : String? = nil
      loop do
        q = {"pageSize" => "100"}
        q["pageToken"] = token if token && !token.empty?
        q.merge!(extra) if extra
        token = yield client.get(path, q)
        break if token.nil? || token.empty?
      end
    end

    module Sessions
      extend self

      def list_all(client : Client, limit : Int32? = nil) : Array(Models::Session)
        result = [] of Models::Session
        API.each_page(client, "/v1alpha/sessions") do |body|
          page = Models::ListSessionsResponse.from_json(body)
          if items = page.sessions
            items.each do |s|
              result << s
              return result if limit && result.size >= limit
            end
          end
          page.nextPageToken
        end
        result
      end

      def get(client : Client, id : String) : Models::Session
        body = client.get("/v1alpha/sessions/#{id}")
        Models::Session.from_json(body)
      end

      def create(client : Client, payload_json : String) : Models::Session
        body = client.post("/v1alpha/sessions", payload_json)
        Models::Session.from_json(body)
      end

      def delete(client : Client, id : String) : Nil
        client.delete("/v1alpha/sessions/#{id}")
      end

      def send_message(client : Client, id : String, prompt : String) : Nil
        body = JSON.build { |j| j.object { j.field "prompt", prompt } }
        client.post("/v1alpha/sessions/#{id}:sendMessage", body)
      end

      def approve_plan(client : Client, id : String) : Nil
        client.post("/v1alpha/sessions/#{id}:approvePlan", "{}")
      end
    end

    module Sources
      extend self

      def list_all(client : Client, filter : String? = nil) : Array(Models::Source)
        result = [] of Models::Source
        API.each_page(client, "/v1alpha/sources", filter ? {"filter" => filter} : nil) do |body|
          page = Models::ListSourcesResponse.from_json(body)
          page.sources.try { |items| result.concat(items) }
          page.nextPageToken
        end
        result
      end

      def get(client : Client, id : String) : Models::Source
        body = client.get("/v1alpha/sources/#{id}")
        Models::Source.from_json(body)
      end
    end

    module Activities
      extend self

      def list_all(client : Client, session_id : String) : Array(Models::Activity)
        result = [] of Models::Activity
        API.each_page(client, "/v1alpha/sessions/#{session_id}/activities") do |body|
          page = Models::ListActivitiesResponse.from_json(body)
          page.activities.try { |items| result.concat(items) }
          page.nextPageToken
        end
        result
      end

      def get(client : Client, session_id : String, activity_id : String) : Models::Activity
        body = client.get("/v1alpha/sessions/#{session_id}/activities/#{activity_id}")
        Models::Activity.from_json(body)
      end
    end
  end
end
