test_that("I wins over A, H, E, S, C", {
  csI <- mockCs(c(1L, 2L), "I")
  csA <- mockCs(c(2L, 3L), "A")
  csH <- mockCs(c(2L, 4L), "H")
  csE <- mockCs(c(2L, 5L), "E")
  csS <- mockCs(c(2L, 6L), "S")
  csC <- mockCs(c(2L, 7L), "C")

  resolved <- resolveConceptSetOverlaps(
    csI, cs_H = csH, cs_S = csS, cs_D = NULL, cs_T = NULL,
    cs_C = csC, cs_A = csA, cs_E = csE, warnOnOverlap = FALSE
  )

  expect_false(2L %in% (resolved$cs_A@Expression |> vapply(function(x) x@Concept@concept_id, integer(1))))
  expect_false(2L %in% (resolved$cs_H@Expression |> vapply(function(x) x@Concept@concept_id, integer(1))))
  expect_false(2L %in% (resolved$cs_E@Expression |> vapply(function(x) x@Concept@concept_id, integer(1))))
  expect_false(2L %in% (resolved$cs_S@Expression |> vapply(function(x) x@Concept@concept_id, integer(1))))
  expect_false(2L %in% (resolved$cs_C@Expression |> vapply(function(x) x@Concept@concept_id, integer(1))))
})

test_that("A wins over H, E, S, C but not I", {
  csI <- mockCs(c(1L), "I")
  csA <- mockCs(c(10L), "A")
  csH <- mockCs(c(10L, 11L), "H")

  resolved <- resolveConceptSetOverlaps(
    csI, cs_H = csH, cs_A = csA, warnOnOverlap = FALSE
  )

  hIds <- vapply(resolved$cs_H@Expression, function(x) x@Concept@concept_id, integer(1))
  expect_false(10L %in% hIds)
  expect_true(11L %in% hIds)
})

test_that("S and C are allowed to overlap", {
  csI <- mockCs(c(1L), "I")
  csS <- mockCs(c(20L), "S")
  csC <- mockCs(c(20L), "C")

  resolved <- resolveConceptSetOverlaps(csI, cs_S = csS, cs_C = csC, warnOnOverlap = FALSE)

  expect_false(is.null(resolved$cs_S))
  expect_false(is.null(resolved$cs_C))
})

test_that("a set reduced to zero concepts becomes NULL", {
  csI <- mockCs(c(30L), "I")
  csA <- mockCs(c(30L), "A")

  resolved <- resolveConceptSetOverlaps(csI, cs_A = csA, warnOnOverlap = FALSE)

  expect_null(resolved$cs_A)
})
