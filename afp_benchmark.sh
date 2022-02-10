#!/usr/bin/env bash
set -eou pipefail

# constants
ml_heap=8
jvm_heap=8
threads=8

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

# Check isabelle version
version=$($isabelle version)
if [[ $version != "Isabelle2021-1" ]]; then
  echo "Wrong isabelle version: $version"
  exit 1
fi

# Create benchmark settings dir
benchmark_user_home="$(pwd)/benchmark_$timestamp"
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

if [[ ! -d afp ]]; then
  curl https://www.isa-afp.org/release/afp-current.tar.gz --output afp.tar.gz
  tar -xzf afp.tar.gz
  rm afp.tar.gz
  mv afp*/ afp
fi

afp=$(realpath "afp")


# Start benchmark settings file
$isabelle components -I

# Find out system
case "$OSTYPE" in
  linux*)   os="linux" ;;
  cygwin*)  os="windows" ;;
  *)        echo "Unsupported os: $OSTYPE"
            exit 1;;
esac

memory=$(($(grep "^MemTotal:" /proc/meminfo | awk '{print $2}') / 1000024))
# Prompt user for cpu model name if not available (some arm systems)
if grep -q -m 1 "^model name" /proc/cpuinfo; then
  cpu=$(grep -m 1 "^model name" /proc/cpuinfo | awk  '{print substr($0, index($0,$4))}')
else
  echo "Could not identify cpu. Please specify cpu model name:"
  read -r cpu
fi
cores=$(grep -c "^processor" /proc/cpuinfo)

case $(uname -m) in
  "x86_64")  arch="x86_64" ;;
  *)         echo "Unsupported platform: $(uname -m)"
             exit 1;;
esac

# Finish settings file
settings="$benchmark_user_home/.isabelle/$version/etc/settings"
{
  echo "ML_OPTIONS=\"--maxheap ${ml_heap}G\"";
  echo "ISABELLE_TOOL_JAVA_OPTIONS=\"-Djava.awt.headless=true -Xms512m -Xmx${jvm_heap}g -Xss16m\"";
  echo "ISABELLE_PLATFORM64=\"${arch}_32-${os}\"";
  echo 'ML_PLATFORM="$ISABELLE_PLATFORM64"';
  echo 'ML_HOME="$ML_HOME/../$ML_PLATFORM"';
  echo 'ML_PLATFORM="$ISABELLE_PLATFORM64"';
} > "$settings"

echo "$afp" > "$benchmark_user_home/.isabelle/$version/etc/components"

echo "Your system: $arch-$os on $cpu with ${memory}G RAM, $cores cores"
jobs=$((cores / threads))
if [[ $memory -lt $((jobs * (ml_heap + jvm_heap))) ]]; then
  echo "Not enough memory for ${jobs} with $ml_heap + $jvm_heap GB heap"
fi
log="benchmark_$timestamp.log"
echo "Building AFP with NUMA, $jobs jobs, $threads threads/job, and $ml_heap + $jvm_heap G heap per job..." | tee "$log"

SECONDS=0
start=$(date +%Y-%m-%d_%H-%M-%S)
echo "Start: $start" | tee -a "$log"
$isabelle build -c -d '$AFP' -o threads="$threads" -v -N -j "$jobs" -X slow -g AFP | tee -a "$log"
end=$(date +%Y-%m-%d_%H-%M-%S)
echo "End: $end" | tee -a "$log"
echo "Duration: $(date -d@$SECONDS -u +%H:%M:%S)" | tee -a "$log"
