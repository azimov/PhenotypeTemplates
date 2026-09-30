
#' Reconstruct an Atlas concept set expression parsed by jsonlite::fromJSON()
#'
#' `jsonlite::fromJSON()` converts the nested `items` array of an Atlas
#' concept set expression into a data.frame, which
#' `ROhdsiWebApi::resolveConceptSet()` cannot consume directly. This rebuilds
#' `items` into the nested list-of-lists structure WebAPI expects.
#'
#' @param cs A concept set expression (as returned by `jsonlite::fromJSON()`)
#'   with a `items` data.frame, or an already-reconstructed list (returned
#'   unchanged).
#' @return The concept set expression with `items` as a list of lists.
#' @noRd
reconstructAtlasConceptSetExpression <- function(cs) {
  if (is.null(cs$items) || !is.data.frame(cs$items)) {
    return(cs)
  }

  cs$items <- lapply(
    seq_len(nrow(cs$items)),
    function(i) {
      list(
        concept = as.list(cs$items$concept[i, ]),
        isExcluded = cs$items$isExcluded[i],
        includeDescendants = cs$items$includeDescendants[i],
        includeMapped = cs$items$includeMapped[i]
      )
    }
  )

  cs
}

#' Resolve a concept set so it only includes indiviudal concepts
#'
#' Accepts an Atlas concept set expression as a JSON string or as a list
#' already parsed by `jsonlite::fromJSON()`. When the parsed `items` field is
#' a data.frame (the shape `jsonlite::fromJSON()` produces), it is
#' automatically reconstructed into the nested list structure
#' `ROhdsiWebApi::resolveConceptSet()` requires.
#'
#' @param cs concept set expression: a JSON string, or a (possibly
#'   data.frame-shaped) parsed list.
#' @param webApiUrl atlas instance
#' @param vocabularySourceKey vocabulary source key to resolve against
#' @export
resolveConceptSetViaWebApi <- function(cs, webApiUrl, vocabularySourceKey) {
  if (is.character(cs)) {
    cs <- jsonlite::fromJSON(cs)
  }
  cs <- reconstructAtlasConceptSetExpression(cs)

  ROhdsiWebApi::resolveConceptSet(conceptSetDefinition = cs, baseUrl = webApiUrl, vocabularySourceKey = vocabularySourceKey)
}

#' Build an exact Capr ConceptSet from already-resolved concept IDs
#'
#' `buildPhenotypeTemplates()` and `resolveConceptSetOverlaps()` require Capr
#' `ConceptSet` S4 objects, not plain vectors of concept IDs. Use this to
#' convert concept IDs resolved via `resolveConceptSet()` (which already
#' performs descendant expansion) into an exact Capr `ConceptSet` — the
#' individual concepts are included as-is, with no further descendant
#' expansion.
#'
#' @param conceptIds Integer/numeric vector of resolved concept IDs.
#' @param name Name to assign to the resulting Capr ConceptSet.
#' @return A Capr `ConceptSet` S4 object.
#' @export
buildExactCaprConceptSet <- function(conceptIds, name) {
  items <- lapply(
    unique(as.integer(conceptIds)),
    function(id) {
      Capr::cs(id, name = paste0(name, "_tmp"))@Expression[[1]]
    }
  )

  do.call(Capr::cs, c(unname(items), list(name = name)))
}


#' Cross platform auth for WebApi
.authWebApi <- function(webApiUrl) {
  params <- list(
    baseUrl = webApiUrl,
    authMethod = "windows"
  )
  if (.Platform$OS.type != "windows") {
    params$webApiUsername <- Sys.info()['user']
    if (rstudioapi::isAvailable())
      params$webApiPassword <- rstudioapi::askForSecret("Enter your web api password")
    else
      params$webApiPassword <- getPass::getPass("Enter your web api password: ")
  }
  do.call(ROhdsiWebApi::authorizeWebApi, params)
}

