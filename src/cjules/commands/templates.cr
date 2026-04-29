require "../help"
require "../config"

module Cjules
  module Commands
    module Templates
      extend self

      EXTENSIONS = %w(.md .txt)

      def dir : String
        File.expand_path("~/.config/cjules/templates", home: true)
      end

      # Resolve a template name to a file path on disk.
      # Tries the bare name first, then `.md` / `.txt`.
      def find(name : String) : String?
        d = dir
        candidates = [File.join(d, name)] + EXTENSIONS.map { |ext| File.join(d, "#{name}#{ext}") }
        candidates.each do |path|
          return path if File.file?(path)
        end
        nil
      end

      def list : Array(String)
        d = dir
        return [] of String unless Dir.exists?(d)
        names = Dir.entries(d).compact_map do |f|
          next nil if f.starts_with?(".")
          next nil unless File.file?(File.join(d, f))
          if ext = EXTENSIONS.find { |e| f.ends_with?(e) }
            f[0...(f.size - ext.size)]
          else
            f
          end
        end
        names.uniq.sort
      end

      def run(args : Array(String)) : Int32
        sub = args.first?
        rest = args.size > 1 ? args[1..].to_a : [] of String
        case sub
        when "ls", "list", nil then ls
        when "show", "cat"     then show(rest)
        when "path"
          puts dir
          0
        when "-h", "--help"
          usage
          0
        else
          STDERR.puts "error: unknown templates subcommand: #{sub}"
          usage(STDERR)
          2
        end
      end

      def usage(io : IO = STDOUT)
        io.puts <<-USAGE
          Usage:
            cjules templates ls
            cjules templates show <name>
            cjules templates path

          Templates are plain text or markdown files in:
            #{dir}

          Use a template with:
            cjules new --template <name>
          USAGE
        io.puts Help::GLOBAL_FLAGS
      end

      private def ls : Int32
        names = list
        if names.empty?
          puts "(no templates — drop *.md or *.txt files into #{dir})"
          return 0
        end
        names.each { |n| puts n }
        0
      end

      private def show(args : Array(String)) : Int32
        name = args.first?
        if name.nil? || name.empty?
          STDERR.puts "usage: cjules templates show <name>"
          return 2
        end
        path = find(name)
        unless path
          STDERR.puts "error: no such template: #{name}"
          return 1
        end
        puts File.read(path)
        0
      end
    end
  end
end
