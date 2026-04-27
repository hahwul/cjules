require "./spec_helper"
require "../src/cjules/util"
require "../src/cjules/models"
require "../src/cjules/output/format"
require "../src/cjules/output/colors"
require "../src/cjules/output/table"
require "../src/cjules/config"

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
  it "maps owner/repo to source name" do
    Cjules::Util::RepoMap.to_source("foo/bar").should eq("sources/github-foo-bar")
  end
end

describe Cjules::Models::Session do
  it "parses minimal API response" do
    json = %({"name":"sessions/abc","id":"abc","prompt":"hi","state":"COMPLETED","createTime":"2026-04-01T12:00:00Z"})
    s = Cjules::Models::Session.from_json(json)
    s.id.should eq("abc")
    s.short_id.should eq("abc")
    s.state.should eq("COMPLETED")
  end

  it "computes repo display from source" do
    s = Cjules::Models::Session.from_json(%({
      "id":"x",
      "sourceContext":{"source":"sources/github-acme-widgets"}
    }))
    s.repo_display.should eq("acme/widgets")
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
    s = Cjules::Models::Session.from_json(%({"id":"x","sourceContext":{"source":"sources/gitlab-foo-bar"}}))
    s.repo_display.should eq("sources/gitlab-foo-bar")
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
