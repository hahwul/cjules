require "yaml"

module Cjules
  class Config
    DEFAULT_BASE = "https://jules.googleapis.com"
    ALIAS_RE     = /\A[A-Za-z0-9._-]+\z/

    def self.path : String
      File.expand_path("~/.config/cjules/config.yml", home: true)
    end

    def self.valid_alias?(name : String) : Bool
      !name.empty? && name.size <= 64 && !!ALIAS_RE.match(name)
    end

    def self.mask(key : String) : String
      return "(empty)" if key.empty?
      return "***" if key.size <= 4
      "***" + key[-4..]
    end

    def self.format_account_line(alias_name : String, key : String, active : Bool) : String
      marker = active ? "* " : "  "
      "#{marker}#{alias_name.ljust(20)} #{mask(key)}"
    end

    property api_base : String
    property default_repo : String?
    property default_branch : String?
    property current : String?
    property accounts : Hash(String, String)

    def initialize(@api_base : String = DEFAULT_BASE,
                   @default_repo : String? = nil,
                   @default_branch : String? = nil,
                   @current : String? = nil,
                   @accounts : Hash(String, String) = {} of String => String)
    end

    # Active key, considering env override > current account.
    def api_key : String?
      if k = ENV["JULES_API_KEY"]?
        return k unless k.empty?
      end
      if a = active_alias
        return @accounts[a]?
      end
      nil
    end

    # Whichever alias is "active" right now (env wins over disk).
    def active_alias : String?
      if v = ENV["JULES_ACCOUNT"]?
        return v unless v.empty?
      end
      @current
    end

    def env_account_override? : Bool
      v = ENV["JULES_ACCOUNT"]?
      !!(v && !v.empty?)
    end

    def self.load : Config
      cfg = new
      file = path
      if File.exists?(file)
        begin
          # Read the node tree rather than YAML.parse: older versions wrote
          # values unquoted, and the core schema would turn an alias like
          # `2024`, `yes` or `0755` into a number/bool and lose its spelling.
          top = {} of String => YAML::Nodes::Node
          pairs(YAML::Nodes.parse(File.read(file)).nodes.first?).each do |k, v|
            if name = text(k)
              top[name] = v
            end
          end

          if base = text(top["api_base"]?)
            cfg.api_base = base
          end
          cfg.default_repo = text(top["default_repo"]?)
          cfg.default_branch = text(top["default_branch"]?)
          cfg.current = text(top["current"]?)

          pairs(top["accounts"]?).each do |k, v|
            key = text(k) || next
            val = text(v) || next
            cfg.accounts[key] = val
          end

          # Backward-compat: legacy single api_key.
          if legacy = text(top["api_key"]?)
            cfg.accounts["default"] = legacy unless cfg.accounts.has_key?("default")
            cfg.current ||= "default"
          end
        rescue Exception
          # treat corrupt or unreadable config as empty
        end
      end

      if b = ENV["JULES_API_BASE"]?
        cfg.api_base = b unless b.empty?
      end
      cfg
    end

    private def self.pairs(node : YAML::Nodes::Node?) : Array({YAML::Nodes::Node, YAML::Nodes::Node})
      result = [] of {YAML::Nodes::Node, YAML::Nodes::Node}
      return result unless node.is_a?(YAML::Nodes::Mapping)
      node.nodes.each_slice(2) { |kv| result << {kv[0], kv[1]} if kv.size == 2 }
      result
    end

    # A scalar's text exactly as written; nil for blanks, a plain null
    # (`~`, `null`) or a non-scalar.
    private def self.text(node : YAML::Nodes::Node?) : String?
      return unless node.is_a?(YAML::Nodes::Scalar)
      return if node.style.plain? && %w[~ null Null NULL].includes?(node.value)
      node.value.presence
    end

    def save
      file = self.class.path
      begin
        Dir.mkdir_p(File.dirname(file))
        data = {"api_base" => @api_base} of String => String | Hash(String, String)
        @default_repo.try { |v| data["default_repo"] = v }
        @default_branch.try { |v| data["default_branch"] = v }
        @current.try { |v| data["current"] = v }
        data["accounts"] = @accounts
        # Hash#to_yaml quotes strings YAML would read as numbers/bools/null.
        File.open(file, "w", perm: 0o600) { |io| data.to_yaml(io) }
        # Tighten perms on existing files too.
        File.chmod(file, 0o600)
      rescue ex : Exception
        STDERR.puts "warning: failed to save config to #{file}: #{ex.message}"
      end
    end

    # Find an existing alias holding this exact key (excluding self).
    def alias_for_key(key : String, except : String? = nil) : String?
      @accounts.each do |a, k|
        next if a == except
        return a if k == key
      end
      nil
    end

    def remove_account(alias_name : String) : Bool
      removed = @accounts.delete(alias_name)
      @current = nil if @current == alias_name
      !removed.nil?
    end

    def require_api_key! : String
      key = api_key
      if key.nil? || key.empty?
        msg = String.build do |io|
          io << "no Jules API key configured."
          env_account = ENV["JULES_ACCOUNT"]?
          if env_account && !env_account.empty? && !@accounts.has_key?(env_account)
            io << "\n  JULES_ACCOUNT=#{env_account} is set, but no such account is saved."
            io << "\n  saved accounts: #{@accounts.keys.join(", ")}" unless @accounts.empty?
            io << "\n  unset the env var or run: cjules login --alias #{env_account}"
          elsif @accounts.empty?
            io << "\n  run: cjules login --alias <name>"
            io << "\n  or set JULES_API_KEY in the environment"
          else
            io << "\n  saved accounts: #{@accounts.keys.join(", ")}"
            io << "\n  run: cjules accounts use <alias>"
            io << "\n  or set JULES_ACCOUNT=<alias>"
          end
        end
        raise Cjules::ConfigError.new(msg)
      end
      key
    end
  end
end
