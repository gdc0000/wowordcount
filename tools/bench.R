# Speed benchmark for the wowordcount counting pipeline.
# Usage:
#   Rscript tools/bench.R [n_docs] [n_tokens_per_doc]
#
# Builds a synthetic corpus + dictionary (exact, wildcard and multi-word
# terms) and times wc_analyze_corpus with and without detected-words
# collection. Seed is fixed for reproducibility.

n_docs <- if (length(commandArgs(TRUE)) >= 1) as.integer(commandArgs(TRUE)[[1]]) else 50L
n_tok  <- if (length(commandArgs(TRUE)) >= 2) as.integer(commandArgs(TRUE)[[2]]) else 1000L

# resolve repo root relative to this script location
script_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))))
for (f in c("tokenizer.R", "counter.R", "dictionary.R", "pipeline.R"))
  source(file.path(script_dir, "..", "R", f))

set.seed(1)
outer2 <- outer(letters, letters, paste0)
vocab <- outer(outer2, letters, paste0)
sp <- " "
texts <- vapply(
  seq_len(n_docs),
  function(i) paste(sample(vocab, n_tok, replace = TRUE), collapse = sp),
  character(1))

dict <- list(
  categories = c("A", "B", "C"),
  exact_single = list(A = sample(vocab, 300), B = sample(vocab, 300),
                      C = sample(vocab, 300)),
  wildcard_single = list(A = letters[1:10], B = letters[11:20],
                         C = letters[5:15]),
  exact_multi = list(A = paste(vocab[1:5], vocab[2:6], sep = " "),
                     B = paste(vocab[10:14], vocab[11:15], sep = " "),
                     C = paste(vocab[20:24], vocab[21:25], sep = " ")),
  wildcard_multi = list(A = paste(c("ab", "ac"), collapse = " "),
                        B = paste(c("ba", "bc"), collapse = " "),
                        C = paste(c("ca", "cb"), collapse = " ")))

cat(sprintf("corpus: %d docs x %d tokens; dict: 3 cats\n", n_docs, n_tok))

t0 <- Sys.time()
invisible(wc_analyze_corpus(texts, dict, collect_detected = FALSE))
t1 <- Sys.time()
cat(sprintf("analyze (no detected):  %8.3f s\n", as.numeric(t1 - t0, "secs")))

t0 <- Sys.time()
invisible(wc_analyze_corpus(texts, dict, collect_detected = TRUE))
t1 <- Sys.time()
cat(sprintf("analyze (detected):     %8.3f s\n", as.numeric(t1 - t0, "secs")))
