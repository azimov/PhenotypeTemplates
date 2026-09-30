test_that("phenotypeConfig requires clinicalCourse and expectedCareSetting", {
  expect_error(phenotypeConfig())
  expect_error(phenotypeConfig(clinicalCourse = "persistent_stable"))
})

test_that("phenotypeConfig produces a list with all expected fields", {
  cfg <- phenotypeConfig(
    clinicalCourse = "persistent_stable",
    expectedCareSetting = "outpatient_expected"
  )

  expect_type(cfg, "list")
  expect_true(all(c(
    "clinicalCourse", "expectedCareSetting", "minAge", "maxAge",
    "male", "female", "minimumInterepisodeDayGap", "recommendedCohortExit",
    "fixedExitDays", "hasDescreteRecordedSymptoms", "requiresDiagnosticTestOrProcedure",
    "requiresActiveTreatmentWithin30d", "expectsConditionSpecificFollowupOrSequelae1yr"
  ) %in% names(cfg)))
})

test_that("phenotypeConfig defaults booleans to FALSE", {
  cfg <- phenotypeConfig(
    clinicalCourse = "persistent_stable",
    expectedCareSetting = "acute_care_common"
  )

  expect_false(cfg$hasDescreteRecordedSymptoms)
  expect_false(cfg$requiresDiagnosticTestOrProcedure)
  expect_false(cfg$requiresActiveTreatmentWithin30d)
  expect_false(cfg$expectsConditionSpecificFollowupOrSequelae1yr)
  expect_false(cfg$male)
  expect_false(cfg$female)
})

test_that("validatePhenotypeConfig coerces NA numeric fields to NULL or 0", {
  cfg <- phenotypeConfig(
    clinicalCourse = "persistent_stable",
    expectedCareSetting = "outpatient_expected",
    minAge = NA,
    maxAge = NA,
    minimumInterepisodeDayGap = NA,
    fixedExitDays = NA
  )

  validated <- validatePhenotypeConfig(cfg)

  expect_null(validated$minAge)
  expect_null(validated$maxAge)
  expect_equal(validated$minimumInterepisodeDayGap, 0)
  expect_null(validated$fixedExitDays)
})

test_that("phenotypeConfig honors provided boolean and numeric values", {
  cfg <- phenotypeConfig(
    clinicalCourse = "transient_recurrent",
    expectedCareSetting = "acute_care_common",
    minAge = 40,
    maxAge = 80,
    male = TRUE,
    minimumInterepisodeDayGap = 90,
    requiresActiveTreatmentWithin30d = TRUE
  )

  expect_equal(cfg$minAge, 40)
  expect_equal(cfg$maxAge, 80)
  expect_true(cfg$male)
  expect_false(cfg$female)
  expect_equal(cfg$minimumInterepisodeDayGap, 90)
  expect_true(cfg$requiresActiveTreatmentWithin30d)
})

test_that("phenotypeConfig can be passed to buildPhenotypeTemplates", {
  cfg <- phenotypeConfig(
    clinicalCourse = "persistent_stable",
    expectedCareSetting = "outpatient_expected"
  )

  cds <- buildPhenotypeTemplates(
    mockCs(c(200L)), NULL, NULL, NULL, NULL, mockCs(c(205L)), NULL, NULL,
    phenotypeLabel = "Test Disease",
    config = cfg
  )

  expect_s3_class(cds, "data.frame")
  expect_true(nrow(cds) > 0)
})
