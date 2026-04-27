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

      def visible_length(s : String) : Int32
        s.gsub(ANSI_RE, "").size
      end
    end
  end
end
