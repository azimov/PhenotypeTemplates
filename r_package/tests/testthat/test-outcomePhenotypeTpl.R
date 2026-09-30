csI <- mockCs(c(100L), "I")
csH <- mockCs(c(101L), "H")
csS <- mockCs(c(102L), "S")
csD <- mockCs(c(103L), "D")
csT <- mockCs(c(104L), "T")
csC <- mockCs(c(105L), "C")
csA <- mockCs(c(106L), "A")
csE <- mockCs(c(107L), "E")

ruleNames <- function(cohortObj) {
  names(cohortObj@attrition@rules)
}

test_that("no flags set produces zero attrition rules", {
  tpl <- outcomePhenotypeTpl(csI, phenotypeLabel = "Test")
  expect_length(ruleNames(tpl), 0)
  expect_equal(attr(tpl, "cohortName"), "[PheTpl] Test tpl base_case")
})

test_that("hasDescreteRecordedSymptoms adds a symptom/complication rule", {
  tpl <- outcomePhenotypeTpl(
    csI, cs_S = csS, cs_C = csC, phenotypeLabel = "Test",
    hasDescreteRecordedSymptoms = TRUE
  )
  expect_length(ruleNames(tpl), 1)
})

test_that("requiresDiagnosticTestOrProcedure alone adds a rule", {
  tpl <- outcomePhenotypeTpl(
    csI, cs_D = csD, phenotypeLabel = "Test",
    requiresDiagnosticTestOrProcedure = TRUE
  )
  expect_length(ruleNames(tpl), 1)
})

test_that("requiresActiveTreatmentWithin30d alone adds a rule", {
  tpl <- outcomePhenotypeTpl(
    csI, cs_T = csT, phenotypeLabel = "Test",
    requiresActiveTreatmentWithin30d = TRUE
  )
  expect_length(ruleNames(tpl), 1)
})

test_that("expectsConditionSpecificFollowupOrSequelae1yr alone adds a rule", {
  tpl <- outcomePhenotypeTpl(
    csI, cs_H = csH, cs_C = csC, cs_E = csE, phenotypeLabel = "Test",
    expectsConditionSpecificFollowupOrSequelae1yr = TRUE
  )
  expect_length(ruleNames(tpl), 1)
})

test_that("excludeA adds an exclusion rule", {
  tpl <- outcomePhenotypeTpl(
    csI, cs_A = csA, phenotypeLabel = "Test", excludeA = TRUE
  )
  expect_length(ruleNames(tpl), 1)
})

test_that("requiresHospitalization adds a hospitalization rule", {
  tpl <- outcomePhenotypeTpl(
    csI, phenotypeLabel = "Test", requiresHospitalization = TRUE
  )
  expect_length(ruleNames(tpl), 1)
})

test_that("all four evidence flags plus exclusion plus hospitalization stack to 4 rules", {
  tpl <- outcomePhenotypeTpl(
    csI, cs_H = csH, cs_S = csS, cs_D = csD, cs_T = csT, cs_C = csC,
    cs_A = csA, cs_E = csE, phenotypeLabel = "Test",
    hasDescreteRecordedSymptoms = TRUE,
    requiresDiagnosticTestOrProcedure = TRUE,
    requiresActiveTreatmentWithin30d = TRUE,
    expectsConditionSpecificFollowupOrSequelae1yr = TRUE,
    excludeA = TRUE,
    requiresHospitalization = TRUE
  )
  expect_length(ruleNames(tpl), 4)
})

test_that("useHypernymAsIndex with no cs_H does not error", {
  tpl <- outcomePhenotypeTpl(csI, phenotypeLabel = "Test", useHypernymAsIndex = TRUE)
  expect_s4_class(tpl, "Cohort")
})
