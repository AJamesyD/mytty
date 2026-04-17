# Mistty - macOS terminal emulator built on libghostty

set shell := ["bash", "-euo", "pipefail", "-c"]

# Xcode 16.3 path for zig/libghostty builds (macOS 26 needs two Xcode versions)
DEVELOPER_DIR := "/Applications/Xcode-16.3.app/Contents/Developer"

# Default recipe
default: build

# Build the app (debug)
build:
    swift build

# Build the app (debug with optimization, for responsive UI without full release cost)
build-dev:
    swift build -Xswiftc -O

# Build the app (release)
build-release: build-libghostty
    swift build -c release

# Build the CLI tool
build-cli:
    swift build --target MisttyCLI

# Build CLI in release mode
build-cli-release:
    swift build --target MisttyCLI -c release

# Install CLI to /usr/local/bin
install-cli: build-cli-release
    cp .build/release/MisttyCLI /usr/local/bin/mistty-cli

# Uninstall CLI
uninstall-cli:
    rm -f /usr/local/bin/mistty-cli

# Package as .app bundle (debug)
bundle: build
    #!/usr/bin/env bash
    set -euo pipefail
    APP="build/Mistty.app"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp .build/debug/Mistty "$APP/Contents/MacOS/Mistty"
    swift build --target MisttyCLI
    cp .build/debug/MisttyCLI "$APP/Contents/MacOS/mistty-cli"
    cp Mistty/Resources/Info.plist "$APP/Contents/"
    codesign -s - -f "$APP"
    echo "Bundled: $APP"

# Package as .app bundle (debug, optimized)
bundle-dev: build-dev
    #!/usr/bin/env bash
    set -euo pipefail
    APP="build/Mistty.app"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp .build/debug/Mistty "$APP/Contents/MacOS/Mistty"
    swift build --target MisttyCLI -Xswiftc -O
    cp .build/debug/MisttyCLI "$APP/Contents/MacOS/mistty-cli"
    cp Mistty/Resources/Info.plist "$APP/Contents/"
    codesign -s - -f "$APP"
    echo "Bundled: $APP (optimized debug)"

# Package as .app bundle (release)
bundle-release: build-release
    #!/usr/bin/env bash
    set -euo pipefail
    APP="build/Mistty.app"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp .build/release/Mistty "$APP/Contents/MacOS/Mistty"
    swift build --target MisttyCLI -c release
    cp .build/release/MisttyCLI "$APP/Contents/MacOS/mistty-cli"
    cp Mistty/Resources/Info.plist "$APP/Contents/"
    codesign -s - -f "$APP"
    echo "Bundled: $APP"

# Install to /Applications (debug)
install: bundle
    #!/usr/bin/env bash
    set -euo pipefail
    osascript -e 'tell application "Mistty" to quit' 2>/dev/null || true
    rm -rf /Applications/Mistty.app
    cp -R build/Mistty.app /Applications/Mistty.app
    echo "Installed: /Applications/Mistty.app"

# Install to /Applications (debug, optimized)
install-dev: bundle-dev
    #!/usr/bin/env bash
    set -euo pipefail
    osascript -e 'tell application "Mistty" to quit' 2>/dev/null || true
    rm -rf /Applications/Mistty.app
    cp -R build/Mistty.app /Applications/Mistty.app
    echo "Installed: /Applications/Mistty.app (optimized debug)"

# Install to /Applications (release)
install-release: bundle-release
    #!/usr/bin/env bash
    set -euo pipefail
    osascript -e 'tell application "Mistty" to quit' 2>/dev/null || true
    rm -rf /Applications/Mistty.app
    cp -R build/Mistty.app /Applications/Mistty.app
    echo "Installed: /Applications/Mistty.app (release)"

# Run the app (debug)
run: install
    open /Applications/Mistty.app

# Run the app (debug, optimized: ~10s build, near-release perf, degraded LLDB)
run-dev: install-dev
    open /Applications/Mistty.app

# Run the app (release)
run-release: install-release
    open /Applications/Mistty.app

# Open the installed app (no rebuild)
open:
    open /Applications/Mistty.app

# Run tests
test:
    swift test

# Run tests matching a filter
test-filter PATTERN:
    swift test --filter {{PATTERN}}

# Clean build artifacts
clean:
    swift package clean
    rm -rf build/

# Build libghostty from the vendored submodule (requires nix)
build-libghostty:
    nix develop --command bash -c "cd vendor/ghostty && DEVELOPER_DIR={{DEVELOPER_DIR}} zig build -Dapp-runtime=none -Demit-xcframework=true -Doptimize=ReleaseFast"

# Enter the nix dev shell
dev:
    nix develop

# Initialize submodules (first-time setup)
setup:
    git submodule update --init --recursive
    @echo "Now run 'just build-libghostty' to build libghostty"

# Format Swift code
fmt-swift:
    swift format --in-place --recursive Mistty/ MisttyTests/ MisttyCLI/ MisttyShared/

# Check formatting without modifying
fmt-check:
    swift format --recursive Mistty/ MisttyTests/ MisttyCLI/ MisttyShared/

# Lint Swift code
lint:
    swiftlint lint --quiet

# Lint and auto-fix Swift code
lint-fix:
    swiftlint lint --fix --quiet

# Lint Swift code (strict: warnings are errors)
lint-strict:
    swiftlint lint --quiet --strict

# Format nix files
nix-fmt:
    nix fmt .

# Format all code (Swift + Nix)
fmt-all: fmt-swift nix-fmt

# Format all code
fmt: fmt-all

# Pre-commit check: format, lint, test
check: fmt-check lint test

# CI pipeline: format check, strict lint, build, test, typos
ci: fmt-check lint-strict build test
    typos

# Show project info
info:
    @echo "Mistty - macOS terminal emulator"
    @echo ""
    @echo "Swift package:"
    @swift package describe 2>/dev/null | head -20
    @echo ""
    @echo "Ghostty submodule:"
    @git submodule status vendor/ghostty
