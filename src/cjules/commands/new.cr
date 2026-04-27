require "option_parser"
require "json"
require "../config"
require "../client"
require "../api"
require "../util"
require "../output/format"

module Cjules
  module Commands
    module New
      extend self

      def run(args : Array(String)) : Int32
        repo : String? = nil
        branch : String? = nil
        title : String? = nil
        file : String? = nil
        source_override : String? = nil
        auto_pr = false
        require_approval = false
        output = "text"
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules new [PROMPT|-] [options]"
          p.on("--repo OWNER/REPO", "GitHub repo (auto-detected from git origin)") { |v| repo = v }
          p.on("--branch BRANCH", "Starting branch (auto-detected from git HEAD)") { |v| branch = v }
          p.on("--source NAME", "Source resource name (overrides --repo mapping)") { |v| source_override = v }
          p.on("--title TITLE", "Session title") { |v| title = v }
          p.on("--file PATH", "Read prompt from file") { |v| file = v }
          p.on("--auto-pr", "Set automationMode=AUTO_CREATE_PR") { auto_pr = true }
          p.on("--require-approval", "Require explicit plan approval") { require_approval = true }
          p.on("-o FMT", "--output=FMT", "Output: text, json, yaml") { |v| output = v }
          p.on("-h", "--help", "Show help") { puts p; exit 0 }
          p.unknown_args { |before, _| positional = before }
        end
        parser.parse(args.dup)

        prompt_arg = positional[0]?
        prompt = Util::PromptInput.resolve(prompt_arg, file)

        cfg = Config.load
        repo ||= cfg.default_repo || Util::Git.detect_repo
        branch ||= cfg.default_branch || Util::Git.detect_branch

        source = source_override
        if source.nil?
          repo_val = repo
          if repo_val.nil? || repo_val.empty?
            STDERR.puts "error: --repo or --source is required (could not auto-detect repo from git)"
            return 2
          end
          source = Util::RepoMap.to_source(repo_val)
        end

        starting_branch = branch
        if starting_branch.nil? || starting_branch.empty?
          STDERR.puts "error: --branch is required (could not auto-detect from git)"
          return 2
        end

        body = JSON.build do |j|
          j.object do
            j.field "prompt", prompt
            j.field "title", title.not_nil! if title
            j.field "requirePlanApproval", true if require_approval
            j.field "automationMode", "AUTO_CREATE_PR" if auto_pr
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

        client = Client.new(cfg)
        session = API::Sessions.create(client, body)
        Output::Format.session(session, output)
        0
      end
    end
  end
end
