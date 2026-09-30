test_that("getMetadataRow matches by canonical name", {
  metadata <- data.frame(
    condition_name = c("Acute liver failure", "Crohn's disease"),
    stringsAsFactors = FALSE
  )

  row <- getMetadataRow("Acute liver failure", metadata)
  expect_equal(nrow(row), 1L)
  expect_equal(row$condition_name, "Acute liver failure")
})

test_that("getMetadataRow applies nameOverrides", {
  metadata <- data.frame(
    condition_name = c("Pulmonary arterial hypertension (idiopathic/heritable forms only)"),
    stringsAsFactors = FALSE
  )
  overrides <- c(
    "Pulmonary arterial hypertension" =
      "Pulmonary arterial hypertension (idiopathic/heritable forms only)"
  )

  row <- getMetadataRow("Pulmonary arterial hypertension", metadata, nameOverrides = overrides)
  expect_equal(nrow(row), 1L)
})

test_that("getMetadataRow errors clearly on zero matches", {
  metadata <- data.frame(condition_name = "Crohn's disease", stringsAsFactors = FALSE)
  expect_error(
    getMetadataRow("Pulmonary arterial hypertension", metadata),
    "no metadata row found"
  )
})

test_that("getMetadataRow errors clearly on multiple matches", {
  metadata <- data.frame(
    condition_name = c("Acute liver failure", "Acute liver failure"),
    stringsAsFactors = FALSE
  )
  expect_error(
    getMetadataRow("Acute liver failure", metadata),
    "expected exactly 1"
  )
})

test_that("translateMetadataConfig produces a valid phenotypeConfig()", {
  metadataRow <- data.frame(
    clinical_course = "PERSISTENT_STABLE",
    expected_care_setting = "OUTPATIENT_EXPECTED",
    min_age_years = 18,
    max_age_years = NA,
    minimum_interepisode_gap_days = NA,
    recommended_cohort_exit = "END_OF_CONTINUOUS_OBSERVATION",
    recommended_exit_days = NA,
    has_discrete_recorded_symptoms = TRUE,
    requires_diagnostic_test_or_procedure = FALSE,
    requires_active_treatment_within_30d = FALSE,
    expects_condition_specific_followup_or_sequelae_1yr = FALSE,
    stringsAsFactors = FALSE
  )

  cfg <- translateMetadataConfig(metadataRow)
  expect_equal(cfg$clinicalCourse, "persistent_stable")
  expect_equal(cfg$expectedCareSetting, "outpatient_expected")
  expect_equal(cfg$recommendedCohortExit, "continuous_observation")

  exitConfig <- resolvePhenotypeExitStrategy(
    clinicalCourse = cfg$clinicalCourse,
    recommendedCohortExit = cfg$recommendedCohortExit,
    minimumInterepisodeDayGap = cfg$minimumInterepisodeDayGap,
    fixedExitDays = cfg$fixedExitDays
  )
  expect_equal(exitConfig$eraDays, 0L)
})
