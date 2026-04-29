require "option_parser"
require "../help"
require "../config"
require "../client"
require "../api"
require "../util"

module Cjules
  module Commands
    module Patch
      extend self

      def run(args : Array(String)) : Int32
        apply = false
        index : Int32? = nil
        list_only = false
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules patch <ID> [--apply] [--index N] [--list]"
          p.on("--apply", "Apply with `git apply` in current directory") { apply = true }
          p.on("--index N", "Pick specific patch (default: last)") { |v| index = v.to_i }
          p.on("--list", "List all patches with metadata, do not print body") { list_only = true }
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
        activities = API::Activities.list_all(client, sid)

        patches = [] of Models::GitPatch
        activities.each do |a|
          if arts = a.artifacts
            arts.each do |art|
              if cs = art.changeSet
                if gp = cs.gitPatch
                  patches << gp
                end
              end
            end
          end
        end

        if patches.empty?
          STDERR.puts "no gitPatch artifacts found in session #{sid}"
          return 1
        end

        if list_only
          patches.each_with_index do |p, i|
            base = p.baseCommitId || "?"
            msg = (p.suggestedCommitMessage || "").lines.first? || ""
            puts "[#{i}] base=#{base[0..11]}  #{msg}"
          end
          return 0
        end

        chosen =
          if idx = index
            unless idx >= 0 && idx < patches.size
              STDERR.puts "error: --index out of range (have #{patches.size})"
              return 2
            end
            patches[idx]
          else
            patches.last
          end

        text = chosen.unidiffPatch
        if text.nil? || text.empty?
          STDERR.puts "error: selected patch has no unidiffPatch body"
          return 1
        end

        if apply
          tmp = File.tempfile("cjules-", ".patch")
          begin
            File.write(tmp.path, text)
            status = Process.run("git", ["apply", tmp.path], output: STDOUT, error: STDERR)
          ensure
            tmp.delete
          end
          unless status.success?
            STDERR.puts "git apply failed"
            return 1
          end
          puts "patch applied"
        else
          puts text
        end
        0
      end
    end
  end
end
