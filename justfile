# Mytty - macOS terminal emulator built on libghostty

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
    swift build --target MyttyCLI

# Build CLI in release mode
build-cli-release:
    swift build --target MyttyCLI -c release

# Install CLI to /usr/local/bin
install-cli: build-cli-release
    cp .build/release/MyttyCLI /usr/local/bin/mytty-cli

# Uninstall CLI
uninstall-cli:
    rm -f /usr/local/bin/mytty-cli

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
    codesign -s - -f "$APP"
    echo "Bundled: $APP"

# Package as .app bundle (debug, optimized)
bundle-dev: build-dev
    #!/usr/bin/env bash
    set -euo pipefail
    APP="build/Mytty.app"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp .build/debug/Mytty "$APP/Contents/MacOS/Mytty"
    swift build --target MyttyCLI -Xswiftc -O
    cp .build/debug/MyttyCLI "$APP/Contents/MacOS/mytty-cli"
    cp Mytty/Resources/Info.plist "$APP/Contents/"
    codesign -s - -f "$APP"
    echo "Bundled: $APP (optimized debug)"

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

# Install to /Applications (debug, optimized)
install-dev: bundle-dev
    #!/usr/bin/env bash
    set -euo pipefail
    osascript -e 'tell application "Mytty" to quit' 2>/dev/null || true
    rm -rf /Applications/Mytty.app
    cp -R build/Mytty.app /Applications/Mytty.app
    echo "Installed: /Applications/Mytty.app (optimized debug)"

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

# Run the app (debug, optimized: ~10s build, near-release perf, degraded LLDB)
run-dev: install-dev
    open /Applications/Mytty.app

# Run the app (release)
run-release: install-release
    open /Applications/Mytty.app

# Open the installed app (no rebuild)
open:
    open /Applications/Mytty.app

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

# Clean all build artifacts including libghostty
clean-all: clean
    rm -rf vendor/ghostty/zig-out vendor/ghostty/.zig-cache vendor/ghostty/macos/GhosttyKit.xcframework

# Build libghostty from the vendored submodule (requires nix)
build-libghostty:
    #!/usr/bin/env bash
    set -euo pipefail
    nix develop --command bash -c "cd vendor/ghostty && DEVELOPER_DIR={{DEVELOPER_DIR}} zig build -Dapp-runtime=none -Demit-xcframework=true -Demit-macos-app=false -Doptimize=ReleaseFast"
    # HACK: Zig-produced .o files are not 8-byte aligned, causing Apple's
    #   libtool to silently drop them. Rebuild the xcframework library from
    #   all arm64 static libs in the zig cache.
    #   Remove after Zig fixes object alignment
    #   (https://github.com/ziglang/zig/issues/22292) or Ghostty switches to ar.
    just _fix-xcframework

# Enter the nix dev shell
dev:
    nix develop

# Initialize submodules (first-time setup)
setup:
    git submodule update --init --recursive
    @echo "Now run 'just build-libghostty' to build libghostty"

# Install git hooks (format + lint on commit)
install-hooks:
    cp scripts/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    @echo "Pre-commit hook installed."

# Format Swift code
fmt-swift:
    swift format --in-place --recursive Mytty/ MyttyTests/ MyttyCLI/ MyttyShared/

# Check formatting without modifying
fmt-check:
    swift format --recursive Mytty/ MyttyTests/ MyttyCLI/ MyttyShared/

# Lint Swift code
lint:
    swiftlint lint --quiet

# Lint and auto-fix Swift code
lint-fix:
    swiftlint lint --fix --quiet

# Lint Swift code (strict: warnings are errors)
lint-strict:
    swiftlint lint --quiet --strict

# Lint shell scripts
shellcheck:
    shellcheck scripts/*

# Check nix formatting
nix-fmt-check:
    nix fmt -- --check flake.nix

# Format nix files
nix-fmt:
    nix fmt flake.nix

# Format all code (Swift + Nix)
fmt-all: fmt-swift nix-fmt

# Format all code
fmt: fmt-all

# Pre-commit check: format, lint, test
check: fmt-check lint shellcheck verify-cli-ref test

# CI pipeline: format check, strict lint, build, test, typos
ci: fmt-check nix-fmt-check lint-strict shellcheck build verify-cli-ref test
    typos

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

# Rebuild xcframework library from zig-cache static libs (workaround for libtool alignment bug)
[private]
_fix-xcframework:
    #!/usr/bin/env bash
    set -euo pipefail
    xcfw="vendor/ghostty/macos/GhosttyKit.xcframework/macos-arm64_x86_64"
    if [ ! -d "$xcfw" ]; then
      echo "No universal xcframework found, skipping fixup"
      exit 0
    fi
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    # HACK: Apple's libtool silently drops Zig-produced .o files that aren't
    #   8-byte aligned. Recombine all macOS static libs with zig's ar (LLVM)
    #   using an MRI script to flatten archives.
    #   Remove after Zig fixes object alignment
    #   (https://github.com/ziglang/zig/issues/22292) or Ghostty switches to ar.
    shopt -s nullglob
    for arch in arm64 x86_64; do
      mri="CREATE $tmp/$arch.a"$'\n'
      count=0
      for f in vendor/ghostty/.zig-cache/o/*/lib*.a; do
        [[ "$f" == *"-fat.a" ]] && continue
        got_arch=$(lipo -info "$f" 2>/dev/null | grep -oE "${arch}$" || true)
        [ "$got_arch" != "$arch" ] && continue
        plat=$(otool -l "$f" 2>/dev/null | grep -A 2 "LC_BUILD_VERSION" | grep "platform" | head -1 | awk '{print $2}')
        [ "$plat" = "1" ] || continue
        absf="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
        mri+="ADDLIB $absf"$'\n'
        count=$((count+1))
      done
      if [ "$count" -eq 0 ]; then
        echo "error: no $arch macOS libraries found in zig cache" >&2
        exit 1
      fi
      mri+="SAVE"$'\n'"END"$'\n'
      echo "$mri" | nix develop --command zig ar -M
    done
    lipo -create "$tmp/arm64.a" "$tmp/x86_64.a" -output "$xcfw/libghostty.a"
    count=$(nm "$xcfw/libghostty.a" | grep -c ' T _ghostty' || echo 0)
    echo "xcframework library rebuilt ($count ghostty symbols)"
