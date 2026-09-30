

#' Resolve a concept set so it only includes individual concepts
#' @param cs A concept set expression (list of items with concept and flags)
#' @param connection A DatabaseConnector connection object
#' @param vocabularyDatabaseSchema The schema containing the OMOP vocabulary tables
#' @return A data frame of resolved concept IDs
resolveConceptSet <- function(cs, connection, vocabularyDatabaseSchema) {

  conceptSetItems <- do.call(rbind, lapply(cs$items, function(item) {
    data.frame(
      concept_id         = item$concept$CONCEPT_ID,
      includeDescendants = as.integer(item$includeDescendants),
      includeMapped      = as.integer(item$includeMapped),
      isExcluded         = as.integer(item$isExcluded),
      stringsAsFactors   = FALSE
    )
  }))

  # Partition concept IDs by their flags
  included        <- conceptSetItems[conceptSetItems$isExcluded == 0, ]
  excluded        <- conceptSetItems[conceptSetItems$isExcluded == 1, ]
  inclDirect      <- included$concept_id
  inclDescendants <- included$concept_id[included$includeDescendants == 1]
  inclMapped      <- included$concept_id[included$includeMapped == 1]
  exclDirect      <- excluded$concept_id
  exclDescendants <- excluded$concept_id[excluded$includeDescendants == 1]
  exclMapped      <- excluded$concept_id[excluded$includeMapped == 1]

  # Helper: turn a vector of IDs into a SQL list, or NULL if empty
  toSqlList <- function(ids) {
    if (length(ids) == 0) return(NULL)
    paste(ids, collapse = ", ")
  }

  # Build included set -- only query tables we actually need
  includeParts <- c()

  if (length(inclDirect) > 0) {
    includeParts <- c(includeParts, sprintf(
      "SELECT concept_id FROM @vocabulary_database_schema.concept
       WHERE concept_id IN (%s)", toSqlList(inclDirect)
    ))
  }

  if (length(inclDescendants) > 0) {
    includeParts <- c(includeParts, sprintf(
      "SELECT descendant_concept_id AS concept_id
       FROM @vocabulary_database_schema.concept_ancestor
       WHERE ancestor_concept_id IN (%s)", toSqlList(inclDescendants)
    ))
  }

  if (length(inclMapped) > 0) {
    includeParts <- c(includeParts, sprintf(
      "SELECT concept_id_1 AS concept_id
       FROM @vocabulary_database_schema.concept_relationship
       WHERE concept_id_2 IN (%s)
         AND relationship_id = 'Maps to'", toSqlList(inclMapped)
    ))
  }

  # Build excluded set
  excludeParts <- c()

  if (length(exclDirect) > 0) {
    excludeParts <- c(excludeParts, sprintf(
      "SELECT concept_id FROM @vocabulary_database_schema.concept
       WHERE concept_id IN (%s)", toSqlList(exclDirect)
    ))
  }

  if (length(exclDescendants) > 0) {
    excludeParts <- c(excludeParts, sprintf(
      "SELECT descendant_concept_id AS concept_id
       FROM @vocabulary_database_schema.concept_ancestor
       WHERE ancestor_concept_id IN (%s)", toSqlList(exclDescendants)
    ))
  }

  if (length(exclMapped) > 0) {
    excludeParts <- c(excludeParts, sprintf(
      "SELECT concept_id_1 AS concept_id
       FROM @vocabulary_database_schema.concept_relationship
       WHERE concept_id_2 IN (%s)
         AND relationship_id = 'Maps to'", toSqlList(exclMapped)
    ))
  }

  # Assemble final SQL
  includeSql <- paste(includeParts, collapse = "\nUNION\n")

  if (length(excludeParts) > 0) {
    excludeSql <- paste(excludeParts, collapse = "\nUNION\n")
    sql <- paste0("
      SELECT DISTINCT inc.concept_id
      FROM (", includeSql, ") inc
      LEFT JOIN (", excludeSql, ") exc
        ON inc.concept_id = exc.concept_id
      WHERE exc.concept_id IS NULL;
    ")
  } else {
    sql <- paste0("
      SELECT DISTINCT concept_id
      FROM (", includeSql, ") inc;
    ")
  }

  result <- DatabaseConnector::renderTranslateQuerySql(
    connection,
    sql,
    vocabulary_database_schema = vocabularyDatabaseSchema
  )
  return(result$concept_id)
}




#' Merge concept sets
#' @description
#' Merge multiple concept sets together, resolve them firsts
#' @param ... concept sets
mergeConceptSets <- function(..., connection, vocabularyDatabaseSchema, webApiUrl, vocabularySourceKey = NULL) {
  csList <- as.list(...)

  print(paste("Resolving concept sets", length(csList)))
  resolvedCsSets <- lapply(csList, function(cs) {
    # turn cs to json (if it isn't already)
    return(resolveConceptSet(cs, connection, vocabularyDatabaseSchema))
  })

  print("ConceptSets resolved")
  # Create one merged concept set
  mergedSet <- unlist(resolvedCsSets) |> unique()
  
  # Look up full concept details from the vocabulary
  conceptDetailsSql <- sprintf(
    "SELECT concept_id, concept_name, domain_id, vocabulary_id,
            concept_class_id, standard_concept, concept_code
    FROM @vocabulary_database_schema.concept
    WHERE concept_id IN (%s)",
    paste(mergedSet, collapse = ", ")
  )

  conceptDetails <- DatabaseConnector::renderTranslateQuerySql(
    connection,
    conceptDetailsSql,
    vocabulary_database_schema = vocabularyDatabaseSchema,
    snakeCaseToCamelCase = TRUE
  )

  mergedConceptSet <- lapply(seq_len(nrow(conceptDetails)), function(i) {
    row <- conceptDetails[i, ]
    list(
      concept = list(
        CONCEPT_ID       = row$conceptId,
        CONCEPT_NAME     = row$conceptName,
        DOMAIN_ID        = row$domainId,
        VOCABULARY_ID    = row$vocabularyId,
        CONCEPT_CLASS_ID = row$conceptClassId,
        STANDARD_CONCEPT = ifelse(is.na(row$standardConcept), "", row$standardConcept),
        CONCEPT_CODE     = row$conceptCode,
        STANDARD_CONCEPT_CAPTION = "Standard",
        INVALID_REASON = "V",
        INVALID_REASON_CAPTION = "Valid"
      ),
      isExcluded         = FALSE,
      includeDescendants = FALSE,
      includeMapped      = FALSE
    )
  })

  # Wrap in the standard concept set expression structure
  conceptSet <- list(items = mergedConceptSet)
  return(conceptSet)
}

#' Convert a vector of concept ids into concept set items
#' @description
#' Fetches concept metadata for each id and wraps it in the concept set item
#' shape (concept + isExcluded + includeDescendants + includeMapped) expected
#' by the WebApi "optimize" endpoint.
#' @param conceptIds integer vector of concept ids
#' @param webApiUrl Atlas WebApi base URL
#' @param vocabularySourceKey vocabulary source key; defaults to the WebApi's priority vocabulary
#' @param isExcluded,includeDescendants,includeMapped flag values applied to every item
#' @return a plain list of concept set items
conceptIdsToItems <- function(conceptIds, webApiUrl, vocabularySourceKey = NULL,
                              isExcluded = FALSE, includeDescendants = FALSE, includeMapped = FALSE) {
  conceptIds <- unique(as.integer(conceptIds))
  if (length(conceptIds) == 0L) {
    return(list())
  }

  if (is.null(vocabularySourceKey)) {
    vocabularySourceKey <- ROhdsiWebApi::getPriorityVocabularyKey(baseUrl = webApiUrl)
  }

  # keep UPPER_SNAKE_CASE field names to match the concept object shape used elsewhere
  concepts <- ROhdsiWebApi::getConcepts(conceptIds, baseUrl = webApiUrl,
                                        vocabularySourceKey = vocabularySourceKey,
                                        snakeCaseToCamelCase = FALSE)

  lapply(split(concepts, seq_len(nrow(concepts))), function(row) {
    list(
      concept = as.list(row),
      isExcluded = isExcluded,
      includeDescendants = includeDescendants,
      includeMapped = includeMapped
    )
  }) |> unname()
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

# From json folder return named list of concept sets
readJsonConceptSets <- function(jsonFolder = "concept_sets") {
  conceptSetList <- list()
  for (csFile in list.files(jsonFolder, "*.json", full.names = TRUE)) {
      conceptSetList[[basename(csFile)]] <- jsonlite::read_json(csFile)
  }
  
  return(conceptSetList)
}

#' Build one Capr concept set per clinical category from a single CSV
#'
#' The "csv form" concept set loader: an alternative to the directory-of-json
#' form (`buildMergedConceptSetsByBin()`/`buildCsFromBins()`) for simple cases
#' where concept ids are maintained in one flat file instead of per-category
#' Atlas concept-set-export json folders. Expects one row per concept, with a
#' category column using the standard letter codes (`I`, `H`, `S`, `D`, `T`,
#' `C`, `A`, `E` — see the header of `R/CaprFunctions.R`).
#'
#' @param csvPath Path to the CSV file.
#' @param categoryCol Column holding the category letter code. Default `"category"`.
#' @param conceptIdCol Column holding the OMOP concept id. Default `"concept_id"`.
#' @param includeDescendantsCol Optional column of TRUE/FALSE indicating whether
#'   descendants of that concept should be included. If the column is missing,
#'   descendants are excluded for every row. Default `"include_descendants"`.
#' @return A named list of `Capr::cs()` concept sets, one per category present
#'   in the file (e.g. `list(I = ..., S = ..., T = ...)`). Categories not
#'   present in the CSV are simply absent from the list (pass `NULL` for
#'   those when calling `buildPhenotypeTemplates()`/`outcomePhenotypeTpl()`).
#' @export
buildCsFromConceptSetCsv <- function(csvPath,
                                     categoryCol = "category",
                                     conceptIdCol = "concept_id",
                                     includeDescendantsCol = "include_descendants") {
  conceptSetTable <- utils::read.csv(csvPath, stringsAsFactors = FALSE)

  if (!categoryCol %in% names(conceptSetTable)) {
    stop(sprintf("CSV is missing the category column '%s'", categoryCol), call. = FALSE)
  }
  if (!conceptIdCol %in% names(conceptSetTable)) {
    stop(sprintf("CSV is missing the concept id column '%s'", conceptIdCol), call. = FALSE)
  }

  hasDescendantsCol <- includeDescendantsCol %in% names(conceptSetTable)

  categories <- unique(conceptSetTable[[categoryCol]])
  csList <- list()
  for (category in categories) {
    rows <- conceptSetTable[conceptSetTable[[categoryCol]] == category, , drop = FALSE]
    conceptIds <- as.integer(rows[[conceptIdCol]])
    includeDescendants <- if (hasDescendantsCol) as.logical(rows[[includeDescendantsCol]]) else rep(FALSE, length(conceptIds))
    includeDescendants[is.na(includeDescendants)] <- FALSE

    items <- Map(function(id, descendants) {
      if (isTRUE(descendants)) Capr::descendants(id) else Capr::cs(id)@Expression[[1]]
    }, conceptIds, includeDescendants)

    csList[[category]] <- do.call(Capr::cs, c(unname(items), list(name = category)))
  }

  csList
}



#' Read the concept set json (one per sub-folder) found under a bin directory

#' @noRd
.readBinConceptSetJsons <- function(binDir) {
  subDirs <- list.dirs(binDir, recursive = FALSE, full.names = TRUE)
  csList <- list()
  usedFiles <- character(0)
  for (sd in subDirs) {
    jsonFiles <- list.files(sd, pattern = "\\.json$", full.names = TRUE)
    if (length(jsonFiles) == 0L) next
    # a sub-folder may contain helper csvs alongside the concept set; take the json
    jsonFile <- jsonFiles[[1]]
    csList[[basename(sd)]] <- jsonlite::read_json(jsonFile)
    usedFiles <- c(usedFiles, jsonFile)
  }
  list(conceptSets = csList, sourceDirs = basename(subDirs), files = usedFiles)
}

#' Build a unioned concept set for each fixed clinical-category bin under a
#' disease folder in largescalephentest/phenelopeConceptSetsNew/
#'
#' Each bin's concept set json files are combined with `unionConceptsets()`,
#' which (unlike the old webApi-based `mergeConceptSets()`) properly honors
#' exclusion entries: a concept only drops out of the bin's union if every
#' contributing concept set that included it also excluded it.
#'
#' @param diseaseFolder Path to the disease directory, e.g.
#'   "largescalephentest/phenelopeConceptSetsNew/Acute liver failure".
#' @param connectionDetails DatabaseConnector connectionDetails for a database
#'   with OMOP vocabulary tables.
#' @param vocabularyDatabaseSchema Schema holding the vocabulary tables.
#' @param binDirs Character vector of bin sub-directory names to process.
#'   Defaults to the fixed set of phenelope categories.
#' @param outputFolder Folder to write each bin's unioned concept set json.
#'   Defaults to a temporary directory.
#' @return A named list (one entry per bin found) where each entry is a list
#'   with: `mergedConceptSet` (the unioned CIRCE concept set expression for
#'   that bin), `binName`, `sourceDirs` (the condition sub-folders that
#'   contributed concepts), and `files` (the concept set json files read).
#'   Bins with no matching directory or no json files are skipped.
#' @export
buildMergedConceptSetsByBin <- function(diseaseFolder,
                                        connectionDetails,
                                        vocabularyDatabaseSchema,
                                        binDirs = .phenelopeBinDirs,
                                        outputFolder = tempdir()) {

  print("Merging bins")
  result <- list()
  for (binName in binDirs) {
    binPath <- file.path(diseaseFolder, binName)
    if (!dir.exists(binPath)) {
      message(sprintf("Skipping bin '%s' — directory not found at %s", binName, binPath))
      next
    }

    binData <- .readBinConceptSetJsons(binPath)
    if (length(binData$conceptSets) == 0L) {
      message(sprintf("Skipping bin '%s' — no concept set json files found", binName))
      next
    }
    message(sprintf("Merging bin '%s'", binName))
    mergedCs <- unionConceptsets(
      conceptsetName = binName,
      conceptSetExpressions = binData$conceptSets,
      connectionDetails = connectionDetails,
      vocabularyDatabaseSchema = vocabularyDatabaseSchema,
      outputFolder = outputFolder
    )

    result[[binName]] <- list(
      mergedConceptSet = mergedCs,
      binName          = binName,
      sourceDirs       = names(binData$conceptSets),
      files            = binData$files
    )
  }

  result
}


# Example: Acute Liver Failure evaluation cohorts -------------------------------
#
# Concept sets are built from the binned concept set json exports under
# largescalephentest/phenelopeConceptSetsNew/Acute liver failure/, merged per
# bin (not optimized) by ConceptSetLogic.R's buildMergedConceptSetsByBin()/
# mergeConceptSets() — see `mergesdCSLists` (loaded via source() above).

#' Union the unioned concept sets of one or more phenelope bins into a Capr cs()
#'
#' Unions the already-merged bin expressions (from `buildMergedConceptSetsByBin()`)
#' across bins with `unionConceptsets()`, preserving exclusions and hierarchy
#' optimization, then loads the result as a Capr concept set.
#' @noRd
buildCsFromBins <- function(binNames, label, mergedCSLists, connectionDetails, vocabularyDatabaseSchema,
                            outputFolder = tempdir()) {

  binExpressions <- lapply(binNames, function(b) mergedCSLists[[b]]$mergedConceptSet)

  unionConceptsets(
    conceptsetName = label,
    conceptSetExpressions = binExpressions,
    connectionDetails = connectionDetails,
    vocabularyDatabaseSchema = vocabularyDatabaseSchema,
    outputFolder = outputFolder
  )

  Capr::readConceptSet(file.path(outputFolder, paste0(label, ".json")), name = label)
}