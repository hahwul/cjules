require "option_parser"
require "../config"
require "../client"
require "../api"
require "../util"
require "../output/colors"
require "../output/format"

module Cjules
  module Commands
    module Prune
      extend self

      def run(args : Array(String)) : Int32
        state : String? = nil
        older : String? = nil
        repo_filter : String? = nil
        completed = false
        failed = false
        apply = false
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = <<-USAGE
            Usage: cjules prune [filters] [-y]

            Bulk-only delete of sessions matching all given filters.
            Default is dry-run; pass -y to actually delete.

            Filters (at least one required):
            USAGE
          p.on("--completed", "Match state=COMPLETED (shortcut)") { completed = true }
          p.on("--failed", "Match state=FAILED (shortcut)") { failed = true }
          p.on("--state STATE", "Match state (e.g. AWAITING_USER_FEEDBACK)") { |v| state = v.upcase }
          p.on("--older-than DUR", "Only sessions older than (e.g. 30d, 12h)") { |v| older = v }
          p.on("--repo OWNER/REPO", "Match by repo substring") { |v| repo_filter = v }
          p.on("-y", "--apply", "Skip dry-run and delete") { apply = true }
          p.on("-h", "--help", "Show help") { puts p; exit 0 }
          p.unknown_args { |before, _| positional = before }
        end
        parser.parse(args.dup)

        unless positional.empty?
          STDERR.puts "error: prune does not accept positional IDs (use `cjules rm <ID...>`)"
          return 2
        end

        if completed && failed
          STDERR.puts "error: --completed and --failed are mutually exclusive"
          return 2
        end
        if completed
          if state && state != "COMPLETED"
            STDERR.puts "error: --completed conflicts with --state #{state}"
            return 2
          end
          state = "COMPLETED"
        elsif failed
          if state && state != "FAILED"
            STDERR.puts "error: --failed conflicts with --state #{state}"
            return 2
          end
          state = "FAILED"
        end

        unless state || older || repo_filter
          STDERR.puts "error: at least one filter is required (--completed, --failed, --state, --older-than, --repo)"
          return 2
        end

        cutoff : Time? = nil
        if o = older
          if span = Util::Duration.parse(o)
            cutoff = Time.utc - span
          else
            STDERR.puts "error: invalid duration: #{o}"
            return 2
          end
        end

        cfg = Config.load
        client = Client.new(cfg)
        all = API::Sessions.list_all(client)
        matched = all.select do |sess|
          next false if state && sess.state != state
          if c = cutoff
            if t = sess.createTime
              begin
                next false if Time.parse_rfc3339(t) >= c
              rescue
                next false
              end
            else
              next false
            end
          end
          if rf = repo_filter
            src = sess.sourceContext.try(&.source) || ""
            next false unless src.includes?(rf)
          end
          true
        end

        if matched.empty?
          puts "no sessions matched"
          return 0
        end

        unless apply
          STDERR.puts "Dry-run: #{matched.size} session(s) would be deleted. Pass -y to apply."
          STDERR.puts ""
          Output::Format.sessions(matched, "table", STDERR)
          return 0
        end

        failed_count = 0
        matched.each do |sess|
          id = sess.id || sess.name.try(&.split("/").last)
          next unless id
          begin
            API::Sessions.delete(client, id)
            puts "#{Output::Colors.green("deleted")} #{id}"
          rescue e : Client::APIError
            STDERR.puts "#{Output::Colors.red("failed")}  #{id}: #{e.detail}"
            failed_count += 1
          end
        end
        failed_count == 0 ? 0 : 1
      end
    end
  end
end
