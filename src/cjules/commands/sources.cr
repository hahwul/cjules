require "option_parser"
require "../help"
require "../config"
require "../client"
require "../api"
require "../util"
require "../output/format"

module Cjules
  module Commands
    module SourcesCmd
      extend self

      def run(args : Array(String)) : Int32
        sub = args.first?
        rest = args.size > 1 ? args[1..].to_a : [] of String
        case sub
        when "ls", "list", nil
          ls(rest)
        when "get", "show"
          get(rest)
        when "-h", "--help"
          usage
          0
        else
          STDERR.puts "error: unknown sources subcommand: #{sub}"
          usage(STDERR)
          2
        end
      end

      def usage(io : IO = STDOUT)
        io.puts <<-USAGE
          Usage:
            cjules sources ls [-o table|json|yaml|jsonl]
            cjules sources get <ID> [-o text|json|yaml]
          USAGE
        io.puts Help::GLOBAL_FLAGS
      end

      private def ls(args : Array(String)) : Int32
        output = "table"
        filter : String? = nil
        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules sources ls [options]"
          p.on("-o FMT", "--output=FMT", "table, json, yaml, jsonl") { |v| output = v }
          p.on("--filter EXPR", "AIP-160 filter (e.g. 'name=sources/foo OR name=sources/bar')") { |v| filter = v }
          p.on("-h", "--help", "Show help") { puts p; puts Help::GLOBAL_FLAGS; exit 0 }
        end
        parser.parse(args.dup)
        cfg = Config.load
        client = Client.new(cfg)
        list = API::Sources.list_all(client, filter)
        Output::Format.sources(list, output)
        0
      end

      private def get(args : Array(String)) : Int32
        output = "text"
        positional = [] of String
        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules sources get <ID>"
          p.on("-o FMT", "--output=FMT", "text, json, yaml") { |v| output = v }
          p.on("-h", "--help", "Show help") { puts p; puts Help::GLOBAL_FLAGS; exit 0 }
          p.unknown_args { |before, _| positional = before }
        end
        parser.parse(args.dup)

        id = positional[0]?
        unless id
          STDERR.puts "error: source ID is required"
          return 2
        end
        cfg = Config.load
        client = Client.new(cfg)
        s = API::Sources.get(client, Util::ID.normalize(id))
        Output::Format.source(s, output)
        0
      end
    end
  end
end
