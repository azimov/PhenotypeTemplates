
connectionDetails <- Eunomia::getEunomiaConnectionDetails()

# Concept ids known to exist in concepts_eunomia.csv
sinusitis <- 4283893L               # Sinusitis (Condition)
acuteBacterialSinusitis <- 4294548L # Acute bacterial sinusitis (Condition)
seasonalRhinitis <- 4280726L        # Seasonal allergic rhinitis (Condition)
perennialRhinitis <- 40486433L      # Perennial allergic rhinitis (Condition)
childhoodAsthma <- 4051466L         # Childhood asthma (Condition)
rupturedAppendix <- 4166224L        # Rupture of appendix (Condition)

# Helper: load a concept set expression (simplified JSON for testing)
makeSimpleExpression <- function(conceptIds, descendants = FALSE, exclusions = NULL) {
  items <- lapply(conceptIds, function(id) {
    list(
      concept = list(CONCEPT_ID = id),
      isExcluded = FALSE,
      includeDescendants = descendants,
      includeMapped = FALSE
    )
  })
  if (!is.null(exclusions)) {
    excItems <- lapply(exclusions, function(id) {
      list(
        concept = list(CONCEPT_ID = id),
        isExcluded = TRUE,
        includeDescendants = FALSE,
        includeMapped = FALSE
      )
    })
    items <- c(items, excItems)
  }
  list(items = items)
}

# ---- Tests ----------------------------------------------------------------

test_that("unionConceptsets handles single concept set", {
  conceptSet <- makeSimpleExpression(c(sinusitis))
  outputDir <- tempfile(pattern = "union_test_")
  dir.create(outputDir)

  result <- unionConceptsets(
    conceptsetName = "single_sinusitis",
    conceptSetExpressions = list(conceptSet),
    connectionDetails = connectionDetails,
    vocabularyDatabaseSchema = "main",
    outputFolder = outputDir
  )

  expect_is(result, "list")
  expect_true("items" %in% names(result))
  expect_true(length(result$items) > 0)

  # Check output file was created
  outFile <- file.path(outputDir, "single_sinusitis.json")
  expect_true(file.exists(outFile))
})

test_that("unionConceptsets correctly unions two non-overlapping sets", {
  cs1 <- makeSimpleExpression(c(sinusitis))
  cs2 <- makeSimpleExpression(c(childhoodAsthma))
  outputDir <- tempfile(pattern = "union_test_")
  dir.create(outputDir)

  result <- unionConceptsets(
    conceptsetName = "union_sinusitis_asthma",
    conceptSetExpressions = list(cs1, cs2),
    connectionDetails = connectionDetails,
    vocabularyDatabaseSchema = "main",
    outputFolder = outputDir
  )

  expect_is(result, "list")
  expect_true(length(result$items) >= 2)
})

test_that("unionConceptsets respects union voting rule: if one set excludes but another includes, concept survives", {
  # cs1: includes and excludes sinusitis (self-canceling)
  cs1 <- makeSimpleExpression(c(sinusitis), exclusions = c(sinusitis))
  # cs2: includes sinusitis cleanly
  cs2 <- makeSimpleExpression(c(sinusitis))
  outputDir <- tempfile(pattern = "union_test_")
  dir.create(outputDir)

  result <- unionConceptsets(
    conceptsetName = "union_with_exclusion_override",
    conceptSetExpressions = list(cs1, cs2),
    connectionDetails = connectionDetails,
    vocabularyDatabaseSchema = "main",
    outputFolder = outputDir
  )

  connection <- DatabaseConnector::connect(connectionDetails)
  resolved <- .resolve(connection, result, vocabularyDatabaseSchema = "main")
  DatabaseConnector::disconnect(connection)

  # sinusitis should survive in union (cs2 includes it without exclusion)
  expect_true(sinusitis %in% resolved)
})

test_that("unionConceptsets drops a concept excluded by every set that included it", {
  # Both sets include and exclude the same concept -- no set truly retains it
  cs1 <- makeSimpleExpression(c(acuteBacterialSinusitis), exclusions = c(acuteBacterialSinusitis))
  cs2 <- makeSimpleExpression(c(acuteBacterialSinusitis), exclusions = c(acuteBacterialSinusitis))
  outputDir <- tempfile(pattern = "union_test_")
  dir.create(outputDir)

  result <- unionConceptsets(
    conceptsetName = "union_unanimous_exclusion",
    conceptSetExpressions = list(cs1, cs2),
    connectionDetails = connectionDetails,
    vocabularyDatabaseSchema = "main",
    outputFolder = outputDir
  )

  connection <- DatabaseConnector::connect(connectionDetails)
  resolved <- .resolve(connection, result, vocabularyDatabaseSchema = "main")
  DatabaseConnector::disconnect(connection)

  expect_false(acuteBacterialSinusitis %in% resolved)
})

test_that("unionConceptsets handles overlapping concept sets", {
  cs1 <- makeSimpleExpression(c(sinusitis, seasonalRhinitis))
  cs2 <- makeSimpleExpression(c(sinusitis, perennialRhinitis))
  outputDir <- tempfile(pattern = "union_test_")
  dir.create(outputDir)

  result <- unionConceptsets(
    conceptsetName = "union_overlapping",
    conceptSetExpressions = list(cs1, cs2),
    connectionDetails = connectionDetails,
    vocabularyDatabaseSchema = "main",
    outputFolder = outputDir
  )

  connection <- DatabaseConnector::connect(connectionDetails)
  resolved <- .resolve(connection, result, vocabularyDatabaseSchema = "main")
  DatabaseConnector::disconnect(connection)

  # sinusitis must be in union (in both sets); other unique concepts also retained
  expect_true(sinusitis %in% resolved)
  expect_true(seasonalRhinitis %in% resolved)
  expect_true(perennialRhinitis %in% resolved)
})

test_that("unionConceptsets produces valid JSON with correct structure", {
  cs1 <- makeSimpleExpression(c(rupturedAppendix))
  outputDir <- tempfile(pattern = "union_test_")
  dir.create(outputDir)

  result <- unionConceptsets(
    conceptsetName = "json_output_test",
    conceptSetExpressions = list(cs1),
    connectionDetails = connectionDetails,
    vocabularyDatabaseSchema = "main",
    outputFolder = outputDir
  )

  outFile <- file.path(outputDir, "json_output_test.json")
  expect_true(file.exists(outFile))

  # Read and validate JSON structure
  readBack <- jsonlite::read_json(outFile, simplifyVector = FALSE)
  expect_true("items" %in% names(readBack))
  expect_true(is.list(readBack$items))

  if (length(readBack$items) > 0) {
    item <- readBack$items[[1]]
    expect_true("concept" %in% names(item))
    expect_true("isExcluded" %in% names(item))
    expect_true("includeDescendants" %in% names(item))
  }
})

test_that("unionConceptsets handles empty concept sets", {
  cs1 <- list(items = list())
  outputDir <- tempfile(pattern = "union_test_")
  dir.create(outputDir)

  result <- unionConceptsets(
    conceptsetName = "empty_union",
    conceptSetExpressions = list(cs1),
    connectionDetails = connectionDetails,
    vocabularyDatabaseSchema = "main",
    outputFolder = outputDir
  )

  expect_is(result, "list")
  expect_true("items" %in% names(result))
})

test_that("unionConceptsets final verification detects union correctness issues", {
  cs1 <- makeSimpleExpression(c(sinusitis))
  outputDir <- tempfile(pattern = "union_test_")
  dir.create(outputDir)

  # Capture messages to verify correctness check runs
  msgs <- capture_messages({
    result <- unionConceptsets(
      conceptsetName = "verify_union",
      conceptSetExpressions = list(cs1),
      connectionDetails = connectionDetails,
      vocabularyDatabaseSchema = "main",
      outputFolder = outputDir
    )
  })

  # Should contain "Union 'verify_union':" message with missing/extra counts
  expect_true(any(grepl("Union", msgs, fixed = TRUE)))
  expect_true(any(grepl("missing", msgs, fixed = TRUE)))
})

