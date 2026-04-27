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
          data = YAML.parse(File.read(file))
          if base = nonempty(data["api_base"]?)
            cfg.api_base = base
          end
          cfg.default_repo = nonempty(data["default_repo"]?)
          cfg.default_branch = nonempty(data["default_branch"]?)
          cfg.current = nonempty(data["current"]?)

          if accounts = data["accounts"]?
            if h = accounts.as_h?
              h.each do |k, v|
                key = k.as_s? || next
                val = v.as_s? || next
                next if key.empty? || val.empty?
                cfg.accounts[key] = val
              end
            end
          end

          # Backward-compat: legacy single api_key.
          if legacy = nonempty(data["api_key"]?)
            cfg.accounts["default"] = legacy unless cfg.accounts.has_key?("default")
            cfg.current ||= "default"
          end
        rescue YAML::ParseException
          # treat corrupt config as empty
        end
      end

      if b = ENV["JULES_API_BASE"]?
        cfg.api_base = b unless b.empty?
      end
      cfg
    end

    private def self.nonempty(node : YAML::Any?) : String?
      return nil unless node
      s = node.as_s?
      return nil if s.nil? || s.empty?
      s
    end

    def save
      file = self.class.path
      Dir.mkdir_p(File.dirname(file))
      File.open(file, "w", perm: 0o600) do |io|
        YAML.build(io) do |y|
          y.mapping do
            y.scalar "api_base"
            y.scalar @api_base
            if v = @default_repo
              y.scalar "default_repo"
              y.scalar v
            end
            if v = @default_branch
              y.scalar "default_branch"
              y.scalar v
            end
            if v = @current
              y.scalar "current"
              y.scalar v
            end
            y.scalar "accounts"
            y.mapping do
              @accounts.each do |k, val|
                y.scalar k
                y.scalar val
              end
            end
          end
        end
      end
      # Tighten perms on existing files too.
      File.chmod(file, 0o600)
    end

    def add_account(alias_name : String, key : String) : Nil
      @accounts[alias_name] = key
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

    def has_account?(alias_name : String) : Bool
      @accounts.has_key?(alias_name)
    end

    def require_api_key! : String
      key = api_key
      if key.nil? || key.empty?
        STDERR.puts "error: no Jules API key configured."
        env_account = ENV["JULES_ACCOUNT"]?
        if env_account && !env_account.empty? && !@accounts.has_key?(env_account)
          STDERR.puts "  JULES_ACCOUNT=#{env_account} is set, but no such account is saved."
          STDERR.puts "  saved accounts: #{@accounts.keys.join(", ")}" unless @accounts.empty?
          STDERR.puts "  unset the env var or run: cjules login --alias #{env_account}"
        elsif @accounts.empty?
          STDERR.puts "  run: cjules login --alias <name>"
          STDERR.puts "  or set JULES_API_KEY in the environment"
        else
          STDERR.puts "  saved accounts: #{@accounts.keys.join(", ")}"
          STDERR.puts "  run: cjules accounts use <alias>"
          STDERR.puts "  or set JULES_ACCOUNT=<alias>"
        end
        exit 1
      end
      key
    end
  end
end
