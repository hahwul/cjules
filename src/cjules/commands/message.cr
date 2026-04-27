require "option_parser"
require "../config"
require "../client"
require "../api"
require "../util"

module Cjules
  module Commands
    module Message
      extend self

      def run(args : Array(String)) : Int32
        file : String? = nil
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules msg <ID> <TEXT|->"
          p.on("--file PATH", "Read message from file") { |v| file = v }
          p.on("-h", "--help", "Show help") { puts p; exit 0 }
          p.unknown_args { |before, _| positional = before }
        end
        parser.parse(args.dup)

        id = positional[0]?
        unless id
          STDERR.puts "error: session ID is required"
          return 2
        end
        text_arg = positional[1]?
        text = Util::PromptInput.resolve(text_arg, file)

        cfg = Config.load
        client = Client.new(cfg)
        API::Sessions.send_message(client, Util::ID.normalize(id), text)
        puts "message sent"
        0
      end
    end
  end
end
