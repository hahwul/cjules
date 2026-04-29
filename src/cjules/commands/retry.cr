require "option_parser"
require "../help"
require "../config"
require "../client"
require "../api"
require "../util"
require "../output/format"
require "./new"
require "./templates"

module Cjules
  module Commands
    module Retry
      extend self

      def run(args : Array(String)) : Int32
        prompt_override : String? = nil
        prompt_file : String? = nil
        template_name : String? = nil
        branch_override : String? = nil
        note : String? = nil
        with_failure_reason = false
        output = "text"
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules retry <ID> [options]"
          p.on("--prompt TEXT", "Replace the original prompt") { |v| prompt_override = v }
          p.on("--prompt-file PATH", "Replace the original prompt from file") { |v| prompt_file = v }
          p.on("--template NAME", "Replace the original prompt with a saved template") { |v| template_name = v }
          p.on("--branch BRANCH", "Override starting branch") { |v| branch_override = v }
          p.on("--note TEXT", "Append a note to the prompt") { |v| note = v }
          p.on("--with-failure-reason", "Append the original session's failure reason as a note") { with_failure_reason = true }
          p.on("-f FMT", "--format=FMT", "Output format: text, json, yaml") { |v| output = v }
          p.on("-o FMT", "--output=FMT", "alias for --format") { |v| output = v }
          p.on("-h", "--help", "Show help") { puts p; puts Help::GLOBAL_FLAGS; exit 0 }
          p.unknown_args { |before, _| positional = before }
        end
        parser.parse(args.dup)

        id = positional[0]?
        unless id
          STDERR.puts "error: session ID is required"
          return 2
        end
        sources_set = [prompt_override, prompt_file, template_name].count { |v| !v.nil? }
        if sources_set > 1
          STDERR.puts "error: --prompt, --prompt-file, and --template are mutually exclusive"
          return 2
        end
        sid = Util::ID.normalize(id)

        if tn = template_name
          tpath = Templates.find(tn)
          unless tpath
            STDERR.puts "error: no such template: #{tn} (looked in #{Templates.dir})"
            return 1
          end
          prompt_file = tpath
        end

        cfg = Config.load
        client = Client.new(cfg)
        original = API::Sessions.get(client, sid)

        prompt =
          if pf = prompt_file
            File.read(pf).strip
          elsif po = prompt_override
            po
          else
            original.prompt || ""
          end
        if prompt.empty?
          STDERR.puts "error: original session has no prompt; pass --prompt or --prompt-file"
          return 1
        end

        if with_failure_reason
          if reason = fetch_failure_reason(client, sid)
            prompt = "#{prompt}\n\nPrevious attempt failed: #{reason}" unless reason.empty?
          end
        end

        if n = note
          prompt = "#{prompt}\n\n#{n}" unless n.empty?
        end

        sc = original.sourceContext
        source = sc.try(&.source)
        starting_branch = branch_override || sc.try(&.githubRepoContext).try(&.startingBranch)

        if source && (starting_branch.nil? || starting_branch.not_nil!.empty?)
          STDERR.puts "error: original session has no startingBranch; pass --branch BRANCH"
          return 2
        end

        title = original.title
        require_approval = original.requirePlanApproval || false
        auto_pr = original.automationMode == "AUTO_CREATE_PR"

        body = New.build_payload(prompt, title, require_approval, auto_pr, source, starting_branch)
        session = API::Sessions.create(client, body)
        Output::Format.session(session, output)
        0
      end

      private def fetch_failure_reason(client : Client, sid : String) : String?
        activities = API::Activities.list_all(client, sid)
        activities.reverse_each do |a|
          if sf = a.sessionFailed
            return sf.reason
          end
        end
        nil
      end
    end
  end
end
