{
  description = "Mytty - macOS terminal emulator built on libghostty";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.git-hooks-nix.flakeModule ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        {
          config,
          system,
          pkgs,
          ...
        }:
        let
          # Ghostty requires Zig 0.15.2 -- keep in sync with vendor/ghostty/flake.nix
          zigPkg = inputs.zig.packages.${system}."0.15.2";

          periphery = pkgs.stdenvNoCC.mkDerivation rec {
            pname = "periphery";
            version = "3.7.4";

            src = pkgs.fetchurl {
              url = "https://github.com/peripheryapp/periphery/releases/download/${version}/periphery-${version}.zip";
              hash = "sha256-+CgyOagsY4pNXPuRxCUZmARit4UymVYvZj6zPOVMjcY=";
            };

            nativeBuildInputs = [ pkgs.unzip ];
            sourceRoot = ".";

            installPhase = ''
              install -Dm755 periphery $out/bin/periphery
            '';

            meta = {
              description = "Identify unused code in Swift projects";
              homepage = "https://github.com/peripheryapp/periphery";
              platforms = [
                "aarch64-darwin"
                "x86_64-darwin"
              ];
            };
          };
        in
        {
          formatter = pkgs.nixfmt;

          # Disable pre-commit check in nix flake check (Swift not available in Nix sandbox)
          pre-commit.check.enable = false;

          pre-commit.settings.hooks = {
            nixfmt.enable = true;

            swift-format = {
              enable = true;
              name = "swift-format";
              entry = "swift format lint --strict --parallel";
              types = [ "swift" ];
              # Package.swift uses Xcode's 4-space indent convention, not project's 2-space
              excludes = [ "Package\\.swift$" ];
              pass_filenames = true;
            };

            # Errors block, warnings print but don't block
            swiftlint = {
              enable = true;
              name = "swiftlint";
              entry = "swiftlint lint --quiet";
              types = [ "swift" ];
              pass_filenames = true;
            };

            shfmt = {
              enable = true;
              name = "shfmt";
              entry = "shfmt -d";
              types = [ "shell" ];
              # .envrc uses direnv builtins (use flake, watch_file) that shfmt misparses
              excludes = [ "\\.envrc$" ];
              pass_filenames = true;
            };

            shellcheck = {
              enable = true;
              name = "shellcheck";
              entry = "shellcheck";
              types = [ "shell" ];
              pass_filenames = true;
            };

            # Warn on typos but don't block commits
            typos = {
              enable = true;
              name = "typos";
              entry = "bash -c 'typos \"$@\" || true' --";
              types_or = [
                "swift"
                "shell"
                "nix"
                "toml"
              ];
              pass_filenames = true;
            };

            # Pre-push: strict lint + tests
            swiftlint-strict = {
              enable = true;
              name = "swiftlint-strict";
              entry = "swiftlint lint --quiet --strict";
              types = [ "swift" ];
              pass_filenames = false;
              stages = [ "pre-push" ];
            };

            tests = {
              enable = false;
              name = "tests";
              entry = "just test";
              pass_filenames = false;
              stages = [ "pre-push" ];
              always_run = true;
            };
          };

          devShells.default = pkgs.mkShellNoCC {
            name = "mytty-dev";

            packages = [
              zigPkg
              pkgs.git
              pkgs.just
              pkgs.jq
              pkgs.shellcheck
              pkgs.shfmt
              pkgs.zls
              pkgs.swiftlint
              pkgs.typos
              pkgs.git-cliff
              pkgs.create-dmg
              periphery
            ];

            shellHook =
              # bash
              ''
                # Use system Xcode SDK, not Nix-provided one
                export SDKROOT="$(/usr/bin/xcrun --show-sdk-path)"
                export PATH=$(echo "$PATH" | awk -v RS=: -v ORS=: '$0 !~ /xcrun/ || $0 == "/usr/bin" {print}' | sed 's/:$//')

                # Add Xcode toolchain to PATH for sourcekit-lsp and swift-format
                XCODE_TOOLCHAIN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin"
                if [ -d "$XCODE_TOOLCHAIN" ]; then
                	export PATH="$XCODE_TOOLCHAIN:$PATH"
                fi

                echo "Mytty dev environment"
                echo "Zig: $(zig version)"

                ${config.pre-commit.installationScript}
              '';
          };
        };
    };
}
