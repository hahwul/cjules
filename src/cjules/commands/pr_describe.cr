require "option_parser"
require "../help"
require "../config"
require "../client"
require "../api"
require "../util"
require "../unidiff"

module Cjules
  module Commands
    module PRDescribe
      extend self

      def run(args : Array(String)) : Int32
        copy = false
        positional = [] of String

        parser = OptionParser.new do |p|
          p.banner = "Usage: cjules pr-describe <ID> [--copy]"
          p.on("-c", "--copy", "Copy generated PR description to clipboard") { copy = true }
          p.on("-h", "--help", "Show help") { Help.show_help(p); exit 0 }
          p.unknown_args { |before, _| positional = before }
        end
        parser.parse(args.dup)

        sid = Util::ID.require!(positional)

        cfg = Config.load
        client = Client.new(cfg)
        sess = API::Sessions.get(client, sid)
        activities = API::Activities.list_all(client, sid)

        md = format_markdown(sess, activities)
        puts md
        Util::Clipboard.copy_or_warn(md) if copy
        0
      end

      def format_markdown(sess : Models::Session, activities : Array(Models::Activity)) : String
        String.build do |io|
          io << "## Summary\n\n"
          io << summary_text(sess, activities) << "\n"

          changes = collect_changes(activities)
          unless changes.empty?
            io << "\n## Changes\n\n"
            changes.each { |c| io << "- " << c << "\n" }
          end

          if patch = latest_patch(activities)
            if diff = patch.unidiffPatch.try(&.presence)
              stats = Unidiff.file_stats(diff)
              unless stats.empty?
                io << "\n## Files Changed\n\n"
                stats.each do |st|
                  io << "- `" << st.path << "` (+" << st.additions << "/-" << st.deletions << ")\n"
                end
              end
            end
          end

          verifications = collect_verifications(activities)
          unless verifications.empty?
            io << "\n## Verification\n\n"
            verifications.each { |v| io << "- " << v << "\n" }
          end
        end
      end

      def latest_patch(activities : Array(Models::Activity)) : Models::GitPatch?
        activities.reverse_each do |a|
          if arts = a.artifacts
            arts.reverse_each do |art|
              if gp = art.changeSet.try(&.gitPatch)
                return gp
              end
            end
          end
        end
        nil
      end

      def latest_agent_message(activities : Array(Models::Activity)) : String?
        activities.reverse_each do |a|
          if msg = a.agentMessaged.try(&.agentMessage).try(&.strip.presence)
            return msg
          end
        end
        nil
      end

      private def summary_text(sess : Models::Session, activities : Array(Models::Activity)) : String
        if outs = sess.outputs
          outs.each do |o|
            if desc = o.pullRequest.try(&.description).try(&.strip.presence)
              return desc
            end
          end
        end

        if msg = latest_patch(activities).try(&.suggestedCommitMessage).try(&.strip.presence)
          return msg
        end

        if msg = latest_agent_message(activities)
          return msg
        end

        sess.title.try(&.strip.presence) || sess.prompt.try(&.strip.presence) || "Session #{sess.short_id}"
      end

      private def collect_changes(activities : Array(Models::Activity)) : Array(String)
        activities.reverse_each do |a|
          if steps = a.planGenerated.try(&.plan).try(&.steps)
            items = steps.compact_map { |s| format_step(s.title, s.description) }
            return items unless items.empty?
          end
        end

        seen = Set(String).new
        items = [] of String
        activities.each do |a|
          if pu = a.progressUpdated
            if (entry = format_step(pu.title, pu.description)) && seen.add?(entry)
              items << entry
            end
          end
        end
        items
      end

      private def format_step(raw_title : String?, raw_desc : String?) : String?
        title = raw_title.try(&.strip.presence)
        desc = raw_desc.try(&.strip.presence)
        if title && desc
          "**#{title}** — #{desc}"
        else
          title || desc
        end
      end

      private def collect_verifications(activities : Array(Models::Activity)) : Array(String)
        seen = Set(String).new
        items = [] of String
        activities.each do |a|
          if arts = a.artifacts
            arts.each do |art|
              if bo = art.bashOutput
                cmd = bo.command.try(&.strip.presence) || next
                entry = "`#{cmd}` (exit #{bo.exitCode || 0})"
                items << entry if seen.add?(entry)
              end
            end
          end
        end
        items
      end
    end
  end
end
