#!/usr/bin/env bash
set -eou pipefail

timestamp=$(date +%Y-%m-%d_%H-%M-%S)
log="benchmark_$timestamp.csv"

# Get Isabelle
if [[ $# -eq 0 ]]; then
  isabelle="isabelle"
elif [[ $# -eq 1 ]]; then
  isabelle="$1"
else
  echo "usage: $0 [ISABELLE]"
  exit 1
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
ISABELLE_PLATFORM64="${PLATFORM}"
ML_PLATFORM="$ISABELLE_PLATFORM64"
ML_HOME="$ML_HOME/../$ML_PLATFORM"
EOF

# Find out system
memory=$(free --giga | grep "^Mem:" | awk '{print $2}')
cpu=$(lscpu | grep "^Model name:" | awk  '{print substr($0, index($0,$3))}' | cut -f1 -d"@" | awk '{$1=$1;print}')
cores=$(lscpu | grep "^CPU(s):" | awk  '{print $2}')
speed=$(dmesg | grep "MHz processor" | awk  '{print $5}' | grep -oP "^[0-9]+")
arch=$(uname -m)
case "$OSTYPE" in
  darwin*)  os="mac" ;;
  linux*)   os="linux" ;;
  msys*)    os="windows" ;;
  cygwin*)  os="windows" ;;
  *)        echo "Unsupported os: $OSTYPE"
            exit 1;;
esac

# Benchmark
run_bench()
{
  export PLATFORM=$1
  export HEAP=$3
  local CORES=$2
  echo -n "$cpu, $speed, $os, $HEAP, $CORES, " | tee -a "$log"
  res=$($isabelle build -c -o threads="$CORES" HOL-Analysis)
  elapsed=$(echo "$res" | grep "Finished HOL-Analysis" | awk '{print $3}' | cut -c2-)
  cpu_time=$(echo "$res" | grep "Finished HOL-Analysis" | awk '{print $6}')
  echo "$elapsed, $cpu_time" | tee -a "$log"
}

# Run configs
echo "Your system: $arch-$os on $cpu with ${memory}G RAM, $cores cores @ ${speed}MHz"
echo "Running benchmarks... result table:"
echo "cpu, speed, os, heap, threads, time, cputime" | tee -a "$log"
for (( cor = 4; cor <= cores; cor = cor * 2 )); do
  for (( mem = cor; (mem <= memory && mem <= cor * cor); mem = mem * 2 )); do
    if [[ $mem -le 16 ]]; then
      run_bench "${arch}_32-$os" "$cor" "$mem"
    else
      run_bench "$arch-$os" "$cor" "$mem"
    fi
  done
done

# Run max. core config
if [[ $cor -lt $cores ]]; then
  for (( mem = cores; (mem <= memory && mem <= cores * cores); mem = mem * 2 )); do
    if [[ $mem -le 16 ]]; then
      run_bench "${arch}_32-$os" "$cores" "$mem"
    else
      run_bench "$arch-$os" "$cores" "$mem"
    fi
  done
fi
