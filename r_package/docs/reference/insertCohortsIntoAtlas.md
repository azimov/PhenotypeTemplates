# Insert a list of Capr cohort definitions into Atlas via WebApi

Converts each Capr cohort object to its Circe/Atlas JSON expression
(\`Capr::toCohortJson()\`), parses it into an R list, and posts it to
the target WebApi instance with
\`ROhdsiWebApi::postCohortDefinition()\`. The cohort's Atlas name is
taken from its \`"cohortName"\` attribute (set by
\`outcomePhenotypeTpl()\`/\`buildPhenotypeTemplates()\`), falling back
to the list name if the attribute is missing.

## Usage

``` r
insertCohortsIntoAtlas(cohortList, baseUrl)
```

## Arguments

- cohortList:

  A named list of Capr Cohort objects, e.g. the output of
  \`buildPhenotypeTemplates()\`.

- baseUrl:

  The base URL for the WebApi instance, e.g.
  \`"http://server.org:80/WebAPI"\`.

- skipExisting:

  If TRUE (default), skip (and warn about) any cohort whose name already
  exists in Atlas, rather than letting WebApi error out.

## Value

A named list, parallel to \`cohortList\`, containing either the WebApi
response (a data frame/tibble with the new cohort definition's id and
details) for newly-inserted cohorts, or the existing definition's
metadata for cohorts skipped because their name already existed.

## Details

Requires the \`ROhdsiWebApi\` and \`jsonlite\` packages.
\`ROhdsiWebApi\` is not on CRAN; install it with
\`remotes::install_github("OHDSI/ROhdsiWebApi")\`.

Call \`ROhdsiWebApi::authorizeWebApi()\` beforehand if the target WebApi
instance requires authentication (see the guarded example below).
