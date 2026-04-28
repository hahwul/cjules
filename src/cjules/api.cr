require "json"
require "./client"
require "./models"

module Cjules
  module API
    module Sessions
      extend self

      def list_page(client : Client, page_size : Int32? = nil, page_token : String? = nil) : Models::ListSessionsResponse
        q = {} of String => String
        q["pageSize"] = page_size.to_s if page_size
        q["pageToken"] = page_token if page_token && !page_token.empty?
        body = client.get("/v1alpha/sessions", q.empty? ? nil : q)
        Models::ListSessionsResponse.from_json(body)
      end

      def list_all(client : Client, limit : Int32? = nil) : Array(Models::Session)
        result = [] of Models::Session
        token : String? = nil
        loop do
          page = list_page(client, 100, token)
          if items = page.sessions
            items.each do |s|
              result << s
              return result if limit && result.size >= limit
            end
          end
          token = page.nextPageToken
          break if token.nil? || token.empty?
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

      def list_page(client : Client, page_size : Int32? = nil, page_token : String? = nil, filter : String? = nil) : Models::ListSourcesResponse
        q = {} of String => String
        q["pageSize"] = page_size.to_s if page_size
        q["pageToken"] = page_token if page_token && !page_token.empty?
        q["filter"] = filter if filter
        body = client.get("/v1alpha/sources", q.empty? ? nil : q)
        Models::ListSourcesResponse.from_json(body)
      end

      def list_all(client : Client, filter : String? = nil) : Array(Models::Source)
        result = [] of Models::Source
        token : String? = nil
        loop do
          page = list_page(client, 100, token, filter)
          if items = page.sources
            items.each { |s| result << s }
          end
          token = page.nextPageToken
          break if token.nil? || token.empty?
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

      def list_page(client : Client, session_id : String, page_size : Int32? = nil, page_token : String? = nil) : Models::ListActivitiesResponse
        q = {} of String => String
        q["pageSize"] = page_size.to_s if page_size
        q["pageToken"] = page_token if page_token && !page_token.empty?
        body = client.get("/v1alpha/sessions/#{session_id}/activities", q.empty? ? nil : q)
        Models::ListActivitiesResponse.from_json(body)
      end

      def list_all(client : Client, session_id : String) : Array(Models::Activity)
        result = [] of Models::Activity
        token : String? = nil
        loop do
          page = list_page(client, session_id, 100, token)
          if items = page.activities
            items.each { |a| result << a }
          end
          token = page.nextPageToken
          break if token.nil? || token.empty?
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
