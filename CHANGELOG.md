# Changelog

All notable changes to **cjules** are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Typed Activity events** — `planGenerated`, `planApproved`, `userMessaged`, `agentMessaged`, `progressUpdated`, `sessionCompleted`, `sessionFailed` are now structured. `watch` and `logs` render agent/user message bodies, progress `title — description`, plan step lists, and `sessionFailed.reason`.
- **`cjules plan <ID>`** — print the latest generated plan with step titles and descriptions; `--all` walks every plan in the session; `-o text|json|yaml`.
- **`watch --auto-approve`** — auto-approve plans when the session enters `AWAITING_PLAN_APPROVAL`.
- **`watch --reply`** — at `AWAITING_USER_FEEDBACK`, prompt on STDIN and send the reply via `sendMessage`.

### Changed

- **`watch` polling** — uses the activities `createTime` filter so each poll only requests events newer than the last seen timestamp instead of re-listing the whole session.

## [0.1.0] - 2026-04-27

Initial public release.

### Added

- **Sessions** — `new`, `ls`, `get`, `rm` (single + bulk filters by `--state` / `--older-than` / `--repo`), `watch`, `msg`, `approve`, `logs`, `patch`, `pr`, `pick`.
- **Sources** — `sources ls`, `sources get`.
- **Multi-account auth** — `login`, `logout`, `accounts ls / use / current`. Aliases stored in `~/.config/cjules/config.yml` with mode `0600`. `JULES_API_KEY`, `JULES_ACCOUNT`, `JULES_API_BASE` env overrides plus global `--account` flag.
- **Output formats** — table (default), `json`, `jsonl`, `yaml` for list views; `md` / `json` / `text` for `logs`.
- **Git-aware `new`** — auto-detect `--repo` from `git remote origin` and `--branch` from `HEAD`.
- **gitPatch handling** — `cjules patch <id>` prints the patch; `--list`, `--apply`, `--index N`.
- **Watch mode** — `cjules watch <id>` polls activities until the session reaches a terminal state.
- **Approve precheck** — aborts when the session isn't `AWAITING_PLAN_APPROVAL` (override with `--force`).
- **Display-width aware table renderer** — East-Asian Wide, Fullwidth, and common emoji codepoints count as 2 cells; ANSI escapes are stripped before measuring.
- **Shell completion** — `cjules completion bash | zsh | fish`.
- **HTTP timeouts** — connect 10 s, read 30 s on every API request; `--verify` on `login` uses tighter limits.
- **Tests** — 49 specs covering models, config save/load round trip, env overrides, util parsers, output formatters.
- **CI / release pipeline** — `ci.yml`, `release-binary.yml`, `release-deb.yml`, `release-rpm.yml`, `release-aur.yml`, `release-sbom.yml`, `publish-homebrew.yml`, `publish-snapcraft.yml`, `publish-ghcr.yml`.
- **AI-agent skill** — `skills/cjules/SKILL.md` for tool-aware automation.

[Unreleased]: https://github.com/hahwul/cjules/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/hahwul/cjules/releases/tag/v0.1.0
