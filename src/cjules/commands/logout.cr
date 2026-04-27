require "option_parser"
require "../config"

module Cjules
  module Commands
    module Logout
      extend self

      def run(args : Array(String)) : Int32
        alias_name : String? = nil
        all = false
        yes = false
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules logout [--alias NAME] [--all] [-y]"
          p.on("--alias NAME", "Remove a specific account") { |v| alias_name = v }
          p.on("--all", "Remove every saved account") { all = true }
          p.on("-y", "--yes", "Skip confirmation") { yes = true }
          p.on("-h", "--help", "Show help") { puts p; exit 0 }
          p.unknown_args { |before, _| positional = before }
        end
        parser.parse(args.dup)

        # Allow `cjules logout NAME` shorthand.
        if alias_name.nil? && !positional.empty?
          alias_name = positional[0]
        end

        cfg = Config.load
        if cfg.accounts.empty?
          puts "no accounts saved"
          return 0
        end

        if all
          unless yes
            unless STDIN.tty? && STDOUT.tty?
              STDERR.puts "error: --all is destructive; pass -y to confirm in non-interactive use"
              return 2
            end
            STDERR.print "remove ALL #{cfg.accounts.size} account(s)? [y/N]: "
            ans = STDIN.gets.try(&.strip) || ""
            unless ans.downcase == "y" || ans.downcase == "yes"
              STDERR.puts "aborted"
              return 1
            end
          end
          cfg.accounts.clear
          cfg.current = nil
          cfg.save
          puts "removed all accounts"
          return 0
        end

        target = alias_name || cfg.active_alias
        if target.nil? || target.empty?
          STDERR.puts "error: no active account; pass --alias NAME or --all"
          return 2
        end

        unless cfg.has_account?(target)
          STDERR.puts "error: no such account: #{target}"
          STDERR.puts "  saved: #{cfg.accounts.keys.join(", ")}"
          return 1
        end

        cfg.remove_account(target)
        cfg.save

        puts "removed account `#{target}`"
        if env_alias = ENV["JULES_ACCOUNT"]?
          if !env_alias.empty? && env_alias == target
            STDERR.puts "warning: JULES_ACCOUNT=#{env_alias} still points to the removed account; unset or change it"
          end
        end
        if cfg.accounts.empty?
          puts "no accounts left"
        elsif cfg.current.nil?
          puts "no active account; run `cjules accounts use <alias>`"
        else
          puts "active account: #{cfg.current}"
        end
        0
      end
    end
  end
end
