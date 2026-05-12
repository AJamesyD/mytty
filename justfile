# Mytty - macOS terminal emulator built on libghostty

set shell := ["bash", "-euo", "pipefail", "-c"]

# Default recipe
default: build

# Kill dangling swift/xctest processes that leak memory after interrupted builds
_kill-zombies:
    @pkill -9 -f 'swift-(build|test|frontend)|xctest' 2>/dev/null || true

# Build the app (debug)
build: _kill-zombies
    swift build

# Build the app (release)
build-release: build-libghostty
    swift build -c release

# Build the CLI tool
build-cli:
    swift build --target MyttyCLI

# Build CLI in release mode
build-cli-release:
    swift build --target MyttyCLI -c release

# Install CLI symlink (no root required)
install-cli: install-release
    @mkdir -p ~/.local/bin
    @rm -f /usr/local/bin/mytty-cli 2>/dev/null || true
    @ln -sf /Applications/Mytty.app/Contents/MacOS/mytty-cli ~/.local/bin/mytty-cli
    @echo "Installed: ~/.local/bin/mytty-cli -> /Applications/Mytty.app/Contents/MacOS/mytty-cli"
    @if ! echo ":$PATH:" | grep -q ":$HOME/.local/bin:"; then \
        echo "Add ~/.local/bin to your PATH:"; \
        echo '  export PATH="$HOME/.local/bin:$PATH"'; \
    fi

# Install app (release) + CLI for daily use
install-all: install-cli
    @echo "Run with: open /Applications/Mytty.app"

# Uninstall CLI
uninstall-cli:
    rm -f ~/.local/bin/mytty-cli

# Package as .app bundle (debug)
bundle: build
    #!/usr/bin/env bash
    set -euo pipefail
    APP="build/Mytty.app"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp .build/debug/Mytty "$APP/Contents/MacOS/Mytty"
    swift build --target MyttyCLI
    cp .build/debug/MyttyCLI "$APP/Contents/MacOS/mytty-cli"
    cp Mytty/Resources/Info.plist "$APP/Contents/"
    cp -R vendor/ghostty/zig-out/share/ghostty "$APP/Contents/Resources/ghostty"
    cp -R vendor/ghostty/zig-out/share/terminfo "$APP/Contents/Resources/terminfo"
    test -f "$APP/Contents/Resources/terminfo/78/xterm-ghostty" \
      || { echo "error: ghostty resources missing from bundle (run build-libghostty first)"; exit 1; }
    codesign -s - -f "$APP"
    echo "Bundled: $APP"

# Package as .app bundle (release)
bundle-release: build-release
    #!/usr/bin/env bash
    set -euo pipefail
    APP="build/Mytty.app"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp .build/release/Mytty "$APP/Contents/MacOS/Mytty"
    swift build --target MyttyCLI -c release
    cp .build/release/MyttyCLI "$APP/Contents/MacOS/mytty-cli"
    cp Mytty/Resources/Info.plist "$APP/Contents/"
    cp -R vendor/ghostty/zig-out/share/ghostty "$APP/Contents/Resources/ghostty"
    cp -R vendor/ghostty/zig-out/share/terminfo "$APP/Contents/Resources/terminfo"
    test -f "$APP/Contents/Resources/terminfo/78/xterm-ghostty" \
      || { echo "error: ghostty resources missing from bundle (run build-libghostty first)"; exit 1; }
    codesign -s - -f "$APP"
    echo "Bundled: $APP"

# Install to /Applications (debug)
install: bundle
    #!/usr/bin/env bash
    set -euo pipefail
    osascript -e 'tell application "Mytty" to quit' 2>/dev/null || true
    rm -rf /Applications/Mytty.app
    cp -R build/Mytty.app /Applications/Mytty.app
    echo "Installed: /Applications/Mytty.app"

# Install to /Applications (release)
install-release: bundle-release
    #!/usr/bin/env bash
    set -euo pipefail
    osascript -e 'tell application "Mytty" to quit' 2>/dev/null || true
    rm -rf /Applications/Mytty.app
    cp -R build/Mytty.app /Applications/Mytty.app
    echo "Installed: /Applications/Mytty.app (release)"

# Run the app (debug)
run: install
    open /Applications/Mytty.app

# Run the app (release)
run-release: install-release
    open /Applications/Mytty.app

# Open the installed app (no rebuild)
open:
    open /Applications/Mytty.app

# Run tests
test: _kill-zombies
    swift test

# Run tests matching a filter
test-filter PATTERN:
    swift test --filter {{PATTERN}}

# Clean build artifacts
clean:
    swift package clean
    rm -rf build/

# Clean all build artifacts including libghostty
clean-all: clean
    rm -rf vendor/ghostty/zig-out vendor/ghostty/.zig-cache vendor/ghostty/macos/GhosttyKit.xcframework

# Build libghostty from the vendored submodule (requires nix devshell for zig)
build-libghostty:
    #!/usr/bin/env bash
    set -euo pipefail
    # Skip if xcframework already exists (cache hit in CI)
    if [ -f "vendor/ghostty/macos/GhosttyKit.xcframework/macos-arm64/libghostty-fat.a" ]; then
      echo "libghostty already built, skipping"
      exit 0
    fi
    # HACK: Xcode 16.x SDK required because macOS 26 SDK only has arm64e tbd stubs
    #   and Zig targets arm64. Remove when Zig supports arm64e or Apple restores
    #   arm64 stubs in the macOS SDK.
    xcode16=$(find /Applications -maxdepth 1 -name 'Xcode*16*' -type d | sort -V | tail -1)
    if [ -z "${DEVELOPER_DIR:-}" ] && [ -z "$xcode16" ]; then
      echo "error: no Xcode 16.x found in /Applications (needed for arm64 SDK stubs)" >&2
      exit 1
    fi
    export DEVELOPER_DIR="${DEVELOPER_DIR:-$xcode16/Contents/Developer}"
    cd vendor/ghostty
    zig build -Dapp-runtime=none -Dxcframework-target=native -Demit-macos-app=false -Doptimize=ReleaseFast
    # HACK: Zig-produced .o files aren't 8-byte aligned, causing Apple's libtool
    #   to silently drop them. Rebuild the library with zig ar (LLVM-based).
    #   Remove after https://github.com/ziglang/zig/issues/22292
    xcfw="macos/GhosttyKit.xcframework/macos-arm64"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    mri="CREATE $tmp/libghostty.a"$'\n'
    count=0
    shopt -s nullglob
    for f in .zig-cache/o/*/lib*.a; do
      [[ "$f" == *"-fat.a" ]] && continue
      arch=$(lipo -info "$f" 2>/dev/null | grep -oE 'arm64$' || true)
      [ "$arch" != "arm64" ] && continue
      plat=$(otool -l "$f" 2>/dev/null | grep -A 2 "LC_BUILD_VERSION" | grep "platform" | head -1 | awk '{print $2}')
      [ "$plat" = "1" ] || continue
      mri+="ADDLIB $(cd "$(dirname "$f")" && pwd)/$(basename "$f")"$'\n'
      count=$((count+1))
    done
    if [ "$count" -eq 0 ]; then
      echo "error: no arm64 macOS libraries found in .zig-cache" >&2
      exit 1
    fi
    mri+="SAVE"$'\n'"END"$'\n'
    echo "$mri" | zig ar -M
    cp "$tmp/libghostty.a" "$xcfw/libghostty-fat.a"
    echo "libghostty built (arm64, native, $count libs merged)"

# Enter the nix dev shell
dev:
    nix develop

# Initialize submodules (first-time setup)
setup:
    git submodule update --init --recursive
    @echo "Now run 'just build-libghostty' to build libghostty"

# Git hooks (auto-installed by nix devshell)
install-hooks:
    @echo "Hooks are auto-installed by nix devshell (direnv allow or nix develop)."

# Format all code (Swift + Nix + Shell)
# swift-format: Xcode toolchain (authoritative for Swift layout)
# nixfmt: nix-provided via `nix fmt` (authoritative for Nix)
# shfmt: nix-provided (authoritative for shell)
fmt:
    swift format --in-place --recursive Mytty/ MyttyTests/ MyttyCLI/ MyttyShared/
    nix fmt flake.nix
    shfmt -w scripts/

# Lint all code (strict: warnings are errors)
lint:
    swift format lint --strict --parallel --recursive Mytty/ MyttyTests/ MyttyCLI/ MyttyShared/
    nix fmt -- --check flake.nix
    shfmt -d scripts/
    swiftlint lint --quiet --strict
    shellcheck scripts/*
    typos

# Auto-fix lint violations
lint-fix:
    swiftlint lint --fix --quiet

# Local check: lint, verify, test
check: lint verify-cli-ref test

# CI pipeline
ci: lint build verify-cli-ref test

# Detect unused code (requires a prior build)
periphery:
    periphery scan --skip-build --index-store-path .build/debug/index/store

# Generate CLI reference from ArgumentParser dump-help
generate-cli-ref: build-cli
    scripts/generate-cli-reference.sh

# Verify CLI reference is up to date
verify-cli-ref: generate-cli-ref
    @git diff --exit-code docs/CLI-REFERENCE.md || (echo "error: docs/CLI-REFERENCE.md is stale. Run 'just generate-cli-ref' to update." && exit 1)

# Generate changelog for a release
changelog TAG:
    git-cliff --latest --tag {{TAG}}

# Create DMG from the release .app bundle
dmg TAG: bundle-release
    create-dmg --volname "Mytty" --window-size 600 400 --icon "Mytty.app" 200 200 --app-drop-link 400 200 "build/Mytty-{{TAG}}-arm64.dmg" build/Mytty.app

# Show project info
info:
    @echo "Mytty - macOS terminal emulator"
    @echo ""
    @echo "Swift package:"
    @swift package describe 2>/dev/null | head -20
    @echo ""
    @echo "Ghostty submodule:"
    @git submodule status vendor/ghostty
