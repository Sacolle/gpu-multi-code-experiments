{
    description = "Flake para rodar os testes para o sscad.";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
        experiments.url = "github:Sacolle/experiments-nix"; 

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
    outputs = { self, nixpkgs, experiments, star-fletcher, fletcher-base,  flake-utils }: 
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
    let
        pkgs = import nixpkgs { inherit system; };

        mk-scratch-folder = name: "$SCRATCH/${name}/$HOSTNAME";
        mk-home-folder = name: "~/experimental-results/${name}/$HOSTNAME";
        tail1 = s: builtins.substring 1 (-1) s;

        fletcher-base-cpu =
          let
            my-fletcher-base = fletcher-base.packages.${system}.default.override {
		          OpenMPbackend = true;
            };
            program = "${my-fletcher-base}/bin/fletcher-base";
            experiment-name = "fletcher-base-max-size";
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
                rm ${rsf-file} ${rsf-at-file}
                cp ${stdout-file} ${home-folder}
            '';
          };

        
        star-fletcher-cpu =  
          let
            my-star-fletcher = star-fletcher.packages.${system}.default.override {
                enableCUDA = false;
                enableTrace = false;
                compileAsRelease = true;
            };
            program = "${my-star-fletcher}/bin/star-fletcher";

            experiment-name = "star-fletcher-cpu";
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
    in
    {
        packages = {
            inherit fletcher-base-cpu star-fletcher-cpu;
        };
    });
}
