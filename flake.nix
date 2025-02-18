{
  description = "Kubernetes resource builder using nix";

  inputs = {
    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;

    flake-utils.url = "github:numtide/flake-utils";
    flake-utils.inputs.nixpkgs.follows = "nixpgks";

    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs:
    (inputs.flake-utils.lib.eachSystem ["x86_64-linux"] (
      #inputs.flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import inputs.nixpkgs {
          overlays = [
            self.overlays.default
            inputs.devshell.overlay
          ];
          config.allowUnsupportedSystem = true;
          inherit system;
        };

        inherit (pkgs) lib;

        kubenix = {
          lib = import ./lib {inherit lib pkgs;};
          evalModules = self.evalModules.${system};
          modules = self.nixosModules.kubenix;
        };

        # evalModules with same interface as lib.evalModules and kubenix as
        # special argument
        evalModules = attrs @ {
          module ? null,
          modules ? [module],
          ...
        }: let
          lib' = lib.extend (lib: _self: import ./lib/upstreamables.nix {inherit lib pkgs;});
          attrs' = builtins.removeAttrs attrs ["module"];
        in
          lib'.evalModules (lib.recursiveUpdate
            {
              modules =
                modules
                ++ [
                  {
                    config._module.args = {
                      inherit pkgs;
                      name = "default";
                    };
                  }
                ];
              specialArgs = {inherit kubenix;
                             inherit pkgs;
                            };
            }
            attrs');
      in {
        inherit evalModules pkgs;

        jobs = import ./jobs {inherit pkgs;};

        devShells.default = import ./devshell {inherit pkgs inputs;};

        packages = inputs.flake-utils.lib.flattenTree {
          inherit (pkgs) kubernetes kubectl;
        };

        checks = let
          wasSuccess = suite:
            if suite.success
            then pkgs.runCommandNoCC "testing-suite-config-assertions-for-${suite.name}-succeeded" {} "echo success > $out"
            else pkgs.runCommandNoCC "testing-suite-config-assertions-for-${suite.name}-failed" {} "exit 1";
          mkExamples = attrs:
            (import ./examples {inherit evalModules;})
            ({registry = "docker.io/gatehub";} // attrs);
          mkK8STests = attrs:
            (import ./tests {inherit evalModules;})
            ({registry = "docker.io/gatehub";} // attrs);
        in {
          # TODO: access "success" derivation with nice testing utils for nice output
          nginx-example = wasSuccess (mkExamples {}).nginx-deployment.config.testing;
          tests-k8s-1_19 = wasSuccess (mkK8STests {k8sVersion = "1.19";});
          tests-k8s-1_20 = wasSuccess (mkK8STests {k8sVersion = "1.20";});
          tests-k8s-1_21 = wasSuccess (mkK8STests {k8sVersion = "1.21";});
          tests-k8s-1_23 = wasSuccess (mkK8STests {k8sVersion = "1.23";});
        };
      }
    ))
    // {
      nixosModules.kubenix = import ./modules;
      overlays.default = _final: prev: {
        kubenix.evalModules = self.evalModules.${prev.system};
        # up to date versions of their nixpkgs equivalents
        # kubernetes =
        #   prev.callPackage ./pkgs/applications/networking/cluster/kubernetes
        #   {};
        # kubectl = prev.callPackage ./pkgs/applications/networking/cluster/kubectl {};
      };
    };
}
