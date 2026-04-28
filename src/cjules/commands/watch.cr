require "option_parser"
require "../config"
require "../client"
require "../api"
require "../util"
require "../output/colors"

module Cjules
  module Commands
    module Watch
      extend self

      TERMINAL_STATES = %w(COMPLETED FAILED CANCELLED)

      def run(args : Array(String)) : Int32
        interval = 3
        auto_approve = false
        reply = false
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules watch <ID> [--interval SEC] [--auto-approve] [--reply]"
          p.on("--interval SEC", "Poll interval in seconds (default 3)") { |v| interval = v.to_i }
          p.on("--auto-approve", "Automatically approve plans on AWAITING_PLAN_APPROVAL") { auto_approve = true }
          p.on("--reply", "Prompt on AWAITING_USER_FEEDBACK and send the reply") { reply = true }
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

        seen = Set(String).new
        last_state : String? = nil

        loop do
          sess = API::Sessions.get(client, sid)
          activities = API::Activities.list_all(client, sid)
          activities.each do |a|
            key = a.id || "#{a.createTime}/#{a.event_type}"
            next if seen.includes?(key)
            seen << key
            print_activity(a)
          end

          state = sess.state
          if state != last_state
            puts "#{Output::Colors.gray("--")} state: #{Output::Colors.state(state || "-")}"
            handle_state_transition(state, sid, client, auto_approve, reply)
            last_state = state
          end

          if state && TERMINAL_STATES.includes?(state)
            break
          end
          sleep interval.seconds
        end
        0
      end

      private def handle_state_transition(state : String?, sid : String, client : Client, auto_approve : Bool, reply : Bool)
        case state
        when "AWAITING_PLAN_APPROVAL"
          if auto_approve
            puts "#{Output::Colors.gray("--")} auto-approving plan…"
            API::Sessions.approve_plan(client, sid)
          end
        when "AWAITING_USER_FEEDBACK"
          if reply
            unless STDIN.tty?
              STDERR.puts "#{Output::Colors.gray("--")} --reply requested but STDIN is not a TTY; skipping"
              return
            end
            print "#{Output::Colors.bold("reply>")} "
            STDOUT.flush
            line = STDIN.gets
            if line.nil? || line.strip.empty?
              puts "#{Output::Colors.gray("--")} skipped (empty reply)"
              return
            end
            API::Sessions.send_message(client, sid, line.strip)
            puts "#{Output::Colors.gray("--")} message sent"
          end
        end
      end

      private def print_activity(a : Models::Activity)
        ts =
          if t = a.createTime
            begin
              Time.parse_rfc3339(t).to_local.to_s("%H:%M:%S")
            rescue
              "??:??:??"
            end
          else
            "??:??:??"
          end
        kind = a.event_type
        head = "#{Output::Colors.gray(ts)}  #{Output::Colors.cyan(kind.ljust(20))}  "
        body = event_body(a)
        body = a.description || "" if body.empty?
        first, *rest = body.lines.empty? ? [body] : body.lines
        puts "#{head}#{first.chomp}"
        rest.each { |line| puts "#{" " * 32}#{line.chomp}" }
      end

      private def event_body(a : Models::Activity) : String
        if pg = a.planGenerated
          if plan = pg.plan
            steps = plan.steps || [] of Models::PlanStep
            return "plan with #{steps.size} step(s)" if steps.empty?
            lines = steps.map { |s| "#{(s.index || 0) + 1}. #{s.title || "(untitled)"}" }
            return ([Output::Colors.bold("plan generated:")] + lines).join("\n")
          end
        end
        if pa = a.planApproved
          return "plan #{pa.planId || "?"} approved"
        end
        if um = a.userMessaged
          msg = um.userMessage || ""
          return "#{Output::Colors.gray("user>")} #{msg}"
        end
        if am = a.agentMessaged
          msg = am.agentMessage || ""
          return "#{Output::Colors.cyan("agent>")} #{msg}"
        end
        if pu = a.progressUpdated
          title = pu.title || ""
          desc = pu.description
          return desc && !desc.empty? ? "#{Output::Colors.bold(title)} — #{desc}" : title
        end
        if sf = a.sessionFailed
          reason = sf.reason || "(no reason given)"
          return Output::Colors.red("failed: #{reason}")
        end
        return Output::Colors.green("session completed") if a.sessionCompleted
        ""
      end
    end
  end
end
