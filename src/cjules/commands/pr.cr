require "option_parser"
require "../config"
require "../client"
require "../api"
require "../util"

module Cjules
  module Commands
    module PR
      extend self

      def run(args : Array(String)) : Int32
        open_browser = false
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules pr <ID> [--open]"
          p.on("--open", "Open the PR in the default browser") { open_browser = true }
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
        sess = API::Sessions.get(client, Util::ID.normalize(id))

        url : String? = nil
        if outs = sess.outputs
          outs.each do |o|
            candidate = o.pullRequest.try(&.url)
            if candidate && !candidate.empty?
              url = candidate
              break
            end
          end
        end
        if url.nil?
          STDERR.puts "no PR found for session #{sess.id}"
          return 1
        end
        puts url

        if open_browser
          opener = {% if flag?(:darwin) %} "open" {% else %} "xdg-open" {% end %}
          Process.run(opener, [url], output: Process::Redirect::Close, error: Process::Redirect::Close)
        end
        0
      end
    end
  end
end
