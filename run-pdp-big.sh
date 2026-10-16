#!/bin/bash
# Runs the pdp#*-big experiments using only git (nix comes from nix-portable via np).
# Usage: ./run-pdp-big.sh [SCRATCH_DIR]
#   SCRATCH_DIR defaults to $SCRATCH, then $HOME/scratch.
set -uo pipefail

export SCRATCH="$(realpath -m "${1:-${SCRATCH:-$HOME/scratch}}")"
WORKDIR="$SCRATCH/pdp-big-run"
mkdir -p "$WORKDIR"

clone_or_update() {  # url dir
    if [ -d "$2/.git" ]; then git -C "$2" pull --ff-only
    else git clone --depth 1 "$1" "$2"; fi
}

clone_or_update https://github.com/Sacolle/experiments-nix            "$WORKDIR/experiments-nix" || exit 1
clone_or_update https://github.com/Sacolle/gpu-multi-code-experiments "$WORKDIR/gpu-multi-code-experiments" || exit 1

NP="$WORKDIR/experiments-nix/np"
PDP="$WORKDIR/gpu-multi-code-experiments/pdp"

failed=()
for exp in fletcher-base-cpu-big fletcher-base-cpu-bind-big star-fletcher-cpu-big; do
    echo "=== $exp ($(date)) ==="
    bash "$NP" nix run "$PDP#$exp" || failed+=("$exp")
done

if [ ${#failed[@]} -gt 0 ]; then echo "FAILED: ${failed[*]}"; exit 1; fi
echo "All experiments finished."
