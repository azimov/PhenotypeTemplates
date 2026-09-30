library(Capr)

# ---- mock ConceptSet helpers ----------------------------------------------

mockCs <- function(ids, name = "mock") {
  do.call(Capr::cs, c(lapply(ids, Capr::descendants), list(name = name)))
}
