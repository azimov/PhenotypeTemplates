# Build one Capr concept set per clinical category from a single CSV

The "csv form" concept set loader: an alternative to the
directory-of-json form
(\`buildMergedConceptSetsByBin()\`/\`buildCsFromBins()\`) for simple
cases where concept ids are maintained in one flat file instead of
per-category Atlas concept-set-export json folders. Expects one row per
concept, with a category column using the standard letter codes (\`I\`,
\`H\`, \`S\`, \`D\`, \`T\`, \`C\`, \`A\`, \`E\` — see the header of
\`R/CaprFunctions.R\`).

## Usage

``` r
buildCsFromConceptSetCsv(
  csvPath,
  categoryCol = "category",
  conceptIdCol = "concept_id",
  includeDescendantsCol = "include_descendants"
)
```

## Arguments

- csvPath:

  Path to the CSV file.

- categoryCol:

  Column holding the category letter code. Default \`"category"\`.

- conceptIdCol:

  Column holding the OMOP concept id. Default \`"concept_id"\`.

- includeDescendantsCol:

  Optional column of TRUE/FALSE indicating whether descendants of that
  concept should be included. If the column is missing, descendants are
  included for every row. Default \`"include_descendants"\`.

## Value

A named list of \`Capr::cs()\` concept sets, one per category present in
the file (e.g. \`list(I = ..., S = ..., T = ...)\`). Categories not
present in the CSV are simply absent from the list (pass \`NULL\` for
those when calling
\`buildPhenotypeTemplates()\`/\`outcomePhenotypeTpl()\`).
