# Build curated evidence-combination cohorts for one phenotype

Build curated evidence-combination cohorts for one phenotype

## Usage

``` r
buildEvidenceCombinationCohorts(
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

- cs_I, cs_H, cs_S, cs_D, cs_T, cs_C, cs_A, cs_E:

  Concept sets (see \`outcomePhenotypeTpl()\`)

- phenotypeLabel:

  Character label

- config:

  Phenotype config (see \`phenotypeConfig()\` /
  \`validatePhenotypeConfig()\`)

- startCohortId:

  Starting cohortId (first output will be +1)

- firstOccurrenceOnly, primaryCriteriaLimit, expressionLimit,
  hospitalVisitOverlapWindow:

  Passed to \`outcomePhenotypeTpl()\`

## Value

data.frame of cohort definitions (cohortId, cohortName, json, sql)
