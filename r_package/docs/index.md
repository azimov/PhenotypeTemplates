# Pheval Outcome Phenotype Evaluation Templates

Programmatic generation of PheValuator-style evaluation cohorts using
[Capr](https://github.com/OHDSI/Capr) (note - currently requires use of
the develop branch of capr). Indexes on the first diagnosis of a
disease, then layers clinical evidence categories as attrition rules to
produce cohorts at varying specificity levels.

## Installation

Install directly from the internal git repository with `remotes`:

``` r
install.packages("remotes")
remotes::install_git(
  "https://sourcecode.jnj.com/scm/itx-asj/phenotype_templating.git",
  dependencies = TRUE
)
```

Or clone the repository and install/load it locally:

``` sh
git clone https://sourcecode.jnj.com/scm/itx-asj/phenotype_templating.git
```

``` r
setwd("phenotype_templating")
renv::restore()   # installs pinned dependencies (Capr, DatabaseConnector, CohortGenerator, ...)
devtools::install()
library(PhenotypeTemplates)
```

## Basic Usage

Every phenotype is built from up to eight OMOP concept-set categories
(`I`, `H`, `S`, `D`, `T`, `C`, `A`, `E` — see the header comment in
[R/CaprFunctions.R](R/CaprFunctions.R) for the full definitions) plus a
[`phenotypeConfig()`](reference/phenotypeConfig.md) describing clinical
course, expected care setting, demographics, and which evidence
categories are relevant.

``` r
library(Capr)
library(PhenotypeTemplates)

config <- phenotypeConfig(
  clinicalCourse = "persistent_transient",
  expectedCareSetting = "acute_care_common",
  minimumInterepisodeDayGap = 180,
  hasDescreteRecordedSymptoms = TRUE,
  requiresDiagnosticTestOrProcedure = TRUE,
  requiresActiveTreatmentWithin30d = TRUE,
  expectsConditionSpecificFollowupOrSequelae1yr = TRUE
)

# buildPhenotypeTemplates() crosses an evidence-strictness ladder with index
# specificity, hospitalization, and alternative-diagnosis exclusion to
# produce a full cohort definition set.
cohortDefinitionSet <- buildPhenotypeTemplates(
  cs_I = my_I, cs_H = my_H, cs_S = my_S, cs_D = my_D,
  cs_T = my_T, cs_C = my_C, cs_A = my_A, cs_E = my_E,
  phenotypeLabel = "My Phenotype",
  config = config
)

# buildEvidenceCombinationCohorts() instead builds a curated base/single-flag/
# "at least K of 4 evidence components" set.
comboCohorts <- buildEvidenceCombinationCohorts(
  cs_I = my_I, cs_H = my_H, cs_S = my_S, cs_D = my_D,
  cs_T = my_T, cs_C = my_C, cs_A = my_A, cs_E = my_E,
  phenotypeLabel = "My Phenotype",
  config = config
)
```

Both functions return a `CohortGenerator`-compatible cohort definition
set (`cohortId`, `cohortName`, `json`, `sql`) that can be passed
directly to
[`CohortGenerator::runCohortGeneration()`](https://ohdsi.github.io/CohortGenerator/reference/runCohortGeneration.html).

### Loading concept sets

`my_I`/`my_H`/`my_S`/… above are plain
[`Capr::cs()`](https://ohdsi.github.io/Capr/reference/cs.html) concept
sets. `R/ConceptSetLogic.R` provides two loaders for building them from
existing exports instead of writing
[`cs()`](https://ohdsi.github.io/Capr/reference/cs.html) calls by hand:

**Directory form** — one sub-directory per clinical category, each
holding Atlas concept-set-export json files (see
`largescalephentest/phenelopeConceptSetsNew/` for an example layout):

``` r
mergedCsLists <- buildMergedConceptSetsByBin(
  diseaseFolder = "largescalephentest/phenelopeConceptSetsNew/Acute liver failure",
  webApiUrl = webApiUrl,
  connectionDetails = connectionDetails,
  vocabularyDatabaseSchema = cdmDatabaseSchema
)

connection <- DatabaseConnector::connect(connectionDetails)
my_I <- buildCsFromBins("Disease of Interest", "My phenotype - disease of interest",
                         mergedCsLists, connection, cdmDatabaseSchema)
my_S <- buildCsFromBins("Clinical Presentation - Sign - Symptom", "My phenotype - symptoms",
                         mergedCsLists, connection, cdmDatabaseSchema)
```

**CSV form** — a single flat file with one row per concept id, a
`category` column using the standard letter codes (`I`, `H`, `S`, `D`,
`T`, `C`, `A`, `E`), and an optional `include_descendants` column:

``` csv
category,concept_id,include_descendants
I,313217,TRUE
H,4232697,TRUE
S,313418,TRUE
T,1310149,FALSE
```

``` r
csByCategory <- buildCsFromConceptSetCsv("concept_sets.csv")

cohortDefinitionSet <- buildPhenotypeTemplates(
  cs_I = csByCategory$I, cs_H = csByCategory$H, cs_S = csByCategory$S,
  cs_T = csByCategory$T,
  phenotypeLabel = "My Phenotype",
  config = config
)
```

For runnable, end-to-end walkthroughs against the Eunomia sample CDM,
see the package vignettes:

- [`vignette("outcome-phenotype-template-basics")`](articles/outcome-phenotype-template-basics.md)
  — building individual cohorts by hand with
  [`outcomePhenotypeTpl()`](reference/outcomePhenotypeTpl.md) and the
  other standard template helpers.
- [`vignette("evidence-combination-cohorts")`](articles/evidence-combination-cohorts.md)
  — generating full cohort definition sets with
  [`buildPhenotypeTemplates()`](reference/buildPhenotypeTemplates.md)
  and
  [`buildEvidenceCombinationCohorts()`](reference/buildEvidenceCombinationCohorts.md).
