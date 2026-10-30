require "option_parser"
require "../help"
require "../config"
require "../client"
require "../api"
require "../util"
require "../output/colors"
require "./retry"

module Cjules
  module Commands
    module Troubleshoot
      extend self

      record Finding, summary : String, fix : String

      # ponytail: findings are capped so the suggested note stays readable;
      # the full log is still available via `cjules logs <ID> --bash`.
      MAX_FINDINGS = 5

      def run(args : Array(String)) : Int32
        yes = false
        dry_run = false
        positional = [] of String
        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules troubleshoot <ID> [-y] [-n]"
          p.on("-y", "--yes", "Retry with the suggested note without asking") { yes = true }
          p.on("-n", "--dry-run", "Only print the diagnosis and suggestion") { dry_run = true }
          p.on("-h", "--help", "Show help") { Help.show_help(p); exit 0 }
          p.unknown_args { |before, _| positional = before }
        end
        parser.parse(args.dup)

        sid = Util::ID.require!(positional)

        cfg = Config.load
        client = Client.new(cfg)
        session = API::Sessions.get(client, sid)
        if session.state != "FAILED"
          STDERR.puts "warning: session #{sid} is #{session.state || "UNKNOWN"}, not FAILED; diagnosis only"
          dry_run = true
        end
        findings = diagnose(API::Activities.list_all(client, sid))

        if findings.empty?
          STDERR.puts "no failure diagnostics found for session #{sid}"
          return 1
        end

        note = suggest_note(findings)
        puts "[Diagnostic] Session failed due to:"
        findings.each { |f| puts "  -> #{f.summary}" }
        puts ""
        puts "[Suggestion] Retry with the following fix note:"
        puts "  #{note.inspect}"

        return 0 if dry_run
        unless yes
          unless STDIN.tty?
            STDERR.puts "error: stdin is not a TTY; pass --yes to retry or --dry-run to skip"
            return 2
          end
          STDERR.print "[Y/n]: "
          ans = (STDIN.gets || "").strip.downcase
          return 0 unless ans.empty? || ans == "y" || ans == "yes"
        end

        Retry.run([sid, "--note", note])
      end

      def suggest_note(findings : Array(Finding)) : String
        findings.map(&.fix).join("; ")
      end

      # Collects findings from the latest run of each failing bash command,
      # falling back to the session's failure reason.
      def diagnose(activities : Array(Models::Activity)) : Array(Finding)
        # Keep only the last run per command: a later success means it was fixed.
        # ponytail: keyed on the exact command string, so `crystal spec` passing
        # doesn't clear an earlier `crystal spec spec/a_spec.cr` failure.
        last = {} of String => Models::BashOutput
        activities.each do |a|
          a.artifacts.try &.each_with_index do |art, i|
            if bo = art.bashOutput
              last[bo.command || "#{a.id}-#{i}"] = bo
            end
          end
        end

        findings = [] of Finding
        last.each_value do |bo|
          code = bo.exitCode
          next if code.nil? || code == 0
          found = parse_output(bo.output || "", bo.command || "")
          if found.empty?
            tail = (bo.output || "").gsub(Output::Colors::ANSI_RE, "").lines.map(&.strip).reject(&.empty?).last?
            cmd = bo.command || "command"
            detail = tail ? ": #{tail}" : ""
            found << Finding.new("`#{cmd}` exited #{code}#{detail}", "Fix `#{cmd}` (exit #{code})#{detail}")
          end
          findings.concat(found)
        end

        if findings.empty?
          reason = Retry.failure_reason(activities)
          if reason && !reason.empty?
            findings << Finding.new(reason, "Previous attempt failed: #{reason}. Address the root cause")
          end
        end

        findings.uniq.first(MAX_FINDINGS)
      end

      # Recognizes Crystal compiler errors, missing shards, shards resolver
      # errors and failing `crystal spec` examples.
      def parse_output(output : String, command : String = "") : Array(Finding)
        findings = [] of Finding
        location : String? = nil
        output.gsub(Output::Colors::ANSI_RE, "").each_line do |raw|
          line = raw.strip
          if m = line.match(/^In (\S+?:\d+)(?::\d+)?$/)
            location = m[1]
          elsif m = line.match(/^Error: (.+)$/)
            msg = m[1]
            where = location
            if dep = msg.match(/^can't find file '([^'.\/][^']*)'/)
              findings << Finding.new("#{where ? "#{where}: " : ""}missing dependency '#{dep[1]}'",
                "Add the missing shard '#{dep[1]}' to shard.yml and run `shards install`")
            else
              findings << Finding.new(where ? "#{where}: #{msg}" : msg,
                where ? "Fix #{msg} at #{where}" : "Fix compile error: #{msg}")
            end
            location = nil
          elsif command.includes?("shards") && (m = line.match(/^E: (.+)$/))
            findings << Finding.new("shards: #{m[1]}", "Fix shard dependencies: #{m[1]}")
          elsif m = line.match(/^crystal spec (\S+:\d+) # (.+)$/)
            findings << Finding.new("#{m[1]}: failing spec '#{m[2]}'", "Fix failing spec '#{m[2]}' (#{m[1]})")
          end
        end
        findings.uniq
      end
    end
  end
end
