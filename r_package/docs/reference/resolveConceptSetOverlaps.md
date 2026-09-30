# Resolve overlapping concepts across clinical category concept sets

Applies precedence rules to remove concepts from lower-priority sets
when they also appear in higher-priority sets. Only affects
condition/observation domain sets (I, A, H, E, S, C). D and T are passed
through unchanged.

## Usage

``` r
resolveConceptSetOverlaps(
  cs_I,
  cs_H = NULL,
  cs_S = NULL,
  cs_D = NULL,
  cs_T = NULL,
  cs_C = NULL,
  cs_A = NULL,
  cs_E = NULL,
  warnOnOverlap = TRUE
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

  ConceptSet for diagnostic tests, or NULL. Passed through unchanged.

- cs_T:

  ConceptSet for treatments, or NULL. Passed through unchanged.

- cs_C:

  ConceptSet for complications, or NULL.

- cs_A:

  ConceptSet for alternative diagnoses, or NULL.

- cs_E:

  ConceptSet for etiology, or NULL.

- warnOnOverlap:

  Logical. If TRUE (default), emit a message listing removed concepts
  for traceability.

## Value

A named list with cleaned concept sets: \`cs_I\`, \`cs_H\`, \`cs_S\`,
\`cs_D\`, \`cs_T\`, \`cs_C\`, \`cs_A\`, \`cs_E\`. Any set reduced to
zero concepts becomes NULL.
