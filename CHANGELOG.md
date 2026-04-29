# Changelog

## v0.2.0

- Added `cjules retry <ID>` to re-run a session by cloning its prompt, repo, branch, and flags. Supports `--prompt` / `--prompt-file` / `--template` / `--branch` / `--note` / `--with-failure-reason`.
- Added `cjules templates` (`ls`, `show`, `path`) for prompt templates kept in `~/.config/cjules/templates/`. Use via `cjules new --template <name>` or `cjules retry --template <name>`.
- Added `-f` / `--format` for output format on `ls`, `get`, `new`, `activity`, `plan`, `logs`, and `sources`. `-o` / `--output` kept as an alias.
- Subcommand `--help` now lists global flags (`--account`, `--no-color`) in a footer.

## v0.1.0

Initial public release.
