require "option_parser"
require "../help"
require "../config"
require "../client"
require "../api"
require "../util"
require "../output/colors"
require "../output/format"

module Cjules
  module Commands
    module Dash
      extend self

      # Entry point for `cjules dash` / `cjules dashboard`.
      def run(args : Array(String)) : Int32
        poll_interval = 2
        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules dash [options]"
          p.on("--interval SEC", "Poll interval in seconds for sessions (default 2)") { |v| poll_interval = v.to_i.clamp(1, 30) }
          p.on("-h", "--help", "Show help") { Help.show_help(p); exit 0 }
        end
        parser.parse(args.dup)

        unless STDOUT.tty? && STDIN.tty?
          STDERR.puts "error: cjules dash requires an interactive terminal (TTY)"
          return 1
        end

        cfg = Config.load
        client = Client.new(cfg)

        # Initial data fetch (fail fast if no auth / network)
        sessions = [] of Models::Session
        begin
          sessions = API::Sessions.list_all(client, 400)
        rescue ex : Client::APIError | Socket::Error | IO::Error
          STDERR.puts "error: failed to load sessions: #{ex.message}"
          return 1
        end

        state = DashState.new(client, sessions, poll_interval)
        state.run_tui
        0
      end

      # Holds mutable UI + data state for the dashboard lifetime.
      private class DashState
        getter client : Client
        getter sessions : Array(Models::Session)
        getter activities : Hash(String, Array(Models::Activity))
        getter seen : Hash(String, Set(String))
        # We track selection by stable ID (not index) so refreshes + filters don't jump highlight.
        property selected_id : String? = nil
        property list_offset : Int32 = 0
        property log_scroll : Int32 = 0
        property? follow : Bool = true
        property filter : String = ""
        property last_error : String? = nil
        property last_refresh : Time = Time.utc
        property? list_focus : Bool = true
        property input_mode : Symbol = :normal # :normal, :filter, :message
        property selected_index : Int32 = 0
        property input_buffer : String = ""
        property status_msg : String? = nil
        property status_msg_until : Time? = nil

        @poll_interval : Int32
        @running = true
        @orig_stty : String? = nil
        @term_rows : Int32 = 24
        @term_cols : Int32 = 80
        @last_sessions_poll : Time = Time.utc - 1.minute
        @last_acts_poll : Time = Time.utc - 1.minute
        @acts_poll_interval = 1.5.seconds
        @sessions_poll_interval = 2.5.seconds

        def initialize(@client, initial_sessions : Array(Models::Session), @poll_interval)
          @sessions = initial_sessions
          @activities = {} of String => Array(Models::Activity)
          @seen = {} of String => Set(String)
          @sessions_poll_interval = @poll_interval.seconds
          update_term_size
          unless initial_sessions.empty?
            @selected_index = 0
            if s = initial_sessions.first?
              @selected_id = s.id || s.short_id
            end
          end
        end

        def run_tui
          setup_terminal
          # Prime activities for initially selected (if any)
          refresh_activities_for_current(force: true)
          render

          key_ch = Channel(String).new(8)
          tick_ch = Channel(Nil).new(1)

          # Input fiber (raw reads)
          spawn do
            loop do
              break unless @running
              begin
                k = read_key
                key_ch.send(k) if k
              rescue
                # ignore transient read errors
              end
            end
          end

          # Ticker fiber
          spawn do
            loop do
              break unless @running
              sleep 0.25.seconds
              tick_ch.send(nil) rescue break
            end
          end

          # Main event loop
          last_tick = Time.instant
          loop do
            break unless @running

            select
            when key = key_ch.receive?
              if key
                if handle_key(key)
                  render
                end
              end
            when tick_ch.receive?
              now = Time.instant
              if (now - last_tick) >= 200.milliseconds
                last_tick = now
                if poll_if_needed
                  render
                elsif @status_msg && @status_msg_until && Time.utc > @status_msg_until.not_nil!
                  @status_msg = nil
                  @status_msg_until = nil
                  render
                end
              end
            else
              # Should not reach; small sleep to avoid busy
              sleep 50.milliseconds
            end
          end
        ensure
          restore_terminal
          if msg = @last_error
            STDERR.puts "last dashboard error: #{msg}"
          end
        end

        private def setup_terminal
          # Save original stty state
          begin
            @orig_stty = `stty -g`.strip
          rescue
            @orig_stty = nil
          end

          # Raw mode, no echo, no signals for ^C (we handle manually)
          system("stty raw -echo -icanon min 1 time 0 2>/dev/null || true")

          # Alternate screen buffer + hide cursor
          STDOUT.print "\e[?1049h\e[?25l"
          STDOUT.flush

          # Install signal handlers for graceful exit
          Signal::INT.trap { stop }
          Signal::TERM.trap { stop }
          # WINCH for resize
          Signal::WINCH.trap do
            update_term_size
            render
          end

          at_exit { restore_terminal }
        end

        private def restore_terminal
          return if @orig_stty.nil? && !@running # already done?

          # Show cursor + leave alt screen
          STDOUT.print "\e[?25h\e[?1049l"
          STDOUT.flush

          if stty = @orig_stty
            system("stty #{stty} 2>/dev/null || stty sane 2>/dev/null || true")
          else
            system("stty sane 2>/dev/null || true")
          end
          @running = false
        end

        private def stop
          @running = false
          # Force a final render attempt? No, just exit loop via channel or flag
        end

        private def update_term_size
          begin
            mem = IO::Memory.new
            if Process.run("stty", ["size"], output: mem, error: Process::Redirect::Close).success?
              parts = mem.to_s.strip.split(/\s+/)
              if parts.size >= 2
                @term_rows = parts[0].to_i.clamp(10, 200)
                @term_cols = parts[1].to_i.clamp(20, 400)
                return
              end
            end
          rescue
          end
          @term_rows = 24
          @term_cols = 80
        end

        # Robust single key (or escape sequence) reader. Returns the raw seq string.
        private def read_key : String?
          ch = STDIN.read_char
          return nil unless ch
          return ch.to_s if ch != '\e'

          seq = "\e"
          # Read a small burst for known CSI / SS3 sequences. Non-blocking intent via quick reads.
          4.times do
            begin
              # After raw mode, next chars arrive promptly for arrows etc.
              # Use a tiny sleep only if needed; in practice bytes are already buffered.
              c2 = STDIN.read_char
              break unless c2
              seq += c2
              # Common terminators
              break if c2 == '~' || (c2.ascii_letter? && seq.size > 1)
            rescue IO::TimeoutError
              break
            rescue
              break
            end
          end
          seq
        end

        private def handle_key(seq : String) : Bool
          # Global quit
          if seq == "\u0003" || seq == "q" || seq == "Q" # Ctrl-C or q
            stop
            return false
          end

          # Input modes take precedence
          case @input_mode
          when :filter
            return handle_filter_input(seq)
          when :message
            return handle_message_input(seq)
          end

          # Normal mode
          case seq
          when "\e" # ESC clears filter or status
            if !@filter.empty?
              @filter = ""
              @list_offset = 0
              clamp_selection
              true
            elsif @status_msg
              @status_msg = nil
              @status_msg_until = nil
              true
            else
              false
            end
          when "\r", "\n", "\e[13~" # Enter
            # Focus log pane or noop (logs are live)
            @list_focus = false
            true
          when "\t" # Tab: toggle focus
            @list_focus = !@list_focus
            true
          when "\e[A", "\eOA", "k", "K" # Up
            if @list_focus
              move_selection(-1)
            else
              scroll_log(-1)
            end
            true
          when "\e[B", "\eOB", "j", "J" # Down
            if @list_focus
              move_selection(+1)
            else
              scroll_log(+1)
            end
            true
          when "\e[5~", "b" # PageUp
            if @list_focus
              move_selection(-visible_list_rows)
            else
              scroll_log(-visible_log_rows)
            end
            true
          when "\e[6~", " " # PageDown or space (when not in list nav conflict)
            if @list_focus
              move_selection(+visible_list_rows)
            else
              scroll_log(+visible_log_rows)
            end
            true
          when "g" # top
            if @list_focus
              @selected_index = 0
              @list_offset = 0
              refresh_activities_for_current
            end
            true
          when "G" # bottom
            if @list_focus
              @selected_index = filtered_sessions.size - 1 if filtered_sessions.size > 0
              clamp_selection
              refresh_activities_for_current
            end
            true
          when "r", "R"
            force_refresh_all
            true
          when "a", "A"
            do_approve_selected
            true
          when "m", "M"
            start_message_compose
            true
          when "f", "F"
            # Quick toggle: show only non-terminal
            # We implement via a virtual "active filter" by prefixing special if needed; simpler: cycle a mode
            # For now treat 'f' as clear filter + hint. Real active-only is via state in list render.
            # Better: 'f' toggles showing only active-ish states.
            toggle_active_only
            true
          when "l", "L"
            # Toggle follow (tail) for log pane
            @follow = !@follow
            if @follow
              @log_scroll = 0
            end
            set_status("follow: #{@follow ? "on" : "off"}")
            true
          when "/", "?"
            if seq == "/"
              start_filter_input
            else
              show_help_overlay
            end
            true
          when "h", "H"
            show_help_overlay
            true
          else
            false
          end
        end

        private def handle_filter_input(seq : String) : Bool
          case seq
          when "\r", "\n"
            @input_mode = :normal
            @input_buffer = ""
            true
          when "\e"
            @input_mode = :normal
            @input_buffer = ""
            @filter = ""
            @list_offset = 0
            clamp_selection
            true
          when "\u007F", "\b" # backspace / DEL
            unless @input_buffer.empty?
              @input_buffer = @input_buffer[0...-1]
              @filter = @input_buffer
              @list_offset = 0
              clamp_selection
            end
            true
          else
            if seq.size == 1 && printable?(seq[0])
              @input_buffer += seq
              @filter = @input_buffer
              @list_offset = 0
              clamp_selection
              true
            else
              false
            end
          end
        end

        private def handle_message_input(seq : String) : Bool
          case seq
          when "\r", "\n"
            text = @input_buffer.strip
            @input_mode = :normal
            @input_buffer = ""
            if text.empty?
              set_status("message cancelled (empty)")
              return true
            end
            sid = current_sid
            unless sid
              set_status("no session selected")
              return true
            end
            begin
              API::Sessions.send_message(@client, sid, text)
              set_status("message sent", 3.seconds)
              # Immediately fetch the new activity so it appears
              refresh_activities_for_current(force: true)
            rescue ex : Client::APIError
              set_status("send failed: #{ex.detail[0..80]}", 5.seconds)
            rescue ex
              set_status("send error: #{ex.message}", 5.seconds)
            end
            true
          when "\e"
            @input_mode = :normal
            @input_buffer = ""
            set_status("message cancelled")
            true
          when "\u007F", "\b"
            @input_buffer = @input_buffer[0...-1] unless @input_buffer.empty?
            true
          else
            if seq.size == 1 && printable?(seq[0])
              @input_buffer += seq
              true
            else
              false
            end
          end
        end

        private def printable?(c : Char) : Bool
          c.ascii? && (c >= ' ' && c <= '~' || c.ord >= 0xA0)
        end

        private def start_filter_input
          @input_mode = :filter
          @input_buffer = @filter
          set_status("filter: type to narrow, esc/enter to finish")
        end

        private def start_message_compose
          sid = current_sid
          unless sid
            set_status("select a session first")
            return
          end
          sess = filtered_sessions[@selected_index]?
          if sess && terminal_state?(sess.state)
            set_status("session is in terminal state; message may be ignored")
          end
          @input_mode = :message
          @input_buffer = ""
          set_status("compose message, enter=send, esc=cancel")
        end

        private def do_approve_selected
          sid = current_sid
          unless sid
            set_status("no session selected")
            return
          end
          sess = filtered_sessions[@selected_index]?
          state = sess.try(&.state)
          if state && state != "AWAITING_PLAN_APPROVAL"
            unless state == "AWAITING_PLAN_APPROVAL"
              set_status("state is #{state || "-"} (use --force in shell if needed)")
              return
            end
          end
          begin
            API::Sessions.approve_plan(@client, sid)
            set_status("plan approved ✓", 4.seconds)
            # nudge refresh
            sleep 100.milliseconds
            force_refresh_all
          rescue ex : Client::APIError
            set_status("approve failed: #{ex.detail[0..70]}", 6.seconds)
          rescue ex
            set_status("approve error: #{ex.message}", 6.seconds)
          end
        end

        private def toggle_active_only
          # Simple heuristic filter: if current filter is empty or special, set a pseudo
          # We keep filter as user text; for 'f' we can clear and rely on visual, or prepend a marker.
          # Better UX: 'f' toggles an internal active_only flag and we filter in filtered_sessions.
          # Implement with a flag.
          # For minimal added state, reuse @filter special value when user didn't type.
          # Simpler: always compute filtered, and 'f' just sets @filter to "" and we can have separate.
          # Let's add an instance var lazily via a check on a convention.
          # Actually, extend filter logic: if filter starts with "!", treat as active-only toggle marker.
          if @filter == "!" || @filter == "!active"
            @filter = ""
          else
            @filter = "!active"
          end
          @list_offset = 0
          clamp_selection
          set_status("active-only: #{active_only? ? "on" : "off"}")
        end

        private def active_only? : Bool
          f = @filter
          f == "!" || f == "!active"
        end

        private def visible_list_rows : Int32
          # header 2 lines + footer 2 + sep 1 => rows-5
          (@term_rows - 6).clamp(3, 80)
        end

        private def visible_log_rows : Int32
          visible_list_rows
        end

        private def move_selection(delta : Int32)
          fs = filtered_sessions
          return if fs.empty?
          @selected_index = (@selected_index + delta).clamp(0, fs.size - 1)
          # keep selected in view
          vr = visible_list_rows
          if @selected_index < @list_offset
            @list_offset = @selected_index
          elsif @selected_index >= @list_offset + vr
            @list_offset = @selected_index - vr + 1
          end
          @log_scroll = 0
          @follow = true
          refresh_activities_for_current
        end

        private def clamp_selection
          fs = filtered_sessions
          return if fs.empty?
          @selected_index = @selected_index.clamp(0, fs.size - 1)
          vr = visible_list_rows
          if @selected_index < @list_offset
            @list_offset = @selected_index
          elsif @selected_index >= @list_offset + vr
            @list_offset = @selected_index - vr + 1
          end
        end

        private def scroll_log(delta : Int32)
          @follow = false
          @log_scroll = (@log_scroll + delta).clamp(0, 10_000)
        end

        private def filtered_sessions : Array(Models::Session)
          base = @sessions
          f = @filter.strip.downcase
          active_only = active_only?
          return base if f.empty? && !active_only

          base.select do |s|
            if active_only && terminal_state?(s.state)
              next false
            end
            next true if f.empty? || f == "!" || f == "!active"

            text = "#{s.id} #{s.title} #{s.prompt} #{s.state} #{s.repo_display}".downcase
            text.includes?(f)
          end
        end

        private def terminal_state?(state : String?) : Bool
          return false unless state
          %w(COMPLETED FAILED CANCELLED).includes?(state)
        end

        private def current_sid : String?
          fs = filtered_sessions
          return nil if fs.empty?
          s = fs[@selected_index]?
          s.try(&.id) || s.try(&.short_id)
        end

        private def force_refresh_all
          @sessions = API::Sessions.list_all(@client, 400)
          @last_sessions_poll = Time.utc
          @last_refresh = Time.utc
          clamp_selection
          refresh_activities_for_current(force: true)
          set_status("refreshed")
        rescue ex : Client::APIError | Socket::Error | IO::Error
          @last_error = ex.message
          set_status("refresh error: #{ex.message.to_s[0..60]}", 5.seconds)
        end

        private def poll_if_needed : Bool
          changed = false
          now = Time.utc

          if now - @last_sessions_poll >= @sessions_poll_interval
            begin
              fresh = API::Sessions.list_all(@client, 400)
              # naive replace; in future we could merge by id to preserve selection better
              @sessions = fresh
              @last_sessions_poll = now
              @last_refresh = now
              clamp_selection
              changed = true
            rescue ex : Client::APIError | Socket::Error | IO::Error
              @last_error = ex.message
            end
          end

          if now - @last_acts_poll >= @acts_poll_interval
            if refresh_activities_for_current
              changed = true
            end
            @last_acts_poll = now
          end

          changed
        end

        # Returns true if new activities were appended for the selected session.
        private def refresh_activities_for_current(force : Bool = false) : Bool
          sid = current_sid
          return false unless sid

          begin
            all = API::Activities.list_all(@client, sid)
            seen_set = @seen[sid] ||= Set(String).new
            new_ones = [] of Models::Activity
            all.each do |a|
              key = activity_key(a)
              unless seen_set.includes?(key)
                seen_set << key
                new_ones << a
              end
            end

            if !new_ones.empty? || force
              base = @activities[sid] ||= [] of Models::Activity
              base.concat(new_ones)
              # Bound memory: keep last ~300 per session
              if base.size > 300
                drop = base.size - 300
                base.shift(drop)
              end
              if @follow
                @log_scroll = 0
              end
              @last_acts_poll = Time.utc
              return true
            end
          rescue ex : Client::APIError | Socket::Error | IO::Error
            @last_error = ex.message
          end
          false
        end

        private def activity_key(a : Models::Activity) : String
          a.id || "#{a.createTime}/#{a.event_type}"
        end

        private def set_status(msg : String, duration : Time::Span = 2.seconds)
          @status_msg = msg
          @status_msg_until = Time.utc + duration
        end

        private def show_help_overlay
          # Simple: set a transient multi-line status; on next render we draw a box if in this state.
          # For simplicity we just print a one-shot banner by mutating a flag for one render.
          @status_msg = "HELP: ↑/k j/↓ nav  enter/tab focus  a approve  m msg  / filter  f active-only  r refresh  l tail  g/G top/bot  q quit  esc clear"
          @status_msg_until = Time.utc + 6.seconds
        end

        # ==================== RENDER ====================

        private def render
          # Full redraw
          STDOUT.print "\e[H\e[2J" # home + clear (keeps alt screen)
          STDOUT.flush

          rows = @term_rows
          cols = @term_cols

          list_w = (cols * 0.42).to_i.clamp(28, 72)
          log_w = cols - list_w - 1
          header_h = 2
          footer_h = 2

          main_h = (rows - header_h - footer_h).clamp(5, 200)

          # Header
          draw_header(cols)

          # Separator under header
          STDOUT.print "─" * cols
          STDOUT.puts

          # Two panes side by side for main_h lines (row-by-row interleaving for real columns)
          fs = filtered_sessions
          list_lines = build_list_lines(fs, list_w, main_h)
          log_lines  = build_log_lines(fs, log_w, main_h)

          (0...main_h).each do |i|
            STDOUT.print list_lines[i]
            STDOUT.print "│"
            STDOUT.puts log_lines[i]
          end

          # Footer separator (reset any reverse video from last highlighted row)
          STDOUT.print "\e[0m"
          STDOUT.print "─" * cols
          STDOUT.puts

          draw_footer(cols)

          # Input line (if in compose/filter)
          if @input_mode != :normal
            prompt = @input_mode == :filter ? "filter> " : "msg> "
            line = prompt + @input_buffer
            # truncate to fit
            max = cols - 1
            if Output::Colors.display_width(line) > max
              line = Output::Colors.truncate_display(line, max)
            end
            STDOUT.print "\r\e[K#{line}"
          end

          STDOUT.flush
        end

        private def draw_header(cols : Int32)
          title = "cjules dash"
          acct = client.config.active_alias || "default"
          if ENV["JULES_ACCOUNT"]?
            acct = "#{acct} (env)"
          end
          right = "account: #{acct}  •  #{Time.utc.to_s("%H:%M:%S")}  •  r=refresh"
          left = title

          # Build one line
          line = left
          pad = cols - Output::Colors.display_width(left) - Output::Colors.display_width(right)
          pad = 1 if pad < 1
          line += " " * pad + right
          STDOUT.puts Output::Colors.bold(line[0, cols])

          # Second header line: counts + last error hint
          fs = filtered_sessions
          active = @sessions.count { |s| !terminal_state?(s.state) }
          cnt = "sessions: #{fs.size}/#{@sessions.size} (#{active} active)"
          err = @last_error ? Output::Colors.red(" err") : ""
          st = @status_msg ? "  #{Output::Colors.yellow(@status_msg.not_nil!)}" : ""
          line2 = cnt + err + st
          if Output::Colors.display_width(line2) > cols
            line2 = Output::Colors.truncate_display(line2, cols)
          end
          STDOUT.puts line2
        end

        private def build_list_lines(fs : Array(Models::Session), width : Int32, height : Int32) : Array(String)
          lines = [] of String
          vr = height
          start_i = @list_offset.clamp(0, [fs.size - 1, 0].max)

          (0...vr).each do |row|
            i = start_i + row
            s = (i < fs.size) ? fs[i] : nil

            prefix = (i == @selected_index && @list_focus) ? "▶ " : "  "
            if s
              sid = (s.short_id || "?")[0..11]
              st = Output::Colors.state(s.state || "-")
              repo = Output::Colors.truncate_display(s.repo_display, 18)
              title = (s.title || s.prompt || "").gsub(/\s+/, " ")
              title = Output::Colors.truncate_display(title, width - 2 - 14 - 20 - 3) # rough budget

              age = Output::Format.age(s.createTime)
              row_str = "#{prefix}#{sid}  #{st.ljust(18)}  #{repo}  #{title}  #{age}"
            else
              row_str = " " * width
            end

            # pad/truncate to width (preserve ANSI for highlight)
            disp_w = Output::Colors.display_width(row_str)
            if disp_w > width
              row_str = Output::Colors.truncate_display(row_str, width)
            elsif disp_w < width
              row_str += " " * (width - disp_w)
            end

            if i == @selected_index && @list_focus
              # reverse video for selected (reset at end of this cell)
              row_str = "\e[7m#{row_str}\e[0m"
            end

            lines << row_str
          end
          lines
        end

        private def build_log_lines(fs : Array(Models::Session), width : Int32, height : Int32) : Array(String)
          lines = [] of String
          sid = current_sid
          acts = sid ? (@activities[sid] || [] of Models::Activity) : [] of Models::Activity

          # First line of the log column acts as a mini title bar for the selected session
          log_title = if sid
                        s = fs[@selected_index]?
                        " #{s.try(&.short_id) || sid}  [#{Output::Colors.state(s.try(&.state) || "-")}]  (#{acts.size})"
                      else
                        " (no selection)"
                      end
          log_title = Output::Colors.truncate_display(log_title, width)
          disp_w = Output::Colors.display_width(log_title)
          if disp_w < width
            log_title += " " * (width - disp_w)
          end
          lines << log_title

          if acts.empty?
            (1...height).each { lines << (" " * width) }
            return lines
          end

          # Determine visible slice (reserve 1 line for the title above)
          total = acts.size
          view_h = height - 1

          visible =
            if @follow || @log_scroll <= 0
              acts.last(view_h)
            else
              # scroll from bottom: offset lines from end
              end_idx = total - @log_scroll
              end_idx = view_h if end_idx < view_h
              start_idx = [end_idx - view_h, 0].max
              acts[start_idx...end_idx] || [] of Models::Activity
            end

          visible.each do |a|
            line = format_activity_line(a, width - 1)
            # pad to width
            dw = Output::Colors.display_width(line)
            if dw > width
              line = Output::Colors.truncate_display(line, width)
            elsif dw < width
              line += " " * (width - dw)
            end
            lines << line
          end

          # Fill remaining lines so we always return exactly `height` lines
          while lines.size < height
            lines << (" " * width)
          end

          lines
        end

        private def format_activity_line(a : Models::Activity, max_width : Int32) : String
          ts = if t = a.createTime
                 begin
                   Time.parse_rfc3339(t).to_local.to_s("%H:%M:%S")
                 rescue
                   "??:??:??"
                 end
               else
                 "??:??:??"
               end
          kind = a.event_type[0..18].ljust(18)
          body = event_body_compact(a)
          body = a.description || "" if body.empty?
          first = body.lines.first? || body
          line = "#{Output::Colors.gray(ts)} #{kind} #{first.chomp}"
          Output::Colors.truncate_display(line, max_width)
        end

        private def event_body_compact(a : Models::Activity) : String
          if pg = a.planGenerated
            if plan = pg.plan
              steps = plan.steps || [] of Models::PlanStep
              return "plan: #{steps.size} step(s)"
            end
            return "plan generated"
          end
          if pa = a.planApproved
            return "plan approved (#{pa.planId || "?"})"
          end
          if um = a.userMessaged
            msg = um.userMessage || ""
            return "user> #{msg[0..80]}"
          end
          if am = a.agentMessaged
            msg = am.agentMessage || ""
            return "agent> #{msg[0..80]}"
          end
          if pu = a.progressUpdated
            t = pu.title || ""
            d = pu.description || ""
            return d.empty? ? t : "#{t} — #{d}" unless t.empty? && d.empty?
          end
          if sf = a.sessionFailed
            return Output::Colors.red("failed: #{sf.reason || "?"}")
          end
          return Output::Colors.green("completed") if a.sessionCompleted
          a.description || ""
        end

        private def draw_footer(cols : Int32)
          # Key hints, condensed
          hints = "q quit • ↑/k ↓/j nav • a approve • m msg • / filter • f active • r refresh • l tail • ? help"
          if @list_focus
            hints += "  [LIST]"
          else
            hints += "  [LOGS]"
          end
          hints = Output::Colors.truncate_display(hints, cols)
          STDOUT.print hints
          STDOUT.puts
          # Small second footer line with last refresh
          age = Util::Duration.humanize(Time.utc - @last_refresh) rescue "-"
          line = "last refresh: #{age} ago  •  poll ~#{@poll_interval}s  •  #{current_sid || "-"}"
          STDOUT.puts Output::Colors.dim(Output::Colors.truncate_display(line, cols))
        end
      end

      # Small wrapper to expose config for acct display (client has no public getter in original).
      # We reach via a tiny extension; in practice we read from the cfg we used.
      # To avoid changing client, we pass through DashState using the same cfg.
    end
  end
end

# Backfill a tiny accessor so header can show active account without changing Client.
class Cjules::Client
  def config : Cjules::Config
    @config
  end
end
