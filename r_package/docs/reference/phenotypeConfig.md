# Create a phenotype config list for use with buildPhenotypeTemplates()

Initializes a config list with all phenotype parameters, using sensible
defaults for omitted boolean flags (defaulting to FALSE).

## Usage

``` r
phenotypeConfig(
  clinicalCourse,
  expectedCareSetting,
  minAge = NULL,
  maxAge = NULL,
  male = FALSE,
  female = FALSE,
  minimumInterepisodeDayGap = NULL,
  recommendedCohortExit = NULL,
  fixedExitDays = NULL,
  hasDescreteRecordedSymptoms = FALSE,
  requiresDiagnosticTestOrProcedure = FALSE,
  requiresActiveTreatmentWithin30d = FALSE,
  expectsConditionSpecificFollowupOrSequelae1yr = FALSE
)
```

## Arguments

- clinicalCourse:

  One of \`"persistent_stable"\`, \`"persistent_transient"\`,
  \`"transient_recurrent"\`, \`"transient_single"\`. Required.

- expectedCareSetting:

  One of \`"acute_care_expected"\`, \`"acute_care_common"\`,
  \`"outpatient_expected"\`. Required.

- minAge:

  Minimum age at index, or NULL. Default NULL.

- maxAge:

  Maximum age at index, or NULL. Default NULL.

- male:

  Require male gender? Default FALSE.

- female:

  Require female gender? Default FALSE.

- minimumInterepisodeDayGap:

  Era-collapse gap. Required for era_persistence exit types. Default
  NULL.

- recommendedCohortExit:

  Explicit exit override, or NULL to use the clinicalCourse default.
  Default NULL.

- fixedExitDays:

  Fixed exit window length (days). Required for fixed_window exit types.
  Default NULL.

- hasDescreteRecordedSymptoms:

  Gate symptom/complication evidence? Default FALSE.

- requiresDiagnosticTestOrProcedure:

  Gate diagnostic evidence? Default FALSE.

- requiresActiveTreatmentWithin30d:

  Gate treatment evidence? Default FALSE.

- expectsConditionSpecificFollowupOrSequelae1yr:

  Gate follow-up care? Default FALSE.

## Value

A named list suitable for passing as \`config\` to
buildPhenotypeTemplates().
