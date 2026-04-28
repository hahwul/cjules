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
