# Changelog

## v0.3.0

### Final release: Jules is shutting down
Google announced on 2026-10-29 that [Jules is winding down](https://jules.google/docs/changelog/2026-10-29):
- Until **November 11, 2026** you can keep creating and finishing sessions.
- After November 11, 2026, Jules is **read-only** until the end of the year.
- On **December 31, 2026**, Jules shuts down.

Expect this to be the last cjules release. The repository will be archived after it ships. Your code, branches, and pull requests stay on GitHub. To keep session history, use the official export (see the announcement), or save individual sessions with `cjules logs <id> -f json` / `cjules patch <id>` while the API still answers.

### Added
- `cjules troubleshoot <ID>` diagnoses a failed session from its bash logs and offers a retry with a fix note. It recognizes Crystal compile errors, missing shards, shards resolver errors, and failing `crystal spec` examples, and falls back to the session's failure reason. It asks `[Y/n]` before it runs `retry --note`. `-y` skips the prompt, and `-n` only prints the diagnosis (#9).
- `cjules commit-msg [<ID>] [--staged] [--copy]` generates a commit message from the local `git diff` through a repoless Jules session, or pulls one out of an existing session (#7).
- `cjules pr-describe <ID> [--copy]` builds a Markdown PR description from a session's plan and progress steps, per-file diff stats, and verification runs (#7).
- `cjules watch --notify desktop|slack|discord` sends a notification when a session reaches COMPLETED, FAILED, or AWAITING_USER_FEEDBACK. Webhooks are set with `cjules config set slack_webhook|discord_webhook`, or with `JULES_SLACK_WEBHOOK` / `JULES_DISCORD_WEBHOOK` (#5).

### Fixed
- Aliases and keys that YAML would read as numbers, booleans, or null (for example `login --alias 2024`) are now quoted on save. Unquoted entries written by older versions are recovered as written instead of being dropped.
- Bad or unknown flags (`ls --bogus`, `ls --limit abc`, `watch --interval x`) are now usage errors (exit 2) instead of stack traces. `--limit` and `--interval` must be >= 1, and oversized `--since` / `--older-than` values are rejected.
- `--account --no-color` is now reported as a missing value instead of being read as an alias named `--no-color`.
- Empty IDs (`get ""`, `rm sessions/`) are rejected before any request is sent, so they no longer hit the collection endpoint.
- `cjules pick` maps the fzf choice back by the full session ID. Before, a 12-character prefix could select, or delete, the wrong session.
- Templates expand `{{.GitDiff}}` and `{{.Var}}` in one pass, so text inside a diff or variable value that looks like a directive is inserted as-is.

### Internal
- Trimmed duplicated and dead code (shared pagination loop, `ID.require!`, `Duration.cutoff!`, `Templates.find!`) with no change in behavior.
- Upgraded ameba to 1.7.0, which now builds from the source pinned in `shard.lock`. CI tests, lints, and builds release binaries with Crystal 1.22.0, and the snapcraft publish action is pinned to a commit SHA.
- Updated `skills/cjules/SKILL.md` for the new commands.

## v0.2.3

### Fixed
- macOS release tarballs are re-signed ad hoc after `install_name_tool` rewrites their dylib load paths. The bundled OpenSSL dylibs were left with a stale signature, and Apple Silicon SIGKILLs any process that maps one, so `cjules-v0.2.2-osx-arm64.tar.gz` could not run at all on Apple Silicon (`zsh: killed cjules`, exit 137). Clearing quarantine did not help: it is a signature check, not Gatekeeper. Packaging now verifies every signature and runs the extracted tarball before publishing it (#20).

## v0.2.2

### Fixed
- macOS release binaries are now shipped as portable `.tar.gz` archives with bundled OpenSSL libraries, instead of a bare executable linked against Homebrew `openssl@1.1` that failed to launch on clean machines (`dyld: libssl.1.1.dylib not found`).

- Internal refactoring: extracted `Help.show_help` to remove duplicated `--help` footer logic across all subcommands. All command help output now routes through the helper.
- Internal: renamed `Commands::SourcesCmd` → `Commands::Sources` for naming consistency with other command modules.
- Continued error centralization: several commands now raise `Cjules::UsageError` for argument problems (central handler in `CLI.run` prints + exits with code 2). Reduces per-command boilerplate.

## v0.2.1

- HTTP client now retries transient failures (5xx, 429, socket/SSL errors) with exponential backoff. GET and DELETE retry up to 3 times; 429 is retried on every method and honors `Retry-After`. POST is excluded from 5xx retry — `cjules new`'s reconcile path covers ambiguous create failures.
- `cjules watch` no longer dies on a transient blip. The polling loop tolerates 5xx/429 and network errors with a bounded backoff (capped at 60s); 4xx surfaces immediately so bad session IDs still fail fast.
- Internal: extracted `Util::SessionFilter` to deduplicate the state/repo/cutoff/search filter logic shared by `ls`, `rm`, and `prune`. No user-visible behavior change; `ls` no longer parses `createTime` twice per session.
- `cjules new` now reconciles 4xx submission failures by looking up sessions created on the account since the call started — works around the Jules API occasionally returning `HTTP 400 Precondition check failed` for a session that *was* created (issue #1). Disable with `--no-reconcile-on-error`.

## v0.2.0

- Added `cjules retry <ID>` to re-run a session by cloning its prompt, repo, branch, and flags. Supports `--prompt` / `--prompt-file` / `--template` / `--branch` / `--note` / `--with-failure-reason`.
- Added `cjules templates` (`ls`, `show`, `path`) for prompt templates kept in `~/.config/cjules/templates/`. Use via `cjules new --template <name>` or `cjules retry --template <name>`.
- Added `-f` / `--format` for output format on `ls`, `get`, `new`, `activity`, `plan`, `logs`, and `sources`. `-o` / `--output` kept as an alias.
- Subcommand `--help` now lists global flags (`--account`, `--no-color`) in a footer.

## v0.1.0

Initial public release.
