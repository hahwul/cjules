<div align="center">
  <img alt="cjules Logo" src="logo.webp" width="120px;">
  <p>A power-user CLI for the Jules API, written in Crystal.</p>
</div>

<p align="center">
<a href="https://github.com/hahwul/cjules/blob/main/CONTRIBUTING.md">
<img src="https://img.shields.io/badge/CONTRIBUTIONS-WELCOME-000000?style=for-the-badge&labelColor=black"></a>
<a href="https://github.com/hahwul/cjules/releases">
<img src="https://img.shields.io/github/v/release/hahwul/cjules?style=for-the-badge&color=black&labelColor=black&logo=web"></a>
<a href="https://crystal-lang.org">
<img src="https://img.shields.io/badge/Crystal-000000?style=for-the-badge&logo=crystal&logoColor=white"></a>
</p>

A scriptable CLI for [Jules](https://jules.google), written in Crystal.

- **Git-aware `new`** — auto-detects `--repo` and `--branch`; reads the prompt from args, `stdin`, or `--file`.
- **Parallel sessions** — `cjules new --parallel N` runs N sessions with the same prompt.
- **Watch** — `cjules watch <id>` tails activities; `--auto-approve --reply` for hands-free runs.
- **Prune** — filter by state, age, repo, or `--all`; dry-run by default, `-y` to apply.
- **Patch & PR** — `cjules patch <id> --apply` runs `git apply`; `cjules pr <id> --open` opens the PR.
- **Logs** — `cjules logs <id> -o md` for a full report, `--bash` for shell transcripts, `--save-media` for artifacts.
- **Pipe-friendly** — `-o table|json|jsonl|yaml` on every list command.
- **Multi-account** — aliases via `cjules accounts use`, or one-shot with `--account`.
- **Pick** — `cjules pick` (uses `fzf` if available) with `--action show|watch|pr|delete`.

> **Heads up:** the Jules API is currently labelled `v1alpha`. Schema and
> behaviour can change without notice. Pin a release of cjules in scripts you
> care about and read the [CHANGELOG](CHANGELOG.md) when upgrading.

## Install
### Homebrew
```
brew tap hahwul/cjules
brew install cjules
```

### Build from Source
```sh
shards build --release
install bin/cjules /usr/local/bin/
```

## Auth

Issue an API key at [jules.google.com/settings/api](https://jules.google.com/settings/api) and save it with `cjules login`.

```sh
cjules login --alias work        # prompts for the API key (input hidden)
cjules login --alias personal --key AIza...
cjules accounts ls
cjules accounts use personal
cjules logout work
```

Resolution order: `JULES_API_KEY` env var → `JULES_ACCOUNT` env var → active alias from config.

## Examples

### Creating sessions

```sh
# Create a session for the current git repo/branch
cjules new "Add a healthcheck endpoint"

# Pipe a longer prompt and let Jules open the PR automatically
cat PROMPT.md | cjules new --auto-pr -

# Read the prompt from a file, override repo/branch, require plan approval
cjules new --file PROMPT.md --repo hahwul/cjules --branch main --require-approval

# Repoless session (no sourceContext)
cjules new --no-repo "Draft release notes for v0.2.0"

# Fan out N parallel sessions with the same prompt and capture the IDs
cjules new --parallel 5 --auto-pr "Refactor the config loader" -o json | jq -r '.[].id' > ids.txt
```

### Watching and steering

```sh
# Watch a session live (3s default poll)
cjules watch <session-id> --interval 5

# Hands-free run: auto-approve plans and reply to feedback prompts
cjules watch <session-id> --auto-approve --reply

# Send a follow-up message
cjules msg <session-id> "Also add a /readyz endpoint"

# Or pipe one in
echo "Please add tests for the error path" | cjules msg <session-id> -

# Approve a pending plan explicitly
cjules approve <session-id>
```

### Listing, filtering, piping

```sh
# Recent failures as JSONL, pipe into jq
cjules ls --state FAILED --since 7d -o jsonl | jq -r '.id + "\t" + .title'

# Re-pull logs for the latest failure
cjules ls --state FAILED --since 7d -o jsonl | jq -r .id | head -1 | xargs cjules logs

# Interactive picker (uses fzf if installed) — default action shows the session
cjules pick
cjules pick --action watch        # pick → watch
cjules pick --action pr           # pick → print PR URL
```

### Patches, PRs, exports

```sh
# Inspect or apply the resulting patch locally
cjules patch <session-id> --list
cjules patch <session-id> --apply

# Print or open the PR
cjules pr <session-id>
cjules pr <session-id> --open

# Full session report as Markdown
cjules logs <session-id> -o md > report.md

# Pull only bash command/output blocks (handy for debugging long runs)
cjules logs <session-id> --bash

# Save media artifacts (screenshots, etc.) to a directory
cjules logs <session-id> --save-media ./artifacts
```

### Bulk cleanup with `prune`

`prune` is dry-run by default — review the matches, then re-run with `-y` to actually delete.

```sh
# Preview what would be deleted
cjules prune --completed --older-than 30d

# Actually delete after the preview looks right
cjules prune --completed --older-than 30d -y

# Sweep failed sessions for a specific repo
cjules prune --failed --repo hahwul/cjules -y

# Match an arbitrary state
cjules prune --state AWAITING_USER_FEEDBACK --older-than 14d -y

# Wipe every session for the active account (cannot be combined with other filters)
cjules prune --all          # dry-run preview
cjules prune --all -y       # prompts for typed 'yes' confirmation

# One-off targeted delete (no filters needed)
cjules rm <session-id> <session-id> ...
```

### Multi-account workflows

```sh
# Run a single command against a non-active account
cjules --account personal ls --since 24h

# One-off override via env var
JULES_ACCOUNT=work cjules new "Bump dependencies"
JULES_API_KEY=AIza... cjules ls
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
