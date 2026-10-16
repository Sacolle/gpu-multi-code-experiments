{
    description = "Flake para gerar os perfmodels.";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
        experiments.url = "github:Sacolle/experiments-nix"; 
        flake-utils.url = "github:numtide/flake-utils";

        StarPU = {
            url = "github:Sacolle/nix-starpu";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        star-fletcher = {
            url = "github:Sacolle/star-fletcher";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        nix-gl-host = {
            url = "github:numtide/nix-gl-host";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        nixpkgs24.url = "github:nixos/nixpkgs/1da52dd49a127ad74486b135898da2cef8c62665";
    };
    outputs = { self, nixpkgs, experiments, flake-utils, star-fletcher, StarPU, nix-gl-host, nixpkgs24 }: 
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
    let
        pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
        pkgs24 = import nixpkgs24 { inherit system; config.allowUnfree = true; };

        mk-scratch-folder = name: "$SCRATCH/${name}/$HOSTNAME";
        mk-home-folder = name: "~/experimental-results/${name}/$HOSTNAME";

        nixglhost = "${nix-gl-host.defaultPackage.${system}}/bin/nixglhost";

        tail1 = s: builtins.substring 1 (-1) s;

        experimentScriptBase = name: options: 
          let
            my-star-fletcher = star-fletcher.packages.${system}.default.override ({
                cudaPackages = pkgs24.cudaPackages_12_2;
                stdenv = pkgs24.gcc12Stdenv;
                enableCUDA = true;
                enableTrace = false;
                compileAsRelease = true;
            } // options);
            program = "${my-star-fletcher}/bin/star-fletcher";

            experiment-name = name;
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
          experiments.lib.mkExperiment {
            inherit pkgs; 
            
            csvFile = ./perf-model-sampler.csv;

            preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
                # start from empty perfmodels; replications accumulate into them during the run
                rm -rf ${scratch-folder}/perfmodel-*
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
                # one perfmodel dir per config, shared by all replications (Blocks)
                perfmodel-name = "perfmodel-${Schedulers}-${BlockSeg}-${WithIO}";
                perfmodel-dir = "${scratch-folder}/${perfmodel-name}";
            in
            ''
                mkdir -p ${perfmodel-dir}

                STARPU_PERF_MODEL_DIR=${perfmodel-dir} \
                STARPU_CALIBRATE=1 \
                STARPU_SCHED=${Schedulers} \
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=${WithIO} \
                ${nixglhost} ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${BlockSeg} ${OutputTime} 2>&1 > ${stdout-file}

                cat ${stdout-file}

                rm ${rsf-file} ${rsf-at-file}

                cp ${stdout-file} ${home-folder}
                tar -czf ${home-folder}/${perfmodel-name}.tar.gz -C ${scratch-folder} ${perfmodel-name}
            '';
          };
        experiment-using-cuda-12-2 = experimentScriptBase "perf-model-12-2" {};
        experiment-using-cuda-12-4 = experimentScriptBase "perf-model-12-4"{
            cudaPackages = pkgs24.cudaPackages_12_4;
            stdenv = pkgs24.gcc13Stdenv;
        };
        experiment-using-cuda-13 = experimentScriptBase "perf-model-13"{
            cudaPackages = pkgs.cudaPackages_13_0;
            stdenv = pkgs.gcc15Stdenv;
        };

    in
    {
        packages = {
          inherit
            experiment-using-cuda-12-2
            experiment-using-cuda-12-4
            experiment-using-cuda-13
          ;
        };
    });
}
