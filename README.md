<div align="center">
  <img alt="cjules Logo" src="logo.webp" width="120px;">
  <p>Directory tag manager — put your directories on the cutting board.</p>
</div>

<p align="center">
<a href="https://github.com/hahwul/cjules/blob/main/CONTRIBUTING.md">
<img src="https://img.shields.io/badge/CONTRIBUTIONS-WELCOME-000000?style=for-the-badge&labelColor=black"></a>
<a href="https://github.com/hahwul/cjules/releases">
<img src="https://img.shields.io/github/v/release/hahwul/cjules?style=for-the-badge&color=black&labelColor=black&logo=web"></a>
<a href="https://crystal-lang.org">
<img src="https://img.shields.io/badge/Crystal-000000?style=for-the-badge&logo=crystal&logoColor=white"></a>
</p>

A focused, scriptable CLI for the [Jules](https://jules.google),
written in Crystal. `cjules` complements the official tooling with the
quality-of-life features power users tend to miss:

- **Multi-account** — save any number of API keys under aliases and switch with `cjules accounts use`.
- **Bulk delete** — `cjules rm --state FAILED --older-than 30d`.
- **Watch mode** — `cjules watch <id>` tails activities until the session terminates.
- **Pipe-friendly output** — `-o table|json|jsonl|yaml` everywhere; pipe straight into `jq`.
- **Git-aware `new`** — auto-detects `--repo` and `--branch` from the current checkout.
- **Patch extraction** — `cjules patch <id> --apply` runs `git apply` with the session's gitPatch.
- **Markdown export** — `cjules logs <id> -o md` produces a full session report.
- **Interactive picker** — `cjules pick` (uses `fzf` if available; falls back to a numeric menu).

> **Heads up:** the Jules API is currently labelled `v1alpha`. Schema and
> behaviour can change without notice. Pin a release of cjules in scripts you
> care about and read the [CHANGELOG](CHANGELOG.md) when upgrading.

## Install

```sh
shards build --release
install bin/cjules /usr/local/bin/
```

Requires Crystal `>= 1.20`.

## Auth

```sh
cjules login --alias work        # prompts for the API key (input hidden)
cjules login --alias personal --key AIza...
cjules accounts ls
cjules accounts use personal
cjules logout work
```

Resolution order: `JULES_API_KEY` env var → `JULES_ACCOUNT` env var → active alias from config.

## Examples

```sh
# Create a session for the current git repo/branch
cjules new "Add a healthcheck endpoint"

# Pipe a longer prompt
cat PROMPT.md | cjules new --auto-pr -

# List recent failures and re-trigger one
cjules ls --state FAILED --since 7d -o jsonl | jq -r .id | head -1 | xargs cjules logs

# Apply the resulting patch locally
cjules patch <session-id> --apply

# Watch a session live
cjules watch <session-id> --interval 5

# Bulk cleanup of old completed sessions
cjules rm --state COMPLETED --older-than 30d
```

## Config

Stored at `~/.config/cjules/config.yml` with `0600` permissions. Set defaults:

```sh
cjules config set default_repo  hahwul/cjules
cjules config set default_branch main
```

## Shell completion

```sh
cjules completion zsh   > "${fpath[1]}/_cjules"
cjules completion bash  > /etc/bash_completion.d/cjules
cjules completion fish  > ~/.config/fish/completions/cjules.fish
```

## Development

```sh
shards build
crystal spec
```

## License

MIT — see `LICENSE`.
