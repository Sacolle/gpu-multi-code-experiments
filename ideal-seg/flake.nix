{
    description = "Flake para rodar os testes.";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
        experiments.url = "github:Sacolle/experiments-nix"; 

        star-fletcher.url = "github:Sacolle/Star-Fletcher?ref=CUDA";

        nixpkgs24.url = "github:nixos/nixpkgs/1da52dd49a127ad74486b135898da2cef8c62665";
    };
    outputs = { self, nixpkgs, experiments, star-fletcher, nixpkgs24 }: 
    let
        system = "x86_64-linux"; 
        pkgs = import nixpkgs { inherit system; };

        pkgs24 = import nixpkgs24 { inherit system; config.allowUnfree = true; };
        cudaPackages24 = pkgs24.cudaPackages_12_2;
        
        experiment-name = "ideal-block-size-machine";
        scratch-folder = "$SCRATCH/${experiment-name}/$HOSTNAME";
        home-folder = "~/experimental-results/${experiment-name}/$HOSTNAME";
        str = toString;
        asNum = builtins.fromJSON;
    
        my-star-fletcher = star-fletcher.packages.${system}.default.override {
            cudaPackages = cudaPackages24;
            stdenv = pkgs24.gcc12Stdenv;
            enableCUDA = true;
            enableTrace = false;
            compileAsRelease = true;
        };

        program = "${my-star-fletcher}/bin/star-fletcher";

        experimentScript = experiments.lib.mkExperiment {
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
                filename = "${Schedulers}-${BlockSeg}-${WithIO}-${builtins.substring 1 (-1) Blocks}";
                stdout-file = "${scratch-folder}/stdout-${filename}.out";
                rsf-file = "${scratch-folder}/out-${filename}.rsf";
                rsf-at-file = "${rsf-file}@";
            in
            ''
                OUTPUT_FOLDER=${scratch-folder} \
                OUTPUT_FILE=${filename} \
                ENABLE_IO=${WithIO} \
                STARPU_SCHED=${Schedulers} \
                ${program} TTI ${Width} ${Width} ${Width} \
                ${AbsorbSize} 12.5 12.5 12.5 \
                ${TimeStep} ${TotalTime} ${BlockSeg} ${OutputTime} 2>&1 > ${stdout-file}

                cat ${stdout-file}

                rm ${rsf-file} ${rsf-at-file}

                cp ${stdout-file} ${home-folder}
            '';
        };
    in
    {
        packages.${system}.default = experimentScript;
    };
}
