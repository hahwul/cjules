require "option_parser"
require "../help"
require "../config"
require "../client"
require "../api"
require "../util"
require "../output/colors"

module Cjules
  module Commands
    module Delete
      extend self

      def run(args : Array(String)) : Int32
        state : String? = nil
        older : String? = nil
        repo_filter : String? = nil
        yes = false
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = <<-USAGE
            Usage:
              cjules rm <ID...>
              cjules rm [--state STATE] [--older-than DUR] [--repo R] [-y]
            USAGE
          p.on("--state STATE", "Bulk filter by state") { |v| state = v.upcase }
          p.on("--older-than DUR", "Bulk: only sessions older than (e.g. 30d)") { |v| older = v }
          p.on("--repo OWNER/REPO", "Bulk filter by repo") { |v| repo_filter = v }
          p.on("-y", "--yes", "Skip confirmation") { yes = true }
          p.on("-h", "--help", "Show help") { puts p; puts Help::GLOBAL_FLAGS; exit 0 }
          p.unknown_args { |before, _| positional = before }
        end
        parser.parse(args.dup)

        cfg = Config.load
        client = Client.new(cfg)

        ids : Array(String)
        if state || older || repo_filter
          unless positional.empty?
            STDERR.puts "error: cannot mix positional IDs with bulk filters"
            return 2
          end
          all = API::Sessions.list_all(client)
          cutoff : Time? = nil
          if o = older
            if span = Util::Duration.parse(o)
              cutoff = Time.utc - span
            else
              STDERR.puts "error: invalid duration: #{o}"
              return 2
            end
          end
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
          ids = matched.compact_map { |s| s.id || s.name.try(&.split("/").last) }
        else
          if positional.empty?
            STDERR.puts "error: provide session IDs or a --state/--older-than/--repo filter"
            return 2
          end
          ids = positional.map { |i| Util::ID.normalize(i) }
        end

        if ids.empty?
          puts "no sessions matched"
          return 0
        end

        unless yes
          STDERR.puts "About to delete #{ids.size} session(s):"
          ids.first(10).each { |i| STDERR.puts "  - #{i}" }
          STDERR.puts "  ... and #{ids.size - 10} more" if ids.size > 10
          STDERR.print "Proceed? [y/N]: "
          ans = STDIN.gets.try(&.strip) || ""
          unless ans.downcase == "y" || ans.downcase == "yes"
            STDERR.puts "aborted"
            return 1
          end
        end

        failed = 0
        ids.each do |i|
          begin
            API::Sessions.delete(client, i)
            puts "#{Output::Colors.green("deleted")} #{i}"
          rescue e : Client::APIError
            STDERR.puts "#{Output::Colors.red("failed")}  #{i}: #{e.detail}"
            failed += 1
          end
        end
        failed == 0 ? 0 : 1
      end
    end
  end
end
