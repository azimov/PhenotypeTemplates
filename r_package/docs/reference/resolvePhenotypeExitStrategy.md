# Resolve the era-collapse gap and exit strategy for a phenotype

\`clinicalCourse\` sets a default \`recommendedCohortExit\`/era-gap
behavior; an explicit \`recommendedCohortExit\` and/or
\`minimumInterepisodeDayGap\` always overrides that default.

## Usage

``` r
resolvePhenotypeExitStrategy(
  clinicalCourse,
  recommendedCohortExit = NULL,
  minimumInterepisodeDayGap = NULL,
  fixedExitDays = NULL
)
```

## Arguments

- clinicalCourse:

  One of \`"persistent_stable"\`, \`"persistent_transient"\`,
  \`"transient_recurrent"\`, \`"transient_single"\`.

- recommendedCohortExit:

  Optional override: \`"era_persistence"\`,
  \`"continuous_observation"\`, or \`"fixed_window"\`. NULL uses the
  clinicalCourse default.

- minimumInterepisodeDayGap:

  Era-collapse gap in days. Required when the resolved exit type is
  \`"era_persistence"\`.

- fixedExitDays:

  Fixed exit window length in days. Required when the resolved exit type
  is \`"fixed_window"\`.

## Value

A list with \`eraDays\` (integer) and \`endStrategy\` (a Capr end
strategy object).
