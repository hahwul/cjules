module Cjules
  module Help
    # Footer appended to subcommand --help output. Subcommands parse their own
    # OptionParser, so global flags (handled in CLI.run before dispatch) would
    # otherwise be invisible from `cjules <cmd> -h`.
    GLOBAL_FLAGS = <<-FLAGS

      Global flags (specify before <command>):
          --account ALIAS                  Use a saved account just for this command
          --no-color                       Disable color output
      FLAGS
  end
end
