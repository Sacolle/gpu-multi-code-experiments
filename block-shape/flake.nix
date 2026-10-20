{
    description = "Flake para o experimento de formato dos blocos (block-shapes).";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
        experiments.url = "github:Sacolle/experiments-nix";
        flake-utils.url = "github:numtide/flake-utils";

        StarPU = {
            url = "github:Sacolle/nix-starpu";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        star-fletcher-block-shapes = {
            url = "github:Sacolle/star-fletcher?ref=block-shapes";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        nix-gl-host = {
            url = "github:numtide/nix-gl-host";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        nixpkgs24.url = "github:nixos/nixpkgs/1da52dd49a127ad74486b135898da2cef8c62665";
    };
    outputs = { self, nixpkgs, experiments, flake-utils, StarPU, star-fletcher-block-shapes, nix-gl-host, nixpkgs24 }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
    let
        pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
        pkgs24 = import nixpkgs24 { inherit system; config.allowUnfree = true; };

        mk-scratch-folder = name: "$SCRATCH/${name}/$HOSTNAME";
        mk-home-folder = name: "~/experimental-results/${name}/$HOSTNAME";

        nixglhost = "${nix-gl-host.defaultPackage.${system}}/bin/nixglhost";

        starpu-no-check = StarPU.packages.${system}.default.overrideAttrs { doCheck = false; };

        # one run of the program; `launcher` wraps the binary (nixglhost on the GPU machines)
        # and `extraEnv` sets the CUDA threads. A failed run is reported and the script goes on.
        run-block-shape = { program, launcher, scratch-folder, home-folder, extraEnv }:
          { Schedulers, Blocks, Shape, BlockX, BlockY, BlockZ, Width, AbsorbSize, TotalTime, TimeStep, OutputTime, ... }:
          let
            filename = "${Schedulers}-${Shape}-${Blocks}";
            stdout-file = "${scratch-folder}/stdout-${filename}.out";
            rsf-file = "${scratch-folder}/out-${filename}.rsf";
            rsf-at-file = "${rsf-file}@";
          in
          ''
            ${extraEnv} \
            STARPU_SCHED=${Schedulers} \
            OUTPUT_FOLDER=${scratch-folder} \
            OUTPUT_FILE=${filename} \
            ENABLE_IO=0 \
            ${launcher} ${program} TTI ${Width} ${Width} ${Width} \
            ${AbsorbSize} 12.5 12.5 12.5 \
            ${TimeStep} ${TotalTime} ${BlockX} ${BlockY} ${BlockZ} ${OutputTime} > ${stdout-file} 2>&1 \
              || echo "[block-shape] run ${filename} failed with exit code $?" | tee -a ${stdout-file}

            cat ${stdout-file}

            rm -f ${rsf-file} ${rsf-at-file}

            cp ${stdout-file} ${home-folder}
          '';

        exp-block-shape-gpu = file: options:
          let
            my-star-fletcher = star-fletcher-block-shapes.packages.${system}.default.override ({
                cudaPackages = pkgs.cudaPackages_13_0;
                stdenv = pkgs.gcc13Stdenv;
                enableCUDA = true;
                enableTrace = false;
                compileAsRelease = true;
                cuda_arch = "sm_89";
            } // options);
            program = "${my-star-fletcher}/bin/star-fletcher";

            experiment-name = "block-shape-gpu";
            scratch-folder = mk-scratch-folder experiment-name;
            home-folder = mk-home-folder experiment-name;
          in
          experiments.lib.mkExperiment {
            inherit pkgs;

            csvFile = file;

            preamble = ''
                mkdir -p ${scratch-folder}
                mkdir -p ${home-folder}
                (nvidia-smi || true) | tee ${home-folder}/nvidia-smi.txt
                ${pkgs.util-linux}/bin/lscpu > ${home-folder}/lscpu.txt
            '';

            bashRunFn = args@{
                Schedulers, Blocks, Shape, BlockX, BlockY, BlockZ,
                ThreadX, ThreadY, ThreadZ,
                Width, AbsorbSize, TotalTime, TimeStep, OutputTime,
                ...
            }: run-block-shape {
                inherit program scratch-folder home-folder;
                launcher = nixglhost;
                extraEnv = "CUDA_THREAD_X=${ThreadX} CUDA_THREAD_Y=${ThreadY} CUDA_THREAD_Z=${ThreadZ}";
            } args;
          };

        exp-block-shape-cpu = file: name:
          let
            my-star-fletcher = star-fletcher-block-shapes.packages.${system}.default.override {
                enableCUDA = false;
                enableTrace = false;
                compileAsRelease = true;
                stdenv = pkgs.gcc13Stdenv;
                StarPU = starpu-no-check;
            };
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
                ${pkgs.util-linux}/bin/lscpu | tee ${home-folder}/lscpu.txt
            '';

            bashRunFn = args@{
                Schedulers, Blocks, Shape, BlockX, BlockY, BlockZ,
                Width, AbsorbSize, TotalTime, TimeStep, OutputTime,
                ...
            }: run-block-shape {
                inherit program scratch-folder home-folder;
                launcher = "";
                extraEnv = "";
            } args;
          };
    in
    {
        packages = {
          exp-block-shape-cidia = exp-block-shape-gpu ./exp-cidia.csv {
            cudaPackages = pkgs24.cudaPackages_12_2;
            stdenv = pkgs24.gcc12Stdenv;
            cuda_arch = "sm_75";
          };
          exp-block-shape-poti = exp-block-shape-gpu ./exp-poti.csv {};
          exp-block-shape-tupi = exp-block-shape-gpu ./exp-tupi.csv {};
          exp-block-shape-grace = exp-block-shape-gpu ./exp-grace.csv {};

          exp-block-shape-cpu = exp-block-shape-cpu ./exp-cpu.csv "block-shape-cpu";
          exp-block-shape-test = exp-block-shape-cpu ./exp-test.csv "block-shape-test";
        };
    });
}
