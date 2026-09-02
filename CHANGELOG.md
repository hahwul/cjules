# Changelog

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
