{
    description = "Flake para rodar os testes de análise do kernel.";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
        experiments.url = "github:Sacolle/experiments-nix"; 
        flake-utils.url = "github:numtide/flake-utils";

        nix-gl-host = {
            url = "github:numtide/nix-gl-host";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        star-fletcher = {
            url = "github:Sacolle/Star-Fletcher?ref=kernel-opt";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };
    outputs = { self, nixpkgs, experiments, flake-utils, nix-gl-host, star-fletcher  }: 
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
    let
        pkgs = import nixpkgs { inherit system; };
    
        kernel-test = star-fletcher.packages.${system}.kernel-test.overrideAttrs { doCheck = false; } ;
        nixglhost = "${nix-gl-host.defaultPackage.${system}}/bin/nixglhost";

        mk-scratch-folder = name: "$SCRATCH/${name}/$HOSTNAME";
        mk-home-folder = name: "~/experimental-results/${name}/$HOSTNAME";

        kernel-func = file:  
          let
            program = "${kernel-test}/bin/kernel-test";
            experiment-name = "fletcher-kernel-analysis";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
          experiments.lib.mkExperiment {
            inherit pkgs; 
            
            csvFile = file;

            preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
            '';
            
            bashRunFn = { ThreadX, ThreadY, ThreadZ, BlockSize, Blocks, BlockCount, Iterations, TotalThreads }: 
              let
                filename = "${ThreadX}-${ThreadY}-${ThreadZ}-${BlockSize}-${Blocks}";
                stdout-file = "${scratch-folder}/stdout-${filename}.out";
            in
            ''
                ${nixglhost} ${program} ${BlockCount} ${BlockSize} ${Iterations} ${ThreadX} ${ThreadY} ${ThreadZ} 2>&1 > ${stdout-file}
                cat ${stdout-file}
                cp ${stdout-file} ${home-folder}
            '';
          };
    in
    {
        packages = {
          kernel-base = kernel-func ./kernel-params.csv;
          kernel-full = kernel-func ./kernel-params-full.csv;
        };
    });
}
