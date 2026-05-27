require "spec"
require "file_utils"
require "../src/cjules"

# WebMock is vendored under lib/webmock (committed in tree) to enable hermetic
# HTTP tests for Client, API, and command layers without a production dependency.
require "../lib/webmock/src/webmock"

def require_webmock!
  # always available in this project
end

# Run a block with WebMock enabled (real net disabled, stubs required).
# Automatically resets after the block. Skips/pends if webmock not vendored.
def with_webmock(&)
  require_webmock!
  WebMock.wrap do
    yield
  end
end

# Stub a successful Jules API response for common paths.
# Usage: stub_jules(:get, "/v1alpha/sessions", body: json, status: 200)
def stub_jules(method : Symbol, path : String, body : String = "", status : Int32 = 200, headers : HTTP::Headers? = nil)
  require_webmock!
  url = "https://jules.googleapis.com#{path}"
  stub = WebMock.stub(method, url)
  stub.to_return(status: status, body: body, headers: headers || HTTP::Headers{"Content-Type" => "application/json"})
  stub
end

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
