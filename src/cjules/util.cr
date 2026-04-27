module Cjules
  module Util
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
        io = IO::Memory.new
        status = Process.run(cmd, args.to_a,
          output: io,
          error: Process::Redirect::Close)
        return nil unless status.success?
        out = io.to_s.strip
        out.empty? ? nil : out
      end
    end

    module PromptInput
      extend self

      # Resolve prompt text from positional arg, file, or stdin.
      def resolve(arg : String?, file : String? = nil) : String
        if file
          return File.read(file).strip
        end
        if arg == "-"
          return STDIN.gets_to_end.strip
        end
        if arg && !arg.empty?
          return arg.strip
        end
        if !STDIN.tty?
          piped = STDIN.gets_to_end.strip
          return piped unless piped.empty?
        end
        STDERR.puts "error: prompt is required (provide as argument, --file, or stdin)"
        exit 2
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
