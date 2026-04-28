require "option_parser"
require "base64"
require "json"
require "../config"
require "../client"
require "../api"
require "../util"

module Cjules
  module Commands
    module Logs
      extend self

      def run(args : Array(String)) : Int32
        output = "md"
        bash_only = false
        save_media : String? = nil
        positional = [] of String
        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules logs <ID> [-o md|json|text] [--bash] [--save-media DIR]"
          p.on("-o FMT", "--output=FMT", "Output: md, json, text") { |v| output = v }
          p.on("--bash", "Print bashOutput artifacts only (command/output/exit)") { bash_only = true }
          p.on("--save-media DIR", "Decode media artifacts and save into DIR") { |v| save_media = v }
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
        session = API::Sessions.get(client, sid)
        activities = API::Activities.list_all(client, sid)

        if dir = save_media
          n = save_media_artifacts(activities, dir)
          STDERR.puts "saved #{n} media artifact(s) to #{dir}"
        end

        if bash_only
          render_bash(activities)
          return 0
        end

        case output
        when "json"
          payload = JSON.build do |j|
            j.object do
              j.field "session" { session.to_json(j) }
              j.field "activities" { activities.to_json(j) }
            end
          end
          puts payload
        when "text"
          puts "Session: #{session.id} (#{session.state})"
          puts "Title:   #{session.title}"
          puts ""
          activities.each do |a|
            summary = event_summary(a)
            line = summary.empty? ? (a.description || "") : summary
            puts "[#{a.createTime}] #{a.event_type}: #{line}"
          end
        else
          render_md(session, activities)
        end
        0
      end

      private def render_bash(activities : Array(Models::Activity))
        any = false
        activities.each do |a|
          if arts = a.artifacts
            arts.each do |art|
              if bo = art.bashOutput
                any = true
                puts "$ #{bo.command}"
                if out = bo.output
                  out.lines.each { |l| puts l.chomp }
                end
                puts "[exit #{bo.exitCode}]"
                puts ""
              end
            end
          end
        end
        STDERR.puts "no bashOutput artifacts found" unless any
      end

      private def save_media_artifacts(activities : Array(Models::Activity), dir : String) : Int32
        Dir.mkdir_p(dir)
        seq = 0
        activities.each do |a|
          if arts = a.artifacts
            arts.each do |art|
              if med = art.media
                data = med.data
                next unless data && !data.empty?
                seq += 1
                ext = ext_for(med.mimeType)
                fname = "%03d.%s" % [seq, ext]
                path = File.join(dir, fname)
                File.write(path, Base64.decode(data))
              end
            end
          end
        end
        seq
      end

      private def ext_for(mime : String?) : String
        case mime
        when "image/png"      then "png"
        when "image/jpeg"     then "jpg"
        when "image/gif"      then "gif"
        when "image/webp"     then "webp"
        when "image/svg+xml"  then "svg"
        when "video/mp4"      then "mp4"
        when "audio/mpeg"     then "mp3"
        when "application/pdf" then "pdf"
        when "text/plain"     then "txt"
        else
          if mime && (slash = mime.index("/"))
            mime[(slash + 1)..].gsub(/[^A-Za-z0-9]+/, "")
          else
            "bin"
          end
        end
      end

      private def render_md(s : Models::Session, activities : Array(Models::Activity))
        puts "# Session #{s.id}"
        puts ""
        puts "- **State**: #{s.state}"
        puts "- **Title**: #{s.title}"
        puts "- **Repo**: #{s.repo_display}"
        puts "- **URL**: #{s.url}"
        puts "- **Created**: #{s.createTime}"
        puts "- **Updated**: #{s.updateTime}"
        puts ""
        puts "## Prompt"
        puts ""
        puts s.prompt
        puts ""
        puts "## Activities"
        activities.each do |a|
          puts ""
          puts "### #{a.createTime} — #{a.event_type}"
          puts ""
          render_event_md(a)
          if arts = a.artifacts
            arts.each do |art|
              if cs = art.changeSet
                if gp = cs.gitPatch
                  puts ""
                  puts "```diff"
                  puts gp.unidiffPatch
                  puts "```"
                end
              elsif bo = art.bashOutput
                puts ""
                puts "**$ #{bo.command}**"
                puts ""
                puts "```"
                puts bo.output
                puts "```"
              elsif med = art.media
                puts ""
                puts "_media: #{med.mimeType}_"
              end
            end
          end
        end
        if outs = s.outputs
          outs.each do |o|
            if pr = o.pullRequest
              puts ""
              puts "## Pull Request"
              puts ""
              puts "- **#{pr.title}**"
              puts "- #{pr.url}"
            end
          end
        end
      end

      private def render_event_md(a : Models::Activity)
        if pg = a.planGenerated
          if plan = pg.plan
            puts "**Plan generated**"
            puts ""
            (plan.steps || [] of Models::PlanStep).each do |s|
              puts "#{(s.index || 0) + 1}. **#{s.title || "(untitled)"}**"
              if d = s.description
                puts "   #{d}" unless d.empty?
              end
            end
            return
          end
        end
        if pa = a.planApproved
          puts "Plan `#{pa.planId || "?"}` approved."
          return
        end
        if um = a.userMessaged
          puts "**User:**"
          puts ""
          puts(um.userMessage || "")
          return
        end
        if am = a.agentMessaged
          puts "**Agent:**"
          puts ""
          puts(am.agentMessage || "")
          return
        end
        if pu = a.progressUpdated
          title = pu.title
          desc = pu.description
          if (title && !title.empty?) || (desc && !desc.empty?)
            puts "**#{title}**" if title && !title.empty?
            puts ""
            puts desc if desc && !desc.empty?
          end
          return
        end
        if sf = a.sessionFailed
          puts "**Session failed:** #{sf.reason || "(no reason given)"}"
          return
        end
        if a.sessionCompleted
          puts "Session completed."
          return
        end
        if d = a.description
          puts d
        end
      end

      private def event_summary(a : Models::Activity) : String
        if pg = a.planGenerated
          n = pg.plan.try(&.steps).try(&.size) || 0
          return "plan generated (#{n} step(s))"
        end
        return "plan #{a.planApproved.not_nil!.planId || "?"} approved" if a.planApproved
        return "user> #{a.userMessaged.not_nil!.userMessage || ""}" if a.userMessaged
        return "agent> #{a.agentMessaged.not_nil!.agentMessage || ""}" if a.agentMessaged
        if pu = a.progressUpdated
          parts = [pu.title, pu.description].compact.reject(&.empty?)
          return parts.join(" — ")
        end
        return "failed: #{a.sessionFailed.not_nil!.reason || "(no reason)"}" if a.sessionFailed
        return "completed" if a.sessionCompleted
        ""
      end
    end
  end
end
