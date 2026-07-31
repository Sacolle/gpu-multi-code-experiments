{
  description = "Flake para gerar projeto experimental e fazer o latex";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=26.05";
    starvz.url = "github:schnorr/starvz";
    starpu.url = "github:Sacolle/nix-starpu";
  };
  outputs = { self, starvz, starpu, nixpkgs }: 
      let 
        system = "x86_64-linux";
        pkgs = import nixpkgs { 
            inherit system; 
            config.allowUnfree = true;
        };
        rEnv = extra: pkgs.rWrapper.override {
            packages = with pkgs.rPackages; [
                languageserver
                numbers
                lintr
                here
                DoE_base
                FrF2
                tidyverse
                janitor
                patchwork
            ] ++ extra;
        };
        StarPU = starpu.packages.${system}.default.override {
            enableCUDA = true;
            compileAsRelease = true;
            enableTrace = true;
            cudaPackages = pkgs.cudaPackages;
            extraOptions = [ "--enable-maxcpus=256" "--enable-fxt-max-files=256" ];
        };
        myStarvzTools = starvz.packages.${system}.starvzTools.override {
            inherit StarPU;
        };
    in 
  {
        devShells.${system} = {
            default = pkgs.mkShell { 
                buildInputs =  [ 
                    (rEnv [ starvz.packages.${system}.starvz ])
                    myStarvzTools
                ]; 
            };
            simple = pkgs.mkShell { 
                buildInputs =  [ (rEnv [ ]) ]; 
            };
        };
  };
}
