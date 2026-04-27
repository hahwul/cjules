require "option_parser"
require "../config"
require "../client"
require "../api"
require "../util"
require "../output/colors"

module Cjules
  module Commands
    module Watch
      extend self

      TERMINAL_STATES = %w(COMPLETED FAILED)

      def run(args : Array(String)) : Int32
        interval = 3
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules watch <ID> [--interval SEC]"
          p.on("--interval SEC", "Poll interval in seconds (default 3)") { |v| interval = v.to_i }
          p.on("-h", "--help", "Show help") { puts p; exit 0 }
          p.unknown_args { |before, _| positional = before }
        end
        parser.parse(args.dup)

        id = positional[0]?
        unless id
          STDERR.puts "error: session ID is required"
          return 2
        end
        sid = Util::ID.normalize(id)

        cfg = Config.load
        client = Client.new(cfg)

        seen = Set(String).new
        last_state : String? = nil
        loop do
          sess = API::Sessions.get(client, sid)
          activities = API::Activities.list_all(client, sid)
          activities.each do |a|
            key = a.id || "#{a.createTime}/#{a.event_type}"
            next if seen.includes?(key)
            seen << key
            print_activity(a)
          end

          state = sess.state
          if state != last_state
            puts "#{Output::Colors.gray("--")} state: #{Output::Colors.state(state || "-")}"
            last_state = state
          end

          if state && TERMINAL_STATES.includes?(state)
            break
          end
          sleep interval.seconds
        end
        0
      end

      private def print_activity(a : Models::Activity)
        ts =
          if t = a.createTime
            begin
              Time.parse_rfc3339(t).to_local.to_s("%H:%M:%S")
            rescue
              "??:??:??"
            end
          else
            "??:??:??"
          end
        kind = a.event_type
        desc = a.description || ""
        puts "#{Output::Colors.gray(ts)}  #{Output::Colors.cyan(kind.ljust(20))}  #{desc}"
      end
    end
  end
end
