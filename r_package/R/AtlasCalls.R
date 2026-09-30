
authWebApi <- function(webApiUrl) {
  params <- list(
    baseUrl = webApiUrl,
    authMethod = "windows"
  )
  if (.Platform$OS.type != "windows" || authMethod != "windows") {
    params$webApiUsername <- Sys.info()['user']
    if (rstudioapi::isAvailable())
      params$webApiPassword <- rstudioapi::askForSecret("Enter your web api password")
    else
      params$webApiPassword <- getPass::getPass("Enter your web api password: ")
  }
  do.call(ROhdsiWebApi::authorizeWebApi, params)
}
# Atlas insertion (ROhdsiWebApi) -----------------------------------------------
#
# Inserts Capr cohort definitions built above into an OHDSI Atlas/WebApi
# instance via the OHDSI/ROhdsiWebApi package. This is opt-in: it is never
# called automatically when this script is sourced (see the guarded example
# at the bottom of the file).

#' Insert a list of Capr cohort definitions into Atlas via WebApi
#'
#' Converts each Capr cohort object to its Circe/Atlas JSON expression
#' (`Capr::toCohortJson()`), parses it into an R list, and posts it to the
#' target WebApi instance with `ROhdsiWebApi::postCohortDefinition()`. The
#' cohort's Atlas name is taken from its `"cohortName"` attribute (set by
#' `outcomePhenotypeTpl()`/`buildPhenotypeTemplates()`), falling back to the list
#' name if the attribute is missing.
#'
#' Requires the `ROhdsiWebApi` and `jsonlite` packages. `ROhdsiWebApi` is not
#' on CRAN; install it with
#' `remotes::install_github("OHDSI/ROhdsiWebApi")`.
#'
#' Call `ROhdsiWebApi::authorizeWebApi()` beforehand if the target WebApi
#' instance requires authentication (see the guarded example below).
#'
#' @param cohortList A named list of Capr Cohort objects, e.g. the output of
#'   `buildPhenotypeTemplates()`.
#' @param baseUrl The base URL for the WebApi instance, e.g.
#'   `"http://server.org:80/WebAPI"`.
#' @param skipExisting If TRUE (default), skip (and warn about) any cohort
#'   whose name already exists in Atlas, rather than letting WebApi error out.
#'
#' @return A named list, parallel to `cohortList`, containing either the
#'   WebApi response (a data frame/tibble with the new cohort definition's id
#'   and details) for newly-inserted cohorts, or the existing definition's
#'   metadata for cohorts skipped because their name already existed.
#' @export
insertCohortsIntoAtlas <- function(cohortList, baseUrl) {

  results <- list()

  for (nm in 1:nrow(cohortList)) {
    cohortObj  <- cohortList[nm,]
    cohortName <- cohortObj$cohortName
    cohortJson       <- cohortObj$json
    cohortExpression <- jsonlite::fromJSON(cohortJson, simplifyVector = FALSE)
    existing <- ROhdsiWebApi::existsCohortName(cohortName = cohortName, baseUrl = baseUrl)
    message(sprintf("Posting cohort '%s' to Atlas...", cohortName))
    if (!isFALSE(existing)) {
      definition <- ROhdsiWebApi::getCohortDefinition(cohortId = existing$id, baseUrl = baseUrl)
      definition$expression <- cohortExpression
      results[[nm]] <- ROhdsiWebApi::updateCohortDefinition(
        cohortDefinition = definition,
        baseUrl          = baseUrl
      )
      
    } else {
      results[[nm]] <- ROhdsiWebApi::postCohortDefinition(
        name             = cohortName,
        cohortDefinition = cohortExpression,
        baseUrl          = baseUrl
      )
    }
  }

  return(results)
}
