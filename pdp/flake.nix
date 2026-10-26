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

        star-fletcher-direct = {
            url = "github:Sacolle/Star-Fletcher?ref=direct_io";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        fletcher-base = {
          url = "github:Sacolle/fletcher-base?dir=original";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        fletcher-base-trace = {
          url = "github:Sacolle/fletcher-base?ref=trace&dir=original";
          inputs.nixpkgs.follows = "nixpkgs";
        };

        starvz.url = "github:schnorr/starvz";
        flake-utils.url = "github:numtide/flake-utils";
    };
    outputs = { self, nixpkgs, experiments, StarPU, star-fletcher, star-fletcher-direct, fletcher-base, fletcher-base-trace, starvz, flake-utils }: 
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

        my-fletcher-base-trace = fletcher-base-trace.packages.${system}.default.override {
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
            # enableVerbose = false;
            stdenv = pkgs.gcc13Stdenv;
            StarPU = starpu-no-check;
        };

        # o starpu_fxt_tool usado pelo starvz tem que ser do mesmo StarPU que gerou o trace,
        # por isso é o mesmo StarPU que o star-fletcher usa quando compilado com enableTrace
        starpu-trace = starpu-no-check.override {
            stdenv = pkgs.gcc13Stdenv;
            enableTrace = true;
            enableCUDA = false;
            compileAsRelease = true;
            maxBuffers = 56;
        };
        starvz-cmd = "${starvz.packages.${system}.starvzTools.override { StarPU = starpu-trace; }}/bin/starvz";

        my-star-fletcher-trace = my-star-fletcher.override { enableTrace = true; };

        mk-scratch-folder = name: "$SCRATCH/${name}/$HOSTNAME";
        mk-home-folder = name: "~/experimental-results/${name}/$HOSTNAME";

        amountWritten = time: base: toString (builtins.floor ((builtins.fromJSON time) / (builtins.fromJSON base)));

        base-fletcher-base-cpu = file: name:
          let
            program = "${my-fletcher-base}/bin/fletcher-base";
            experiment-name = name;
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
        fletcher-base-cpu = base-fletcher-base-cpu ./fletcher-base-exp.csv "fletcher-base-pdp-exp";
        fletcher-base-cpu-big = base-fletcher-base-cpu ./fletcher-base-exp-big.csv "fletcher-base-pdp-exp-big";

        base-fletcher-base-cpu-bind = file: name:
          let
            program = "${my-fletcher-base}/bin/fletcher-base";
            experiment-name = name;
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

        fletcher-base-cpu-bind = base-fletcher-base-cpu-bind ./fletcher-base-exp.csv "fletcher-base-pdp-exp-bind";
        fletcher-base-cpu-bind-big = base-fletcher-base-cpu-bind ./fletcher-base-exp-big.csv "fletcher-base-pdp-exp-bind-big";

        fletcher-base-cpu-scalability = name: file:
          let
            program = "${my-fletcher-base}/bin/fletcher-base";
            experiment-name = name;
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


        fletcher-base-cpu-scalability-trace = file:
          let
            program = "${my-fletcher-base-trace}/bin/fletcher-base";
            experiment-name = "fletcher-base-pdp-exp-scale-trace";
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
                NumCPUs, OutputTime, WithIO, Width, AbsorbSize, TotalTime, TimeStep, SMT, CpuList, Schedulers
              }:
                let
                  tt = amountWritten OutputTime TimeStep;
                  filename = "${NumCPUs}-${Schedulers}-${tt}";
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
        
        base-star-fletcher-cpu =  file: name:
          let
            program = "${my-star-fletcher}/bin/star-fletcher";
            experiment-name = name;
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
        star-fletcher-cpu = base-star-fletcher-cpu ./star-fletcher-exp.csv "star-fletcher-cpu-pdp-exp";
        star-fletcher-cpu-big = base-star-fletcher-cpu ./star-fletcher-exp-big.csv "star-fletcher-cpu-pdp-exp-big";

        star-fletcher-cpu-big-direct-io = 
          let
            program = "${
              (star-fletcher-direct.packages.${system}.default.override {
                enableCUDA = false;
                enableTrace = false;
                compileAsRelease = true;
                stdenv = pkgs.gcc13Stdenv;
                StarPU = starpu-no-check;
              })
            }/bin/star-fletcher";
            experiment-name = "star-fletcher-cpu-pdp-exp-big-direct";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
          experiments.lib.mkExperiment {
            inherit pkgs; 
            
            csvFile = ./star-fletcher-exp-big.csv;

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
                meta-file = "${scratch-folder}/out-${filename}.meta";
            in
            ''
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=${WithIO} \
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${BlockSeg} ${OutputTime} > ${stdout-file} 2>&1
                cat ${stdout-file}
                ${if WithIO == "1" then "rm -f ${rsf-file} ${meta-file} ${scratch-folder}/out-${filename}-w*.bin" else ""}
                cp ${stdout-file} ${home-folder}
            '';
          };

        star-fletcher-cpu-scalability = name: file:
          let
            program = "${my-star-fletcher}/bin/star-fletcher";
            experiment-name = name;
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

        star-fletcher-cpu-scalability-grace-trace = 
          let
            program = "${my-star-fletcher-trace}/bin/star-fletcher";
            experiment-name = "star-fletcher-cpu-pdp-exp-scale-trace";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
          experiments.lib.mkExperiment {
            inherit pkgs;

            csvFile = ./star-fletcher-scal-grace-trace.csv;

            preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
            '';

            bashRunFn = {
                NumCPUs, OutputTime, WithIO, BlockSeg, Width, AbsorbSize, TotalTime, TimeStep, SMT, StarpuCpuList, ...
            }:
              let
                tt = amountWritten OutputTime TimeStep;
                filename = "${NumCPUs}-${BlockSeg}-${tt}";
                # uma pasta por execução, pois o starvz -1 lê todos os prof_file_* da pasta como uma execução só
                trace-folder = "${scratch-folder}/${filename}";
                stdout-file = "${trace-folder}/stdout-${filename}.out";
                rsf-file = "${scratch-folder}/out-${filename}.rsf";
                rsf-at-file = "${rsf-file}@";
                prof-name = "prof_file_${filename}";
                prof-file = "${trace-folder}/${prof-name}_0";
                archive = "${scratch-folder}/${filename}.tar.gz";
            in
            ''
                mkdir -p ${trace-folder}
                STARPU_TRACE_BUFFER_SIZE=8192 \
                STARPU_FXT_TRACE=1 \
                STARPU_FXT_PREFIX=${trace-folder} \
                STARPU_FXT_SUFFIX=${prof-name} \
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

                # fase 1 do StarVZ logo após a execução: converte o trace bruto em parquet, que é bem menor.
                # Se ela falhar, o trace bruto é mantido para poder ser convertido depois.
                if ${starvz-cmd} -1 ${trace-folder} > ${trace-folder}/phase1.log 2>&1; then
                  rm ${prof-file}
                else
                  echo "starvz phase 1 failed for ${filename}, keeping the raw trace"
                fi

                # compacta a pasta da execução (parquet, log e stdout) e copia para a home
                tar -czf ${archive} -C ${scratch-folder} ${filename}
                cp ${archive} ${home-folder}
            '';
          };

        # one package per machine for the scalability experiment, each with its own csv
        scalability-machines = [ "cei" "draco" "grace" "lunaris" "poti" "tupi" ];
        scalability-pkgs = pkgs.lib.listToAttrs (pkgs.lib.concatMap (m: [
          {
            name = "fletcher-base-cpu-scalability-${m}";
            value = fletcher-base-cpu-scalability "fletcher-base-pdp-exp-scale" (./scalability + "/fletcher-base-scal-${m}.csv");
          }
          {
            name = "star-fletcher-cpu-scalability-${m}";
            value = star-fletcher-cpu-scalability "star-fletcher-cpu-pdp-exp-scale" (./scalability + "/star-fletcher-scal-${m}.csv");
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
          fletcher-base-cpu-scalability-trace-grace = fletcher-base-cpu-scalability-trace ./fletcher-base-scal-grace-trace.csv;
          fletcher-base-cpu-scalability-trace-lunaris = fletcher-base-cpu-scalability-trace ./fletcher-base-scal-lunaris-trace.csv;

          star-fletcher-cpu-scalability-grace-extra = star-fletcher-cpu-scalability "fletcher-base-pdp-exp-scale" ./scalability/star-fletcher-scal-grace-extra.csv;


           fletcher-base-cpu-scalability-grace-big = fletcher-base-cpu-scalability "fletcher-base-pdp-exp-scale-big" ./scalability/fletcher-base-scal-big-grace.csv;
           star-fletcher-cpu-scalability-grace-big = star-fletcher-cpu-scalability "star-fletcher-cpu-pdp-exp-scale-big" ./scalability/star-fletcher-scal-big-grace.csv;

          inherit
            star-fletcher-cpu-scalability-grace-trace
            # my-star-fletcher
            fletcher-base-cpu
            fletcher-base-cpu-bind
            star-fletcher-cpu
            fletcher-base-cpu-big
            fletcher-base-cpu-bind-big
            star-fletcher-cpu-big
            star-fletcher-cpu-trace
            fio-exp

            star-fletcher-cpu-big-direct-io
          ;
          # pkgs 
          # fletcher-base-cpu-scalability-${machine}
          # star-fletcher-cpu-scalability-${machine}
          # with machines [ "cei" "draco" "grace" "lunaris" "poti" "tupi" ]
        } // scalability-pkgs;
    });
}
