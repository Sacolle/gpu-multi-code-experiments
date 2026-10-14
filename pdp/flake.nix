{
    description = "Flake para rodar os testes para o pdp.";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
        experiments.url = "github:Sacolle/experiments-nix"; 
	      StarPU = {
            url = "github:Sacolle/nix-starpu";
            inputs.nixpkgs.follows = "nixpkgs";
	      };
        star-fletcher = {
            url = "github:Sacolle/Star-Fletcher";
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

        my-fletcher-base = (fletcher-base.packages.${system}.default.override {
            CUDAbackend = false;
            OpenMPbackend = true;
            OpenACCbackend = false;
        }).overrideAttrs (old: {
            patches = (old.patches or []) ++ [
                ./runtime.patch
            ];
            patchFlags = [ "-p2" ];
        });

        starpu-no-check = StarPU.packages.${system}.default.overrideAttrs {
            doCheck = false;
        };

        my-star-fletcher = star-fletcher.packages.${system}.default.override {
            enableCUDA = false;
            enableTrace = false;
            compileAsRelease = true;
            # enableVerbose = false;
            stdenv = pkgs.gcc13Stdenv;
            StarPU = starpu-no-check;
        };

        my-star-fletcher-trace = my-star-fletcher.override { enableTrace = true; };

        mk-scratch-folder = name: "$SCRATCH/${name}/$HOSTNAME";
        mk-home-folder = name: "~/experimental-results/${name}/$HOSTNAME";

        amountWritten = time: base: toString (builtins.floor ((builtins.fromJSON time) / (builtins.fromJSON base)));

        fletcher-base-cpu =
          let
            program = "${my-fletcher-base}/bin/fletcher-base";
            experiment-name = "fletcher-base-pdp-exp";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
            experiments.lib.mkExperiment {
              inherit pkgs;

              csvFile = ./fletcher-base-exp.csv;

              preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
                '';

              bashRunFn = {
                WithIO, Blocks, Width, AbsorbSize, TotalTime, TimeStep, OutputTime, Schedulers
              }: 
                let
                  tt = amountWritten OutputTime TimeStep;
                  filename = "${Schedulers}-${tt}-${Blocks}";
                  stdout-file = "${scratch-folder}/stdout-${filename}.out";
                  rsf-file = "${scratch-folder}/${filename}.rsf";
                  rsf-at-file = "${rsf-file}@";
                in
                  ''
                env -u OMP_NUM_THREADS -u OMP_PLACES -u GOMP_CPU_AFFINITY -u KMP_AFFINITY \
                OMP_SCHEDULE=${Schedulers} \
                OMP_PROC_BIND=false \
                OMP_DISPLAY_ENV=true \
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=${WithIO} \
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${OutputTime} > ${stdout-file} 2>&1 

                cat ${stdout-file}
                ${if WithIO == "1" then "rm ${rsf-file} ${rsf-at-file}" else ""}
                cp ${stdout-file} ${home-folder}
            '';
          };

        fletcher-base-cpu-bind =
          let
            program = "${my-fletcher-base}/bin/fletcher-base";
            experiment-name = "fletcher-base-pdp-exp-bind";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
            experiments.lib.mkExperiment {
              inherit pkgs;

              csvFile = ./fletcher-base-exp.csv;

              preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
                '';

              bashRunFn = {
                WithIO, Blocks, Width, AbsorbSize, TotalTime, TimeStep, OutputTime, Schedulers
              }: 
                let
                  tt = amountWritten OutputTime TimeStep;
                  filename = "${Schedulers}-${tt}-${Blocks}";
                  stdout-file = "${scratch-folder}/stdout-${filename}.out";
                  rsf-file = "${scratch-folder}/${filename}.rsf";
                  rsf-at-file = "${rsf-file}@";
                in
                  ''
                NCORES=$(${pkgs.util-linux}/bin/lscpu -p=core,socket | grep -v '^#' | sort -u | wc -l)
                env -u OMP_NUM_THREADS -u OMP_PLACES -u GOMP_CPU_AFFINITY -u KMP_AFFINITY \
                OMP_SCHEDULE=${Schedulers} \
                OMP_PROC_BIND=close \
                OMP_PLACES=cores \
                OMP_NUM_THREADS=$NCORES \
                OMP_DISPLAY_ENV=true \
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=${WithIO} \
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${OutputTime} > ${stdout-file} 2>&1 

                cat ${stdout-file}
                ${if WithIO == "1" then "rm ${rsf-file} ${rsf-at-file}" else ""}
                cp ${stdout-file} ${home-folder}
            '';
          };

        fletcher-base-cpu-scalability = file:
          let
            program = "${my-fletcher-base}/bin/fletcher-base";
            experiment-name = "fletcher-base-pdp-exp-scale";
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
                NumCPUs, OutputTime, Blocks, WithIO, Width, AbsorbSize, TotalTime, TimeStep, SMT, CpuList, Schedulers
              }:
                let
                  tt = amountWritten OutputTime TimeStep;
                  filename = "${NumCPUs}-${Schedulers}-${tt}-${Blocks}";
                  stdout-file = "${scratch-folder}/stdout-${filename}.out";
                  rsf-file = "${scratch-folder}/${filename}.rsf";
                  rsf-at-file = "${rsf-file}@";
                  # "0 2 4" -> "{0},{2},{4}": one place per CPU, in the order of the csv
                  places = "{" + pkgs.lib.concatStringsSep "},{" (pkgs.lib.splitString " " CpuList) + "}";
                in
                  ''
                env -u OMP_NUM_THREADS -u OMP_PLACES -u GOMP_CPU_AFFINITY -u KMP_AFFINITY \
                OMP_SCHEDULE=${Schedulers} \
                OMP_PROC_BIND=close \
                OMP_PLACES="${places}" \
                OMP_NUM_THREADS=${NumCPUs} \
                OMP_DISPLAY_ENV=true \
                OMP_DISPLAY_AFFINITY=true \
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=${WithIO} \
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${OutputTime} > ${stdout-file} 2>&1 

                cat ${stdout-file}
                ${if WithIO == "1" then "rm ${rsf-file} ${rsf-at-file}" else ""}
                cp ${stdout-file} ${home-folder}
            '';
          };
        
        star-fletcher-cpu =  
          let
            program = "${my-star-fletcher}/bin/star-fletcher";
            experiment-name = "star-fletcher-cpu-pdp-exp";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
          experiments.lib.mkExperiment {
            inherit pkgs; 
            
            csvFile = ./star-fletcher-exp.csv;

            preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
            '';
            
            bashRunFn = {
                BlockSeg, OutputTime, Blocks, WithIO, Width, AbsorbSize, TotalTime, TimeStep
            }: 
              let
                tt = amountWritten OutputTime TimeStep;
                filename = "${BlockSeg}-${tt}-${Blocks}";
                stdout-file = "${scratch-folder}/stdout-${filename}.out";
                rsf-file = "${scratch-folder}/out-${filename}.rsf";
                rsf-at-file = "${rsf-file}@";
            in
            ''
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=${WithIO} \
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${BlockSeg} ${OutputTime} > ${stdout-file} 2>&1
                cat ${stdout-file}
                rm ${rsf-file} ${rsf-at-file}
                cp ${stdout-file} ${home-folder}
            '';
          };

        star-fletcher-cpu-scalability = file:
          let
            program = "${my-star-fletcher}/bin/star-fletcher";
            experiment-name = "star-fletcher-cpu-pdp-exp-scale";
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
                NumCPUs, OutputTime, Blocks, WithIO, BlockSeg, Width, AbsorbSize, TotalTime, TimeStep, SMT, StarpuCpuList, ...
            }:
              let
                tt = amountWritten OutputTime TimeStep;
                filename = "${NumCPUs}-${BlockSeg}-${tt}-${Blocks}";
                stdout-file = "${scratch-folder}/stdout-${filename}.out";
                rsf-file = "${scratch-folder}/out-${filename}.rsf";
                rsf-at-file = "${rsf-file}@";
            in
            ''
                STARPU_NCPU=${NumCPUs} \
                STARPU_NCUDA=0 \
                STARPU_NOPENCL=0 \
                STARPU_WORKERS_CPUID="${StarpuCpuList}" \
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=${WithIO} \
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${BlockSeg} ${OutputTime} > ${stdout-file} 2>&1
                cat ${stdout-file}
                rm ${rsf-file} ${rsf-at-file}
                cp ${stdout-file} ${home-folder}
            '';
          };

        # one package per machine for the scalability experiment, each with its own csv
        scalability-machines = [ "cei" "draco" "grace" "lunaris" "poti" "tupi" ];
        scalability-pkgs = pkgs.lib.listToAttrs (pkgs.lib.concatMap (m: [
          {
            name = "fletcher-base-cpu-scalability-${m}";
            value = fletcher-base-cpu-scalability (./scalability + "/fletcher-base-scal-${m}.csv");
          }
          {
            name = "star-fletcher-cpu-scalability-${m}";
            value = star-fletcher-cpu-scalability (./scalability + "/star-fletcher-scal-${m}.csv");
          }
        ]) scalability-machines);

        star-fletcher-cpu-trace =  
          let
            program = "${my-star-fletcher-trace}/bin/star-fletcher";
            experiment-name = "star-fletcher-cpu-pdp-trace";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
          experiments.lib.mkExperiment {
            inherit pkgs; 
            
            csvFile = ./star-fletcher-trace.csv;

            preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
            '';
            
            bashRunFn = {
                BlockSeg, OutputTime, WithIO, Width, AbsorbSize, TotalTime, TimeStep
            }: 
              let

                tt = amountWritten OutputTime TimeStep;
                filename = "${BlockSeg}-${tt}";
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
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=${WithIO} \
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${BlockSeg} ${OutputTime} 2>&1 > ${stdout-file}
                cat ${stdout-file}
                rm ${rsf-file} ${rsf-at-file}

                gzip -f ${prof-file}

                cp ${stdout-file} ${home-folder}
                cp ${prof-file}.gz ${home-folder}
            '';
          };

        fio-exp =
          let
            program = "${pkgs.fio}/bin/fio";
            experiment-name = "fio-disk-perf";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
            target-folder = "${scratch-folder}/target";

            mode-flags = {
              buffered = "--direct=0";
              flushed  = "--direct=0 --end_fsync=1";
              direct   = "--direct=1";
            };
          in
            experiments.lib.mkExperiment {
              inherit pkgs;

              csvFile = ./fio-write.csv;

              preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
                mkdir -p ${target-folder}

                {
                  echo "== lscpu"
                  ${pkgs.util-linux}/bin/lscpu

                  echo "== lscpu -e (one line per logical CPU)"
                  ${pkgs.util-linux}/bin/lscpu -e=CPU,CORE,SOCKET,NODE,MAXMHZ,MINMHZ

                  echo "== hybrid Intel: P-core / E-core CPU ids"
                  echo "P-cores: $(cat /sys/devices/cpu_core/cpus 2>/dev/null || echo none)"
                  echo "E-cores: $(cat /sys/devices/cpu_atom/cpus 2>/dev/null || echo none)"

                  echo "== hwloc cpukinds"
                  ${pkgs.hwloc}/bin/lstopo-no-graphics --cpukinds

                  echo "== hwloc topology"
                  ${pkgs.hwloc}/bin/lstopo-no-graphics --no-io

                  echo "== NUMA"
                  ${pkgs.numactl}/bin/numactl --hardware
                } > ${home-folder}/cpu-info.txt 2>&1 || true
              '';

            bashRunFn = {
                Engine, Mode, NumJobs, BlockSize, Blocks
            }: 
              let
                filename = "${Engine}-${Mode}-${NumJobs}-${BlockSize}-${Blocks}";
                stdout-file = "${scratch-folder}/stdout-${filename}.out";
            in
              ''
                sync
                ${program} --name=${filename} \
                  --directory=${target-folder} \
                  --rw=write \
                  --ioengine=${Engine} \
                  --bs=${BlockSize} \
                  --numjobs=${NumJobs} \
                  --size=$(( 2048 / ${NumJobs} ))M \
                  ${mode-flags.${Mode}} \
                  --runtime=60 \
                  --invalidate=1 \
                  --unlink=1 \
                  --group_reporting \
                  --output-format=json > ${stdout-file}

                cat ${stdout-file}
                cp ${stdout-file} ${home-folder}
            '';

            };

    in
    {
        packages = {
            # test = my-star-fletcher.override { compileAsRelease = false; };
          inherit
            # my-star-fletcher
            fletcher-base-cpu
            fletcher-base-cpu-bind
            star-fletcher-cpu
            star-fletcher-cpu-trace
            fio-exp
          ;
          # pkgs 
          # fletcher-base-cpu-scalability-${machine}
          # star-fletcher-cpu-scalability-${machine}
          # with machines [ "cei" "draco" "grace" "lunaris" "poti" "tupi" ]
        } // scalability-pkgs;
    });
}
