#!/usr/bin/env bash
set -eou pipefail

timestamp=$(date +%Y-%m-%d_%H-%M-%S)

# Get Isabelle
if [[ $# -eq 0 ]]; then
  isabelle="isabelle"
elif [[ $# -eq 1 ]]; then
  isabelle="$1"
else
  echo "usage: $0 [ISABELLE]"
  exit 1
fi

# Prompt user for cpu model name if not available (some arm systems)
if grep -q -m 1 "^model name" /proc/cpuinfo; then
  cpu=$(grep -m 1 "^model name" /proc/cpuinfo | awk  '{print substr($0, index($0,$4))}')
else
  echo "Could not identify cpu. Please specify model name:"
  read -r cpu
fi

# Check isabelle version
version=$($isabelle version)
if [[ $version != "Isabelle2021-1" ]]; then
  echo "Wrong isabelle version: $version"
  exit 1
fi

# Create benchmark settings dir
benchmark_user_home=$(realpath "benchmark_$timestamp")
if [[ -d "$benchmark_user_home" ]]; then
  echo "Benchmark directory already exists"
  exit 1
else
  mkdir -p "$benchmark_user_home"
  export USER_HOME="$benchmark_user_home"
fi
# Clean up benchmark settings dir
cleanup()
{
  if [[ -d "$benchmark_user_home" ]]; then
    rm -r "$benchmark_user_home"
  fi
}
trap cleanup 0 1 2 3 6

# Write benchmark settings file
$isabelle components -I
cat << \EOF > "$benchmark_user_home/.isabelle/$version/etc/settings"
ML_OPTIONS="--maxheap ${HEAP}G"
ISABELLE_TOOL_JAVA_OPTIONS="-Djava.awt.headless=true -Xms512m -Xmx4${HEAP}g -Xss16m"
ISABELLE_PLATFORM64="${PLATFORM}"
ML_PLATFORM="$ISABELLE_PLATFORM64"
ML_HOME="$ML_HOME/../$ML_PLATFORM"
EOF

# Find out system
memory=$(($(grep "^MemTotal:" /proc/meminfo | awk '{print $2}') / 1000024))
cores=$(grep -c "^processor" /proc/cpuinfo)
case $(uname -m) in
  "aarch64")  arch="arm64" ;;
  *)          arch=$(uname -m) ;;
esac
case "$OSTYPE" in
  darwin*)  os="darwin" ;;
  linux*)   os="linux" ;;
  msys*)    os="windows" ;;
  cygwin*)  os="windows" ;;
  *)        echo "Unsupported os: $OSTYPE"
            exit 1;;
esac

echo "Your system: $arch-$os on $cpu with ${memory}G RAM, $cores cores"
echo "Creating benchmark configs. Note that heap settings apply to both the polyml/jvm process."
declare -a configs=()

mk_mem_configs()
{
  local cor=$1
  if [[ $cor -gt 16 && 32 -le $memory ]]; then
      configs+=("${arch}_32-$os 16 $cor")
  fi
  for (( mem = cor; (2 * mem <= memory && mem <= 2 * cor); mem = 2 * mem )); do
    if [[ $mem -le 16 ]]; then
      configs+=("${arch}_32-$os $mem $cor")
    else
      configs+=("$arch-$os $mem $cor")
    fi
  done
}

if [[ $memory -ge 8 ]]; then
  configs+=("${arch}_32-$os 4 1")
fi
if [[ $memory -ge 16 ]]; then
  configs+=("${arch}_32-$os 8 1")
fi
for (( cor = 4; cor <= cores; cor = cor * 2 )); do
  mk_mem_configs "$cor"
done
# Run max. core config if not power of 2
if [[ $cor -lt $cores ]]; then
  mk_mem_configs "$cores"
fi
echo "(platform heap cores):"

for config in "${configs[@]}"; do
  echo -n " ($config)"
done
echo ""

log="benchmark_$timestamp.csv"
echo "Running benchmarks. Result table..."
echo "cpu, os, heap, threads, time, cputime" | tee -a "$log"

# Benchmark
do_run()
{
  export PLATFORM=$1
  export HEAP=$2
  local CORES=$3
  echo -n "$cpu, $os, $HEAP, $CORES, " | tee -a "$log"
  res=$($isabelle build -c -o threads="$CORES" HOL-Analysis)
  elapsed=$(echo "$res" | grep "Finished HOL-Analysis" | awk '{print $3}' | cut -c2-)
  cpu_time=$(echo "$res" | grep "Finished HOL-Analysis" | awk '{print $6}')
  echo "$elapsed, $cpu_time" | tee -a "$log"
}

for config in "${configs[@]}"; do
  do_run $config
done
