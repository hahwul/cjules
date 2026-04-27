module Cjules
  module Output
    module Colors
      extend self

      @@enabled : Bool = STDOUT.tty? && ENV["NO_COLOR"]?.nil?

      def disable!
        @@enabled = false
      end

      def enable!
        @@enabled = true
      end

      def enabled? : Bool
        @@enabled
      end

      def wrap(s : String, code : String) : String
        return s unless @@enabled
        "\e[#{code}m#{s}\e[0m"
      end

      def red(s);     wrap(s, "31"); end
      def green(s);   wrap(s, "32"); end
      def yellow(s);  wrap(s, "33"); end
      def blue(s);    wrap(s, "34"); end
      def magenta(s); wrap(s, "35"); end
      def cyan(s);    wrap(s, "36"); end
      def gray(s);    wrap(s, "90"); end
      def bold(s);    wrap(s, "1"); end
      def dim(s);     wrap(s, "2"); end

      def state(s : String) : String
        case s
        when "QUEUED", "PLANNING"
          yellow(s)
        when "AWAITING_PLAN_APPROVAL", "AWAITING_USER_FEEDBACK", "PAUSED"
          magenta(s)
        when "IN_PROGRESS"
          blue(s)
        when "COMPLETED"
          green(s)
        when "FAILED"
          red(s)
        else
          s
        end
      end

      ANSI_RE = /\e\[[0-9;]*m/

      # Approximate terminal display width: 2 cells for East-Asian Wide /
      # Fullwidth / common emoji codepoints, 1 cell otherwise. ANSI escapes
      # are stripped first.
      def display_width(s : String) : Int32
        width = 0
        s.gsub(ANSI_RE, "").each_char do |c|
          width += char_width(c)
        end
        width
      end

      # Backwards-compatible alias used by tables; same as display_width.
      def visible_length(s : String) : Int32
        display_width(s)
      end

      # Truncate a string to a maximum display width (cells), appending an
      # ellipsis when something was cut. The result's display_width is <= max.
      def truncate_display(s : String, max : Int32) : String
        return s if display_width(s) <= max
        return "" if max <= 0
        ellipsis = "…"
        budget = max - 1 # reserve a cell for the ellipsis
        result = String::Builder.new
        consumed = 0
        s.gsub(ANSI_RE, "").each_char do |c|
          w = char_width(c)
          break if consumed + w > budget
          result << c
          consumed += w
        end
        result << ellipsis
        result.to_s
      end

      private def char_width(c : Char) : Int32
        cp = c.ord
        return 1 if cp < 0x1100
        # East Asian Wide / Fullwidth / common wide ranges (approximation).
        if (cp >= 0x1100 && cp <= 0x115F) ||
           (cp >= 0x2E80 && cp <= 0x303E) ||
           (cp >= 0x3041 && cp <= 0x33FF) ||
           (cp >= 0x3400 && cp <= 0x4DBF) ||
           (cp >= 0x4E00 && cp <= 0x9FFF) ||
           (cp >= 0xA000 && cp <= 0xA4CF) ||
           (cp >= 0xAC00 && cp <= 0xD7A3) ||
           (cp >= 0xF900 && cp <= 0xFAFF) ||
           (cp >= 0xFE30 && cp <= 0xFE4F) ||
           (cp >= 0xFF00 && cp <= 0xFF60) ||
           (cp >= 0xFFE0 && cp <= 0xFFE6) ||
           (cp >= 0x1F300 && cp <= 0x1F9FF) ||
           (cp >= 0x20000 && cp <= 0x3FFFD)
          2
        else
          1
        end
      end
    end
  end
end
