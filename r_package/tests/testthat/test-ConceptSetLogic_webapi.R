test_that("reconstructAtlasConceptSetExpression rebuilds data.frame-shaped items", {
  cs <- list(
    items = data.frame(
      isExcluded = FALSE,
      includeDescendants = TRUE,
      includeMapped = FALSE,
      concept.CONCEPT_ID = 12345,
      concept.CONCEPT_NAME = "Mock concept",
      check.names = FALSE
    )
  )
  names(cs$items) <- c("isExcluded", "includeDescendants", "includeMapped", "concept.CONCEPT_ID", "concept.CONCEPT_NAME")

  rebuilt <- PhenotypeTemplates:::reconstructAtlasConceptSetExpression(cs)

  expect_type(rebuilt$items, "list")
  expect_false(is.data.frame(rebuilt$items))
  expect_equal(length(rebuilt$items), 1L)
  expect_equal(rebuilt$items[[1]]$isExcluded, FALSE)
  expect_equal(rebuilt$items[[1]]$includeDescendants, TRUE)
})

test_that("reconstructAtlasConceptSetExpression leaves already-list items unchanged", {
  cs <- list(items = list(list(concept = list(CONCEPT_ID = 1), isExcluded = FALSE)))
  rebuilt <- PhenotypeTemplates:::reconstructAtlasConceptSetExpression(cs)
  expect_identical(rebuilt, cs)
})

test_that("buildExactCaprConceptSet builds a Capr ConceptSet from a plain ID vector", {
  csObj <- buildExactCaprConceptSet(c(1L, 2L, 2L, 3L), name = "myConceptSet")

  expect_s4_class(csObj, "ConceptSet")
  expect_equal(csObj@Name, "myConceptSet")
  expect_equal(length(csObj@Expression), 3L)
})
