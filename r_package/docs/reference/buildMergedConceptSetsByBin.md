# Build a merged concept set for each fixed clinical-category bin under a disease folder in largescalephentest/phenelopeConceptSetsNew/

Build a merged concept set for each fixed clinical-category bin under a
disease folder in largescalephentest/phenelopeConceptSetsNew/

Build a merged concept set for each fixed clinical-category bin under a
disease folder in largescalephentest/phenelopeConceptSetsNew/

## Usage

``` r
buildMergedConceptSetsByBin(
  diseaseFolder,
  webApiUrl,
  vocabularySourceKey = NULL,
  binDirs = .phenelopeBinDirs
)

buildMergedConceptSetsByBin(
  diseaseFolder,
  webApiUrl,
  vocabularySourceKey = NULL,
  binDirs = .phenelopeBinDirs
)
```

## Arguments

- diseaseFolder:

  Path to the disease directory, e.g.
  "largescalephentest/phenelopeConceptSetsNew/Acute liver failure".

- webApiUrl:

  Atlas WebApi base URL, passed through to mergeConceptSets().

- vocabularySourceKey:

  Optional vocabulary source key, passed through to mergeConceptSets().

- binDirs:

  Character vector of bin sub-directory names to process. Defaults to
  the fixed set of phenelope categories.

## Value

A named list (one entry per bin found) where each entry is a list with:
\`mergedConceptSet\` (the merged concept set for that bin), \`binName\`,
\`sourceDirs\` (the condition sub-folders that contributed concepts),
and \`files\` (the concept set json files read). Bins with no matching
directory or no json files are skipped.

A named list (one entry per bin found) where each entry is a list with:
\`mergedConceptSet\` (the merged concept set for that bin), \`binName\`,
\`sourceDirs\` (the condition sub-folders that contributed concepts),
and \`files\` (the concept set json files read). Bins with no matching
directory or no json files are skipped.
