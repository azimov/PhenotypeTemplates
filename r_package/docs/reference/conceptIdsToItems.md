# Convert a vector of concept ids into concept set items

Fetches concept metadata for each id and wraps it in the concept set
item shape (concept + isExcluded + includeDescendants + includeMapped)
expected by the WebApi "optimize" endpoint.

## Usage

``` r
conceptIdsToItems(
  conceptIds,
  webApiUrl,
  vocabularySourceKey = NULL,
  isExcluded = FALSE,
  includeDescendants = TRUE,
  includeMapped = FALSE
)
```

## Arguments

- conceptIds:

  integer vector of concept ids

- webApiUrl:

  Atlas WebApi base URL

- vocabularySourceKey:

  vocabulary source key; defaults to the WebApi's priority vocabulary

- isExcluded, includeDescendants, includeMapped:

  flag values applied to every item

## Value

a plain list of concept set items
