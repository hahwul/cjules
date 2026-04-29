require "option_parser"
require "../help"
require "http/client"
require "uri"
require "../config"

module Cjules
  module Commands
    module Login
      extend self

      def run(args : Array(String)) : Int32
        alias_name : String? = nil
        key_arg : String? = nil
        from_stdin = false
        activate = false
        verify = false

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules login [--alias NAME] [--key KEY] [--stdin] [--activate] [--verify]"
          p.on("--alias NAME", "Account alias (prompted if omitted)") { |v| alias_name = v }
          p.on("--key KEY", "API key value (prompted if omitted)") { |v| key_arg = v }
          p.on("--stdin", "Read API key from stdin") { from_stdin = true }
          p.on("--activate", "Make this account active (default: only on first login)") { activate = true }
          p.on("--verify", "Test the key against the API before saving") { verify = true }
          p.on("-h", "--help", "Show help") { puts p; puts Help::GLOBAL_FLAGS; exit 0 }
        end
        parser.parse(args.dup)

        cfg = Config.load

        if alias_name.nil? || alias_name.not_nil!.empty?
          unless STDIN.tty?
            STDERR.puts "error: --alias is required in non-interactive use"
            return 2
          end
          STDERR.print "alias: "
          ans = STDIN.gets.try(&.strip)
          alias_name = ans
        end
        if alias_name.nil? || alias_name.not_nil!.empty?
          STDERR.puts "error: alias is required"
          return 2
        end
        an = alias_name.not_nil!
        unless Config.valid_alias?(an)
          STDERR.puts "error: alias must match [A-Za-z0-9._-]+ (max 64 chars), got: #{an.inspect}"
          return 2
        end

        if from_stdin
          key_arg = STDIN.gets_to_end.strip
        end
        if key_arg.nil? || key_arg.not_nil!.empty?
          unless STDIN.tty?
            STDERR.puts "error: --key or --stdin is required in non-interactive use"
            return 2
          end
          STDERR.print "API key (input hidden): "
          key_arg = read_secret
          STDERR.puts ""
        end
        if key_arg.nil? || key_arg.not_nil!.empty?
          STDERR.puts "error: API key is required"
          return 2
        end
        key = key_arg.not_nil!

        if verify
          STDERR.print "verifying... "
          if verify_key(cfg.api_base, key)
            STDERR.puts "OK"
          else
            STDERR.puts "FAILED"
            STDERR.puts "  the key did not authenticate against #{cfg.api_base}"
            return 1
          end
        end

        if dup = cfg.alias_for_key(key, except: an)
          STDERR.puts "warning: this key is already saved as `#{dup}`"
        end

        existed = cfg.has_account?(an)
        cfg.add_account(an, key)

        # New default: activate only when there's no current account, or when --activate.
        was_activated = false
        if activate || cfg.current.nil?
          cfg.current = an
          was_activated = true
        end
        cfg.save

        verb = existed ? "updated" : "added"
        puts "#{verb} account `#{an}` (#{Config.mask(key)})"
        if was_activated
          puts "active account: #{an}"
        else
          puts "active account unchanged: #{cfg.current}"
          puts "  switch with: cjules accounts use #{an}"
        end
        0
      end

      private def verify_key(api_base : String, key : String) : Bool
        uri = URI.parse(api_base)
        client = HTTP::Client.new(uri)
        client.connect_timeout = 5.seconds
        client.read_timeout = 10.seconds
        headers = HTTP::Headers{
          "x-goog-api-key" => key,
          "Accept"         => "application/json",
        }
        response = client.get("/v1alpha/sessions?pageSize=1", headers: headers)
        response.status_code < 400
      rescue
        false
      end

      # Read a line from STDIN with terminal echo disabled.
      # Restores terminal state via stdlib `noecho` (ensure-block) and an INT trap.
      private def read_secret : String?
        unless STDIN.tty?
          return STDIN.gets.try(&.strip)
        end

        Signal::INT.trap do
          # On Ctrl+C, force-restore echo before exiting.
          Process.run("stty", ["echo"], output: Process::Redirect::Close, error: Process::Redirect::Close)
          STDERR.puts ""
          exit 130
        end

        begin
          STDIN.noecho do
            STDIN.gets.try(&.strip)
          end
        ensure
          Signal::INT.reset
        end
      rescue
        # If noecho fails (e.g. unsupported terminal), fall back to plain input.
        STDIN.gets.try(&.strip)
      end
    end
  end
end
