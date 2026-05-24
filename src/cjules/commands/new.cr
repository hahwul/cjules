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
        reconcile_on_error = true
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
          p.on("--no-reconcile-on-error", "Do not look up matching recent sessions after a 4xx; just report the error") { reconcile_on_error = false }
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
        # Buffer for clock skew between local clock and server-assigned createTime.
        started_at = Time.utc - 30.seconds

        if parallel == 1
          begin
            session = API::Sessions.create(client, body)
            Output::Format.session(session, output)
            return 0
          rescue e : Client::APIError
            raise e unless reconcile_on_error && e.status >= 400 && e.status < 500
            recovered = reconcile_failures(client, title, prompt, source, started_at, 1, [] of Models::Session)
            raise e if recovered.empty?
            STDERR.puts "info: HTTP #{e.status} on submit but a matching session was created server-side; reporting it instead (use --no-reconcile-on-error to disable)"
            Output::Format.session(recovered[0], output)
            return 0
          end
        end

        results = create_concurrent(client, body, parallel)
        successes = results.compact_map { |r| r.is_a?(Models::Session) ? r : nil }
        client_errors = results.count { |r| r.is_a?(Client::APIError) && r.status >= 400 && r.status < 500 }
        failures = results.count { |r| r.is_a?(Exception) }

        if reconcile_on_error && client_errors > 0
          recovered = reconcile_failures(client, title, prompt, source, started_at, client_errors, successes)
          if recovered.size > 0
            STDERR.puts "info: reconciled #{recovered.size} of #{client_errors} 4xx failure(s) by matching recent sessions (use --no-reconcile-on-error to disable)"
            successes.concat(recovered)
            failures -= recovered.size
          end
        end

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
          exceptions = results.compact_map { |r| r.is_a?(Exception) ? r : nil }
          error_msgs = exceptions.map do |e|
            case e
            when Client::APIError
              "API error (HTTP #{e.status}): #{e.detail}"
            when Socket::Error | IO::Error
              "network error: #{e.message}"
            when JSON::ParseException
              "malformed JSON: #{e.message}"
            else
              e.message || "unknown error"
            end
          end.uniq
          error_msgs.each { |msg| STDERR.puts "  - #{msg}" }
          return 1
        end
        0
      end

      # After a 4xx, the Jules API sometimes returns "Precondition check failed"
      # while having already created the session (see issue #1). Look up sessions
      # created since `started_at` that match the title (or prompt fallback) and
      # are not already in `claimed`; return up to `expected` of them.
      private def reconcile_failures(client : Client, title : String?, prompt : String, source : String?, started_at : Time, expected : Int32, claimed : Array(Models::Session)) : Array(Models::Session)
        return [] of Models::Session if expected <= 0
        return [] of Models::Session if title.nil? && prompt.empty?

        recent = fetch_sessions_since(client, started_at)
        match_recovered(recent, title, prompt, source, claimed, expected)
      end

      # Pure matching logic — exposed (non-private) so specs can drive it
      # without a live API. `recent` should already be filtered to the
      # post-`started_at` window.
      def match_recovered(recent : Array(Models::Session), title : String?, prompt : String, source : String?, claimed : Array(Models::Session), expected : Int32) : Array(Models::Session)
        return [] of Models::Session if expected <= 0
        return [] of Models::Session if title.nil? && prompt.empty?

        claimed_ids = Set(String).new
        claimed.each { |s| (id = s.id) && claimed_ids.add(id) }

        candidates = recent.select do |s|
          next false if (id = s.id) && claimed_ids.includes?(id)
          if t = title
            next false unless s.title == t
          else
            next false unless s.prompt == prompt
          end
          if src = source
            next false unless s.sourceContext.try(&.source) == src
          end
          true
        end
        candidates.first(expected)
      end

      # Paginate sessions newest-first until we cross `cutoff`. Mirrors the
      # cutoff-aware pagination in `cjules ls`. Network/API/parse errors are
      # silently swallowed so the caller can surface the *original* submission
      # error; programmer errors still propagate.
      private def fetch_sessions_since(client : Client, cutoff : Time) : Array(Models::Session)
        result = [] of Models::Session
        begin
          token : String? = nil
          loop do
            page = API::Sessions.list_page(client, 100, token)
            if items = page.sessions
              items.each do |sess|
                if ct = sess.createTime
                  begin
                    return result if Time.parse_rfc3339(ct) < cutoff
                  rescue
                    next
                  end
                else
                  next
                end
                result << sess
              end
            end
            token = page.nextPageToken
            break if token.nil? || token.empty?
          end
        rescue Client::APIError | Socket::Error | IO::Error | JSON::ParseException
          # Reconciliation lookup failed — fall through with whatever we
          # gathered so far (likely empty).
        end
        result
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
