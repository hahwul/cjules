require "./version"
require "./config"
require "./client"
require "./output/colors"
require "./commands/new"
require "./commands/list"
require "./commands/get"
require "./commands/delete"
require "./commands/watch"
require "./commands/message"
require "./commands/approve"
require "./commands/logs"
require "./commands/patch"
require "./commands/plan"
require "./commands/pr"
require "./commands/pick"
require "./commands/sources"
require "./commands/config"
require "./commands/login"
require "./commands/logout"
require "./commands/accounts"
require "./commands/completion"

module Cjules
  module CLI
    extend self

    def run(args : Array(String)) : Int32
      argv = args.dup

      # Strip global flags before dispatch.
      i = 0
      while i < argv.size
        a = argv[i]
        if a == "--no-color"
          Output::Colors.disable!
          argv.delete_at(i)
        elsif a == "--account"
          val = argv[i + 1]?
          if val.nil? || val.empty?
            STDERR.puts "error: --account requires a value"
            return 2
          end
          unless Config.valid_alias?(val)
            STDERR.puts "error: --account value must match [A-Za-z0-9._-]+ (got #{val.inspect})"
            return 2
          end
          ENV["JULES_ACCOUNT"] = val
          argv.delete_at(i + 1)
          argv.delete_at(i)
        elsif a.starts_with?("--account=")
          val = a["--account=".size..]
          if val.empty?
            STDERR.puts "error: --account requires a value"
            return 2
          end
          unless Config.valid_alias?(val)
            STDERR.puts "error: --account value must match [A-Za-z0-9._-]+ (got #{val.inspect})"
            return 2
          end
          ENV["JULES_ACCOUNT"] = val
          argv.delete_at(i)
        else
          i += 1
        end
      end

      cmd = argv.shift?
      if cmd.nil? || cmd == "-h" || cmd == "--help" || cmd == "help"
        usage
        return 0
      end

      begin
        case cmd
        when "version", "--version", "-V"
          puts "cjules #{Cjules::VERSION}"
          0
        when "new", "create"       then Commands::New.run(argv)
        when "ls", "list"          then Commands::List.run(argv)
        when "get", "show"         then Commands::Get.run(argv)
        when "rm", "delete"        then Commands::Delete.run(argv)
        when "watch", "tail"       then Commands::Watch.run(argv)
        when "msg", "message"      then Commands::Message.run(argv)
        when "approve"             then Commands::Approve.run(argv)
        when "logs", "log"         then Commands::Logs.run(argv)
        when "patch", "diff"       then Commands::Patch.run(argv)
        when "plan"                then Commands::Plan.run(argv)
        when "pr"                  then Commands::PR.run(argv)
        when "pick"                then Commands::Pick.run(argv)
        when "sources"             then Commands::SourcesCmd.run(argv)
        when "config"              then Commands::ConfigCmd.run(argv)
        when "login"               then Commands::Login.run(argv)
        when "logout"              then Commands::Logout.run(argv)
        when "accounts", "account" then Commands::Accounts.run(argv)
        when "completion"          then Commands::Completion.run(argv)
        else
          STDERR.puts "error: unknown command: #{cmd}"
          STDERR.puts ""
          usage(STDERR)
          1
        end
      rescue e : Client::APIError
        STDERR.puts "API error (HTTP #{e.status}): #{e.detail}"
        1
      rescue e : Socket::Error | IO::Error
        STDERR.puts "network error: #{e.message}"
        1
      end
    end

    def usage(io : IO = STDOUT)
      io.puts <<-USAGE
        cjules — Crystal CLI for the Jules API (v#{Cjules::VERSION})

        USAGE:
          cjules [--account ALIAS] [--no-color] <command> [options]

        SESSIONS:
          new [PROMPT|-]      Create a session (auto-detects repo/branch from git)
          ls                  List sessions with filters (--state, --since, --search, --repo)
          get <ID>            Show a session
          rm <ID...>          Delete sessions, or bulk by --state/--older-than/--repo
          watch <ID>          Tail activities; --auto-approve / --reply for hands-free runs
          msg <ID> <TEXT|->   Send a follow-up message
          approve <ID>        Approve a pending plan
          plan <ID>           Show the latest generated plan (--all for history)
          logs <ID>           Export full activity log (md/json/text)
          patch <ID>          Print, list, or --apply gitPatch artifacts
          pr <ID>             Print PR URL (--open to launch browser)
          pick                Interactive picker (uses fzf if installed)

        SOURCES:
          sources ls
          sources get <ID>

        ACCOUNTS:
          login               Save an API key under an alias
          logout              Remove a saved account
          accounts ls         List saved accounts
          accounts use <NAME> Switch active account
          accounts current    Print active account alias

        CONFIG:
          config show         Show effective config
          config set <K> <V>  Set api_base / default_repo / default_branch
          config path         Print config file path

        MISC:
          completion bash|zsh|fish
          version

        Run `cjules <command> --help` for command-specific options.

        ENV:
          JULES_API_KEY   override key for one-off invocations
          JULES_ACCOUNT   override active account alias
          JULES_API_BASE  override API base URL
          NO_COLOR        disable color output
        USAGE
    end
  end
end
