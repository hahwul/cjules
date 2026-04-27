require "../config"

module Cjules
  module Commands
    module ConfigCmd
      extend self

      KEYS = %w(api_base default_repo default_branch)

      def run(args : Array(String)) : Int32
        sub = args.first?
        case sub
        when "show", nil
          show
        when "set"
          if args.size < 3
            STDERR.puts "usage: cjules config set <KEY> <VALUE>"
            STDERR.puts "  available keys: #{KEYS.join(", ")}"
            return 2
          end
          set(args[1], args[2])
        when "path"
          puts Config.path
          0
        when "-h", "--help"
          puts <<-USAGE
            Usage:
              cjules config show
              cjules config set <KEY> <VALUE>
              cjules config path

            Keys: #{KEYS.join(", ")}

            For API keys / accounts, use:
              cjules login --alias <name>
              cjules accounts ls
              cjules accounts use <alias>
              cjules logout [--alias <name>] [--all]
            USAGE
          0
        else
          STDERR.puts "unknown config subcommand: #{sub}"
          2
        end
      end

      private def show : Int32
        cfg = Config.load
        active = cfg.active_alias
        env_override = cfg.env_account_override?

        puts "config file    : #{Config.path}"
        puts "api_base       : #{cfg.api_base}"
        puts "default_repo   : #{cfg.default_repo || "(unset)"}"
        puts "default_branch : #{cfg.default_branch || "(unset)"}"

        active_label =
          if env_override
            "#{active} (overridden by JULES_ACCOUNT)"
          else
            active || "(none)"
          end
        puts "active account : #{active_label}"
        puts "config current : #{cfg.current || "(none)"}" if env_override

        if cfg.accounts.empty?
          puts "accounts       : (none — run `cjules login --alias <name>`)"
        else
          puts "accounts       :"
          cfg.accounts.each do |alias_name, key|
            puts "  #{Config.format_account_line(alias_name, key, active == alias_name)}"
          end
        end
        0
      end

      private def set(key : String, value : String) : Int32
        cfg = Config.load
        case key
        when "api_base"
          if value.empty?
            STDERR.puts "error: api_base cannot be empty"
            return 2
          end
          cfg.api_base = value
        when "default_repo"
          cfg.default_repo = value.empty? ? nil : value
        when "default_branch"
          cfg.default_branch = value.empty? ? nil : value
        else
          STDERR.puts "error: unknown key: #{key}"
          STDERR.puts "  available: #{KEYS.join(", ")}"
          return 2
        end
        cfg.save
        puts "saved"
        0
      end
    end
  end
end
