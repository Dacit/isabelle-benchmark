# Isabelle Community Benchmark
Isabelle user benchmark.
Results are in the [spreadsheet](https://docs.google.com/spreadsheets/d/12GhEwSNSopowDBq5gSem3u39fliiIcoTIZHMnX4RE3A) -
put yours in as well!

## Prerequisites
Download and install [Isabelle](https://isabelle.in.tum.de/).

## Running the benchmark automatically
Download the [benchmark script](https://raw.githubusercontent.com/Dacit/isabelle-benchmark/main/benchmark.sh).
The first two configurations will take 30 minutes each; each further configuration about 5 minutes.

### Linux / Os X
If you have Isabelle in your `$PATH`, run `./benchmark.sh`.

Otherwise, specify the path to your Isabelle installation, e.g.: `./benchmark.sh /your/isabelle/dir/bin/isabelle`

### Windows
Copy the script into your isabelle folder, start the isabelle cygwin terminal (`Cygwin-Terminal.bat`) and run the script from there: `./benchmark.sh`
