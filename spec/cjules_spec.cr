require "./spec_helper"
require "../src/cjules/util"
require "../src/cjules/models"
require "../src/cjules/output/format"
require "../src/cjules/output/colors"
require "../src/cjules/output/table"
require "../src/cjules/config"
require "../src/cjules/commands/new"
require "../src/cjules/template_renderer"
require "file_utils"

describe Cjules::Util::ID do
  it "strips sessions/ prefix" do
    Cjules::Util::ID.normalize("sessions/abc123").should eq("abc123")
  end

  it "strips sources/ prefix" do
    Cjules::Util::ID.normalize("sources/github-foo-bar").should eq("github-foo-bar")
  end

  it "leaves bare ids alone" do
    Cjules::Util::ID.normalize("abc123").should eq("abc123")
  end
end

describe Cjules::Util::Duration do
  it "parses common units" do
    Cjules::Util::Duration.parse("30s").should eq(30.seconds)
    Cjules::Util::Duration.parse("5m").should eq(5.minutes)
    Cjules::Util::Duration.parse("2h").should eq(2.hours)
    Cjules::Util::Duration.parse("7d").should eq(7.days)
    Cjules::Util::Duration.parse("1w").should eq(1.week)
  end

  it "is case insensitive and trims" do
    Cjules::Util::Duration.parse(" 12H ").should eq(12.hours)
  end

  it "returns nil for garbage" do
    Cjules::Util::Duration.parse("nope").should be_nil
    Cjules::Util::Duration.parse("10").should be_nil
  end

  it "humanizes spans" do
    Cjules::Util::Duration.humanize(45.seconds).should eq("45s")
    Cjules::Util::Duration.humanize(3.minutes).should eq("3m")
    Cjules::Util::Duration.humanize(5.hours).should eq("5h")
    Cjules::Util::Duration.humanize(10.days).should eq("10d")
  end
end

describe Cjules::Util::SessionFilter do
  sess = ->(state : String?, source : String?, create : String?, prompt : String?, title : String?) do
    parts = [] of String
    parts << %("state":#{state.to_json}) if state
    parts << %("sourceContext":{"source":#{source.to_json}}) if source
    parts << %("createTime":#{create.to_json}) if create
    parts << %("prompt":#{prompt.to_json}) if prompt
    parts << %("title":#{title.to_json}) if title
    body = parts.empty? ? "" : ",#{parts.join(",")}"
    Cjules::Models::Session.from_json(%({"id":"x"#{body}}))
  end

  it "filters by state" do
    s1 = sess.call("COMPLETED", nil, nil, nil, nil)
    s2 = sess.call("FAILED", nil, nil, nil, nil)
    Cjules::Util::SessionFilter.matches?(s1, state: "COMPLETED").should be_true
    Cjules::Util::SessionFilter.matches?(s2, state: "COMPLETED").should be_false
  end

  it "filters by repo substring against sourceContext.source" do
    s = sess.call(nil, "sources/github/foo/bar", nil, nil, nil)
    Cjules::Util::SessionFilter.matches?(s, repo: "foo/bar").should be_true
    Cjules::Util::SessionFilter.matches?(s, repo: "baz").should be_false
  end

  it "newer_than keeps sessions at or after cutoff and rejects missing/malformed times" do
    now = Time.utc
    fresh = sess.call(nil, nil, (now - 1.minute).to_rfc3339, nil, nil)
    stale = sess.call(nil, nil, (now - 2.hours).to_rfc3339, nil, nil)
    bare = sess.call(nil, nil, nil, nil, nil)
    bad = sess.call(nil, nil, "not-a-time", nil, nil)
    cutoff = now - 1.hour
    Cjules::Util::SessionFilter.matches?(fresh, newer_than: cutoff).should be_true
    Cjules::Util::SessionFilter.matches?(stale, newer_than: cutoff).should be_false
    Cjules::Util::SessionFilter.matches?(bare, newer_than: cutoff).should be_false
    Cjules::Util::SessionFilter.matches?(bad, newer_than: cutoff).should be_false
  end

  it "older_than keeps sessions strictly before cutoff" do
    now = Time.utc
    fresh = sess.call(nil, nil, (now - 1.minute).to_rfc3339, nil, nil)
    stale = sess.call(nil, nil, (now - 2.hours).to_rfc3339, nil, nil)
    cutoff = now - 1.hour
    Cjules::Util::SessionFilter.matches?(fresh, older_than: cutoff).should be_false
    Cjules::Util::SessionFilter.matches?(stale, older_than: cutoff).should be_true
  end

  it "search matches across prompt and title, case-insensitive" do
    s = sess.call(nil, nil, nil, "Build the GIZMO module", "fixup")
    Cjules::Util::SessionFilter.matches?(s, search: "gizmo").should be_true
    Cjules::Util::SessionFilter.matches?(s, search: "FIXUP").should be_true
    Cjules::Util::SessionFilter.matches?(s, search: "absent").should be_false
  end

  it "returns true when no filter is supplied" do
    Cjules::Util::SessionFilter.matches?(sess.call("ANY", nil, nil, nil, nil)).should be_true
  end
end

describe Cjules::Util::Git do
  it "parses https github URL" do
    Cjules::Util::Git.parse_repo("https://github.com/foo/bar.git").should eq("foo/bar")
    Cjules::Util::Git.parse_repo("https://github.com/foo/bar").should eq("foo/bar")
  end

  it "parses ssh github URL" do
    Cjules::Util::Git.parse_repo("git@github.com:foo/bar.git").should eq("foo/bar")
  end

  it "returns nil for non-github" do
    Cjules::Util::Git.parse_repo("https://gitlab.com/foo/bar.git").should be_nil
  end
end

describe Cjules::Util::RepoMap do
  it "maps owner/repo to slash-form source name" do
    Cjules::Util::RepoMap.to_source("foo/bar").should eq("sources/github/foo/bar")
  end

  it "preserves hyphens in repo names" do
    Cjules::Util::RepoMap.to_source("hahwul/hwaro-examples").should eq("sources/github/hahwul/hwaro-examples")
  end
end

describe Cjules::Models::Session do
  it "parses minimal API response and exposes full id via short_id" do
    json = %({"name":"sessions/18077675164109662449","id":"18077675164109662449","prompt":"hi","state":"COMPLETED","createTime":"2026-04-01T12:00:00Z"})
    s = Cjules::Models::Session.from_json(json)
    s.id.should eq("18077675164109662449")
    s.short_id.should eq("18077675164109662449")
    s.state.should eq("COMPLETED")
  end

  it "computes repo display from slash-form source" do
    s = Cjules::Models::Session.from_json(%({
      "id":"x",
      "sourceContext":{"source":"sources/github/hahwul/hwaro-examples"}
    }))
    s.repo_display.should eq("hahwul/hwaro-examples")
  end

  it "tolerates unknown fields" do
    json = %({"id":"x","mysteryField":"value","prompt":"yo"})
    s = Cjules::Models::Session.from_json(json)
    s.id.should eq("x")
  end
end

describe Cjules::Models::Activity do
  it "detects event_type from populated key" do
    json = %({"id":"a","planGenerated":{"plan":{"id":"p1"}}})
    a = Cjules::Models::Activity.from_json(json)
    a.event_type.should eq("plan_generated")
  end

  it "is unknown when no event populated" do
    a = Cjules::Models::Activity.from_json(%({"id":"a"}))
    a.event_type.should eq("unknown")
  end

  it "parses typed planGenerated payload with steps" do
    json = %({"id":"a","planGenerated":{"plan":{"id":"p1","steps":[{"id":"s1","index":0,"title":"first","description":"do it"}]}}})
    a = Cjules::Models::Activity.from_json(json)
    plan = a.planGenerated.not_nil!.plan.not_nil!
    plan.id.should eq("p1")
    steps = plan.steps.not_nil!
    steps.size.should eq(1)
    steps[0].title.should eq("first")
    steps[0].index.should eq(0)
  end

  it "parses typed agentMessaged payload" do
    a = Cjules::Models::Activity.from_json(%({"id":"a","agentMessaged":{"agentMessage":"hi there"}}))
    a.agentMessaged.not_nil!.agentMessage.should eq("hi there")
  end

  it "parses typed progressUpdated payload" do
    a = Cjules::Models::Activity.from_json(%({"id":"a","progressUpdated":{"title":"writing","description":"tests"}}))
    pu = a.progressUpdated.not_nil!
    pu.title.should eq("writing")
    pu.description.should eq("tests")
  end

  it "parses typed sessionFailed payload with reason" do
    a = Cjules::Models::Activity.from_json(%({"id":"a","sessionFailed":{"reason":"deps broken"}}))
    a.sessionFailed.not_nil!.reason.should eq("deps broken")
  end

  it "parses empty sessionCompleted payload" do
    a = Cjules::Models::Activity.from_json(%({"id":"a","sessionCompleted":{}}))
    a.sessionCompleted.should_not be_nil
    a.event_type.should eq("session_completed")
  end

  it "parses planGenerated steps in declared index order" do
    json = %({
      "id":"a",
      "planGenerated":{"plan":{"id":"p","steps":[
        {"id":"s1","index":0,"title":"first"},
        {"id":"s2","index":1,"title":"second","description":"do that"}
      ]}}
    })
    a = Cjules::Models::Activity.from_json(json)
    steps = a.planGenerated.not_nil!.plan.not_nil!.steps.not_nil!
    steps.map(&.title).should eq(["first", "second"])
    steps[1].description.should eq("do that")
  end

  it "round-trips a media artifact for save-media decoding" do
    # Just verify the model carries mimeType + base64 data; decoding is exercised
    # by the logs command at runtime.
    json = %({"id":"a","artifacts":[{"media":{"mimeType":"image/png","data":"aGVsbG8="}}]})
    a = Cjules::Models::Activity.from_json(json)
    med = a.artifacts.not_nil![0].media.not_nil!
    med.mimeType.should eq("image/png")
    med.data.should eq("aGVsbG8=")
  end
end

describe Cjules::Config do
  describe ".valid_alias?" do
    it "accepts safe names" do
      Cjules::Config.valid_alias?("work").should be_true
      Cjules::Config.valid_alias?("hahwul-personal").should be_true
      Cjules::Config.valid_alias?("a.b_c-1").should be_true
    end

    it "rejects empty, slashed, spaced, or non-ascii names" do
      Cjules::Config.valid_alias?("").should be_false
      Cjules::Config.valid_alias?("foo bar").should be_false
      Cjules::Config.valid_alias?("path/like").should be_false
      Cjules::Config.valid_alias?("한글").should be_false
      Cjules::Config.valid_alias?("a" * 65).should be_false
    end
  end

  describe ".mask" do
    it "masks short and long keys" do
      Cjules::Config.mask("").should eq("(empty)")
      Cjules::Config.mask("abcd").should eq("***")
      Cjules::Config.mask("AIzaSyABC1234").should eq("***1234")
    end
  end

  describe ".format_account_line" do
    it "marks active account with an asterisk" do
      Cjules::Config.format_account_line("work", "AIzaSyXXXXyyyy", true).should start_with("* work")
      Cjules::Config.format_account_line("work", "AIzaSyXXXXyyyy", false).should start_with("  work")
    end
  end

  describe "#alias_for_key" do
    it "finds duplicate keys across aliases" do
      cfg = Cjules::Config.new(accounts: {"a" => "K1", "b" => "K2"})
      cfg.alias_for_key("K2").should eq("b")
      cfg.alias_for_key("K2", except: "b").should be_nil
      cfg.alias_for_key("K_NOPE").should be_nil
    end
  end
end

describe Cjules::Output::Format do
  it "renders relative age" do
    t = (Time.utc - 3.hours).to_rfc3339
    Cjules::Output::Format.age(t).should eq("3h")
  end

  it "returns dash on bad timestamp" do
    Cjules::Output::Format.age(nil).should eq("-")
    Cjules::Output::Format.age("not-a-time").should eq("-")
  end
end

describe Cjules::Util::PromptInput do
  it "reads and trims from file" do
    tmp = File.tempfile("cjules-spec-prompt-")
    File.write(tmp.path, "  hello\nworld  \n")
    begin
      Cjules::Util::PromptInput.resolve(nil, tmp.path).should eq("hello\nworld")
    ensure
      tmp.delete
    end
  end

  it "uses positional arg over absent file" do
    Cjules::Util::PromptInput.resolve("  hi  ", nil).should eq("hi")
  end

  it "prefers --file over arg" do
    tmp = File.tempfile("cjules-spec-prompt-")
    File.write(tmp.path, "from file")
    begin
      Cjules::Util::PromptInput.resolve("from arg", tmp.path).should eq("from file")
    ensure
      tmp.delete
    end
  end
end

describe Cjules::Output::Colors do
  it "strips ANSI codes when computing visible length" do
    Cjules::Output::Colors.visible_length("\e[31mhello\e[0m").should eq(5)
    Cjules::Output::Colors.visible_length("plain").should eq(5)
    Cjules::Output::Colors.visible_length("\e[1;32mok\e[0m\e[2mzz\e[0m").should eq(4)
  end

  it "counts CJK / fullwidth chars as 2 cells in display_width" do
    Cjules::Output::Colors.display_width("hi").should eq(2)
    Cjules::Output::Colors.display_width("안녕").should eq(4)
    Cjules::Output::Colors.display_width("a한b").should eq(4)
    Cjules::Output::Colors.display_width("\e[31m한국\e[0m").should eq(4)
    Cjules::Output::Colors.display_width("漢字テスト").should eq(10)
  end

  it "truncate_display respects display width and adds ellipsis" do
    Cjules::Output::Colors.truncate_display("short", 10).should eq("short")
    Cjules::Output::Colors.truncate_display("hello world", 8).should eq("hello w…")
    # 안녕하세요 = 10 cells; truncate to 6 -> 2 chars (4 cells) + … (1 cell) = 5 cells <= 6
    Cjules::Output::Colors.display_width(Cjules::Output::Colors.truncate_display("안녕하세요", 6)).should be <= 6
  end

  it "color-codes session states only when enabled" do
    Cjules::Output::Colors.disable!
    Cjules::Output::Colors.state("COMPLETED").should eq("COMPLETED")
    Cjules::Output::Colors.state("FAILED").should eq("FAILED")

    Cjules::Output::Colors.enable!
    Cjules::Output::Colors.state("COMPLETED").should contain("\e[32m")
    Cjules::Output::Colors.state("FAILED").should contain("\e[31m")
    Cjules::Output::Colors.state("IN_PROGRESS").should contain("\e[34m")
    Cjules::Output::Colors.state("QUEUED").should contain("\e[33m")
    Cjules::Output::Colors.state("PAUSED").should contain("\e[35m")
    Cjules::Output::Colors.state("UNKNOWN").should eq("UNKNOWN")
  ensure
    Cjules::Output::Colors.disable!
  end
end

describe Cjules::Commands::New do
  describe ".match_recovered" do
    sess = ->(id : String, title : String?, prompt : String?, source : String?) do
      ctx = source ? %(,"sourceContext":{"source":#{source.to_json}}) : ""
      ttl = title ? %(,"title":#{title.to_json}) : ""
      pmt = prompt ? %(,"prompt":#{prompt.to_json}) : ""
      Cjules::Models::Session.from_json(%({"id":#{id.to_json}#{ttl}#{pmt}#{ctx}}))
    end
    none = [] of Cjules::Models::Session

    it "returns empty when expected <= 0" do
      recent = [sess.call("a", "T", "P", nil)]
      Cjules::Commands::New.match_recovered(recent, "T", "P", nil, none, 0).should be_empty
    end

    it "returns empty when no title and prompt is empty" do
      recent = [sess.call("a", nil, "", nil)]
      Cjules::Commands::New.match_recovered(recent, nil, "", nil, none, 1).should be_empty
    end

    it "matches by exact title and skips already-claimed ids" do
      recent = [
        sess.call("a", "batch 1", "p", "sources/github/o/r"),
        sess.call("b", "batch 1", "p", "sources/github/o/r"),
        sess.call("c", "other", "p", "sources/github/o/r"),
      ]
      claimed = [sess.call("a", "batch 1", "p", "sources/github/o/r")]
      out = Cjules::Commands::New.match_recovered(recent, "batch 1", "p", "sources/github/o/r", claimed, 5)
      out.map(&.id).should eq(["b"])
    end

    it "falls back to exact prompt match when title is nil" do
      recent = [
        sess.call("a", nil, "hello world", nil),
        sess.call("b", nil, "different", nil),
      ]
      out = Cjules::Commands::New.match_recovered(recent, nil, "hello world", nil, none, 5)
      out.map(&.id).should eq(["a"])
    end

    it "rejects sessions whose source does not match" do
      recent = [
        sess.call("a", "T", "p", "sources/github/o/r"),
        sess.call("b", "T", "p", "sources/github/o/different"),
      ]
      out = Cjules::Commands::New.match_recovered(recent, "T", "p", "sources/github/o/r", none, 5)
      out.map(&.id).should eq(["a"])
    end

    it "ignores source filter when caller passed source=nil (e.g. --no-repo)" do
      recent = [
        sess.call("a", "T", "p", "sources/github/o/r"),
        sess.call("b", "T", "p", nil),
      ]
      out = Cjules::Commands::New.match_recovered(recent, "T", "p", nil, none, 5)
      out.map(&.id).should eq(["a", "b"])
    end

    it "caps results at expected" do
      recent = (1..5).map { |i| sess.call("s#{i}", "T", "p", nil) }.to_a
      out = Cjules::Commands::New.match_recovered(recent, "T", "p", nil, none, 2)
      out.map(&.id).should eq(["s1", "s2"])
    end

    it "prefers title over prompt when both are provided (title is the discriminator)" do
      recent = [
        sess.call("a", "T", "different prompt", nil),
        sess.call("b", "OTHER", "matching prompt", nil),
      ]
      out = Cjules::Commands::New.match_recovered(recent, "T", "matching prompt", nil, none, 5)
      out.map(&.id).should eq(["a"])
    end
  end
end

describe Cjules::Output::Table do
  it "renders header and rows aligned to widest cell" do
    Cjules::Output::Colors.disable!
    t = Cjules::Output::Table.new(["A", "BB"])
    t.add_row(["1", "22"])
    t.add_row(["333", "4"])
    io = IO::Memory.new
    t.render(io)
    lines = io.to_s.lines.map(&.rstrip)
    lines.size.should eq(3)
    lines[0].should eq("A    BB")
    lines[1].should eq("1    22")
    lines[2].should eq("333  4")
  end
end

describe Cjules::Models do
  it "parses ListSessionsResponse with pagination" do
    json = %({"sessions":[{"id":"a","state":"COMPLETED"},{"id":"b","state":"FAILED"}],"nextPageToken":"tok-2"})
    res = Cjules::Models::ListSessionsResponse.from_json(json)
    res.sessions.not_nil!.size.should eq(2)
    res.sessions.not_nil![0].id.should eq("a")
    res.nextPageToken.should eq("tok-2")
  end

  it "parses Activity with gitPatch artifact" do
    json = %({
      "id":"act-1","createTime":"2026-04-01T00:00:00Z",
      "artifacts":[{"changeSet":{"source":"jules","gitPatch":{"baseCommitId":"deadbeef","unidiffPatch":"--- a\\n+++ b\\n","suggestedCommitMessage":"fix"}}}],
      "progressUpdated":{}
    })
    a = Cjules::Models::Activity.from_json(json)
    a.event_type.should eq("progress_updated")
    arts = a.artifacts.not_nil!
    arts.size.should eq(1)
    gp = arts[0].changeSet.not_nil!.gitPatch.not_nil!
    gp.baseCommitId.should eq("deadbeef")
    gp.unidiffPatch.should eq("--- a\n+++ b\n")
    gp.suggestedCommitMessage.should eq("fix")
  end

  it "parses Activity with bashOutput artifact" do
    json = %({
      "id":"act-2",
      "artifacts":[{"bashOutput":{"command":"ls","output":"a\\nb","exitCode":0}}]
    })
    a = Cjules::Models::Activity.from_json(json)
    bo = a.artifacts.not_nil![0].bashOutput.not_nil!
    bo.command.should eq("ls")
    bo.exitCode.should eq(0)
  end

  it "leaves repo_display untouched for unknown source format" do
    s = Cjules::Models::Session.from_json(%({"id":"x","sourceContext":{"source":"sources/gitlab/foo/bar"}}))
    s.repo_display.should eq("sources/gitlab/foo/bar")
  end
end

describe Cjules::Config do
  describe "save then load" do
    it "round-trips accounts, current, and api_base" do
      with_isolated_home do
        cfg = Cjules::Config.new(
          api_base: "https://example.test",
          default_repo: "foo/bar",
          default_branch: "main",
          current: "x",
          accounts: {"x" => "K1", "y" => "K2"},
        )
        cfg.save

        loaded = Cjules::Config.load
        loaded.api_base.should eq("https://example.test")
        loaded.default_repo.should eq("foo/bar")
        loaded.default_branch.should eq("main")
        loaded.current.should eq("x")
        loaded.accounts.should eq({"x" => "K1", "y" => "K2"})
      end
    end

    it "drops nil default_repo / default_branch on save" do
      with_isolated_home do
        cfg = Cjules::Config.new(default_repo: "foo/bar", current: "x", accounts: {"x" => "K"})
        cfg.save
        cfg.default_repo = nil
        cfg.default_branch = nil
        cfg.save

        body = File.read(Cjules::Config.path)
        body.should_not contain("default_repo")
        body.should_not contain("default_branch")

        loaded = Cjules::Config.load
        loaded.default_repo.should be_nil
        loaded.default_branch.should be_nil
      end
    end

    it "writes the config file with mode 0600" do
      with_isolated_home do
        Cjules::Config.new(accounts: {"x" => "K"}, current: "x").save
        mode = File.info(Cjules::Config.path).permissions.value & 0o777
        mode.should eq(0o600)
      end
    end
  end

  describe ".load" do
    it "treats empty default_repo string in YAML as nil" do
      with_isolated_home do
        Dir.mkdir_p(File.dirname(Cjules::Config.path))
        File.write(Cjules::Config.path, "default_repo: \"\"\ndefault_branch: \"\"\n")
        loaded = Cjules::Config.load
        loaded.default_repo.should be_nil
        loaded.default_branch.should be_nil
      end
    end

    it "migrates legacy api_key field to accounts['default']" do
      with_isolated_home do
        Dir.mkdir_p(File.dirname(Cjules::Config.path))
        File.write(Cjules::Config.path, "api_key: legacy_key_xxxx\n")
        loaded = Cjules::Config.load
        loaded.accounts["default"]?.should eq("legacy_key_xxxx")
        loaded.current.should eq("default")
        loaded.api_key.should eq("legacy_key_xxxx")
      end
    end

    it "treats corrupt YAML as empty config" do
      with_isolated_home do
        Dir.mkdir_p(File.dirname(Cjules::Config.path))
        File.write(Cjules::Config.path, "::not yaml::\n  !!! garbage")
        loaded = Cjules::Config.load
        loaded.accounts.should be_empty
        loaded.current.should be_nil
      end
    end

    it "treats completely empty config file as empty config without crashing" do
      with_isolated_home do
        Dir.mkdir_p(File.dirname(Cjules::Config.path))
        File.write(Cjules::Config.path, "")
        loaded = Cjules::Config.load
        loaded.accounts.should be_empty
        loaded.current.should be_nil
      end
    end

    it "treats scalar-only config file as empty config without crashing" do
      with_isolated_home do
        Dir.mkdir_p(File.dirname(Cjules::Config.path))
        File.write(Cjules::Config.path, "hello")
        loaded = Cjules::Config.load
        loaded.accounts.should be_empty
        loaded.current.should be_nil
      end
    end
  end

  describe "env overrides" do
    it "JULES_API_KEY beats stored account key" do
      with_isolated_home do
        Cjules::Config.new(accounts: {"x" => "stored"}, current: "x").save
        ENV["JULES_API_KEY"] = "FROM_ENV"
        Cjules::Config.load.api_key.should eq("FROM_ENV")
      end
    end

    it "JULES_ACCOUNT picks a different alias than current" do
      with_isolated_home do
        Cjules::Config.new(accounts: {"x" => "K1", "y" => "K2"}, current: "x").save
        ENV["JULES_ACCOUNT"] = "y"
        loaded = Cjules::Config.load
        loaded.active_alias.should eq("y")
        loaded.api_key.should eq("K2")
        loaded.env_account_override?.should be_true
      end
    end

    it "JULES_API_BASE overrides config api_base" do
      with_isolated_home do
        Cjules::Config.new(api_base: "https://disk.example", accounts: {"x" => "K"}, current: "x").save
        ENV["JULES_API_BASE"] = "https://env.example"
        Cjules::Config.load.api_base.should eq("https://env.example")
      end
    end

    it "env_account_override? is false when env var is unset or empty" do
      with_isolated_home do
        Cjules::Config.new.env_account_override?.should be_false
        ENV["JULES_ACCOUNT"] = ""
        Cjules::Config.new.env_account_override?.should be_false
      end
    end
  end

  describe "#remove_account" do
    it "clears current when removing the active alias" do
      cfg = Cjules::Config.new(accounts: {"x" => "K1", "y" => "K2"}, current: "x")
      cfg.remove_account("x").should be_true
      cfg.current.should be_nil
      cfg.accounts.has_key?("x").should be_false
    end

    it "leaves current alone when removing a different alias" do
      cfg = Cjules::Config.new(accounts: {"x" => "K1", "y" => "K2"}, current: "x")
      cfg.remove_account("y")
      cfg.current.should eq("x")
    end

    it "returns false for unknown alias" do
      cfg = Cjules::Config.new(accounts: {"x" => "K"})
      cfg.remove_account("nope").should be_false
    end
  end
end
describe Cjules::TemplateRenderer do
  describe ".parse_vars" do
    it "parses key=value pairs" do
      vars = Cjules::TemplateRenderer.parse_vars(["foo=bar", "baz=qux"])
      vars.should eq({"foo" => "bar", "baz" => "qux"})
    end

    it "handles values with = signs" do
      vars = Cjules::TemplateRenderer.parse_vars(["url=http://example.com?a=1"])
      vars.should eq({"url" => "http://example.com?a=1"})
    end

    it "handles empty values" do
      vars = Cjules::TemplateRenderer.parse_vars(["empty="])
      vars.should eq({"empty" => ""})
    end

    it "warns and skips malformed arguments" do
      vars = Cjules::TemplateRenderer.parse_vars(["good=value", "bad_no_equals", "another=ok"])
      vars.should eq({"good" => "value", "another" => "ok"})
    end
  end

  describe ".render" do
    it "returns unchanged template when no directives present" do
      template = "Hello world"
      Cjules::TemplateRenderer.render(template).should eq("Hello world")
    end

    it "renders {{.Var}} directives with provided variables" do
      template = "Hello {{.Var \"name\"}}, you are {{.Var \"age\"}} years old"
      vars = {"name" => "Alice", "age" => "30"}
      result = Cjules::TemplateRenderer.render(template, vars)
      result.should eq("Hello Alice, you are 30 years old")
    end

    it "renders {{.Var}} with single quotes" do
      template = "Hello {{.Var 'name'}}"
      vars = {"name" => "Bob"}
      result = Cjules::TemplateRenderer.render(template, vars)
      result.should eq("Hello Bob")
    end

    it "replaces undefined variables with placeholder" do
      template = "Value: {{.Var \"missing\"}}"
      result = Cjules::TemplateRenderer.render(template)
      result.should eq("Value: [undefined variable: missing]")
    end

    it "renders {{.File}} directives with existing files" do
      with_isolated_home do |tmp|
        test_file = File.join(tmp, "test.txt")
        File.write(test_file, "File contents here")

        template = "Content: {{.File \"#{test_file}\"}}"
        result = Cjules::TemplateRenderer.render(template)
        result.should eq("Content: File contents here")
      end
    end

    it "handles missing files gracefully" do
      template = "Content: {{.File \"/nonexistent/file.txt\"}}"
      result = Cjules::TemplateRenderer.render(template)
      result.should eq("Content: [file not found: /nonexistent/file.txt]")
    end

    it "renders {{.GitDiff}} when git is available and has changes" do
      # Note: diff content can legitimately contain the string "{{.GitDiff}}" (e.g. in our own test code),
      # so we only verify that substitution for *our input template* happened (result changed) and prefix ok.
      template = "Changes:\n{{.GitDiff}}"
      result = Cjules::TemplateRenderer.render(template)
      result.should start_with("Changes:\n")
      result.should_not eq(template) # substitution or processing occurred
      # Output is either a real diff, a placeholder, or error string from renderer
      (result.includes?("diff --git") || result.includes?("[no git changes]") || result.includes?("[git diff") || result.includes?("[error running git")).should be_true
    end

    it "handles multiple directives in one template" do
      with_isolated_home do |tmp|
        test_file = File.join(tmp, "data.txt")
        File.write(test_file, "DATA")

        template = "Name: {{.Var \"name\"}}\nFile: {{.File \"#{test_file}\"}}\nAge: {{.Var \"age\"}}"
        vars = {"name" => "Charlie", "age" => "25"}
        result = Cjules::TemplateRenderer.render(template, vars)
        result.should eq("Name: Charlie\nFile: DATA\nAge: 25")
      end
    end

    it "preserves template content around directives" do
      template = "Before {{.Var \"x\"}} middle {{.Var \"y\"}} after"
      vars = {"x" => "X", "y" => "Y"}
      result = Cjules::TemplateRenderer.render(template, vars)
      result.should eq("Before X middle Y after")
    end
  end
end

# =============================================================================
# Client & API layer tests (use vendored WebMock for hermetic HTTP)
# =============================================================================

describe Cjules::Client do
  it "parses JSON error bodies for APIError#detail" do
    err = Cjules::Client::APIError.new(400, %({"error":{"message":"bad request details"}}))
    err.detail.should eq("bad request details")
    err.status.should eq(400)
  end

  it "falls back to raw body when error JSON is absent or malformed" do
    err1 = Cjules::Client::APIError.new(503, "plain text error")
    err1.detail.should eq("plain text error")

    err2 = Cjules::Client::APIError.new(500, %({"not":"an-error-wrapper"}))
    err2.detail.should eq(%({"not":"an-error-wrapper"}))

    err3 = Cjules::Client::APIError.new(429, "")
    err3.detail.should eq("")
  end
end

describe "Client HTTP behavior with WebMock" do
  it "performs successful GET and returns body" do
    with_webmock do
      cfg = Cjules::Config.new(api_base: "https://jules.googleapis.com", accounts: {"t" => "KEY"}, current: "t")
      stub_jules(:get, "/v1alpha/sessions/abc123", body: %({"id":"abc123","state":"COMPLETED"}))

      client = Cjules::Client.new(cfg)
      body = client.get("/v1alpha/sessions/abc123")
      body.should contain("COMPLETED")
    end
  end

  it "raises APIError on 4xx responses" do
    with_webmock do
      cfg = Cjules::Config.new(api_base: "https://jules.googleapis.com", accounts: {"t" => "KEY"}, current: "t")
      stub_jules(:get, "/v1alpha/sessions/missing", status: 404, body: %({"error":{"message":"not found"}}))

      client = Cjules::Client.new(cfg)
      expect_raises(Cjules::Client::APIError, /404/) do
        client.get("/v1alpha/sessions/missing")
      end
    end
  end

  it "retries on 429 and eventually succeeds" do
    with_webmock do
      cfg = Cjules::Config.new(api_base: "https://jules.googleapis.com", accounts: {"t" => "KEY"}, current: "t")

      attempts = 0
      WebMock.stub(:get, "https://jules.googleapis.com/v1alpha/sessions/r1").to_return do |_|
        attempts += 1
        if attempts <= 2
          HTTP::Client::Response.new(429, body: "", headers: HTTP::Headers{"Retry-After" => "0"})
        else
          HTTP::Client::Response.new(200, body: %({"id":"r1"}))
        end
      end

      client = Cjules::Client.new(cfg)
      body = client.get("/v1alpha/sessions/r1")
      body.should contain("r1")
      attempts.should eq(3)
    end
  end
end

describe Cjules::API::Sessions do
  it "lists sessions via client (stubbed)" do
    with_webmock do
      cfg = Cjules::Config.new(api_base: "https://jules.googleapis.com", accounts: {"t" => "KEY"}, current: "t")
      stub_jules(:get, "/v1alpha/sessions?pageSize=100", body: %({"sessions":[{"id":"s1","state":"QUEUED"}],"nextPageToken":""} ))

      client = Cjules::Client.new(cfg)
      page = Cjules::API::Sessions.list_page(client, 100)
      page.sessions.not_nil!.size.should eq(1)
      page.sessions.not_nil![0].id.should eq("s1")
    end
  end
end
