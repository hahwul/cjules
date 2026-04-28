require "option_parser"
require "../config"
require "../client"
require "../api"
require "../util"
require "../output/colors"

module Cjules
  module Commands
    module Activity
      extend self

      def run(args : Array(String)) : Int32
        output = "text"
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules activity <SESSION_ID> <ACTIVITY_ID> [-o text|json|yaml]"
          p.on("-o FMT", "--output=FMT", "text, json, yaml") { |v| output = v }
          p.on("-h", "--help", "Show help") { puts p; exit 0 }
          p.unknown_args { |before, _| positional = before }
        end
        parser.parse(args.dup)

        sid_arg = positional[0]?
        aid_arg = positional[1]?
        unless sid_arg && aid_arg
          STDERR.puts "error: session ID and activity ID are required"
          STDERR.puts "usage: cjules activity <SESSION_ID> <ACTIVITY_ID>"
          return 2
        end
        sid = Util::ID.normalize(sid_arg)
        aid = aid_arg.starts_with?("sessions/") ? aid_arg.split("/").last : aid_arg

        cfg = Config.load
        client = Client.new(cfg)
        a = API::Activities.get(client, sid, aid)

        case output
        when "json" then puts a.to_json
        when "yaml" then puts a.to_yaml
        else
          render_text(a)
        end
        0
      end

      private def render_text(a : Models::Activity)
        puts "#{Output::Colors.bold("ID")}        : #{a.id}"
        puts "#{Output::Colors.bold("Name")}      : #{a.name}"
        puts "#{Output::Colors.bold("Type")}      : #{a.event_type}"
        puts "#{Output::Colors.bold("Originator")}: #{a.originator}"
        puts "#{Output::Colors.bold("Created")}   : #{a.createTime}"
        if d = a.description
          puts "#{Output::Colors.bold("Desc")}      : #{d}"
        end

        if pg = a.planGenerated
          if plan = pg.plan
            puts ""
            puts Output::Colors.bold("Plan:")
            (plan.steps || [] of Models::PlanStep).each do |s|
              puts "  #{(s.index || 0) + 1}. #{s.title || "(untitled)"}"
              if d = s.description
                d.lines.each { |l| puts "     #{l.chomp}" } unless d.empty?
              end
            end
          end
        elsif pa = a.planApproved
          puts ""
          puts "Plan #{pa.planId || "?"} approved."
        elsif um = a.userMessaged
          puts ""
          puts Output::Colors.bold("User message:")
          puts(um.userMessage || "")
        elsif am = a.agentMessaged
          puts ""
          puts Output::Colors.bold("Agent message:")
          puts(am.agentMessage || "")
        elsif pu = a.progressUpdated
          title = pu.title
          desc = pu.description
          if (title && !title.empty?) || (desc && !desc.empty?)
            puts ""
            puts Output::Colors.bold(title) if title && !title.empty?
            puts desc if desc && !desc.empty?
          end
        elsif sf = a.sessionFailed
          puts ""
          puts "#{Output::Colors.red("Failed:")} #{sf.reason || "(no reason given)"}"
        elsif a.sessionCompleted
          puts ""
          puts Output::Colors.green("Session completed.")
        end

        if arts = a.artifacts
          arts.each_with_index do |art, i|
            puts ""
            label = "Artifact ##{i + 1}"
            if cs = art.changeSet
              puts Output::Colors.bold("#{label} (changeSet):")
              if gp = cs.gitPatch
                puts "  source: #{cs.source}"
                puts "  base:   #{gp.baseCommitId}"
                puts "  msg:    #{(gp.suggestedCommitMessage || "").lines.first?.try(&.chomp)}"
                if patch = gp.unidiffPatch
                  patch_lines = patch.lines.size
                  puts "  patch:  #{patch_lines} line(s); use `cjules patch <SID>` to view"
                end
              end
            elsif bo = art.bashOutput
              puts Output::Colors.bold("#{label} (bashOutput):")
              puts "  $ #{bo.command}"
              if out = bo.output
                out.lines.each { |l| puts "    #{l.chomp}" }
              end
              puts "  exit: #{bo.exitCode}"
            elsif med = art.media
              puts Output::Colors.bold("#{label} (media):")
              puts "  type: #{med.mimeType}"
              if d = med.data
                puts "  bytes: ~#{d.size * 3 // 4} (base64 encoded)"
              end
            end
          end
        end
      end
    end
  end
end
