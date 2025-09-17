#!/usr/bin/env bash
set -euo pipefail

# On SIGINT (Ctrl‑C), print a message and exit with 130
trap 'echo "⏹  Aborted by user (SIGINT)"; exit 130' SIGINT

# Benchmark configuration (overridable via environment variables)
INPUT_TOKENS=${INPUT_TOKENS:-128}
OUTPUT_TOKENS=${OUTPUT_TOKENS:-2048}
NUM_PROMPTS=${NUM_PROMPTS:-16384}
CONCURRENCY_LEVELS=${CONCURRENCY_LEVELS:-"8192 16384 32768"}

# Run at a single concurrency level.
run_benchmark() {
  local concurrency=$1
  local outfile="${outdir}/${concurrency}_${NUM_PROMPTS}_${INPUT_TOKENS}_${OUTPUT_TOKENS}.log"
  if ! just benchmark "$concurrency" "$NUM_PROMPTS" "$INPUT_TOKENS" "$OUTPUT_TOKENS" |& tee "$outfile"; then
    echo "⚠️  Benchmark failed at concurrency ${concurrency}; continuing" | tee -a "$outfile"
  fi
}

# create out dir
outdir="/app/results/$(cat ./TIMESTAMP)"

# reproducibility
mkdir -p "${outdir}/repro"
cp "/app/NAME" "${outdir}/NAME"
cat "$0" > ${outdir}/repro/run.sh # 
cp "/app/values.yaml" "${outdir}/repro/values.yaml"


# Sweep it
for X in ${CONCURRENCY_LEVELS}; do
  run_benchmark "$X"
done
