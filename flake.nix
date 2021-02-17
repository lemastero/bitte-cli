{
  description = "Bitte fläken Sie sich";

  inputs = {
    crystal.url = "github:kreisys/crystal";
    utils.url = "github:kreisys/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
    rust.url = "github:input-output-hk/rust.nix/work";
    rust.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, devshell, crystal, rust, utils, ... }:
    utils.lib.simpleFlake {
      inherit nixpkgs;

      systems = [ "x86_64-darwin" "x86_64-linux" ];

      preOverlays = [
        crystal
        rust
        devshell
        (final: prev: {
          crystal = if final.stdenv.isDarwin then
            prev.crystal
          else
            nixpkgs.legacyPackages.x86_64-linux.crystal;
        })
      ];

      overlay = final: prev: {
        inherit (final.callPackages ./shards { }) shards;

        nixos-rebuild = prev.nixos-rebuild.overrideAttrs (o: {
          src = final.runCommand "nixos-rebuild.sh" { inherit (o) src; } ''
            substitute $src $out \
            --replace systemctl false
          '';
        });

        bitte-kristall = final.callPackage ./package.nix { };
        bitte-rost = with builtins; final.rust-nix.buildPackage {
          # Without this we end up with a drv called `rust-workspace-unknown`
          # which makes `nix run` try to execute a bin with that name.
          inherit ((fromTOML (readFile ./rust/Cargo.toml)).package)
            name version;
          root = self;
          buildInputs = with final; [ pkg-config openssl ];
        };
        bitte = final.bitte-rost;
      };

      packages = { bitte-kristall, bitte-rost }: {
        inherit bitte-kristall bitte-rost;
        defaultPackage = bitte-rost;
      };

      hydraJobs = { bitte-kristall, bitte-rost }@ps: ps;

      devShell = { devshell, pkgs }: devshell.mkShell {
        env = {
          RUST_SRC_PATH = pkgs.rustPlatform.rustLibSrc;
          RUST_BACKTRACE = 1;
        };

        packages = with pkgs; [
          nixFlakes
          pkgs.crystal
          crystal2nix
          shards
          libssh2
          cfssl
          sops
          openssl
          pkg-config

          # Rust
          rustc
          cargo
          (rustracer.overrideAttrs (_: { checkPhase = null; }))
          rust-analyzer
          rustfmt
          clippy
        ];
      };
    };
}
