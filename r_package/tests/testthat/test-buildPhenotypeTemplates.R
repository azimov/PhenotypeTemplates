csI <- mockCs(c(200L), "I")
csH <- mockCs(c(201L), "H")
csS <- mockCs(c(202L), "S")
csD <- mockCs(c(203L), "D")
csT <- mockCs(c(204L), "T")
csC <- mockCs(c(205L), "C")
csA <- mockCs(c(206L), "A")
csE <- mockCs(c(207L), "E")

baseConfig <- list(
  clinicalCourse = "persistent_stable",
  hasDescreteRecordedSymptoms = TRUE,
  requiresDiagnosticTestOrProcedure = TRUE,
  requiresActiveTreatmentWithin30d = TRUE,
  expectsConditionSpecificFollowupOrSequelae1yr = TRUE
)

test_that("acute_care_common produces both hosp variants x ladder x index x A axes", {
  config <- modifyList(baseConfig, list(expectedCareSetting = "acute_care_common"))

  cds <- buildPhenotypeTemplates(
    csI, csH, csS, csD, csT, csC, csA, csE,
    phenotypeLabel = "Mock Disease", config = config
  )

  # ladder: L0, L1, L2 (3) x index: I, I|H (2) x hosp: TRUE, FALSE (2) x A: with/without (2)
  expect_equal(nrow(cds), 3 * 2 * 2 * 2)
  expect_equal(length(unique(cds$cohortName)), nrow(cds))
  expect_equal(length(unique(cds$cohortId)), nrow(cds))
})

test_that("acute_care_expected produces only the hospitalization-restricted axis", {
  config <- modifyList(baseConfig, list(expectedCareSetting = "acute_care_expected"))

  cds <- buildPhenotypeTemplates(
    csI, csH, csS, csD, csT, csC, csA, csE,
    phenotypeLabel = "Mock Disease", config = config
  )

  expect_equal(nrow(cds), 3 * 2 * 1 * 2)
})

test_that("outpatient_expected produces only the non-hospitalization axis", {
  config <- modifyList(baseConfig, list(expectedCareSetting = "outpatient_expected"))

  cds <- buildPhenotypeTemplates(
    csI, csH, csS, csD, csT, csC, csA, csE,
    phenotypeLabel = "Mock Disease", config = config
  )

  expect_equal(nrow(cds), 3 * 2 * 1 * 2)
})

test_that("no cs_H and no cs_A collapses those axes to a single option", {
  config <- modifyList(baseConfig, list(expectedCareSetting = "outpatient_expected"))

  cds <- buildPhenotypeTemplates(
    csI, cs_H = NULL, cs_S = csS, cs_D = csD, cs_T = csT, cs_C = csC,
    cs_A = NULL, cs_E = csE,
    phenotypeLabel = "Mock Disease", config = config
  )

  expect_equal(nrow(cds), 3 * 1 * 1 * 1)
})

test_that("all evidence flags FALSE only produces the L0 base-case ladder level", {
  config <- list(
    clinicalCourse = "persistent_stable",
    expectedCareSetting = "outpatient_expected"
  )

  cds <- buildPhenotypeTemplates(
    csI, csH, csS, csD, csT, csC, csA, csE,
    phenotypeLabel = "Mock Disease", config = config
  )

  expect_equal(nrow(cds), 1 * 2 * 1 * 2)
  expect_true(all(grepl("^\\[PheTpl\\] Mock Disease tpl L0-", cds$cohortName)))
})

test_that("transient_single without fixedExitDays errors before building any cohort", {
  config <- modifyList(baseConfig, list(
    clinicalCourse = "transient_single", expectedCareSetting = "outpatient_expected"
  ))

  expect_error(
    buildPhenotypeTemplates(
      csI, csH, csS, csD, csT, csC, csA, csE,
      phenotypeLabel = "Mock Disease", config = config
    ),
    "fixedExitDays"
  )
})
