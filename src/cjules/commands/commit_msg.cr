require "option_parser"
require "../help"
require "../config"
require "../client"
require "../api"
require "../util"
require "./new"
require "./pr_describe"

module Cjules
  module Commands
    module CommitMsg
      extend self

      def run(args : Array(String)) : Int32
        staged = false
        copy = false
        interval = 2
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules commit-msg [<ID>] [--staged] [--copy] [--interval SEC]"
          p.on("-s", "--staged", "Generate from staged changes (git diff --cached)") { staged = true }
          p.on("-c", "--copy", "Copy generated commit message to clipboard") { copy = true }
          p.on("--interval SEC", "Poll interval in seconds (default 2)") { |v| interval = Util.int_flag!("--interval", v, min: 1) }
          p.on("-h", "--help", "Show help") { Help.show_help(p); exit 0 }
          p.unknown_args { |before, _| positional = before }
        end
        parser.parse(args.dup)

        sid : String? = nil
        unless positional.empty?
          if staged
            raise Cjules::UsageError.new("cannot combine session ID with --staged")
          end
          sid = Util::ID.require!(positional)
        end

        cfg = Config.load
        client = Client.new(cfg)

        msg =
          if target_id = sid
            activities = API::Activities.list_all(client, target_id)
            extract_from_activities(activities) || begin
              STDERR.puts "no commit message found for session #{target_id}"
              return 1
            end
          else
            diff = Util::Git.diff(staged)
            if diff.nil? || diff.empty?
              STDERR.puts "no git changes found"
              return 1
            end
            generate_from_diff(client, diff, interval) || return 1
          end

        puts msg
        Util::Clipboard.copy_or_warn(msg) if copy
        0
      end

      def extract_from_activities(activities : Array(Models::Activity)) : String?
        if cm = PRDescribe.latest_patch(activities).try(&.suggestedCommitMessage).try(&.strip.presence)
          return strip_code_fence(cm)
        end
        if am = PRDescribe.latest_agent_message(activities)
          return strip_code_fence(am)
        end
        nil
      end

      def strip_code_fence(text : String) : String
        s = text.strip
        if m = s.match(/\A```[^\n]*\n(.*?)\n```\z/m)
          m[1].strip
        else
          s
        end
      end

      private def generate_from_diff(client : Client, diff : String, interval : Int32) : String?
        prompt = "Generate a concise, meaningful git commit message template (subject line and bulleted body) for the following git diff. Output only the commit message text without surrounding markdown code fences:\n\n```diff\n#{diff}\n```"
        body = New.build_payload(prompt, "Generate commit message", false, false, nil, nil)
        created = API::Sessions.create(client, body)
        sid = API.id!(Util::ID.normalize(created.id.presence || created.name || ""))

        loop do
          sess = API::Sessions.get(client, sid)
          activities = API::Activities.list_all(client, sid)
          if state = sess.state
            case state
            when "FAILED", "CANCELLED"
              STDERR.puts "session #{sid} #{state.downcase}"
              return
            when "COMPLETED", "AWAITING_USER_FEEDBACK"
              if msg = extract_from_activities(activities)
                return msg
              end
              if state == "COMPLETED"
                STDERR.puts "no commit message generated in session #{sid}"
                return
              end
            end
          end

          sleep interval.seconds
        end
      end
    end
  end
end
