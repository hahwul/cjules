alias b := build
alias t := test
alias vc := version-check
alias vu := version-update

# List available tasks.
default:
    @just --list

# Build cjules binary.
[group('build')]
build:
    shards install
    shards build

# Build release binary.
[group('build')]
release:
    shards install --production
    shards build --release --no-debug

# Clean build artifacts.
[group('build')]
clean:
    rm -rf bin/
    rm -rf lib/

# Auto-format code.
[group('development')]
fix:
    crystal tool format

# Check code format without changes.
[group('development')]
check:
    crystal tool format --check

# Run ameba static linter (requires shards install first).
# Rule configuration lives in .ameba.yml so local and CI stay in sync.
# ameba 1.7 dropped its `executables:` entry, so `shards install` no longer
# drops a binary into bin/ -- build it from the revision shard.lock pins.
[group('development')]
lint:
    @[ -f lib/ameba/src/cli.cr ] || shards install
    @[ -f bin/ameba ] || (mkdir -p bin && crystal build lib/ameba/src/cli.cr -o bin/ameba)
    bin/ameba

# Run all tests.
[group('development')]
test:
    crystal spec

# Check version consistency across all files.
[group('development')]
version-check:
    crystal run scripts/version_check.cr

# Update version across all files.
[group('development')]
version-update:
    crystal run scripts/version_update.cr
