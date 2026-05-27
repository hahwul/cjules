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

    # Prints the parser banner/options followed by the global flags footer.
    # Used by all subcommands for consistent --help output.
    def self.show_help(parser : OptionParser, io : IO = STDOUT) : Nil
      io.puts parser
      io.puts GLOBAL_FLAGS
    end
  end
end
