require "json"
require "yaml"
require "./colors"
require "./table"
require "../models"
require "../util"

module Cjules
  module Output
    module Format
      extend self

      # Sessions ----------------------------------------------------

      def sessions(list : Array(Models::Session), format : String, io : IO = STDOUT)
        case format
        when "json"
          io.puts list.to_json
        when "jsonl"
          list.each { |s| io.puts s.to_json }
        when "yaml"
          io.puts list.to_yaml
        when "table", "text"
          render_session_table(list, io)
        else
          STDERR.puts "error: unknown output format: #{format}"
          exit 2
        end
      end

      def session(s : Models::Session, format : String, io : IO = STDOUT)
        case format
        when "json"
          io.puts s.to_json
        when "yaml"
          io.puts s.to_yaml
        else
          render_session_detail(s, io)
        end
      end

      def sources(list : Array(Models::Source), format : String, io : IO = STDOUT)
        case format
        when "json"  then io.puts list.to_json
        when "jsonl" then list.each { |s| io.puts s.to_json }
        when "yaml"  then io.puts list.to_yaml
        when "table", "text"
          t = Table.new(["ID", "REPO", "DEFAULT", "PRIVATE"])
          list.each do |s|
            gh = s.githubRepo
            repo = if gh && gh.owner && gh.repo
                     "#{gh.owner}/#{gh.repo}"
                   else
                     "-"
                   end
            default = gh.try(&.defaultBranch).try(&.displayName) || "-"
            priv = gh.try(&.isPrivate) ? "yes" : "no"
            t.add_row([s.id || "-", repo, default, priv])
          end
          t.render(io)
        else
          STDERR.puts "error: unknown output format: #{format}"
          exit 2
        end
      end

      def source(s : Models::Source, format : String, io : IO = STDOUT)
        case format
        when "json" then io.puts s.to_json
        when "yaml" then io.puts s.to_yaml
        else
          gh = s.githubRepo
          io.puts "#{Colors.bold("ID")}     : #{s.id}"
          io.puts "#{Colors.bold("Name")}   : #{s.name}"
          if gh
            io.puts "#{Colors.bold("Repo")}   : #{gh.owner}/#{gh.repo}"
            io.puts "#{Colors.bold("Default")}: #{gh.defaultBranch.try(&.displayName)}"
            io.puts "#{Colors.bold("Private")}: #{gh.isPrivate}"
            if branches = gh.branches
              io.puts "#{Colors.bold("Branches")}:"
              branches.each { |b| io.puts "  - #{b.displayName}" }
            end
          end
        end
      end

      private def render_session_table(list : Array(Models::Session), io : IO)
        t = Table.new(["ID", "STATE", "REPO", "TITLE", "AGE"])
        list.each do |s|
          title = (s.title || s.prompt || "").gsub(/\s+/, " ")
          title = title[0..60] if title.size > 60
          t.add_row([
            s.short_id,
            Colors.state(s.state || "-"),
            s.repo_display,
            title,
            age(s.createTime),
          ])
        end
        t.render(io)
      end

      private def render_session_detail(s : Models::Session, io : IO)
        io.puts "#{Colors.bold("ID")}      : #{s.short_id}"
        io.puts "#{Colors.bold("Name")}    : #{s.name}"
        io.puts "#{Colors.bold("State")}   : #{Colors.state(s.state || "-")}"
        io.puts "#{Colors.bold("Title")}   : #{s.title}"
        io.puts "#{Colors.bold("Repo")}    : #{s.repo_display}"
        io.puts "#{Colors.bold("Branch")}  : #{s.sourceContext.try(&.githubRepoContext).try(&.startingBranch)}"
        io.puts "#{Colors.bold("URL")}     : #{s.url}"
        io.puts "#{Colors.bold("Created")} : #{s.createTime}"
        io.puts "#{Colors.bold("Updated")} : #{s.updateTime}"
        if s.requirePlanApproval
          io.puts "#{Colors.bold("Approval")}: required"
        end
        if mode = s.automationMode
          io.puts "#{Colors.bold("Auto")}    : #{mode}"
        end
        io.puts ""
        io.puts Colors.bold("Prompt:")
        io.puts(s.prompt || "(empty)")
        if outputs = s.outputs
          outputs.each do |o|
            if pr = o.pullRequest
              io.puts ""
              io.puts Colors.bold("Pull Request:")
              io.puts "  #{pr.title}"
              io.puts "  #{pr.url}"
            end
          end
        end
      end

      def age(t : String?) : String
        return "-" unless t
        begin
          time = Time.parse_rfc3339(t)
          Util::Duration.humanize(Time.utc - time)
        rescue
          "-"
        end
      end
    end
  end
end
