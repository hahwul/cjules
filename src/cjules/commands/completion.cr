module Cjules
  module Commands
    module Completion
      extend self

      def run(args : Array(String)) : Int32
        shell = args.first?
        case shell
        when "bash" then puts BASH; 0
        when "zsh"  then puts ZSH; 0
        when "fish" then puts FISH; 0
        else
          STDERR.puts "usage: cjules completion bash|zsh|fish"
          2
        end
      end

      BASH = <<-'B'
        # cjules bash completion
        _cjules() {
          local cur prev cmds
          cur="${COMP_WORDS[COMP_CWORD]}"
          cmds="new ls get rm prune watch msg approve plan logs activity patch pr pick retry sources templates config login logout accounts completion version help"
          if [[ $COMP_CWORD -eq 1 ]]; then
            COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
          fi
        }
        complete -F _cjules cjules
        B

      ZSH = <<-'Z'
        #compdef cjules
        _cjules() {
          local -a cmds
          cmds=(
            'new:Create a new session'
            'ls:List sessions'
            'get:Show a session'
            'rm:Delete session(s)'
            'prune:Bulk delete with dry-run'
            'watch:Tail a session'
            'msg:Send a message'
            'approve:Approve a plan'
            'plan:Show generated plans'
            'logs:Export activity log'
            'activity:Show a single activity'
            'patch:Print or apply gitPatch'
            'pr:Print PR URL'
            'pick:Interactive picker'
            'retry:Re-run a session'
            'sources:Manage sources'
            'templates:Manage prompt templates'
            'config:Show or set config'
            'login:Add an API key/account'
            'logout:Remove an API key/account'
            'accounts:List or switch accounts'
            'completion:Print shell completion script'
            'version:Show version'
          )
          _arguments '1: :->cmd' '*::arg:->args'
          case $state in
            cmd) _describe 'command' cmds ;;
          esac
        }
        _cjules
        Z

      FISH = <<-'F'
        # cjules fish completion
        complete -c cjules -f
        complete -c cjules -n "__fish_use_subcommand" -a "new"      -d "Create a new session"
        complete -c cjules -n "__fish_use_subcommand" -a "ls"       -d "List sessions"
        complete -c cjules -n "__fish_use_subcommand" -a "get"      -d "Show a session"
        complete -c cjules -n "__fish_use_subcommand" -a "rm"       -d "Delete session(s)"
        complete -c cjules -n "__fish_use_subcommand" -a "prune"    -d "Bulk delete with dry-run"
        complete -c cjules -n "__fish_use_subcommand" -a "watch"    -d "Tail a session"
        complete -c cjules -n "__fish_use_subcommand" -a "msg"      -d "Send a message"
        complete -c cjules -n "__fish_use_subcommand" -a "approve"  -d "Approve a plan"
        complete -c cjules -n "__fish_use_subcommand" -a "plan"     -d "Show generated plans"
        complete -c cjules -n "__fish_use_subcommand" -a "logs"     -d "Export activity log"
        complete -c cjules -n "__fish_use_subcommand" -a "activity" -d "Show a single activity"
        complete -c cjules -n "__fish_use_subcommand" -a "patch"    -d "Print or apply gitPatch"
        complete -c cjules -n "__fish_use_subcommand" -a "pr"       -d "Print PR URL"
        complete -c cjules -n "__fish_use_subcommand" -a "pick"     -d "Interactive picker"
        complete -c cjules -n "__fish_use_subcommand" -a "retry"    -d "Re-run a session"
        complete -c cjules -n "__fish_use_subcommand" -a "sources"  -d "Manage sources"
        complete -c cjules -n "__fish_use_subcommand" -a "templates" -d "Manage prompt templates"
        complete -c cjules -n "__fish_use_subcommand" -a "config"   -d "Show or set config"
        complete -c cjules -n "__fish_use_subcommand" -a "login"    -d "Add an API key/account"
        complete -c cjules -n "__fish_use_subcommand" -a "logout"   -d "Remove an API key/account"
        complete -c cjules -n "__fish_use_subcommand" -a "accounts" -d "List or switch accounts"
        complete -c cjules -n "__fish_use_subcommand" -a "completion" -d "Print shell completion"
        complete -c cjules -n "__fish_use_subcommand" -a "version"  -d "Show version"
        F
    end
  end
end
