require "./models"
require "./template_renderer"
require "./errors"

module Cjules
  module Util
    module SessionFilter
      extend self

      # Parse a session's createTime as RFC3339; returns nil on missing/malformed.
      def parse_create_time(sess : Models::Session) : Time?
        if t = sess.createTime
          begin
            Time.parse_rfc3339(t)
          rescue
            nil
          end
        end
      end

      # Single predicate covering the state + repo + cutoff + search filter set
      # used by `ls`, `rm`, and `prune`. `newer_than` keeps sessions created at
      # or after the cutoff (i.e. `--since`); `older_than` keeps sessions
      # created strictly before the cutoff (i.e. `--older-than`). A session
      # with a missing/malformed createTime fails any cutoff filter.
      def matches?(sess : Models::Session,
                   state : String? = nil,
                   repo : String? = nil,
                   newer_than : Time? = nil,
                   older_than : Time? = nil,
                   search : String? = nil) : Bool
        return false if state && sess.state != state
        if rf = repo
          src = sess.sourceContext.try(&.source) || ""
          return false unless src.includes?(rf)
        end
        if newer_than || older_than
          ct = parse_create_time(sess)
          return false unless ct
          return false if (n = newer_than) && ct < n
          return false if (o = older_than) && ct >= o
        end
        if q = search
          combined = "#{sess.prompt} #{sess.title}"
          return false unless combined.downcase.includes?(q.downcase)
        end
        true
      end
    end

    module ID
      extend self

      def normalize(id : String) : String
        id.sub(/^sessions\//, "").sub(/^sources\//, "")
      end
    end

    module Duration
      extend self

      # Parse strings like "30s", "5m", "2h", "7d", "1w".
      def parse(s : String) : Time::Span?
        if m = s.strip.match(/^(\d+)\s*([smhdw])$/i)
          n = m[1].to_i
          case m[2].downcase
          when "s" then n.seconds
          when "m" then n.minutes
          when "h" then n.hours
          when "d" then n.days
          when "w" then n.weeks
          end
        end
      end

      def humanize(span : Time::Span) : String
        if span.total_days >= 1
          "#{span.total_days.to_i}d"
        elsif span.total_hours >= 1
          "#{span.total_hours.to_i}h"
        elsif span.total_minutes >= 1
          "#{span.total_minutes.to_i}m"
        else
          "#{span.total_seconds.to_i}s"
        end
      end
    end

    module Git
      extend self

      def detect_repo : String?
        url = run("git", "config", "--get", "remote.origin.url")
        return nil unless url
        parse_repo(url)
      end

      def detect_branch : String?
        run("git", "rev-parse", "--abbrev-ref", "HEAD")
      end

      # Extract "owner/repo" from a git remote URL.
      def parse_repo(url : String) : String?
        if m = url.match(/github\.com[:\/]([^\/]+)\/([^\/\s]+?)(?:\.git)?\s*$/)
          "#{m[1]}/#{m[2]}"
        end
      end

      private def run(cmd : String, *args) : String?
        begin
          io = IO::Memory.new
          status = Process.run(cmd, args.to_a,
            output: io,
            error: Process::Redirect::Close)
          return nil unless status.success?
          out = io.to_s.strip
          out.empty? ? nil : out
        rescue Exception
          nil
        end
      end
    end

    module PromptInput
      extend self

      # Resolve prompt text from positional arg, file, or stdin.
      # If vars is provided, applies template rendering with variable substitution.
      def resolve(arg : String?, file : String? = nil, vars : TemplateRenderer::Variables? = nil) : String
        raw_prompt = if file
                       File.read(file).strip
                     elsif arg == "-"
                       STDIN.gets_to_end.strip
                     elsif arg && !arg.empty?
                       arg.strip
                     elsif !STDIN.tty?
                       piped = STDIN.gets_to_end.strip
                       return piped unless piped.empty?
                       raise Cjules::UsageError.new("prompt is required (provide as argument, --file, or stdin)")
                     else
                       raise Cjules::UsageError.new("prompt is required (provide as argument, --file, or stdin)")
                     end

        # Apply template rendering (always render to support {{.File}}, {{.GitDiff}}, etc.)
        TemplateRenderer.render(raw_prompt, vars || TemplateRenderer::Variables.new)
      end
    end

    # Convert "owner/repo" to the source resource name used by the Jules API.
    # The live API uses slash-separated source IDs, e.g. "sources/github/owner/repo",
    # rather than the hyphen form sometimes shown in API examples.
    module RepoMap
      extend self

      def to_source(repo : String) : String
        "sources/github/#{repo}"
      end
    end
  end
end
