# Re-running experiments
First fill in the benchmark values in [the results spreadsheets](./data/),
then run `data.R` from its directory.
# Building Document
To generate LaTeX document and plots, run `R -e 'library(knitr);knit("data.Rtex")'` from the data dir,
and then compile with tex.