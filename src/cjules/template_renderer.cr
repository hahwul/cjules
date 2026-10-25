module Cjules
  # TemplateRenderer processes template strings with variable substitution.
  # Supports:
  # - {{.File "path"}} - Inserts file content
  # - {{.GitDiff}} - Inserts git diff output
  # - {{.Var "name"}} - Inserts user-defined variables
  module TemplateRenderer
    extend self

    # Variable storage for user-defined variables
    alias Variables = Hash(String, String)

    # Render a template string with variable substitution
    def render(template : String, vars : Variables = Variables.new) : String
      # {{.File}} first, so included partials can use {{.GitDiff}}/{{.Var}}.
      result = process_file_directives(template)

      # {{.GitDiff}} and {{.Var}} in a single pass, so directive-like text inside
      # the diff or a variable value is inserted verbatim, not expanded again.
      diff : String? = nil
      result.gsub(/\{\{\.GitDiff\}\}|\{\{\.Var\s+"([^"]+)"\}\}|\{\{\.Var\s+'([^']+)'\}\}/) do
        if var_name = $~[1]? || $~[2]?
          vars[var_name]? || "[undefined variable: #{var_name}]"
        else
          diff ||= get_git_diff
        end
      end
    end

    # Parse --var arguments from CLI (format: key=value)
    def parse_vars(var_args : Array(String)) : Variables
      vars = Variables.new
      var_args.each do |arg|
        if m = arg.match(/^([^=]+)=(.*)$/)
          key = m[1]
          value = m[2]
          vars[key] = value
        else
          STDERR.puts "warning: ignoring malformed --var argument: #{arg} (expected key=value)"
        end
      end
      vars
    end

    private def process_file_directives(content : String) : String
      # Match {{.File "path"}} or {{.File 'path'}}
      content.gsub(/\{\{\.File\s+"([^"]+)"\}\}|\{\{\.File\s+'([^']+)'\}\}/) do
        # Extract path from either double or single quotes
        path = $~[1]? || $~[2]
        read_file(path)
      end
    end

    private def read_file(path : String) : String
      # Resolve relative paths from current directory
      abs_path = File.expand_path(path)

      unless File.exists?(abs_path)
        return "[file not found: #{path}]"
      end

      unless File.file?(abs_path)
        return "[not a file: #{path}]"
      end

      begin
        File.read(abs_path)
      rescue e : Exception
        "[error reading file #{path}: #{e.message}]"
      end
    end

    private def get_git_diff : String
      io = IO::Memory.new
      status = Process.run("git", ["diff"], output: io, error: Process::Redirect::Close)

      unless status.success?
        return "[git diff failed]"
      end

      diff = io.to_s
      if diff.empty?
        return "[no git changes]"
      end

      diff
    rescue e : Exception
      "[error running git diff: #{e.message}]"
    end
  end
end
