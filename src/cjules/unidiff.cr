module Cjules
  # Minimal unified-diff parser + interactive hunk selector.
  #
  # The Jules API returns a `git format-patch`-style unidiff in `gitPatch.unidiffPatch`.
  # We split it into "chunks" that can be applied independently via `git apply`.
  module Unidiff
    extend self

    record Chunk, label : String, lines : Array(String)

    # Split a unidiff into independent chunks (usually hunks). Each returned chunk
    # includes the necessary file headers so it can be applied on its own.
    def chunks(text : String) : Array(Chunk)
      raw_lines = text.lines.map(&.chomp)
      sections = split_sections(raw_lines)
      out = [] of Chunk
      sections.each do |section|
        label = section_label(section)
        header, hunks = split_header_and_hunks(section)
        if hunks.empty?
          # Binary patches / mode-only changes can contain no @@ hunks. Treat the
          # whole section as one chunk.
          out << Chunk.new(label, section.dup)
        else
          hunks.each do |h|
            out << Chunk.new(label, header + h)
          end
        end
      end
      out
    end

    module Interactive
      extend self

      enum Decision
        Apply
        Skip
        Quit
        ApplyAll
        SkipAll
        Edit
        Help
      end

      struct Result
        getter selected_patch : String
        getter selected_chunks : Int32
        getter skipped_chunks : Int32
        getter quit_early : Bool

        def initialize(@selected_patch : String, @selected_chunks : Int32, @skipped_chunks : Int32, @quit_early : Bool)
        end
      end

      def select(text : String,
                 input : IO = STDIN,
                 output : IO = STDERR,
                 display : IO = STDOUT) : Result
        all = Unidiff.chunks(text)
        if all.empty?
          return Result.new("", 0, 0, false)
        end

        selected = [] of Array(String)
        selected_count = 0
        skipped_count = 0
        quit_early = false

        i = 0
        while i < all.size
          chunk = all[i]
          show_chunk(chunk, i + 1, all.size, display)

          loop do
            output.print "Apply this hunk? [y,n,q,a,d,e,?] "
            output.flush
            line = input.gets
            if line.nil?
              quit_early = true
              i = all.size
              break
            end
            decision = parse_decision(line)
            case decision
            when Decision::Apply
              selected << chunk.lines
              selected_count += 1
              break
            when Decision::Skip
              skipped_count += 1
              break
            when Decision::Quit
              quit_early = true
              i = all.size
              break
            when Decision::ApplyAll
              selected << chunk.lines
              selected_count += 1
              (i + 1).upto(all.size - 1) do |j|
                selected << all[j].lines
                selected_count += 1
              end
              i = all.size
              break
            when Decision::SkipAll
              skipped_count += 1
              skipped_count += (all.size - (i + 1))
              i = all.size
              break
            when Decision::Edit
              edited = edit_chunk(chunk, output, display)
              if edited
                selected << edited
                selected_count += 1
                break
              end
              # If editing failed/aborted, re-prompt for the same chunk.
            when Decision::Help
              print_help(output)
            end
          end

          i += 1
        end

        patch = render_selected(selected)
        Result.new(patch, selected_count, skipped_count, quit_early)
      end

      private def show_chunk(chunk : Chunk, idx : Int32, total : Int32, display : IO)
        display.puts "\n#{chunk.label} (hunk #{idx}/#{total})"
        display.puts "-" * 72
        chunk.lines.each { |l| display.puts l }
        display.puts "-" * 72
        display.flush
      end

      private def parse_decision(line : String) : Decision
        c = line.strip.downcase[0]?
        case c
        when 'y' then Decision::Apply
        when 'n' then Decision::Skip
        when 'q' then Decision::Quit
        when 'a' then Decision::ApplyAll
        when 'd' then Decision::SkipAll
        when 'e' then Decision::Edit
        else
          Decision::Help
        end
      end

      private def print_help(io : IO)
        io.puts "y - apply this hunk"
        io.puts "n - skip this hunk"
        io.puts "q - quit; apply already-selected hunks"
        io.puts "a - apply this and all remaining hunks"
        io.puts "d - skip this and all remaining hunks"
        io.puts "e - edit the current hunk"
        io.puts "? - show this help"
        io.flush
      end

      private def render_selected(chunks : Array(Array(String))) : String
        return "" if chunks.empty?
        String.build do |s|
          chunks.each_with_index do |lines, i|
            lines.each { |l| s << l << '\n' }
            s << '\n' if i < chunks.size - 1
          end
        end
      end

      private def edit_chunk(chunk : Chunk, output : IO, display : IO) : Array(String)?
        editor = resolve_editor
        if editor.nil?
          output.puts "error: no editor found (set $EDITOR or $VISUAL)"
          output.flush
          return nil
        end

        tmp = File.tempfile("cjules-hunk-", ".patch")
        begin
          File.write(tmp.path, chunk.lines.join("\n") + "\n")
          ok = run_editor(editor, tmp.path, output, display)
          return nil unless ok
          edited_text = File.read(tmp.path)
          if edited_text.strip.empty?
            output.puts "edit produced an empty patch; not applying"
            output.flush
            return nil
          end
          if check_applies?(tmp.path, output)
            return edited_text.lines.map(&.chomp)
          end
          nil
        ensure
          tmp.delete
        end
      end

      private def resolve_editor : String?
        ENV["CJULES_EDITOR"]? || ENV["GIT_EDITOR"]? || ENV["VISUAL"]? || ENV["EDITOR"]?
      end

      private def run_editor(editor : String, path : String, output : IO, display : IO) : Bool
        # Parse editor command into program + flags and pass path as a separate arg
        # to avoid shell injection and quoting issues.
        parts = editor.split
        program = parts[0]
        args = parts[1..] + [path]
        status = Process.run(program, args,
          input: input_for_editor,
          output: display,
          error: output)
        status.success?
      rescue ex : Exception
        output.puts "error: failed to run editor: #{ex.message}"
        output.flush
        false
      end

      private def input_for_editor : IO
        # Editor needs the real stdin for interactive control (not the prompt IO).
        STDIN
      end

      private def check_applies?(patch_path : String, output : IO) : Bool
        out_io = IO::Memory.new
        err = IO::Memory.new
        status = Process.run("git", ["apply", "--check", patch_path], output: out_io, error: err)
        return true if status.success?
        output.puts "edited hunk does not apply (git apply --check failed):"
        o = out_io.to_s.strip
        e = err.to_s.strip
        output.puts o unless o.empty?
        output.puts e unless e.empty?
        output.flush
        false
      rescue ex : Exception
        output.puts "error: failed to validate edited hunk: #{ex.message}"
        output.flush
        false
      end
    end

    private def split_sections(lines : Array(String)) : Array(Array(String))
      starts = [] of Int32
      lines.each_with_index do |l, i|
        starts << i if l.starts_with?("diff --git ")
      end
      return [lines] if starts.empty?

      sections = [] of Array(String)
      starts.each_with_index do |s, idx|
        e = starts[idx + 1]? || lines.size
        sections << lines[s...e].to_a
      end
      sections
    end

    private def split_header_and_hunks(section : Array(String)) : {Array(String), Array(Array(String))}
      header = [] of String
      hunks = [] of Array(String)
      current : Array(String)? = nil
      section.each do |l|
        if l.starts_with?("@@")
          current = [] of String
          current << l
          hunks << current
        else
          if cur = current
            cur << l
          else
            header << l
          end
        end
      end
      {header, hunks}
    end

    private def section_label(section : Array(String)) : String
      diff = section.find { |l| l.starts_with?("diff --git ") }
      if diff
        if m = diff.match(/^diff --git a\/(\S+)\s+b\/(\S+)$/)
          return m[2]
        end
      end
      plus = section.find { |l| l.starts_with?("+++ ") }
      if plus
        return plus.sub(/^\+\+\+\s+/, "")
      end
      minus = section.find { |l| l.starts_with?("--- ") }
      if minus
        return minus.sub(/^---\s+/, "")
      end
      "patch"
    end
  end
end
