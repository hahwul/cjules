module Cjules
  # Base error for cjules application errors.
  class Error < Exception
  end

  # Raised for invalid user input / CLI usage (maps to exit code 2).
  class UsageError < Error
  end

  # Raised when required configuration (e.g. API key) is missing (maps to exit 1).
  class ConfigError < Error
  end
end
