{
  description = "simple html page";

  # Nixpkgs / NixOS version to use.
  # inputs.nixpkgs.url = "nixpkgs/nixos-unstable";

  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let

      # System types to support.
      supportedSystems =
        [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        });
    in
    {

      # A Nixpkgs overlay.
      overlays.default = final: prev: {
        mc3000 = with final;

          stdenv.mkDerivation rec {
            name = "mc3000";

            unpackPhase = ":";
            src = ./.;

            # buildPhase = '' '';

            installPhase =
              ''
                mkdir -p $out
                cp $src/index.html $out/index.html
              '';
          };
      };

      # Package
      packages = forAllSystems (system: {
        inherit (nixpkgsFor.${system}) mc3000;
        default = self.packages.${system}.mc3000;
      });

      # Nixos module
      nixosModules.mc3000 = { pkgs, lib, config, ... }:
        with lib;
        let cfg = config.services.mc3000;
        in {

          # Optios for configuration
          options.services.mc3000.enable = mkEnableOption "mc3000 page";

          config = mkIf cfg.enable {
            nixpkgs.overlays = [ self.overlays.default ];

            services.nginx = {
              enable = true;
              virtualHosts."server" = {
                root = pkgs.mc3000;
              };
            };
          };
        };


      # Tests run by 'nix flake check' and by Hydra.
      checks = forAllSystems
        (system:
          with nixpkgsFor.${system};


          lib.optionalAttrs stdenv.isLinux {
            # A VM test of the NixOS module.
            vmTest =
              with import (nixpkgs + "/nixos/lib/testing-python.nix")
                {
                  inherit system;
                };

              (makeTest {
                name = "mc3000-test";
                nodes = {
                  server = {
                    imports = [ self.nixosModules.mc3000 ];

                    services.mc3000.enable = true;

                    networking.firewall = {
                      enable = true;
                      allowPing = true;
                      allowedTCPPorts = [ 80 ];
                    };
                  };
                  client = { };
                };

                testScript =
                  ''
                    start_all()
                    client.wait_for_unit("multi-user.target")
                    server.wait_for_unit("multi-user.target")
                    server.wait_for_open_port(80)
                    client.succeed("curl -sSfL http://server:80", timeout=5)
                  '';
              }).test;
          }
        );
    };
}
