require "option_parser"
require "../help"
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
          p.on("-f FMT", "--format=FMT", "Output format: table, json, yaml, jsonl") { |v| output = v }
          p.on("-o FMT", "--output=FMT", "alias for --format") { |v| output = v }
          p.on("-h", "--help", "Show help") { puts p; puts Help::GLOBAL_FLAGS; exit 0 }
        end
        parser.parse(args.dup)

        cfg = Config.load
        client = Client.new(cfg)

        cutoff : Time? = nil
        if s = since
          span = Util::Duration.parse(s)
          if span.nil?
            STDERR.puts "error: invalid --since duration: #{s.inspect} (expected e.g. 30s, 5m, 2h, 7d, 1w)"
            return 2
          end
          cutoff = Time.utc - span
        end

        match = ->(sess : Models::Session) do
          return false if state_filter && sess.state != state_filter
          if rf = repo_filter
            src = sess.sourceContext.try(&.source) || ""
            return false unless src.includes?(rf)
          end
          if c = cutoff
            if t = sess.createTime
              begin
                return false if Time.parse_rfc3339(t) < c
              rescue
                return false
              end
            else
              return false
            end
          end
          if q = search
            combined = "#{sess.prompt} #{sess.title}"
            return false unless combined.downcase.includes?(q.downcase)
          end
          true
        end

        # Paginate; stop early when --since cutoff is exceeded (API returns newest-first),
        # or when we have enough post-filter matches (unless --all).
        filtered = [] of Models::Session
        token : String? = nil
        stop_paging = false
        loop do
          page = API::Sessions.list_page(client, 100, token)
          if items = page.sessions
            items.each do |sess|
              if c = cutoff
                if t = sess.createTime
                  begin
                    if Time.parse_rfc3339(t) < c
                      stop_paging = true
                      next
                    end
                  rescue
                    # malformed timestamp — skip but keep paging
                  end
                end
              end
              filtered << sess if match.call(sess)
              if !all && filtered.size >= limit
                stop_paging = true
                break
              end
            end
          end
          break if stop_paging
          token = page.nextPageToken
          break if token.nil? || token.empty?
        end

        filtered = filtered[0...limit] unless all || filtered.size <= limit

        Output::Format.sessions(filtered, output)
        0
      end
    end
  end
end
