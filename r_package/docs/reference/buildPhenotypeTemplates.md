# Build a cohort definition set of phenotype template variants

Replaces the old fixed V0-V11 lattice: generates a combinatorial set of
cohort definitions for one phenotype, crossed on evidence-strictness
ladder level x index specificity (I vs I\|H) x hospitalization (per
\`config\$expectedCareSetting\`) x alternative-diagnosis exclusion
(with/without, only if cs_A supplied). See header comment for the full
config field reference.

## Usage

``` r
buildPhenotypeTemplates(
  cs_I,
  cs_H = NULL,
  cs_S = NULL,
  cs_D = NULL,
  cs_T = NULL,
  cs_C = NULL,
  cs_A = NULL,
  cs_E = NULL,
  phenotypeLabel,
  config,
  startCohortId = 0,
  firstOccurrenceOnly = TRUE,
  primaryCriteriaLimit = c("First", "All", "Last"),
  expressionLimit = c("First", "All", "Last"),
  hospitalVisitOverlapWindow = 99999
)
```

## Arguments

- cs_I:

  ConceptSet for disease of interest. Required.

- cs_H:

  ConceptSet for hypernyms, or NULL.

- cs_S:

  ConceptSet for symptoms, or NULL.

- cs_D:

  ConceptSet for diagnostic tests, or NULL.

- cs_T:

  ConceptSet for treatments, or NULL.

- cs_C:

  ConceptSet for complications, or NULL.

- cs_A:

  ConceptSet for alternative diagnoses, or NULL.

- cs_E:

  ConceptSet for etiology, or NULL.

- phenotypeLabel:

  Character. The phenotype label from the Concept Set Builder.

- config:

  A list with: \`clinicalCourse\`, \`expectedCareSetting\`, \`minAge\`,
  \`maxAge\`, \`male\`, \`female\`, \`minimumInterepisodeDayGap\`,
  \`recommendedCohortExit\`, \`fixedExitDays\`,
  \`hasDescreteRecordedSymptoms\`,
  \`requiresDiagnosticTestOrProcedure\`,
  \`requiresActiveTreatmentWithin30d\`,
  \`expectsConditionSpecificFollowupOrSequelae1yr\`.

- startCohortId:

  cohortId to begin templates (use if you're building multiple template
  sets). First output id will be param + 1.

- firstOccurrenceOnly:

  Passed through to \`outcomePhenotypeTpl()\`. Default TRUE.

- primaryCriteriaLimit:

  Passed through to \`outcomePhenotypeTpl()\`. Default "First".

- expressionLimit:

  Passed through to \`outcomePhenotypeTpl()\`. Default "First".

- hospitalVisitOverlapWindow:

  Passed through to \`outcomePhenotypeTpl()\`. Default 99999.

## Value

A cohort definition set data frame (cohortId, cohortName, json, sql).
