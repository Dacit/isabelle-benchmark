suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(tidyr))
suppressPackageStartupMessages(library(readr))
suppressPackageStartupMessages(library(lubridate))
suppressPackageStartupMessages(library(knitr))
suppressPackageStartupMessages(library(caret))
suppressPackageStartupMessages(library(stringr))

the <- function(.data, .row) {
  if (count(.data) == 1) {
    single <- .data %>% slice_head(n = 1)
    if (missing(.row)) single %>% pull() %>% head()
    else single %>% pull(var = { { .row } }) %>% head()
  } else simpleError("Expected single row")
}

extract_where <- function(.data, .cond, .row, ...) {
  groups <- .data %>%
    group_by(...) %>%
    filter(any({ { .cond } }))
  if (dim(groups)[1] == 0) groups
  else groups %>%
    group_modify(~.x %>%
      mutate(res = .x %>%
        filter({ { .cond } }) %>%
        the({ { .row } })))
}

box <- function(.data, .group, .val) {
  .data %>%
    group_by({ { .group } }) %>%
    summarise(
      lw = min({ { .val } }),
      lq = quantile({ { .val } }, 0.25),
      med = median({ { .val } }),
      uq = quantile({ { .val } }, 0.75),
      uw = max({ { .val } }),
      ss = n(),
      .groups = 'drop')
}

benchmark_results <- subset(read.csv(file = 'Isabelle 2021-1 Benchmark - Answers_Batch.csv'), cpu != '')
cpu_score_results <- subset(subset(read.csv(file = 'Isabelle Benchmark Experiments - results.csv'), X != ''), status == 'OK')

num_cpus <- nrow(unique(cpu_score_results['X']))
num_runs <- nrow(benchmark_results)
num_conf <- nrow(unique(benchmark_results[c('cpu', 'heap', 'threads')]))

cpus <- unique(benchmark_results['cpu']) %>%
  pull(cpu) %>%
  sort() %>%
  combine_words(sep = ',', and = '')

threads <- unique(benchmark_results['threads']) %>%
  pull(threads) %>%
  sort() %>%
  combine_words(sep = ',', and = '')

median_time_df <- data.frame(benchmark_results[c('cpu', 'heap', 'threads', 'time')]) %>%
  mutate(time = period_to_seconds(hms(time))) %>%
  group_by(cpu, heap, threads) %>%
  summarise(time = median(time), .groups = 'drop')

best_time <- median_time_df %>%
  filter(time == min(time)) %>%
  the(time)

worst_time_h <- median_time_df %>%
  filter(time == max(time)) %>%
  the(time) / (60 * 60)

best_server_time <- median_time_df %>%
  filter(grepl('EPYC', cpu, fixed = TRUE) | grepl('Threadripper', cpu, fixed = TRUE) | grepl('Xeon', cpu, fixed = TRUE)) %>%
  filter(time == min(time)) %>%
  the(time)

rel_time_by_heap_df <- bind_rows(
  median_time_df %>%
    filter(threads == 1) %>%
    extract_where(cpu, .cond = heap == 4, .row = time),
  median_time_df %>%
    filter(threads < 16) %>%
    group_by(threads) %>%
    group_modify(~.x %>%
      extract_where(cpu, .cond = heap == the(.y), .row = time)),
  median_time_df %>%
    filter(threads >= 16) %>%
    group_by(threads) %>%
    group_modify(~.x %>%
      extract_where(cpu, .cond = heap == 16, .row = time))) %>%
  group_by(threads, heap) %>%
  filter(n() > 2) %>%
  ungroup() %>%
  transmute(cpu, threads = threads, heap = heap, rel = time / res)

rel_time_by_heap_box <- rel_time_by_heap_df %>%
  filter(threads %in% c(8, 16, 32, 64)) %>%
  group_by(threads) %>%
  group_modify(~.x %>% box(heap, rel)) %>%
  mutate(heap = log2(heap)) %>%
  format_csv()

heap_outlier <- rel_time_by_heap_df %>%
  filter(threads == 64 & heap == 128) %>%
  pull(rel) %>%
  min()

median_min_time_df <- median_time_df %>%
  group_by(cpu, threads) %>%
  summarise(time = min(time), .groups = 'drop')

median_min_df <- median_min_time_df %>%
  mutate(isascore = (24 * 60 * 60) / time)

median_min_cputime_by_thread <- data.frame(benchmark_results[c('cpu', 'heap', 'threads', 'cputime')]) %>%
  filter(cputime != '') %>%
  mutate(cputime = period_to_seconds(hms(cputime))) %>%
  group_by(cpu, heap, threads) %>%
  summarise(cputime = median(cputime), .groups = 'drop') %>%
  group_by(cpu, threads) %>%
  summarise(cputime = min(cputime), .groups = 'drop') %>%
  mutate(cputime = cputime / threads)

trim <- function(data, sep) {
  str_split_fixed(data, sep, 2)[1]
}

top_cpus <- right_join(median_min_time_df, cpu_score_results[c('X', 'Cores', 'Base.Freq')], by = c('cpu' = 'X')) %>%
  group_by(cpu, Cores, Base.Freq) %>%
  summarise(time = min(time), .groups = 'drop') %>%
  rowwise() %>%
  transmute(cpu = cpu %>% trim('Processor') %>% trim('CPU') %>% trim('\\d+-Core') %>% trim('@'),
            time = time, baseclock = Base.Freq / 1000, cores = Cores) %>%
  ungroup() %>%
  top_n(n = -5, wt = time) %>%
  arrange(time = time) %>%
  format_csv()

time_by_threads <- median_min_time_df %>%
  format_csv()

cputime_by_threads <- median_min_cputime_by_thread %>%
  format_csv()

mt_score_df <- median_min_df %>%
  group_by(cpu) %>%
  summarise(threads = threads, time = time, mintime = min(time), .groups = 'drop') %>%
  group_by(cpu) %>%
  group_modify(~ .x %>% filter(time == mintime)) %>%
  ungroup() %>%
  mutate(isascore = (24 * 60 * 60) / time)

parallel_efficiency_df <- median_min_time_df %>%
  extract_where(cpu, .cond = threads == 1, .row = time) %>%
  mutate(rel = (res / threads) / time)

parallel_efficiency <- parallel_efficiency_df %>%
  select(cpu, threads, rel) %>%
  format_csv()

eff_32 <- parallel_efficiency_df %>%
  filter(threads == 32) %>%
  pull(rel) %>%
  median()
eff_128 <- parallel_efficiency_df %>%
  filter(threads == 128) %>%
  pull(rel) %>%
  median()

by_os <- data.frame(benchmark_results[c('os', 'cpu', 'heap', 'threads', 'time')]) %>%
  mutate(time = period_to_seconds(hms(time))) %>%
  group_by(os, cpu, heap, threads) %>%
  summarise(time = median(time), .groups = 'drop') %>%
  group_by(cpu, heap, threads) %>%
  filter(n() > 1) %>%
  ungroup() %>%
  extract_where(cpu, heap, threads, .cond = os == 'linux', .row = time) %>%
  mutate(rel = time / res)

####################################################################################################

join_res <- function(.data, ...) {
  right_join(.data, cpu_score_results, by = c('cpu' = 'X')) %>%
    transmute(time = time, isascore = isascore, ...) %>%
    gather('benchmark', 'score', -time, -isascore) %>%
    filter(!is.na(score) & !is.na(time))
}

# Cpu Parameters

cpu_specs_df <- bind_rows(
  median_min_df %>%
    filter(threads == 1) %>%
    join_res(
      cache = Cache,
      base = Base.Freq,
      max = Max.Freq) %>%
    mutate(threads = '1 thread'),
  median_min_df %>%
    filter(threads == 8) %>%
    join_res(
      cache = Cache,
      base = Base.Freq,
      max = Max.Freq) %>%
    mutate(threads = '8 threads'),
  median_min_df %>%
    group_by(cpu) %>%
    summarise(time = min(time), isascore = max(isascore)) %>%
    join_res(
      cache = Cache,
      base = Base.Freq,
      max = Max.Freq) %>%
    mutate(threads = 'optimal config'))

cpu_specs_cor_df <- cpu_specs_df %>%
  group_by(benchmark, threads) %>%
  summarise(cor = cor(isascore, score, use = "complete.obs"), p = cor.test(isascore, score, use = "complete.obs")$p.value, n = n(), .groups = 'drop') %>%
  filter(p < 0.05) %>%
  pivot_wider(names_from = benchmark, values_from = c(cor, p, n), names_sep = '') %>%
  arrange(threads)

boostfreq_1t_cor_n <- cpu_specs_cor_df %>% filter(threads == '1 thread') %>% the(nmax)
boostfreq_1t_cor <- cpu_specs_cor_df %>% filter(threads == '1 thread') %>% the(cormax)
boostfreq_1t_cor_p <- sprintf("%f", cpu_specs_cor_df %>% filter(threads == '1 thread') %>% the(pmax))
basefreq_mt_cor_n <- cpu_specs_cor_df %>% filter(threads == 'optimal config') %>% the(nbase)
basefreq_mt_cor <- cpu_specs_cor_df %>% filter(threads == 'optimal config') %>% the(corbase)
basefreq_mt_cor_p <- sprintf("%f", cpu_specs_cor_df %>% filter(threads == 'optimal config') %>% the(pbase))

cpu_specs_mt_cor <- cpu_specs_cor_df %>% select(cormax) %>% max()

cpu_specs_cor <- cpu_specs_cor_df %>% mutate_if(is.numeric, round, 3) %>% format_csv(na = '')

# Single-threaded Analysis

benchmarks_consumer_1t_df <- median_min_df %>%
  filter(threads == 1) %>%
  join_res(
    passmark = Passmark.1T,
    x3dmark = X3DMark.CPU.Profile.1T,
    geekbench = Geekbench.1T,
    cinebench = Cinebench.R15.1T)

benchmarks_consumer_mt_df <- mt_score_df %>%
  join_res(
    passmark_1t = Passmark.1T,
    passmark_mt = Passmark.MT,
    x3dmark_1t = X3DMark.CPU.Profile.1T,
    x3dmark_mt = X3DMark.CPU.Profile.MT,
    geekbench_1t = Geekbench.1T,
    geekbench_mt = Geekbench.MT,
    cinebench_1t = Cinebench.R15.1T,
    cinebench_mt = Cinebench.R15.MT)

benchmarks_consumer_1t_r2_df <- benchmarks_consumer_1t_df %>%
  group_by(benchmark) %>%
  summarise(r2 = summary(lm(isascore ~ score))$r.squared)

benchmarks_consumer_mt_r2_df <- benchmarks_consumer_mt_df %>%
  group_by(benchmark) %>%
  summarise(r2 = summary(lm(isascore ~ score))$r.squared)

benchmarks_consumer_1t_rel_df <- benchmarks_consumer_1t_df %>%
  group_by(benchmark) %>%
  summarise(isascore = isascore, score = (score - min(score)) / (max(score) - min(score)), .groups = 'drop')

passmark_1t_rel <- benchmarks_consumer_1t_rel_df %>% filter(benchmark == 'passmark') %>% format_csv()
passmark_1t_r2 <- benchmarks_consumer_1t_r2_df %>% filter(benchmark == 'passmark') %>% the(r2)
passmark_mt_r2 <- benchmarks_consumer_mt_r2_df %>% filter(benchmark == 'passmark_1t') %>% the(r2)
passmarkm_mt_r2 <- benchmarks_consumer_mt_r2_df %>% filter(benchmark == 'passmark_mt') %>% the(r2)
x3dmark_1t_rel <- benchmarks_consumer_1t_rel_df %>% filter(benchmark == 'x3dmark') %>% format_csv()
x3dmark_1t_r2 <- benchmarks_consumer_1t_r2_df %>% filter(benchmark == 'x3dmark') %>% the(r2)
x3dmark_mt_r2 <- benchmarks_consumer_mt_r2_df %>% filter(benchmark == 'x3dmark_1t') %>% the(r2)
x3dmarkm_mt_r2 <- benchmarks_consumer_mt_r2_df %>% filter(benchmark == 'x3dmark_mt') %>% the(r2)
geekbench_1t_rel <- benchmarks_consumer_1t_rel_df %>% filter(benchmark == 'geekbench') %>% format_csv()
geekbench_1t_r2 <- benchmarks_consumer_1t_r2_df %>% filter(benchmark == 'geekbench') %>% the(r2)
geekbench_mt_r2 <- benchmarks_consumer_mt_r2_df %>% filter(benchmark == 'geekbench_1t') %>% the(r2)
geekbenchm_mt_r2 <- benchmarks_consumer_mt_r2_df %>% filter(benchmark == 'geekbench_mt') %>% the(r2)
cinebench_1t_rel <- benchmarks_consumer_1t_rel_df %>% filter(benchmark == 'cinebench') %>% format_csv()
cinebench_1t_r2 <- benchmarks_consumer_1t_r2_df %>% filter(benchmark == 'cinebench') %>% the(r2)
cinebench_mt_r2 <- benchmarks_consumer_mt_r2_df %>% filter(benchmark == 'cinebench_1t') %>% the(r2)
cinebenchm_mt_r2 <- benchmarks_consumer_mt_r2_df %>% filter(benchmark == 'cinebench_mt') %>% the(r2)

benchmarks_hpc_1t_df <- median_min_df %>%
  filter(threads == 1) %>%
  join_res(
    himeno = Himeno,
    namd = NAMD,
    dolfyn = Dolfyn)

benchmarks_hpc_mt_df <- mt_score_df %>%
  join_res(
    himeno = Himeno,
    namd = NAMD,
    dolfyn = Dolfyn)

himeno_1t <- benchmarks_hpc_1t_df %>% filter(benchmark == 'himeno') %>% select(isascore, score) %>% format_csv()
himeno_1t_r2 <- summary(lm(isascore ~ score, data = benchmarks_hpc_1t_df %>% filter(benchmark == 'himeno')))$r.squared
himeno_mt_r2 <- summary(lm(isascore ~ score, data = benchmarks_hpc_mt_df %>% filter(benchmark == 'himeno')))$r.squared

namd_1t_df <- benchmarks_hpc_1t_df %>% filter(benchmark == 'namd')
namd_1t <- namd_1t_df %>% select(time, score) %>% format_csv()
namd_1t_p <- cor.test(namd_1t_df$time, namd_1t_df$score, use = "complete.obs")$p.value
namd_1t_r2 <- summary(lm(time ~ score, data = namd_1t_df))$r.squared
namd_mt <- benchmarks_hpc_mt_df %>% filter(benchmark == 'namd') %>% select(time, score) %>% format_csv()
namd_mt_r2 <- summary(lm(time ~ score, data = benchmarks_hpc_mt_df %>% filter(benchmark == 'namd')))$r.squared

dolfyn_1t <- benchmarks_hpc_1t_df %>% filter(benchmark == 'dolfyn') %>% select(time, score) %>% format_csv()
dolfyn_1t_r2 <- summary(lm(time ~ score, data = benchmarks_hpc_1t_df %>% filter(benchmark == 'dolfyn')))$r.squared
dolfyn_mt_r2 <- summary(lm(time ~ score, data = benchmarks_hpc_mt_df %>% filter(benchmark == 'dolfyn')))$r.squared

# Prediction
set.seed(42)
ctrl <- trainControl(method = "repeatedcv", number = 10, repeats = 10)

x3dmark_8t_df <- median_min_df %>%
  filter(threads == 8) %>%
  join_res(x3dmark = X3DMark.CPU.Profile.8T)

x3dmark_8t_r2 <- summary(lm(isascore ~ score, data = x3dmark_8t_df))$r.squared

x3dmark_16t_df <- median_min_df %>%
  filter(threads == 16) %>%
  join_res(x3dmark = X3DMark.CPU.Profile.16T)

x3dmark_16t_r2 <- summary(lm(isascore ~ score, data = x3dmark_16t_df))$r.squared

x3dmark_score_df <- cpu_score_results %>%
  filter(!is.na(X3DMark.CPU.Profile.8T) & !is.na(X3DMark.CPU.Profile.16T)) %>%
  mutate(score = 0.5 * X3DMark.CPU.Profile.8T + 0.5 * X3DMark.CPU.Profile.16T)

x3dmark_mt_df <- mt_score_df %>%
  right_join(x3dmark_score_df, by = c('cpu' = 'X')) %>%
  filter(!is.na(score))

x3dmark_mt <- x3dmark_mt_df %>%
  select(score, isascore, time) %>%
  format_csv()

predict_df <- x3dmark_mt_df %>%
  select(isascore, score)

model <- train(isascore ~ score, data = predict_df, method = "lm", trControl = ctrl, na.action = na.omit)
model_ax <- model$finalModel$coefficients[['score']]
model_b <- model$finalModel$coefficients[['(Intercept)']]

model_r2 <- model$results$Rsquared
predict_df$residual <- resid(model$finalModel)
predict_df$pred <- predict(model$finalModel, predict_df %>% select(score))

x3dmark_mt_residuals <- predict_df %>%
  select(score, residual) %>%
  format_csv()

model_final_r2 <- defaultSummary(predict_df %>% transmute(pred = pred, obs = isascore))[['Rsquared']]

prediction_time_df <- predict_df %>%
  mutate(obs = (24 * 60 * 60) / isascore, pred = (24 * 60 * 60) / pred)

model_final_time_mae <- defaultSummary(prediction_time_df)[['MAE']]


# Model with non-public data (true medians)
cpu_score_results_private <- subset(subset(read.csv(file = 'Isabelle Benchmark Experiments - private results.csv'), X != ''), status == 'OK')

x3dmark_score_private_df <- cpu_score_results_private %>%
  filter(!is.na(X3DMark.CPU.Profile.8T) & !is.na(X3DMark.CPU.Profile.16T)) %>%
  mutate(score = 0.5 * X3DMark.CPU.Profile.8T + 0.5 * X3DMark.CPU.Profile.16T)

predict_private_df <- mt_score_df %>%
  right_join(x3dmark_score_private_df, by = c('cpu' = 'X')) %>%
  filter(!is.na(score)) %>%
  select(isascore, score)

model_private <- train(isascore ~ score, data = predict_private_df, method = "lm", trControl = ctrl, na.action = na.omit)
model_private_r2 <- model_private$results$Rsquared
predict_private_df$pred <- predict(model_private$finalModel, predict_private_df %>% select(score))

model_private_final_r2 <- defaultSummary(predict_private_df %>% transmute(pred = pred, obs = isascore))[['Rsquared']]

prediction_time_private_df <- predict_private_df %>%
  mutate(obs = (24 * 60 * 60) / isascore, pred = (24 * 60 * 60) / pred)

model_private_final_time_mae <- defaultSummary(prediction_time_private_df)[['MAE']]
