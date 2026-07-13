{
  description = "Flake para gerar projeto experimental e fazer o latex";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=26.05";
    #starvz.url = "github:schnorr/starvz";
    #starpu.url = "github:Sacolle/nix-starpu";
  };
  outputs = { self, /* starvz, starpu, */ nixpkgs }: 
      let 
        system = "x86_64-linux";
        pkgs = import nixpkgs { inherit system; };
        rEnv = pkgs.rWrapper.override {
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
                #starvz.packages.${system}.starvz
            ];
        };
        /*
        StarPU = starpu.packages.${system}.default.override {
            enableCUDA = false;
            enableTrace = true;
            extraOptions = [ "--enable-maxcpus=256" "--enable-fxt-max-files=256" ];
        };
        myStarvzTools = starvz.packages.${system}.starvzTools.override {
            inherit StarPU;
        };*/
    in 
  {
        devShells.${system}.default = pkgs.mkShell { 
            buildInputs =  [ 
                rEnv 
                #myStarvzTools
            ]; 
        };
  };
}
