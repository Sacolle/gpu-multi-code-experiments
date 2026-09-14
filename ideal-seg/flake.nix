{
    description = "Flake para rodar os testes.";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
        experiments.url = "github:Sacolle/experiments-nix"; 
        flake-utils.url = "github:numtide/flake-utils";

        star-fletcher = {
            url = "github:Sacolle/Star-Fletcher?ref=CUDA";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        StarPU = {
            url = "github:Sacolle/nix-starpu";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        star-fletcher-main = {
            url = "github:Sacolle/star-fletcher";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        fletcher-base = {
          url = "github:Sacolle/fletcher-base?dir=original";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        nix-gl-host = {
            url = "github:numtide/nix-gl-host";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        nixpkgs24.url = "github:nixos/nixpkgs/1da52dd49a127ad74486b135898da2cef8c62665";
    };
    outputs = { self, nixpkgs, experiments, flake-utils, star-fletcher, StarPU, star-fletcher-main, fletcher-base, nix-gl-host, nixpkgs24 }: 
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
    let
        pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
        pkgs24 = import nixpkgs24 { inherit system; config.allowUnfree = true; };

        mk-scratch-folder = name: "$SCRATCH/${name}/$HOSTNAME";
        mk-home-folder = name: "~/experimental-results/${name}/$HOSTNAME";
        tail1 = s: builtins.substring 1 (-1) s;

        nixglhost = "${nix-gl-host.defaultPackage.${system}}/bin/nixglhost";

        fletcher-base-experiment =
          let
            my-fletcher-base = fletcher-base.packages.${system}.default.override {
              
            };
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
                rsf-file = "${scratch-folder}/${filename}.rsf";
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

        no-cpu-msamples = 
          let
            my-star-fletcher = star-fletcher.packages.${system}.default.override {
                cudaPackages = pkgs24.cudaPackages_12_2;
                stdenv = pkgs24.gcc12Stdenv;
                enableCUDA = true;
                enableTrace = false;
                disableCPUKernel = true;
                compileAsRelease = true;
            };
            program = "${my-star-fletcher}/bin/star-fletcher";
            experiment-name = "ideal-block-size-machine-no-cpu-msamples";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
          experiments.lib.mkExperiment {
            inherit pkgs; 
            
            csvFile = ./ideal-block-segment-no-cpu-trace.csv;

            preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
            '';
            
            bashRunFn = { BlockSeg, Schedulers, Width, AbsorbSize, TotalTime, TimeStep, OutputTime, ... }: 
              let

                filename = "${Schedulers}-${BlockSeg}";
                stdout-file = "${scratch-folder}/stdout-${filename}.out";
                rsf-file = "${scratch-folder}/out-${filename}.rsf";
                rsf-at-file = "${rsf-file}@";
            in
            ''
                STARPU_SCHED=${Schedulers} \
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=0 \
                ${nixglhost} ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${BlockSeg} ${OutputTime} 2>&1 > ${stdout-file}

                cat ${stdout-file}

                rm ${rsf-file} ${rsf-at-file}

                cp ${stdout-file} ${home-folder}
            '';
          };

        trace-no-cpu = 
          let
            my-star-fletcher = star-fletcher.packages.${system}.default.override {
                cudaPackages = pkgs24.cudaPackages_12_2;
                stdenv = pkgs24.gcc12Stdenv;
                enableCUDA = true;
                enableTrace = true;
                disableCPUKernel = true;
                compileAsRelease = true;
            };
            program = "${my-star-fletcher}/bin/star-fletcher";
            experiment-name = "ideal-block-size-machine-no-cpu";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
          experiments.lib.mkExperiment {
            inherit pkgs; 
            
            csvFile = ./ideal-block-segment-no-cpu-trace.csv;

            preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
            '';
            
            bashRunFn = { BlockSeg, Schedulers, Width, AbsorbSize, TotalTime, TimeStep, OutputTime, ... }: 
              let

                filename = "${Schedulers}-${BlockSeg}";
                stdout-file = "${scratch-folder}/stdout-${filename}.out";
                rsf-file = "${scratch-folder}/out-${filename}.rsf";
                rsf-at-file = "${rsf-file}@";
                prof-name = "prof_file_${filename}";
		prof-file = "${scratch-folder}/${prof-name}_0";
            in
            ''
                STARPU_TRACE_BUFFER_SIZE=4096 \
                STARPU_FXT_TRACE=1 \
                STARPU_FXT_PREFIX=${scratch-folder} \
                STARPU_FXT_SUFFIX=${prof-name} \
                STARPU_SCHED=${Schedulers} \
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=0 \
                ${nixglhost} ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${BlockSeg} ${OutputTime} 2>&1 > ${stdout-file}

                cat ${stdout-file}

                rm ${rsf-file} ${rsf-at-file}

                cp ${stdout-file} ${home-folder}
                cp ${prof-file} ${home-folder}
            '';
          };

        
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
            ''
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
            '';
          };
        experiment-using-cuda-12-2 = experimentScriptBase "ideal-block-size-machine-12-2" {};
        experiment-using-cuda-12-4 = experimentScriptBase "ideal-block-size-machine-12-4"{
            cudaPackages = pkgs24.cudaPackages_12_4;
            stdenv = pkgs24.gcc13Stdenv;
        };

        exp-optimized-kernel = file: options: 
          let
            my-star-fletcher = star-fletcher-main.packages.${system}.default.override ({
                cudaPackages = pkgs24.cudaPackages_12_2;
                stdenv = pkgs24.gcc12Stdenv;
                enableCUDA = true;
                enableTrace = false;
                compileAsRelease = true;
            } // options);
            program = "${my-star-fletcher}/bin/star-fletcher";

            experiment-name = "experiment-optimized-kernel";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
          experiments.lib.mkExperiment {
            inherit pkgs; 
            
            csvFile = file;

            preamble = ''
                nvidia-smi
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
            '';
            
            bashRunFn = { 
              WithIO, Schedulers, Blocks,
                ThreadX,ThreadY,ThreadZ,
                BlockSeg,Width,AbsorbSize,
                TotalTime,TimeStep,OutputTime,
                ...
            }: 
              let
                filename = "${Schedulers}-${BlockSeg}-${WithIO}-${ThreadX}-${ThreadY}-${ThreadZ}-${Blocks}";
                stdout-file = "${scratch-folder}/stdout-${filename}.out";
                rsf-file = "${scratch-folder}/out-${filename}.rsf";
                rsf-at-file = "${rsf-file}@";
            in
              ''
                CUDA_THREAD_X=${ThreadX} \
                CUDA_THREAD_Y=${ThreadY} \
                CUDA_THREAD_Z=${ThreadZ} \
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
            '';
          };
    in
    {
        packages = {
          exp-optimized-kernel-cidia = exp-optimized-kernel ./from-kernel-exp-cidia.csv {};
          exp-optimized-kernel-poti = exp-optimized-kernel ./from-kernel-exp-poti.csv {};
          exp-optimized-kernel-tupi = exp-optimized-kernel ./from-kernel-exp-tupi.csv {};
          exp-optimized-kernel-grace = exp-optimized-kernel ./from-kernel-exp-grace.csv {
            cudaPackages = pkgs.cudaPackages_12_8;
            stdenv = pkgs.gcc13Stdenv;
            # disable tests on the aarch machines
            StarPU = StarPU.packages.${system}.default.overrideAttrs { doCheck = false; } ;
          };
          inherit
            experiment-using-cuda-12-2
            experiment-using-cuda-12-4
            fletcher-base-experiment
            trace-no-cpu
            no-cpu-msamples
          ;
        };
    });
}
