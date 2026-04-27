require "option_parser"
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
        positional = [] of String
        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules logs <ID> [-o md|json|text]"
          p.on("-o FMT", "--output=FMT", "Output: md, json, text") { |v| output = v }
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
            puts "[#{a.createTime}] #{a.event_type}: #{a.description}"
          end
        else
          render_md(session, activities)
        end
        0
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
          if d = a.description
            puts d
          end
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
    end
  end
end
