require "http/client"
require "json"
require "uri"
require "./config"
require "./errors"
require "./models"

module Cjules
  module Notifier
    extend self

    NOTIFY_STATES   = %w[COMPLETED FAILED AWAITING_USER_FEEDBACK]
    TARGETS         = %w[desktop slack discord]
    WEBHOOK_TIMEOUT = 10.seconds

    def parse_targets(raw : Array(String)) : Array(String)
      targets = [] of String
      raw.each do |entry|
        parts = entry.split(',').map(&.strip.downcase)
        if parts.empty? || parts.any?(&.empty?)
          raise UsageError.new("--notify requires a target (#{TARGETS.join(", ")})")
        end
        parts.each do |t|
          unless TARGETS.includes?(t)
            raise UsageError.new("unknown --notify target: #{t} (expected #{TARGETS.join(", ")})")
          end
          targets << t unless targets.includes?(t)
        end
      end
      targets
    end

    def valid_webhook_url?(url : String?) : Bool
      return false if url.nil? || url.empty?
      uri = URI.parse(url)
      scheme = uri.scheme
      host = uri.host
      (scheme == "http" || scheme == "https") && !host.nil? && !host.empty?
    rescue URI::Error
      false
    end

    def validate_config!(targets : Array(String), cfg : Config) : Nil
      if targets.includes?("slack")
        url = cfg.slack_webhook
        if url.nil? || url.empty?
          raise ConfigError.new("slack_webhook is not configured.\n  run: cjules config set slack_webhook <URL>\n  or set JULES_SLACK_WEBHOOK in the environment")
        end
        unless valid_webhook_url?(url)
          raise ConfigError.new("slack_webhook must be a valid http(s) URL (got #{url.inspect})")
        end
      end

      if targets.includes?("discord")
        url = cfg.discord_webhook
        if url.nil? || url.empty?
          raise ConfigError.new("discord_webhook is not configured.\n  run: cjules config set discord_webhook <URL>\n  or set JULES_DISCORD_WEBHOOK in the environment")
        end
        unless valid_webhook_url?(url)
          raise ConfigError.new("discord_webhook must be a valid http(s) URL (got #{url.inspect})")
        end
      end
    end

    def should_notify?(state : String?) : Bool
      !!(state && NOTIFY_STATES.includes?(state))
    end

    def format_message(sess : Models::Session, state : String) : {String, String}
      title = "cjules: #{state}"
      sid = sess.short_id
      label = (sess.title || sess.prompt || "").gsub(/\s+/, " ").strip
      body = if label.empty?
               "Session #{sid}: #{state}"
             else
               "Session #{sid} (#{label[0, 80]}): #{state}"
             end
      {title, body}
    end

    def desktop_command(title : String, body : String, darwin : Bool = {% if flag?(:darwin) %}true{% else %}false{% end %}) : {String, Array(String)}
      if darwin
        {"osascript", [
          "-e", "on run argv",
          "-e", "display notification (item 2 of argv) with title (item 1 of argv)",
          "-e", "end run",
          "--",
          title,
          body,
        ]}
      else
        {"notify-send", ["--", title, body]}
      end
    end

    def notify(targets : Array(String), sess : Models::Session, state : String, cfg : Config) : Nil
      title, body = format_message(sess, state)
      targets.each do |target|
        case target
        when "desktop"
          notify_desktop(title, body)
        when "slack"
          if url = cfg.slack_webhook
            notify_webhook("slack", url, {"text" => "[#{title}] #{body}"}.to_json)
          end
        when "discord"
          if url = cfg.discord_webhook
            notify_webhook("discord", url, {"content" => "[#{title}] #{body}"}.to_json)
          end
        end
      end
    end

    def notify_desktop(title : String, body : String) : Nil
      prog, argv = desktop_command(title, body)
      status = Process.run(prog, argv,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close)
      unless status.success?
        STDERR.puts "warning: desktop notification (#{prog}) exited with status #{status.exit_code}"
      end
    rescue ex : Exception
      STDERR.puts "warning: failed to send desktop notification: #{ex.message}"
    end

    def notify_webhook(name : String, url : String, payload : String) : Nil
      uri = URI.parse(url)
      client = HTTP::Client.new(uri)
      client.connect_timeout = WEBHOOK_TIMEOUT
      client.read_timeout = WEBHOOK_TIMEOUT
      begin
        res = client.post(
          uri.request_target,
          headers: HTTP::Headers{"Content-Type" => "application/json"},
          body: payload,
        )
        if res.status_code >= 400
          STDERR.puts "warning: #{name} webhook returned HTTP #{res.status_code}"
        end
      ensure
        client.close
      end
    rescue ex : Exception
      STDERR.puts "warning: failed to send #{name} notification: #{ex.message}"
    end
  end
end
