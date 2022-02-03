# isabelle-benchmark
Isabelle user benchmark, results in the [spreadsheet](https://docs.google.com/spreadsheets/d/12GhEwSNSopowDBq5gSem3u39fliiIcoTIZHMnX4RE3A).

## Prerequisites
Download and install [Isabelle2021-1](https://isabelle.in.tum.de/).

## Running the benchmark automatically
Download the [benchmark script](https://raw.githubusercontent.com/Dacit/isabelle-benchmark/main/benchmark.sh).
Each configuration takes about 5 minutes.

### Linux
If you have Isabelle2021-1 in your `$PATH`, run `./benchmark.sh`.

Otherwise, specify the path to your Isabelle2021-1 installation, e.g.: `./benchmark.sh /opt/Isabelle2021-1/bin/isabelle`

### Windows
Copy the script into your isabelle folder, start the isabelle cygwin shell and run the script from there: `./benchmark.sh`
