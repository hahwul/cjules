require "option_parser"
require "../help"
require "../config"
require "../client"
require "../api"
require "./get"
require "./watch"
require "./delete"
require "./pr"

module Cjules
  module Commands
    module Pick
      extend self

      def run(args : Array(String)) : Int32
        action = "show"
        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules pick [--action show|watch|delete|pr]"
          p.on("--action ACTION", "show, watch, delete, pr (default show)") { |v| action = v }
          p.on("-h", "--help", "Show help") { puts p; puts Help::GLOBAL_FLAGS; exit 0 }
        end
        parser.parse(args.dup)

        cfg = Config.load
        client = Client.new(cfg)
        sessions = API::Sessions.list_all(client, 200)
        if sessions.empty?
          puts "no sessions"
          return 0
        end

        chosen_id : String? = nil

        if has_fzf?
          lines = sessions.compact_map do |s|
            sid = s.id
            next nil unless sid
            title = (s.title || s.prompt || "").gsub(/\s+/, " ")
            "#{sid[0..11]}\t#{(s.state || "-").ljust(24)}\t#{title[0..80]}"
          end
          chosen_line = run_fzf(lines.join("\n"))
          if chosen_line && !chosen_line.empty?
            short = chosen_line.split("\t", 2).first?
            sessions.each do |s|
              sid = s.id
              next unless sid
              if short && sid.starts_with?(short)
                chosen_id = sid
                break
              end
            end
          end
        else
          sessions.each_with_index do |s, i|
            label = "#{(s.title || s.prompt || "").gsub(/\s+/, " ")[0..70]}"
            puts "#{(i + 1).to_s.rjust(3)}. #{(s.id || "?")[0..11]}  [#{s.state}]  #{label}"
          end
          STDERR.print "select # (1-#{sessions.size}): "
          ans = STDIN.gets.try(&.strip) || ""
          if n = ans.to_i?
            if n >= 1 && n <= sessions.size
              chosen_id = sessions[n - 1].id
            end
          end
        end

        unless chosen_id
          STDERR.puts "no selection"
          return 1
        end

        case action
        when "show"   then Get.run([chosen_id])
        when "watch"  then Watch.run([chosen_id])
        when "delete" then Delete.run([chosen_id])
        when "pr"     then PR.run([chosen_id])
        else
          STDERR.puts "unknown --action: #{action}"
          2
        end
      end

      private def has_fzf? : Bool
        Process.run("which", ["fzf"],
          output: Process::Redirect::Close,
          error: Process::Redirect::Close).success?
      end

      private def run_fzf(input : String) : String?
        captured = IO::Memory.new
        in_io = IO::Memory.new(input)
        status = Process.run("fzf", ["--no-sort", "--ansi"],
          input: in_io,
          output: captured,
          error: Process::Redirect::Inherit)
        return nil unless status.success?
        s = captured.to_s.strip
        s.empty? ? nil : s
      end
    end
  end
end
