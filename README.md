# isabelle-benchmark
Isabelle user benchmark, results in the [spreadsheet](https://docs.google.com/spreadsheets/d/12GhEwSNSopowDBq5gSem3u39fliiIcoTIZHMnX4RE3A).

## Prerequisites
Download and extract [Isabelle2021-1](https://isabelle.in.tum.de/).

## Running the benchmark automatically
Download the [benchmark script](https://raw.githubusercontent.com/Dacit/isabelle-benchmark/main/benchmark.sh) into your Isabelle folder,
run it, and report the results. 
Each configuration takes about 5 minutes.
Windows users: start the isabelle cygwin shell and run the script from there.

## Running the Benchmark manually
In you Isabelle2021-1 `etc/settings`, put:
```sh
init_component "${ISABELLE_COMPONENTS_BASE:-$USER_HOME/.isabelle/contrib}"
ML_OPTIONS="--maxheap ${HEAP}"
ISABELLE_PLATFORM64="${PLATFORM}"
ML_PLATFORM="$ISABELLE_PLATFORM64"
ML_HOME="$ML_HOME/../$ML_PLATFORM"
```
Then run Isabelle with (put in proper values for `<?>`):
```sh
export HEAP=<?> && export PLATFORM=<?> && isabelle build -o threads=<?> -c HOL-Analysis
```
And look for the output line `Finished HOL-Analysis (0:05:06 elapsed time, 0:33:48 cpu time, factor 6.61)`.
Careful: There are multiple lines with elapsed/cpu time.
