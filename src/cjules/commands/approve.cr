require "option_parser"
require "../config"
require "../client"
require "../api"
require "../util"

module Cjules
  module Commands
    module Approve
      extend self

      def run(args : Array(String)) : Int32
        positional = [] of String
        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules approve <ID>"
          p.on("-h", "--help", "Show help") { puts p; exit 0 }
          p.unknown_args { |before, _| positional = before }
        end
        parser.parse(args.dup)

        id = positional[0]?
        unless id
          STDERR.puts "error: session ID is required"
          return 2
        end
        cfg = Config.load
        client = Client.new(cfg)
        API::Sessions.approve_plan(client, Util::ID.normalize(id))
        puts "plan approved"
        0
      end
    end
  end
end
