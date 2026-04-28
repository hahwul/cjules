require "option_parser"
require "../config"
require "../client"
require "../api"
require "../util"
require "../output/colors"

module Cjules
  module Commands
    module Plan
      extend self

      def run(args : Array(String)) : Int32
        output = "text"
        all = false
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules plan <ID> [-o text|json|yaml] [--all]"
          p.on("-o FMT", "--output=FMT", "text, json, yaml") { |v| output = v }
          p.on("--all", "Show every plan generated in the session (default: latest only)") { all = true }
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
        activities = API::Activities.list_all(client, sid)

        plans = [] of Models::Plan
        activities.each do |a|
          if pg = a.planGenerated
            if plan = pg.plan
              plans << plan
            end
          end
        end

        if plans.empty?
          STDERR.puts "no plans found in session #{sid}"
          return 1
        end

        case output
        when "json"
          puts(all ? plans.to_json : plans.last.to_json)
        when "yaml"
          puts(all ? plans.to_yaml : plans.last.to_yaml)
        else
          chosen = all ? plans : [plans.last]
          chosen.each_with_index do |plan, i|
            puts "" if i > 0
            render_text(plan, all && plans.size > 1 ? i + 1 : nil)
          end
        end
        0
      end

      private def render_text(plan : Models::Plan, num : Int32?)
        header = num ? "Plan ##{num} (#{plan.id})" : "Plan #{plan.id}"
        puts Output::Colors.bold(header)
        if t = plan.createTime
          puts Output::Colors.gray("  created: #{t}")
        end
        (plan.steps || [] of Models::PlanStep).each do |s|
          puts ""
          puts "  #{(s.index || 0) + 1}. #{Output::Colors.bold(s.title || "(untitled)")}"
          if d = s.description
            d.lines.each { |l| puts "     #{l.chomp}" } unless d.empty?
          end
        end
      end
    end
  end
end
