require "option_parser"
require "../help"
require "json"
require "../config"
require "../client"
require "../api"
require "../util"
require "../output/format"
require "./templates"

module Cjules
  module Commands
    module New
      extend self

      def run(args : Array(String)) : Int32
        repo : String? = nil
        branch : String? = nil
        title : String? = nil
        file : String? = nil
        template_name : String? = nil
        source_override : String? = nil
        no_repo = false
        auto_pr = false
        require_approval = false
        parallel = 1
        output = "text"
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules new [PROMPT|-] [options]"
          p.on("--repo OWNER/REPO", "GitHub repo (auto-detected from git origin)") { |v| repo = v }
          p.on("--branch BRANCH", "Starting branch (auto-detected from git HEAD)") { |v| branch = v }
          p.on("--source NAME", "Source resource name (overrides --repo mapping)") { |v| source_override = v }
          p.on("--no-repo", "Create a repoless session (omit sourceContext)") { no_repo = true }
          p.on("--title TITLE", "Session title") { |v| title = v }
          p.on("--file PATH", "Read prompt from file") { |v| file = v }
          p.on("--template NAME", "Use a saved prompt template (see `cjules templates`)") { |v| template_name = v }
          p.on("--auto-pr", "Set automationMode=AUTO_CREATE_PR") { auto_pr = true }
          p.on("--require-approval", "Require explicit plan approval") { require_approval = true }
          p.on("--parallel N", "Create N concurrent sessions with the same prompt (account plan may limit N)") { |v| parallel = v.to_i }
          p.on("-f FMT", "--format=FMT", "Output format: text, json, yaml") { |v| output = v }
          p.on("-o FMT", "--output=FMT", "alias for --format") { |v| output = v }
          p.on("-h", "--help", "Show help") { puts p; puts Help::GLOBAL_FLAGS; exit 0 }
          p.unknown_args { |before, _| positional = before }
        end
        parser.parse(args.dup)

        if parallel < 1
          STDERR.puts "error: --parallel must be >= 1"
          return 2
        end

        if tn = template_name
          if file
            STDERR.puts "error: --template and --file are mutually exclusive"
            return 2
          end
          tpath = Templates.find(tn)
          unless tpath
            STDERR.puts "error: no such template: #{tn} (looked in #{Templates.dir})"
            return 1
          end
          file = tpath
        end

        prompt_arg = positional[0]?
        prompt = Util::PromptInput.resolve(prompt_arg, file)

        cfg = Config.load

        source : String? = nil
        starting_branch : String? = nil
        unless no_repo
          repo ||= cfg.default_repo || Util::Git.detect_repo
          branch ||= cfg.default_branch || Util::Git.detect_branch

          source = source_override
          if source.nil?
            repo_val = repo
            if repo_val.nil? || repo_val.empty?
              STDERR.puts "error: --repo, --source, or --no-repo is required (could not auto-detect repo from git)"
              return 2
            end
            source = Util::RepoMap.to_source(repo_val)
          end

          starting_branch = branch
          if starting_branch.nil? || starting_branch.empty?
            STDERR.puts "error: --branch is required (could not auto-detect from git)"
            return 2
          end
        end

        body = build_payload(prompt, title, require_approval, auto_pr, source, starting_branch)

        client = Client.new(cfg)
        if parallel == 1
          session = API::Sessions.create(client, body)
          Output::Format.session(session, output)
          return 0
        end

        results = create_concurrent(client, body, parallel)
        successes = results.compact_map { |r| r.is_a?(Models::Session) ? r : nil }
        failures = results.count { |r| r.is_a?(Exception) }

        case output
        when "json" then puts successes.to_json
        when "yaml" then puts successes.to_yaml
        else
          successes.each do |s|
            puts "#{Output::Colors.bold(s.short_id)}  #{Output::Colors.state(s.state || "QUEUED")}  #{s.url}"
          end
        end
        if failures > 0
          STDERR.puts "warning: #{failures} of #{parallel} session(s) failed to create"
          return 1
        end
        0
      end

      def build_payload(prompt : String, title : String?, require_approval : Bool, auto_pr : Bool, source : String?, starting_branch : String?) : String
        JSON.build do |j|
          j.object do
            j.field "prompt", prompt
            j.field "title", title.not_nil! if title
            j.field "requirePlanApproval", true if require_approval
            j.field "automationMode", "AUTO_CREATE_PR" if auto_pr
            if source && starting_branch
              j.field "sourceContext" do
                j.object do
                  j.field "source", source
                  j.field "githubRepoContext" do
                    j.object { j.field "startingBranch", starting_branch }
                  end
                end
              end
            end
          end
        end
      end

      private def create_concurrent(client : Client, body : String, n : Int32) : Array(Models::Session | Exception)
        ch = Channel(Models::Session | Exception).new(n)
        n.times do
          spawn do
            begin
              ch.send(API::Sessions.create(client, body))
            rescue e
              ch.send(e)
            end
          end
        end
        results = [] of Models::Session | Exception
        n.times { results << ch.receive }
        results
      end
    end
  end
end
