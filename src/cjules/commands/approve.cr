require "option_parser"
require "../help"
require "../config"
require "../client"
require "../api"
require "../util"

module Cjules
  module Commands
    module Approve
      extend self

      def run(args : Array(String)) : Int32
        force = false
        positional = [] of String
        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules approve <ID> [--force]"
          p.on("-f", "--force", "Skip the state precheck and call approvePlan anyway") { force = true }
          p.on("-h", "--help", "Show help") { puts p; puts Help::GLOBAL_FLAGS; exit 0 }
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

        unless force
          sess = API::Sessions.get(client, sid)
          state = sess.state
          if state && state != "AWAITING_PLAN_APPROVAL"
            STDERR.puts "error: session #{sid} is in state #{state}, not AWAITING_PLAN_APPROVAL"
            STDERR.puts "  pass --force to call approvePlan anyway"
            return 1
          end
        end

        API::Sessions.approve_plan(client, sid)
        puts "plan approved"
        0
      end
    end
  end
end
