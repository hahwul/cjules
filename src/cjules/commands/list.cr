require "option_parser"
require "../config"
require "../client"
require "../api"
require "../util"
require "../output/format"

module Cjules
  module Commands
    module List
      extend self

      def run(args : Array(String)) : Int32
        state_filter : String? = nil
        repo_filter : String? = nil
        since : String? = nil
        search : String? = nil
        limit = 30
        all = false
        output = "table"

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules ls [options]"
          p.on("--state STATE", "Filter by state (e.g. FAILED)") { |v| state_filter = v.upcase }
          p.on("--repo OWNER/REPO", "Filter by repo") { |v| repo_filter = v }
          p.on("--since DURATION", "Only sessions newer than (e.g. 7d, 24h)") { |v| since = v }
          p.on("--search QUERY", "Substring match on prompt/title") { |v| search = v }
          p.on("--limit N", "Max sessions to show (default 30)") { |v| limit = v.to_i }
          p.on("--all", "Fetch all pages, ignore --limit") { all = true }
          p.on("-o FMT", "--output=FMT", "table, json, yaml, jsonl") { |v| output = v }
          p.on("-h", "--help", "Show help") { puts p; exit 0 }
        end
        parser.parse(args.dup)

        cfg = Config.load
        client = Client.new(cfg)

        # Fetch enough rows to satisfy filters; cap at a reasonable number unless --all.
        fetch_cap = all ? nil : Math.max(limit * 4, 100)
        sessions = API::Sessions.list_all(client, fetch_cap)

        cutoff : Time? = nil
        if s = since
          if span = Util::Duration.parse(s)
            cutoff = Time.utc - span
          end
        end

        filtered = sessions.select do |sess|
          next false if state_filter && sess.state != state_filter
          if rf = repo_filter
            src = sess.sourceContext.try(&.source) || ""
            next false unless src.includes?(rf)
          end
          if c = cutoff
            if t = sess.createTime
              begin
                next false if Time.parse_rfc3339(t) < c
              rescue
                next false
              end
            else
              next false
            end
          end
          if q = search
            combined = "#{sess.prompt} #{sess.title}"
            next false unless combined.downcase.includes?(q.downcase)
          end
          true
        end

        filtered = filtered[0...limit] unless all || filtered.size <= limit

        Output::Format.sessions(filtered, output)
        0
      end
    end
  end
end
