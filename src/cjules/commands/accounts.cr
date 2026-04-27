require "../config"

module Cjules
  module Commands
    module Accounts
      extend self

      def run(args : Array(String)) : Int32
        sub = args.first?
        rest = args.size > 1 ? args[1..].to_a : [] of String
        case sub
        when "ls", "list", nil
          ls
        when "use", "switch"
          use(rest)
        when "current", "whoami"
          current
        when "-h", "--help"
          usage
          0
        else
          STDERR.puts "unknown accounts subcommand: #{sub}"
          usage(STDERR)
          2
        end
      end

      def usage(io : IO = STDOUT)
        io.puts <<-USAGE
          Usage:
            cjules accounts ls
            cjules accounts use <alias>
            cjules accounts current
          USAGE
      end

      private def ls : Int32
        cfg = Config.load
        active = cfg.active_alias
        if cfg.accounts.empty?
          puts "(no accounts — run `cjules login --alias <name>`)"
          return 0
        end
        cfg.accounts.each do |alias_name, key|
          puts Config.format_account_line(alias_name, key, active == alias_name)
        end
        if cfg.env_account_override?
          puts ""
          puts "(active set via JULES_ACCOUNT env var)"
        end
        0
      end

      private def use(args : Array(String)) : Int32
        target = args.first?
        if target.nil? || target.empty?
          STDERR.puts "usage: cjules accounts use <alias>"
          return 2
        end
        unless Config.valid_alias?(target)
          STDERR.puts "error: alias must match [A-Za-z0-9._-]+ (got #{target.inspect})"
          return 2
        end
        cfg = Config.load
        unless cfg.has_account?(target)
          STDERR.puts "error: no such account: #{target}"
          STDERR.puts "  saved: #{cfg.accounts.keys.join(", ")}" unless cfg.accounts.empty?
          return 1
        end
        cfg.current = target
        cfg.save
        puts "active account: #{target}"
        if cfg.env_account_override?
          puts "note: JULES_ACCOUNT env var is set and will override this for the current shell"
        end
        0
      end

      private def current : Int32
        cfg = Config.load
        if a = cfg.active_alias
          puts a
          0
        else
          STDERR.puts "(no active account)"
          1
        end
      end
    end
  end
end
