#!/usr/bin/env bash

timestamp=$(date +%Y-%m-%d_%H-%M-%S)

run_safe() {
  echo "> $*"
  "$@" || exit 255
}


print_help() {
  echo """
    Usage: $0 [options]
    Runs isabelle benchmark for Phoronix Test Suite

    Options:
      --threads <num>             Specify the number of threads to use for Isabelle. Recommended <= 32 threads.
      --output-file <file>        The output file to write the isabelle log and solver time to.
      --pts                       Enable benchmarking within phoronix test suite. Sets output file to \$LOG_FILE environment variable.
      --install-only              Only detect or extract isabelle, don't actually benchmark.
      --target                    Set the Isabelle target to build. Defaults to HOL-Analysis.
      --isabelle-location <file>  Manually specify the location of isabelle.
      -h --print_help             Print this help page.
  """
}

isabelle=""
threads=4
output_file="/dev/null"
install_only=""
ISABELLE_TARGET="HOL-Analysis"

# Options parse
while [ $# -gt 0 ]
do
  case "$1" in
    "--threads")
      threads="$2"
      if [ "$threads" == "all" ]
      then
        threads="$(nproc)"
      fi
      shift
      ;;
    "--output-file")
      output_file="$2"
      shift
      ;;
    "--pts")
      output_file="$LOG_FILE"
      ;;
    "--install-only")
      install_only=1
      ;;
    "--target")
      ISABELLE_TARGET="$2"
      shift
      ;;
    "--isabelle-location")
      isabelle="$2"
      shift
      ;;
    "-h"|"--help")
      print_help
      exit 255
      ;;
    *)
      echo "Unknown option: $1"
      print_help
      exit 255
      ;;
  esac
  shift
done


detect_isabelle() {
  if [ -n "$isabelle" ]
  then
    # Already have isabelle
    return
  fi

  isabelle="$(which isabelle)"
  if [ $? -eq 0 ]
  then
    # Isabelle is on the path
    true
  elif [ -n "$ISABELLE_PATH" ]
  then
    isabelle="$ISABELLE_PATH"
  elif [ -f "Isabelle2022/bin/isabelle" ]
  then
    isabelle="Isabelle2022/bin/isabelle"
  elif [ -f "Isabelle2022.exe" ]
  then
    isabelle="Isabelle2022.exe"
  else
    echo "No isabelle detected yet (set --isabelle-location or \$ISABELLE_PATH to manually specify isabelle location)"
  fi
}

extract_archive() {
  isabelle_archive=""
  isabelle_archive_paths=("Isabelle2022_linux.tar.gz" "Isabelle2022_linux_arm.tar.gz" "Isabelle2022_macos.tar.gz")
  for isabelle_archive_path in "${isabelle_archive_paths[@]}"
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

if [ -n "$install_only" ]
then
  echo "Installation success".
  exit 0
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

# Write benchmark settings file
$isabelle components -I
cat << \EOF > "$benchmark_user_home/.isabelle/$version/etc/settings"
ISABELLE_TOOL_JAVA_OPTIONS="-Djava.awt.headless=true -Xms512m -Xmx4g -Xss16m"
ISABELLE_PLATFORM64="${PLATFORM}"
ML_PLATFORM="$ISABELLE_PLATFORM64"
ML_HOME="$ML_HOME/../$ML_PLATFORM"
EOF

# Fabian:
# isabelle build -b -R <session>. Das baut die requirements der session
# Sollte mit schnellen optionen gebaut werden, damit nicht Zeit mit dependencies vergeudet wird.
#

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
if [[ $version == "Isabelle2021-1" && $os == "darwin" && $arch == "arm64" ]]; then
  echo "Using rosetta emulation with x86_64..."
  arch="x86_64"
fi
export PLATFORM="${arch}_32-$os"


echo "Creating benchmark configs. Note that heap settings apply to both the polyml/jvm process."
configs=("$threads")

echo "cores:"
for config in "${configs[@]}"; do
  echo -n " ($config)"
done
echo ""

# Credit: https://stackoverflow.com/questions/18149127/convert-a-duration-hhmmss-to-seconds-in-bash
to_seconds () {
    IFS=: read h m s <<< "$1"
    echo $(( 10#$h * 3600 + 10#$m * 60 + 10#$s ))
}

# Benchmark
do_run()
{
  local CORES=$1
  echo "Running Isabelle $ISABELLE_TARGET..."
  run_safe $isabelle build -c -o threads="$CORES" "$ISABELLE_TARGET" | tee "$output_file"
  MATCH_STRING="s/Finished $ISABELLE_TARGET (\([0-9:]*\).*/\1/p"
#  echo "MATCH_STRING"
  result=$(sed -ne "$MATCH_STRING" "$output_file")
#  echo "Result match: '$result'"
  result_seconds=$(to_seconds "$result")
  echo "Total runtime: $result_seconds s" | tee -a "$output_file"
}

for config in "${configs[@]}"; do
  do_run $config
done
