#!/usr/bin/env bash
set -eu

timestamp=$(date +%Y-%m-%d_%H-%M-%S)

run_safe() {
  echo "> $*"
  "$@" || exit 255
}

threads=4

# Options parse
while [ $# -gt 0 ]
do
  case "$1" in
    "--threads")
      threads="$2"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 255
      ;;
  esac
  shift
done


detect_isabelle() {
  isabelle=""
  if [ -f "Isabelle2022/bin/isabelle" ]
  then
    isabelle="Isabelle2022/bin/isabelle"
  elif [ -f "Isabelle2022.exe" ]
  then
    isabelle="Isabelle2022.exe"
  else
    echo "No isabelle detected yet."
  fi
}

extract_archive() {
  isabelle_archive=""
  isabelle_archive_paths=("Isabelle2022_linux.tar.gz" "Isabelle2022_linux_arm.tar.gz" "Isabelle2022_macos.tar.gz")
  for isabelle_archive_path in $isabelle_archive_paths
  do
    if [ -f "$isabelle_archive_path" ]
    then
      isabelle_archive="$isabelle_archive_path"
      break
    fi
  done

  if [ -z "$isabelle_archive" ]
  then
    echo "Error: No isabelle archive found."
    exit 255
  fi

  echo "Extracting archive..."
  run_safe tar -xf "$isabelle_archive"
}


detect_isabelle

if [ -z "$isabelle" ]
then
  extract_archive
else
  echo "Detected existing Isabelle at $isabelle, not extracting archive."
fi

detect_isabelle

if [ -z "$isabelle" ]
then
    echo "Error: No isabelle found after extracting archives."
    exit 255
else
  echo "Detected Isabelle at $isabelle"
fi

# Check isabelle version
versions=("Isabelle2021-1" "Isabelle2022")
version=$($isabelle version)
if [[ ! " ${versions[*]} " =~ " $version " ]]; then
  echo "Wrong isabelle version: $version"
  exit 1
fi
echo "Using $version"

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

# Write benchmark settings file
$isabelle components -I
cat << \EOF > "$benchmark_user_home/.isabelle/$version/etc/settings"
ML_OPTIONS="--maxheap ${HEAP}G"
ISABELLE_TOOL_JAVA_OPTIONS="-Djava.awt.headless=true -Xms512m -Xmx${HEAP}g -Xss16m"
ISABELLE_PLATFORM64="${PLATFORM}"
ML_PLATFORM="$ISABELLE_PLATFORM64"
ML_HOME="$ML_HOME/../$ML_PLATFORM"
EOF

# Find out system
case "$OSTYPE" in
  darwin*)  os="darwin" ;;
  linux*)   os="linux" ;;
  msys*)    os="windows" ;;
  cygwin*)  os="windows" ;;
  *)        echo "Unsupported os: $OSTYPE"
            exit 1;;
esac

case $(uname -m) in
  "aarch64")  arch="arm64" ;;
  *)          arch=$(uname -m) ;;
esac


echo "Creating benchmark configs. Note that heap settings apply to both the polyml/jvm process."
if [[ $version == "Isabelle2021-1" && $os == "darwin" && $arch == "arm64" ]]; then
  echo "Using rosetta emulation with x86_64..."
  arch="x86_64"
fi

configs=("$arch 4 $threads")

echo "(platform heap cores):"

for config in "${configs[@]}"; do
  echo -n " ($config)"
done
echo ""


# Benchmark
do_run()
{
  export PLATFORM=$1
  export HEAP=$2
  local CORES=$3
  echo "Running Isabelle HOL analysis..."
  res=$($isabelle build -c -o threads="$CORES" HOL-Analysis)
  elapsed=$(echo "$res" | grep "Finished HOL-Analysis" | awk '{print $3}' | cut -c2-)
  echo "Total runtime: $(elapsed) Seconds"
}

for config in "${configs[@]}"; do
  do_run $config
done
