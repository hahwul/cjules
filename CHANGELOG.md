# Changelog

## Unreleased

- Subcommand `--help` now lists global flags (`--account`, `--no-color`) in a footer for discoverability.
- Added `-f` / `--format` for output format selection on `ls`, `get`, `new`, `activity`, `plan`, `logs`, `sources ls`, `sources get`. The existing `-o` / `--output` is retained as an alias.
- Added `cjules retry <ID>` which clones an existing session's prompt, repo, branch, and flags into a new session. Supports `--prompt` / `--prompt-file` / `--template` / `--branch` / `--note` / `--with-failure-reason`.
- Added `cjules templates` (subcommands `ls`, `show`, `path`) for managing prompt templates stored in `~/.config/cjules/templates/`. Use them via `cjules new --template <name>`.

## v0.1.0

Initial public release.
