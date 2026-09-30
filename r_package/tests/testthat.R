library(testthat)

# Not an R package -- run all tests under tests/testthat/ directly.
# Invoke from the repo root, e.g.:
#   Rscript tests/testthat.R
test_dir("tests/testthat", reporter = "summary")
