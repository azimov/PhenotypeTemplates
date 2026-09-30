# Build a Phevaluator-style outcome phenotype variant

Constructs a first-occurrence evaluation cohort: index on the first
diagnosis of the disease (I) — or, when \`useHypernymAsIndex\` is TRUE,
either I or the broader Hypernym (H) — in condition OR observation
domain, then layer on supporting evidence gated by the phenotype's
clinical-evidence booleans. Usually called once per variant from
\`buildPhenotypeTemplates()\` rather than directly.

## Usage

``` r
outcomePhenotypeTpl(
  cs_I,
  cs_H = NULL,
  cs_S = NULL,
  cs_D = NULL,
  cs_T = NULL,
  cs_C = NULL,
  cs_A = NULL,
  cs_E = NULL,
  phenotypeLabel,
  templateSuffix = "base_case",
  useHypernymAsIndex = FALSE,
  hasDescreteRecordedSymptoms = FALSE,
  requiresDiagnosticTestOrProcedure = FALSE,
  requiresActiveTreatmentWithin30d = FALSE,
  expectsConditionSpecificFollowupOrSequelae1yr = FALSE,
  treatmentFollowUpOp = c("any", "all"),
  evidenceThreshold = NULL,
  excludeA = FALSE,
  requiresHospitalization = FALSE,
  demographicCriteria = NULL,
  firstOccurrenceOnly = TRUE,
  primaryCriteriaLimit = c("First", "All", "Last"),
  expressionLimit = c("First", "All", "Last"),
  hospitalVisitOverlapWindow = 99999,
  eraDays = 0L,
  endStrategy = NULL
)
```

## Arguments

- cs_I:

  ConceptSet for the disease of interest (index event). Required.

- cs_H:

  ConceptSet for hypernyms (broader/less-specific alternative to cs_I),
  or NULL.

- cs_S:

  ConceptSet for symptoms, or NULL.

- cs_D:

  ConceptSet for diagnostic tests, or NULL.

- cs_T:

  ConceptSet for treatments, or NULL.

- cs_C:

  ConceptSet for complications, or NULL.

- cs_A:

  ConceptSet for alternative diagnoses (excluded), or NULL.

- cs_E:

  ConceptSet for etiology / suspected cause, or NULL. Only used as a
  component of Follow-up Care — never a standalone rule.

- phenotypeLabel:

  Character string. The phenotype label (from the Concept Set Builder).
  Used in cohort naming. Required.

- templateSuffix:

  Character. Variant suffix for naming (e.g. \`"L0-I-noHosp-noA"\`).
  Default \`"base_case"\`.

- useHypernymAsIndex:

  If TRUE, index on cs_I OR cs_H (whichever occurs first). If FALSE
  (default), index on cs_I only.

- hasDescreteRecordedSymptoms:

  If TRUE, include a rule requiring symptom (S, -30 to 0d) OR
  complication (C, +1 to +365d) evidence. Default FALSE.

- requiresDiagnosticTestOrProcedure:

  If TRUE, include a rule requiring diagnostic (D) evidence within -30
  to 0 days. Default FALSE.

- requiresActiveTreatmentWithin30d:

  If TRUE, include a rule requiring Treatment (T) evidence within 0 to
  +30 days. Default FALSE.

- expectsConditionSpecificFollowupOrSequelae1yr:

  If TRUE, include a rule requiring Follow-up Care evidence (see
  \`makeFollowUpCareCriterion()\`). Default FALSE.

- treatmentFollowUpOp:

  When both \`requiresActiveTreatmentWithin30d\` and
  \`expectsConditionSpecificFollowupOrSequelae1yr\` are TRUE, how to
  combine them: \`"any"\` (OR) or \`"all"\` (AND). Default \`"any"\`.

- excludeA:

  If TRUE, add an exclusion rule: zero records for alternative
  diagnoses (A) within -30 to +30 days around index. Default FALSE.

- requiresHospitalization:

  Does the entry event itself require hospitalization (ER or Inpatient)?
  When TRUE, restricts the entry criteria (I, and H when used as index)
  to records with a visit type in the hard-coded ER/Inpatient concept
  set — attached to the index event on Day 0, not a separate inclusion
  rule. Default FALSE.

- firstOccurrenceOnly:

  If TRUE (default), index only a person's first-ever I (and/or H)
  diagnosis. If FALSE, every qualifying diagnosis is a candidate index
  event.

- primaryCriteriaLimit:

  Which qualifying index event(s) to keep per person: \`"First"\`,
  \`"All"\`, or \`"Last"\`. Default \`"First"\`.

- expressionLimit:

  Which qualifying events survive attrition: \`"First"\`, \`"All"\`, or
  \`"Last"\`. Default \`"First"\`.

- eraDays:

  Gap in days below which consecutive episodes are collapsed into a
  single era. Default 0 (no collapse). See
  \`resolvePhenotypeExitStrategy()\`.

- endStrategy:

  A Capr end-strategy object (e.g. from
  \`resolvePhenotypeExitStrategy()\`). Defaults to
  \`observationExit()\`.

## Value

A Capr Cohort object.

## Details

All inclusion criteria allow events outside the observation period.
