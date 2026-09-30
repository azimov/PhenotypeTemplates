# Union of OHDSI CIRCE concept set expressions.
# Requires: CirceR, SqlRender, DatabaseConnector, jsonlite

.flag <- function(item, name) isTRUE(item[[name]])

.idList <- function(ids) paste(as.integer(unique(ids)), collapse = ",")

.readExpression <- function(x) {
  if (is.list(x)) return(x)
  if (length(x) == 1 && file.exists(x)) return(jsonlite::read_json(x, simplifyVector = FALSE))
  jsonlite::parse_json(x, simplifyVector = FALSE)
}

.toJson <- function(expr) {
  as.character(jsonlite::toJSON(expr, auto_unbox = TRUE, null = "null", digits = NA))
}

.itemDf <- function(items) {
  if (length(items) == 0) {
    return(data.frame(conceptId = integer(0), includeDescendants = logical(0),
                      includeMapped = logical(0), isExcluded = logical(0)))
  }
  data.frame(
    conceptId = vapply(items, function(i) as.integer(i$concept$CONCEPT_ID), integer(1)),
    includeDescendants = vapply(items, .flag, logical(1), name = "includeDescendants"),
    includeMapped = vapply(items, .flag, logical(1), name = "includeMapped"),
    isExcluded = vapply(items, .flag, logical(1), name = "isExcluded")
  )
}

.countIds <- function(idsPerSet) {
  ids <- unlist(lapply(idsPerSet, unique))
  if (length(ids) == 0) return(data.frame(conceptId = integer(0), n = integer(0)))
  t <- table(ids)
  data.frame(conceptId = as.integer(names(t)), n = as.integer(t))
}

# Resolve a concept set expression to its concept ids using CIRCE-generated SQL.
.resolve <- function(connection, expr, vocabularyDatabaseSchema) {
  if (length(expr$items) == 0) return(integer(0))
  sql <- CirceR::buildConceptSetQuery(.toJson(expr))
  sql <- SqlRender::render(sql, vocabulary_database_schema = vocabularyDatabaseSchema)
  sql <- SqlRender::translate(sql, targetDialect = DatabaseConnector::dbms(connection))
  as.integer(DatabaseConnector::querySql(connection, sql, snakeCaseToCamelCase = TRUE)$conceptId)
}

# Resolve many atomic items (conceptId/includeDescendants/includeMapped rows) in one DB round trip.
# Returns a named list keyed by df$rowId (or row position if rowId is absent) of resolved concept ids.
.resolveItemsBatch <- function(connection, df, vocabularyDatabaseSchema) {
  if (nrow(df) == 0) return(list())
  if (is.null(df$rowId)) df$rowId <- seq_len(nrow(df))
  values <- paste0("(", df$rowId, ", ", as.integer(df$conceptId), ", ",
                    as.integer(df$includeDescendants), ", ", as.integer(df$includeMapped), ")",
                    collapse = ",\n")
  sql <- "
  WITH items (row_id, concept_id, include_descendants, include_mapped) AS (
    VALUES @values
  ),
  desc_ids AS (
    SELECT row_id, concept_id FROM items WHERE include_descendants = 0
    UNION ALL
    SELECT i.row_id, ca.descendant_concept_id AS concept_id
    FROM items i
    INNER JOIN @vocab.concept_ancestor ca ON ca.ancestor_concept_id = i.concept_id
    WHERE i.include_descendants = 1
  )
  SELECT DISTINCT row_id, concept_id FROM desc_ids
  UNION
  SELECT DISTINCT d.row_id, cr.concept_id_1 AS concept_id
  FROM desc_ids d
  INNER JOIN items i ON i.row_id = d.row_id AND i.include_mapped = 1
  INNER JOIN @vocab.concept_relationship cr
    ON cr.concept_id_2 = d.concept_id AND cr.relationship_id = 'Maps to' AND cr.invalid_reason IS NULL;
  "
  res <- DatabaseConnector::renderTranslateQuerySql(
    connection, sql, vocab = vocabularyDatabaseSchema, values = values, snakeCaseToCamelCase = TRUE
  )
  split(as.integer(res$conceptId), as.character(res$rowId))
}

.resolveItems <- function(connection, df, vocabularyDatabaseSchema) {
  if (nrow(df) == 0) return(integer(0))
  sort(unique(unlist(.resolveItemsBatch(connection, df, vocabularyDatabaseSchema))))
}

# Remove inclusion entries already covered by another entry (ancestor + descendants).
.optimizeInclusions <- function(connection, inc, vocabularyDatabaseSchema) {
  if (nrow(inc) == 0) return(data.frame(conceptId = integer(0), includeDescendants = logical(0),
                                         includeMapped = logical(0), isExcluded = logical(0)))
  inc <- aggregate(cbind(includeDescendants, includeMapped) ~ conceptId, data = inc, FUN = any)
  inc$isExcluded <- FALSE
  ancestors <- inc$conceptId[inc$includeDescendants]
  if (length(ancestors) == 0) return(inc)

  pairs <- DatabaseConnector::renderTranslateQuerySql(
    connection,
    "SELECT ancestor_concept_id, descendant_concept_id
     FROM @vocab.concept_ancestor
     WHERE ancestor_concept_id IN (@ancestors)
       AND descendant_concept_id IN (@all)
       AND ancestor_concept_id <> descendant_concept_id;",
    vocab = vocabularyDatabaseSchema,
    ancestors = .idList(ancestors),
    all = .idList(inc$conceptId),
    snakeCaseToCamelCase = TRUE
  )
  pairs <- merge(pairs, inc[inc$includeDescendants, c("conceptId", "includeMapped")],
                 by.x = "ancestorConceptId", by.y = "conceptId")

  redundant <- vapply(seq_len(nrow(inc)), function(i) {
    any(pairs$descendantConceptId == inc$conceptId[i] & (pairs$includeMapped | !inc$includeMapped[i]))
  }, logical(1))
  inc[!redundant, ]
}

.conceptObjects <- function(connection, ids, vocabularyDatabaseSchema) {
  d <- DatabaseConnector::renderTranslateQuerySql(
    connection,
    "SELECT concept_id, concept_name, domain_id, vocabulary_id, concept_class_id,
            standard_concept, concept_code, valid_start_date, valid_end_date, invalid_reason
     FROM @vocab.concept WHERE concept_id IN (@ids);",
    vocab = vocabularyDatabaseSchema,
    ids = .idList(ids)
  )
  names(d) <- toupper(names(d))
  objs <- lapply(seq_len(nrow(d)), function(i) {
    r <- d[i, ]
    ir <- if (is.na(r$INVALID_REASON)) "V" else r$INVALID_REASON
    sc <- if (is.na(r$STANDARD_CONCEPT)) "N" else r$STANDARD_CONCEPT
    list(
      CONCEPT_CLASS_ID = r$CONCEPT_CLASS_ID,
      CONCEPT_CODE = r$CONCEPT_CODE,
      CONCEPT_ID = as.integer(r$CONCEPT_ID),
      CONCEPT_NAME = r$CONCEPT_NAME,
      DOMAIN_ID = r$DOMAIN_ID,
      INVALID_REASON = ir,
      INVALID_REASON_CAPTION = if (ir == "V") "Valid" else "Invalid",
      STANDARD_CONCEPT = sc,
      STANDARD_CONCEPT_CAPTION = switch(sc, S = "Standard", C = "Classification", "Non-Standard"),
      VOCABULARY_ID = r$VOCABULARY_ID,
      VALID_START_DATE = format(as.Date(r$VALID_START_DATE)),
      VALID_END_DATE = format(as.Date(r$VALID_END_DATE))
    )
  })
  setNames(objs, as.character(d$CONCEPT_ID))
}

#' Union a list of CIRCE concept set expressions into one expression.
#'
#' @param conceptsetName Name of the new concept set; output is written to <outputFolder>/<conceptsetName>.json
#' @param conceptSetExpressions List/vector of concept set expressions (file paths, JSON strings, or parsed lists)
#' @param connectionDetails DatabaseConnector connectionDetails for a database with OMOP vocabulary tables
#' @param vocabularyDatabaseSchema Schema holding the vocabulary tables
#' @param outputFolder Folder to write the output JSON
#' @export
#' @return The union concept set expression (list), invisibly
unionConceptsets <- function(conceptsetName,
                             conceptSetExpressions,
                             connectionDetails,
                             vocabularyDatabaseSchema,
                             outputFolder = ".") {
  connection <- DatabaseConnector::connect(connectionDetails)
  on.exit(DatabaseConnector::disconnect(connection))

  exprs <- lapply(conceptSetExpressions, .readExpression)

  # L: concepts from inclusion entries (before exclusions), counted by number of concept sets including each.
  # All sets' inclusion items are tagged by set index and resolved in a single DB round trip.
  incTagged <- do.call(rbind, lapply(seq_along(exprs), function(k) {
    df <- .itemDf(exprs[[k]]$items)
    df <- df[!df$isExcluded, ]
    if (nrow(df) == 0) return(NULL)
    df$setIdx <- k
    df
  }))
  if (!is.null(incTagged)) incTagged$rowId <- seq_len(nrow(incTagged))
  incResolved <- if (is.null(incTagged)) list() else .resolveItemsBatch(connection, incTagged, vocabularyDatabaseSchema)
  includedPerSet <- lapply(seq_along(exprs), function(k) {
    if (is.null(incTagged)) return(integer(0))
    rows <- which(incTagged$setIdx == k)
    if (length(rows) == 0) return(integer(0))
    sort(unique(unlist(incResolved[as.character(incTagged$rowId[rows])])))
  })
  L <- .countIds(includedPerSet)

  # U: all inclusion entries, optimized
  allItems <- .itemDf(unlist(lapply(exprs, `[[`, "items"), recursive = FALSE))
  inc <- .optimizeInclusions(connection, allItems[!allItems$isExcluded, ], vocabularyDatabaseSchema)
  includedByU <- .resolveItems(connection, inc, vocabularyDatabaseSchema)

  # EC: excluded concepts, counted by number of concept sets whose own inclusions they remove.
  # All sets' exclusion items are similarly tagged and resolved in a single DB round trip.
  excTagged <- do.call(rbind, lapply(seq_along(exprs), function(k) {
    df <- .itemDf(exprs[[k]]$items)
    df <- df[df$isExcluded, ]
    if (nrow(df) == 0) return(NULL)
    df$isExcluded <- FALSE
    df$setIdx <- k
    df
  }))
  if (!is.null(excTagged)) excTagged$rowId <- seq_len(nrow(excTagged))
  excResolved <- if (is.null(excTagged)) list() else .resolveItemsBatch(connection, excTagged, vocabularyDatabaseSchema)
  excPerSet <- lapply(seq_along(exprs), function(k) {
    if (is.null(excTagged)) return(integer(0))
    rows <- which(excTagged$setIdx == k)
    if (length(rows) == 0) return(integer(0))
    ids <- sort(unique(unlist(excResolved[as.character(excTagged$rowId[rows])])))
    intersect(ids, includedPerSet[[k]])
  })
  EC <- .countIds(excPerSet)

  # Each input set's fully-resolved concepts (its own inclusions minus its own exclusions), derived without extra queries
  resolved <- Map(setdiff, includedPerSet, excPerSet)

  counts <- merge(EC, L, by = "conceptId", all.x = TRUE, suffixes = c("Excluded", "Included"))
  counts$nIncluded[is.na(counts$nIncluded)] <- 0L
  toExclude <- counts$conceptId[counts$nExcluded >= counts$nIncluded]

  # Keep an original exclusion entry if all its concepts qualify; otherwise exclude qualifying concepts individually
  exc <- unique(allItems[allItems$isExcluded, ])
  excEntryResolved <- if (nrow(exc) == 0) list() else {
    tmp <- exc
    tmp$isExcluded <- FALSE
    tmp$rowId <- seq_len(nrow(tmp))
    .resolveItemsBatch(connection, tmp, vocabularyDatabaseSchema)
  }
  keepEntry <- logical(nrow(exc))
  singleExclusions <- integer(0)
  for (i in seq_len(nrow(exc))) {
    r <- intersect(excEntryResolved[[as.character(i)]], includedByU)
    if (length(r) == 0) next
    if (all(r %in% toExclude)) {
      keepEntry[i] <- TRUE
    } else {
      singleExclusions <- c(singleExclusions, intersect(r, toExclude))
    }
  }
  singleExclusions <- setdiff(unique(singleExclusions), exc$conceptId[keepEntry & !exc$includeDescendants & !exc$includeMapped])
  finalExc <- rbind(
    exc[keepEntry, ],
    data.frame(conceptId = singleExclusions, includeDescendants = rep(FALSE, length(singleExclusions)),
               includeMapped = rep(FALSE, length(singleExclusions)), isExcluded = rep(TRUE, length(singleExclusions)))
  )

  final <- rbind(inc, finalExc)
  concepts <- .conceptObjects(connection, final$conceptId, vocabularyDatabaseSchema)
  missingIds <- setdiff(final$conceptId, as.integer(names(concepts)))
  if (length(missingIds) > 0) {
    warning("Concept id(s) not found in vocabulary schema '", vocabularyDatabaseSchema, "': ",
         paste(missingIds, collapse = ", "), " — dropping from concept set")
    final <- final[!(final$conceptId %in% missingIds), ]
  }
  expression <- list(items = lapply(seq_len(nrow(final)), function(i) list(
    concept = concepts[[as.character(final$conceptId[i])]],
    isExcluded = final$isExcluded[i],
    includeDescendants = final$includeDescendants[i],
    includeMapped = final$includeMapped[i]
  )))

  # Compare against the true union of the resolved inputs
  resolvedUnion <- .resolve(connection, expression, vocabularyDatabaseSchema)
  trueUnion <- unique(unlist(resolved))
  message(sprintf("Union '%s': %d entries (%d inclusions, %d exclusions) resolving to %d concepts; true union of inputs = %d concepts; missing = %d, extra = %d",
                  conceptsetName, nrow(final), nrow(inc), nrow(finalExc), length(resolvedUnion), length(trueUnion),
                  length(setdiff(trueUnion, resolvedUnion)), length(setdiff(resolvedUnion, trueUnion))))

  dir.create(outputFolder, showWarnings = FALSE, recursive = TRUE)
  outFile <- file.path(outputFolder, paste0(conceptsetName, ".json"))
  jsonlite::write_json(expression, outFile, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null")
  message("Saved: ", outFile)

  invisible(expression)
}
