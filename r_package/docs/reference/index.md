# Package index

## Phenotype configuration

Build and validate the per-phenotype config used by the cohort-set
builders below.

- [`phenotypeConfig()`](phenotypeConfig.md) : Create a phenotype config
  list for use with buildPhenotypeTemplates()
- [`resolvePhenotypeExitStrategy()`](resolvePhenotypeExitStrategy.md) :
  Resolve the era-collapse gap and exit strategy for a phenotype
- [`resolveHospitalizationVariants()`](resolveHospitalizationVariants.md)
  : Resolve which requiresHospitalization variants to emit for a care
  setting

## Cohort-set builders

High-level, batch entry points that produce a CohortGenerator-compatible
cohort definition set for a phenotype.

- [`buildPhenotypeTemplates()`](buildPhenotypeTemplates.md) : Build a
  cohort definition set of phenotype template variants
- [`buildEvidenceCombinationCohorts()`](buildEvidenceCombinationCohorts.md)
  : Build curated evidence-combination cohorts for one phenotype

## Single-cohort building blocks

The standard template and helpers used internally by the batch builders,
also usable directly for one-off cohort variants.

- [`outcomePhenotypeTpl()`](outcomePhenotypeTpl.md) : Build a
  Phevaluator-style outcome phenotype variant
- [`resolveConceptSetOverlaps()`](resolveConceptSetOverlaps.md) :
  Resolve overlapping concepts across clinical category concept sets
- [`greateDemographicCriteria()`](greateDemographicCriteria.md) : Create
  gender criteria for templates

## Concept set loaders

Load concept sets from Atlas concept-set-export json (directory form) or
a single flat file (csv form).

- [`buildMergedConceptSetsByBin()`](buildMergedConceptSetsByBin.md) :
  Build a merged concept set for each fixed clinical-category bin under
  a disease folder in largescalephentest/phenelopeConceptSetsNew/
- [`buildCsFromConceptSetCsv()`](buildCsFromConceptSetCsv.md) : Build
  one Capr concept set per clinical category from a single CSV
- [`conceptIdsToItems()`](conceptIdsToItems.md) : Convert a vector of
  concept ids into concept set items
- [`mergeConceptSets()`](mergeConceptSets.md) : Merge concept sets
- [`resolveConceptSet()`](resolveConceptSet.md) : Resolve a concept set
  so it only includes individual concepts
- [`.phenelopeBinDirs`](dot-phenelopeBinDirs.md) : Fixed
  clinical-category bin sub-directory names under a disease folder

## Atlas integration

- [`insertCohortsIntoAtlas()`](insertCohortsIntoAtlas.md) : Insert a
  list of Capr cohort definitions into Atlas via WebApi
- [`.authWebApi()`](dot-authWebApi.md) : Cross platform auth for WebApi
