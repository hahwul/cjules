require "option_parser"
require "../help"
require "../config"
require "../client"
require "../api"
require "../util"
require "../output/format"
require "../errors"

module Cjules
  module Commands
    module Get
      extend self

      def run(args : Array(String)) : Int32
        output = "text"
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules get <ID> [options]"
          p.on("-f FMT", "--format=FMT", "Output format: text, json, yaml") { |v| output = v }
          p.on("-o FMT", "--output=FMT", "alias for --format") { |v| output = v }
          p.on("-h", "--help", "Show help") { Help.show_help(p); exit 0 }
          p.unknown_args { |before, _| positional = before }
        end
        parser.parse(args.dup)

        id = positional[0]?
        raise Cjules::UsageError.new("session ID is required") if id.nil?

        cfg = Config.load
        client = Client.new(cfg)
        sess = API::Sessions.get(client, Util::ID.normalize(id))
        Output::Format.session(sess, output)
        0
      end
    end
  end
end
