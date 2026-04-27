require "spec"
require "file_utils"
require "../src/cjules"

# Run a block with a fresh, isolated $HOME and cjules-related env vars cleared.
# Restores the prior environment and removes the temp directory afterward.
def with_isolated_home(&)
  tmp = File.tempname("cjules-spec")
  Dir.mkdir_p(tmp)
  keys = %w(HOME JULES_ACCOUNT JULES_API_KEY JULES_API_BASE)
  saved = keys.map { |k| {k, ENV[k]?} }.to_h
  keys.each { |k| ENV.delete(k) }
  ENV["HOME"] = tmp
  begin
    yield tmp
  ensure
    saved.each do |k, v|
      v ? (ENV[k] = v) : ENV.delete(k)
    end
    FileUtils.rm_rf(tmp)
  end
end
