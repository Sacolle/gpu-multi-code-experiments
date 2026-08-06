{
    description = "Flake para rodar os testes para o sscad.";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
        experiments.url = "github:Sacolle/experiments-nix"; 
	StarPU = {
            url = "github:Sacolle/nix-starpu";
            inputs.nixpkgs.follows = "nixpkgs";
	};
        star-fletcher = {
            url = "github:Sacolle/Star-Fletcher?ref=CUDA";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        fletcher-base = {
          url = "github:Sacolle/fletcher-base?dir=original";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        flake-utils.url = "github:numtide/flake-utils";
    };
    outputs = { self, nixpkgs, experiments, StarPU, star-fletcher, fletcher-base,  flake-utils }: 
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
    let
        pkgs = import nixpkgs { inherit system; };

        my-fletcher-base = fletcher-base.packages.${system}.default.override {
            CUDAbackend = false;
            OpenMPbackend = true;
            OpenACCbackend = false;
        };

        starpu-no-check = StarPU.packages.${system}.default.overrideAttrs {
            doCheck = false;
        };

        my-star-fletcher = star-fletcher.packages.${system}.default.override {
            enableCUDA = false;
            enableTrace = false;
            compileAsRelease = true;
            enableVerbose = false;
            stdenv = pkgs.gcc13Stdenv;
            StarPU = starpu-no-check;
        };

        mk-scratch-folder = name: "$SCRATCH/${name}/$HOSTNAME";
        mk-home-folder = name: "~/experimental-results/${name}/$HOSTNAME";
        tail1 = s: builtins.substring 1 (-1) s;

        fletcher-base-cpu =
          let
            program = "${my-fletcher-base}/bin/fletcher-base";
            experiment-name = "fletcher-base-cpu-fix-size";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
            experiments.lib.mkExperiment {
              inherit pkgs;

              csvFile = ./fletcher-base-fix-size.csv;

              preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
                '';

              bashRunFn = {
                WithIO, Blocks, Width, AbsorbSize, TotalTime, TimeStep, OutputTime
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
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${OutputTime} 2>&1 > ${stdout-file}

                cat ${stdout-file}
                ${if WithIO == "1" then "rm ${rsf-file} ${rsf-at-file}" else ""}
                cp ${stdout-file} ${home-folder}
            '';
          };

        fletcher-base-cpu-p-core = name: config:
          let
            program = "${my-fletcher-base}/bin/fletcher-base";
            experiment-name = name;
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
            experiments.lib.mkExperiment {
              inherit pkgs;

              csvFile = ./fletcher-base-fix-size.csv;

              preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
                '';

              bashRunFn = { WithIO, Blocks, Width, AbsorbSize, TotalTime, TimeStep, OutputTime }: 
              let
                filename = "${WithIO}-${tail1 Blocks}";
                stdout-file = "${scratch-folder}/stdout-${filename}.out";
                rsf-file = "${scratch-folder}/${filename}.rsf";
                rsf-at-file = "${rsf-file}@";
            in
              ''
                ${config} \
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=${WithIO} \
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${OutputTime} 2>&1 > ${stdout-file}

                cat ${stdout-file}
                ${if WithIO == "1" then "rm ${rsf-file} ${rsf-at-file}" else ""}
                cp ${stdout-file} ${home-folder}
            '';
            };
        fletcher-base-cpu-tupi = fletcher-base-cpu-p-core "fletcher-base-cpu-fix-size-p-core-tupi" ''OMP_PLACES="{0},{2},{4},{6},{8},{10},{12},{14}" OMP_PROC_BIND=true OMP_NUM_THREADS=8''; 
        fletcher-base-cpu-poti = fletcher-base-cpu-p-core "fletcher-base-cpu-fix-size-p-core-poti" ''OMP_PLACES="{0},{2},{4},{6},{8},{10},{12},{14}" OMP_PROC_BIND=true OMP_NUM_THREADS=8''; 
        
        fletcher-base-cpu-fix-order = id: file:
          let
            program = "${my-fletcher-base}/bin/fletcher-base";
            experiment-name = "fletcher-base-cpu-fix-order-${id}";
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

              bashRunFn = {
                WithIO, Blocks, Width, AbsorbSize, TotalTime, TimeStep, OutputTime
              }: 
              let
                filename = "${Width}-${WithIO}-${tail1 Blocks}";
                stdout-file = "${scratch-folder}/stdout-${filename}.out";
                rsf-file = "${scratch-folder}/${filename}.rsf";
                rsf-at-file = "${rsf-file}@";
            in
            ''
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=${WithIO} \
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${OutputTime} 2>&1 > ${stdout-file}

                cat ${stdout-file}
                ${if WithIO == "1" then "rm ${rsf-file} ${rsf-at-file}" else ""}
                cp ${stdout-file} ${home-folder}
            '';
          };
        fletcher-base-cpu-fix-order-32 = fletcher-base-cpu-fix-order "32" ./fletcher-base-fix-order.csv;
        fletcher-base-cpu-fix-order-64 = fletcher-base-cpu-fix-order "64" ./fletcher-base-fix-order-64.csv;

        
        star-fletcher-cpu =  
          let
            program = "${my-star-fletcher}/bin/star-fletcher";
            experiment-name = "star-fletcher-cpu-fix-size";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
          experiments.lib.mkExperiment {
            inherit pkgs; 
            
            csvFile = ./star-fletcher-fix-size.csv;

            preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
            '';
            
            bashRunFn = {
              WithIO, BlockSeg, Schedulers, Blocks, Width,
              AbsorbSize, TotalTime, TimeStep, OutputTime
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
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${BlockSeg} ${OutputTime} 2>&1 > ${stdout-file}
                cat ${stdout-file}
                rm ${rsf-file} ${rsf-at-file}
                cp ${stdout-file} ${home-folder}
            '';
          };

        star-fletcher-cpu-p-cores =  name: config:
          let
            program = "${my-star-fletcher}/bin/star-fletcher";
            experiment-name = name;
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
          experiments.lib.mkExperiment {
            inherit pkgs; 
            
            csvFile = ./star-fletcher-fix-size.csv;

            preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
            '';
            
            bashRunFn = {
              WithIO, BlockSeg, Schedulers, Blocks, Width,
              AbsorbSize, TotalTime, TimeStep, OutputTime
            }: 
              let
                filename = "${Schedulers}-${BlockSeg}-${WithIO}-${tail1 Blocks}";
                stdout-file = "${scratch-folder}/stdout-${filename}.out";
                rsf-file = "${scratch-folder}/out-${filename}.rsf";
                rsf-at-file = "${rsf-file}@";
            in
              ''
                ${config} \
                STARPU_SCHED=${Schedulers} \
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=${WithIO} \
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${BlockSeg} ${OutputTime} 2>&1 > ${stdout-file}
                cat ${stdout-file}
                rm ${rsf-file} ${rsf-at-file}
                cp ${stdout-file} ${home-folder}
            '';
          };
        star-fletcher-cpu-tupi = star-fletcher-cpu-p-cores "star-fletcher-cpu-fix-size-p-core-tupi" ''STARPU_NCPU=8 STARPU_NCUDA=0 STARPU_NOPENCL=0 STARPU_WORKERS_CPUID="0 2 4 6 8 10 12 14"'';
        star-fletcher-cpu-poti = star-fletcher-cpu-p-cores "star-fletcher-cpu-fix-size-p-core-poti" ''STARPU_NCPU=8 STARPU_NCUDA=0 STARPU_NOPENCL=0 STARPU_WORKERS_CPUID="0 2 4 6 8 10 12 14"'';

        star-fletcher-cpu-trace =  
          let
            trace-star-fletcher = star-fletcher.packages.${system}.default.override {
                enableCUDA = false;
                enableTrace = true;
                compileAsRelease = true;
                enableVerbose = false;
                stdenv = pkgs.gcc13Stdenv;
                StarPU = starpu-no-check;
            };
            program = "${trace-star-fletcher}/bin/star-fletcher";
            experiment-name = "star-fletcher-cpu-fix-size-trace";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
          experiments.lib.mkExperiment {
            inherit pkgs; 
            
            csvFile = ./star-fletcher-fix-size-traces.csv;

            preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
            '';
            
            bashRunFn = {
              WithIO, BlockSeg, Schedulers, Width,
              AbsorbSize, TotalTime, TimeStep, OutputTime
            }: 
              let
                filename = "${Schedulers}-${BlockSeg}-${WithIO}";
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
                ENABLE_IO=${WithIO} \
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${BlockSeg} ${OutputTime} 2>&1 > ${stdout-file}
                cat ${stdout-file}
                rm ${rsf-file} ${rsf-at-file}
                cp ${stdout-file} ${home-folder}
                cp ${prof-file} ${home-folder}
            '';
          };

        star-fletcher-cpu-trace-p-core =  
          let
            trace-star-fletcher = star-fletcher.packages.${system}.default.override {
                enableCUDA = false;
                enableTrace = true;
                compileAsRelease = true;
                enableVerbose = false;
                stdenv = pkgs.gcc13Stdenv;
                StarPU = starpu-no-check;
            };
            program = "${trace-star-fletcher}/bin/star-fletcher";
            experiment-name = "star-fletcher-cpu-fix-size-p-core-trace";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
          experiments.lib.mkExperiment {
            inherit pkgs; 
            
            csvFile = ./star-fletcher-fix-size-traces.csv;

            preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
            '';
            
            bashRunFn = {
              WithIO, BlockSeg, Schedulers, Width,
              AbsorbSize, TotalTime, TimeStep, OutputTime
            }: 
              let
                filename = "${Schedulers}-${BlockSeg}-${WithIO}";
                stdout-file = "${scratch-folder}/stdout-${filename}.out";
                rsf-file = "${scratch-folder}/out-${filename}.rsf";
                rsf-at-file = "${rsf-file}@";
                prof-name = "prof_file_${filename}";
                prof-file = "${scratch-folder}/${prof-name}_0";
            in
              ''
                STARPU_NCPU=8 \
                STARPU_NCUDA=0 \
                STARPU_NOPENCL=0 \
                STARPU_WORKERS_CPUID="0 2 4 6 8 10 12 14 \
                STARPU_TRACE_BUFFER_SIZE=4096 \
                STARPU_FXT_TRACE=1 \
                STARPU_FXT_PREFIX=${scratch-folder} \
                STARPU_FXT_SUFFIX=${prof-name} \
                STARPU_SCHED=${Schedulers} \
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=${WithIO} \
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${BlockSeg} ${OutputTime} 2>&1 > ${stdout-file}
                cat ${stdout-file}
                rm ${rsf-file} ${rsf-at-file}
                cp ${stdout-file} ${home-folder}
                cp ${prof-file} ${home-folder}
            '';
          };

        star-fletcher-cpu-fix-order = id: file:  
          let
            program = "${my-star-fletcher}/bin/star-fletcher";
            experiment-name = "star-fletcher-cpu-fix-order-${id}";
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
            
            bashRunFn = {
              WithIO, BlockSeg, Schedulers, Blocks, Width,
              AbsorbSize, TotalTime, TimeStep, OutputTime
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
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${BlockSeg} ${OutputTime} 2>&1 > ${stdout-file}
                cat ${stdout-file}
                rm ${rsf-file} ${rsf-at-file}
                cp ${stdout-file} ${home-folder}
            '';
          };
        star-fletcher-cpu-fix-order-32 = star-fletcher-cpu-fix-order "32" ./star-fletcher-fix-order.csv;
        star-fletcher-cpu-fix-order-64 = star-fletcher-cpu-fix-order "64" ./star-fletcher-fix-order-64.csv;
    in
    {
        packages = {
          inherit fletcher-base-cpu star-fletcher-cpu
            star-fletcher-cpu-fix-order-32 
            star-fletcher-cpu-fix-order-64 
            fletcher-base-cpu-fix-order-32 
            fletcher-base-cpu-fix-order-64 
            star-fletcher-cpu-tupi
            star-fletcher-cpu-poti
            fletcher-base-cpu-tupi
            fletcher-base-cpu-poti
            star-fletcher-cpu-trace
            star-fletcher-cpu-trace-p-core
          ;
        };
    });
}
