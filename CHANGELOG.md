# Changelog

## Unreleased

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
