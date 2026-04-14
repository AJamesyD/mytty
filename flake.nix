{
  description = "Mistty - macOS terminal emulator built on libghostty";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    zig,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      # Ghostty requires Zig 0.15.2 -- keep in sync with vendor/ghostty/flake.nix
      zigPkg = zig.packages.${system}."0.15.2";
    in {
      devShells.default = pkgs.mkShellNoCC {
        name = "mistty-dev";

        packages = [
          zigPkg
          pkgs.git
          pkgs.xcodes
          pkgs.aria2
          pkgs.zls
          pkgs.swiftlint
        ];

        shellHook = ''
          # Use system Xcode SDK, not Nix-provided one (same as Ghostty's devShell)
          unset SDKROOT
          unset DEVELOPER_DIR
          export PATH=$(echo "$PATH" | awk -v RS=: -v ORS=: '$0 !~ /xcrun/ || $0 == "/usr/bin" {print}' | sed 's/:$//')

          # Add Xcode toolchain to PATH for sourcekit-lsp and swift-format
          XCODE_TOOLCHAIN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin"
          if [ -d "$XCODE_TOOLCHAIN" ]; then
            export PATH="$XCODE_TOOLCHAIN:$PATH"
          fi

          echo "Mistty dev environment"
          echo "Zig: $(zig version)"
        '';
      };

      formatter = pkgs.alejandra;
    });
}
