{
    description = "Flake para rodar os testes.";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
        experiments.url = "github:Sacolle/experiments-nix"; 

        star-fletcher = {
            url = "github:Sacolle/Star-Fletcher?ref=CUDA";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        fletcher-base = {
          url = "github:Sacolle/fletcher-base";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        nix-gl-host = {
            url = "github:numtide/nix-gl-host";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        nixpkgs24.url = "github:nixos/nixpkgs/1da52dd49a127ad74486b135898da2cef8c62665";
    };
    outputs = { self, nixpkgs, experiments, star-fletcher, fletcher-base, nix-gl-host, nixpkgs24 }: 
    let
        system = "x86_64-linux"; 
        pkgs = import nixpkgs { inherit system; };
        pkgs24 = import nixpkgs24 { inherit system; config.allowUnfree = true; };

        mk-scratch-folder = name: "$SCRATCH/${name}/$HOSTNAME";
        mk-home-folder = name: "~/experimental-results/${name}/$HOSTNAME";
        tail1 = s: builtins.substring 1 (-1) s;

        nixglhost = "${nix-gl-host.defaultPackage.${system}}/bin/nixglhost";

        # TODO:
        # 1. add the fletcher-code
        #    - [ ] insturment the ENABLE_IO
        #    - [ ] check if it runs on cidia
        #    - [ ] get which parameters are used to set name, io and output time

        fletcher-base-experiment =
          let
            my-fletcher-base = fletcher-base.packages.${system}.default;
            program = "${my-fletcher-base}/bin/fletcher-base";
            experiment-name = "fletcher-base-max-size";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
            experiments.lib.mkExperiment {
              inherit pkgs;

            
              csvFile = ./base-test.csv;


              preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
                '';

              bashRunFn = { 
                WithIO,
                Blocks,
                Width,
                AbsorbSize,
                BorderSize,
                TotalTime,
                TimeStep,
                OutputTime,
                  ...
              }: 
              let
                filename = "${WithIO}-${tail1 Blocks}";
                stdout-file = "${scratch-folder}/stdout-${filename}.out";
                rsf-file = "${scratch-folder}/out-${filename}.rsf";
                rsf-at-file = "${rsf-file}@";
            in
            ''
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=${WithIO} \
                ${nixglhost} ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${OutputTime} 2>&1 > ${stdout-file}

                cat ${stdout-file}

                rm ${rsf-file} ${rsf-at-file}

                cp ${stdout-file} ${home-folder}
            '';
          };

        
        experimentScriptBase = options:
          let
            my-star-fletcher = star-fletcher.packages.${system}.default.override ({
                cudaPackages = pkgs24.cudaPackages_12_2;
                stdenv = pkgs24.gcc12Stdenv;
                enableCUDA = true;
                enableTrace = false;
                compileAsRelease = true;
            } // options);
            program = "${my-star-fletcher}/bin/star-fletcher";

            experiment-name = "ideal-block-size-machine";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
          experiments.lib.mkExperiment {
            inherit pkgs; 
            
            csvFile = ./ideal-block-segment.csv;

            preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
            '';
            
            bashRunFn = { 
                WithIO,
                BlockSeg,
                Schedulers,
                Blocks,
                Width,
                AbsorbSize,
                BorderSize,
                TotalTime,
                TimeStep,
                OutputTime,
                ...
            }: 
              let
                filename = "${Schedulers}-${BlockSeg}-${WithIO}-${tail1 Blocks}";
                stdout-file = "${scratch-folder}/stdout-${filename}.out";
                rsf-file = "${scratch-folder}/out-${filename}.rsf";
                rsf-at-file = "${rsf-file}@";
            in
# STARPU_SCHED=${Schedulers} \
            ''
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=${WithIO} \
                ${nixglhost} ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${BlockSeg} ${OutputTime} 2>&1 > ${stdout-file}

                cat ${stdout-file}

                rm ${rsf-file} ${rsf-at-file}

                cp ${stdout-file} ${home-folder}
            '';
          };
        experiment-using-cuda-12-2 = experimentScriptBase {};
        experiment-using-cuda-12-4 = experimentScriptBase {
          cudaPackages = pkgs24.cudaPackages_12_4;
          stdenv = pkgs24.gcc13Stdenv;
        };
    in
    {
      packages.${system}.default = experiment-using-cuda-12-2;
      inherit experiment-using-cuda-12-2 experiment-using-cuda-12-4;
    };
}
