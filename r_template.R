# Pheval Outcome Phenotype Evaluation Templates --------------------------------
#
# Builds first-occurrence evaluation cohorts by composing clinical evidence
# categories into attrition rules that tune specificity. Based on the Phevaluator
# xSpec pattern: index on the first diagnosis of a disease, then layer on
# supporting evidence from related clinical categories.
#
# Categories:
#   I - disease of interest (index event)
#   S - symptoms (30 days before through index day)
#   D - diagnostic tests (30 days before through index day)
#   T - treatments (index day through 30 days after)
#   C - complications (1-365 days after index)
#   F - follow-up care (second I code within 365d OR ER/inpatient visit at index)
#   A - alternative diagnoses (excluded, -30 to +30 days around index)
#
# Each category queries multiple OMOP domains where the concept may be recorded:
#   S, C, A  -> conditionOccurrence OR observation
#   D        -> measurement OR procedure OR deviceExposure
#   T        -> drugExposure OR procedure OR deviceExposure
#   F (I)    -> conditionOccurrence OR observation
#   F (visit)-> visit (hard-coded ER/Inpatient concept set)
#   I (entry)-> conditionOccurrence OR observation
#
# A NULL concept set means that category is not relevant for this disease
# and is silently omitted from the logic group.
#
# All inclusion criteria have "allow events outside observation period" enabled.
#
# Naming convention:
#   Base case:  [PheTpl] <phenotypeLabel> tpl base_case
#   Scenarios:  [PheTpl] <phenotypeLabel> tpl 1, tpl 2, ..., tpl 22
#
# Templates 1-8 are single-criterion "primitive" templates — a single
# category (or a bare exclusion), with no other requirement:
#   1: (S|D)             4: T             7: (S|D) ^ !A
#   2: (T|C|F)            5: !A            8: (T|C|F) ^ !A
#   3: F                  6: D
#
# Templates 9-14 combine S/D and T/C/F with "any"/"all" operators
# (with/without excluding A). Templates 15-22 always require S AND D
# pre-index, paired with a specific AND-combination of post-index categories
# via `postCombo` (T^F, F^C, T^C, or T^C^F), with/without excluding A:
#   9:  (S|D) ^ (T|C|F)
#   10: (S|D) ^ (T|C|F) ^ !A
#   11: (S^D) ^ (T|C|F)
#   12: (S^D) ^ (T|C|F) ^ !A
#   13: (S|D) ^ (T^C^F)
#   14: (S|D) ^ (T^C^F) ^ !A
#   15: (S^D) ^ (T^F)
#   16: (S^D) ^ (F^C)
#   17: (S^D) ^ (T^C)
#   18: (S^D) ^ (T^F) ^ !A
#   19: (S^D) ^ (F^C) ^ !A
#   20: (S^D) ^ (T^C) ^ !A
#   21: (S^D) ^ (T^C^F)
#   22: (S^D) ^ (T^C^F) ^ !A
#
# Usage:
#   outcomePhenotypeTpl(
#     cs_I, phenotypeLabel = "Atrial Fibrillation",
#     preOp = "any", postOp = "any", excludeA = FALSE, exit = "chronic"
#   )
#   outcomePhenotypeTpl(
#     cs_I, phenotypeLabel = "Atrial Fibrillation",
#     preOp = "all", postOp = "all", postCombo = c("T", "F"),
#     excludeA = FALSE, exit = "chronic"
#   )
#   outcomePhenotypeTpl(
#     cs_I, phenotypeLabel = "Atrial Fibrillation",
#     preCombo = character(0), postCombo = c("F"), exit = "chronic"
#   )


library(Capr)

# Internal helpers -------------------------------------------------------------

#' Hard-coded ER/Inpatient visit concept set
#'
#' This is not user-supplied; it is a fixed part of the template logic.
#' Concept IDs: 9201 (Inpatient Visit), 9203 (Emergency Room Visit),
#' 262 (ER + Inpatient)
#' @noRd
getERInpatientVisitCs <- function() {
  cs(
    descendants(9201L, 9203L, 262L),
    name = "ER/Inpatient visit types (hard-coded)"
  )
}

#' Build a multi-domain criterion group
#'
#' Given a concept set and a list of domain query constructors, build
#' `withAny(domain1(cs, ...), domain2(cs, ...), ...)` — all share the same
#' window. Returns NULL if cs is NULL.
#'
#' All criteria allow events outside the observation period
#' (`duringInterval(ignoreObservationPeriod = TRUE)`).
#'
#' @param cs A ConceptSet, or NULL.
#' @param domainFns List of domain constructor functions (e.g.
#'   `list(conditionOccurrence, observation)`).
#' @param startWindow An EventWindow from `eventStarts()`.
#' @param endWindow An optional EventWindow from `eventEnds()`.
#' @param minCount Minimum occurrences. Default 1 (`atLeast`). Use 0 for
#'   absence checks.
#' @return A Group (from `withAny`) or NULL.
#' @noRd
makeMultiDomainCriterion <- function(cs, domainFns, startWindow,
                                     endWindow = NULL, minCount = 1L) {
  if (is.null(cs)) return(NULL)

  criteria <- lapply(domainFns, function(fn) {
    if (minCount == 0L) {
      exactly(0L, fn(cs),
              duringInterval(startWindow = startWindow, endWindow = endWindow,
                              ignoreObservationPeriod = TRUE))
    } else {
      atLeast(as.integer(minCount), fn(cs),
              duringInterval(startWindow = startWindow, endWindow = endWindow,
                              ignoreObservationPeriod = TRUE))
    }
  })

  do.call(withAny, criteria)
}

#' Build the F (follow-up) criterion group
#'
#' F = second I code within 365 days after index (condition OR observation)
#'     OR ER/inpatient visit overlapping the index date (hard-coded concept set).
#'
#' @param cs_I The index disease ConceptSet.
#' @return A Group or NULL.
#' @noRd
makeFCriterion <- function(cs_I) {
  secondI <- makeMultiDomainCriterion(
    cs_I, list(conditionOccurrence, observation),
    startWindow = eventStarts(1, 365)
  )

  cs_F_visit <- getERInpatientVisitCs()
  visitCriterion <- atLeast(
    1L, visit(cs_F_visit),
    duringInterval(
      startWindow = eventStarts(-Inf, 0),
      endWindow   = eventEnds(0, Inf),
      ignoreObservationPeriod = TRUE
    )
  )

  parts <- Filter(Negate(is.null), list(secondI, visitCriterion))

  if (length(parts) == 0L) return(NULL)
  if (length(parts) == 1L) return(parts[[1L]])
  do.call(withAny, parts)
}

#' Build the A (alternative diagnosis) exclusion criterion
#'
#' Returns a `withAll(exactly(0, conditionOccurrence(cs_A), ...),
#' exactly(0, observation(cs_A), ...))` group — zero records in either domain.
#' Window: -30 to +30 days around index.
#'
#' @param cs_A ConceptSet for alternative diagnoses, or NULL.
#' @return A Group or NULL.
#' @noRd
makeExclusionCriterion <- function(cs_A) {
  if (is.null(cs_A)) return(NULL)

  critCond <- exactly(
    0L, conditionOccurrence(cs_A),
    duringInterval(startWindow = eventStarts(-30, 30), ignoreObservationPeriod = TRUE)
  )
  critObs <- exactly(
    0L, observation(cs_A),
    duringInterval(startWindow = eventStarts(-30, 30), ignoreObservationPeriod = TRUE)
  )

  withAll(critCond, critObs)
}

#' Combine a list of criteria with `withAny` or `withAll`
#'
#' Filters NULLs, then applies the operator. Returns NULL if no non-NULL
#' members remain.
#'
#' @param criteria A list of Group / Criteria objects (may contain NULLs).
#' @param op `"any"` or `"all"`.
#' @return A Group or NULL.
#' @noRd
combineCriteria <- function(criteria, op) {
  parts <- Filter(Negate(is.null), criteria)
  if (length(parts) == 0L) return(NULL)
  if (length(parts) == 1L) return(parts[[1L]])
  if (op == "any") do.call(withAny, parts) else do.call(withAll, parts)
}

# Concept Set Overlap Resolution -----------------------------------------------
#
# Enforces precedence rules for concept sets that share condition/observation
# concepts. Only condition/observation domains (I, S, C, A) can overlap;
# D and T live in different domains (measurement/procedure/device, drug/procedure/device)
# and are not subject to these rules.
#
# Precedence (highest -> lowest):
#   1. I (disease of interest) — wins over all others
#   2. A (alternative diagnosis) — wins over S and C
#   3. S and C — allowed to overlap (different time windows)

#' Resolve overlapping concepts across clinical category concept sets
#'
#' Applies precedence rules to remove concepts from lower-priority sets when
#' they also appear in higher-priority sets. Only affects condition/observation
#' domain sets (I, S, C, A). D and T are passed through unchanged.
#'
#' @param cs_I ConceptSet for disease of interest. Required.
#' @param cs_S ConceptSet for symptoms, or NULL.
#' @param cs_D ConceptSet for diagnostic tests, or NULL. Passed through unchanged.
#' @param cs_T ConceptSet for treatments, or NULL. Passed through unchanged.
#' @param cs_C ConceptSet for complications, or NULL.
#' @param cs_A ConceptSet for alternative diagnoses, or NULL.
#' @param warnOnOverlap Logical. If TRUE (default), emit a message listing
#'   removed concepts for traceability.
#'
#' @return A named list with cleaned concept sets:
#'   `cs_I`, `cs_S`, `cs_D`, `cs_T`, `cs_C`, `cs_A`.
#'   Any set reduced to zero concepts becomes NULL.
#' @export
resolveConceptSetOverlaps <- function(cs_I,
                                      cs_S       = NULL,
                                      cs_D       = NULL,
                                      cs_T       = NULL,
                                      cs_C       = NULL,
                                      cs_A       = NULL,
                                      warnOnOverlap = TRUE) {
  if (is.null(cs_I)) stop("cs_I (disease of interest) is required", call. = FALSE)

  # Extract concept IDs from a ConceptSet object
  getIds <- function(cs) {
    if (is.null(cs)) return(integer(0))
    vapply(cs@Expression, function(x) x@Concept@concept_id, integer(1))
  }

  # Remove specific concept IDs from a ConceptSet, return modified or NULL
  removeIds <- function(cs, idsToRemove, label) {
    if (is.null(cs) || length(idsToRemove) == 0L) return(cs)

    currentIds <- getIds(cs)
    overlap <- intersect(currentIds, idsToRemove)

    if (length(overlap) == 0L) return(cs)

    if (warnOnOverlap) {
      message(
        sprintf("resolveConceptSetOverlaps: removed %d concept(s) from %s due to precedence: [%s]",
                length(overlap), label, paste(overlap, collapse = ", "))
      )
    }

    keepIdx <- which(!currentIds %in% idsToRemove)

    if (length(keepIdx) == 0L) {
      if (warnOnOverlap) {
        message(sprintf("  -> %s is now empty (set to NULL)", label))
      }
      return(NULL)
    }

    cs@Expression <- cs@Expression[keepIdx]
    cs
  }

  ids_I <- getIds(cs_I)

  # Rule 1: I wins over everything — remove I concepts from S, C, A
  cs_S <- removeIds(cs_S, ids_I, "cs_S (symptoms)")
  cs_C <- removeIds(cs_C, ids_I, "cs_C (complications)")
  cs_A <- removeIds(cs_A, ids_I, "cs_A (alternative diagnoses)")

  # Rule 2: A wins over S and C — remove A concepts from S and C
  ids_A <- getIds(cs_A)
  cs_S <- removeIds(cs_S, ids_A, "cs_S (symptoms, A-precedence)")
  cs_C <- removeIds(cs_C, ids_A, "cs_C (complications, A-precedence)")

  # Rule 3: S and C are allowed to overlap — no action needed

  list(
    cs_I = cs_I,
    cs_S = cs_S,
    cs_D = cs_D,
    cs_T = cs_T,
    cs_C = cs_C,
    cs_A = cs_A
  )
}


# Main function ----------------------------------------------------------------

#' Build a Phevaluator-style outcome phenotype
#'
#' Constructs a first-occurrence evaluation cohort: index on the first diagnosis
#' of the disease (I) in condition OR observation domain, then layer on
#' supporting evidence from clinical categories (S, D, T, C, F, A) to tune
#' specificity. Each category queries multiple OMOP domains automatically.
#'
#' The ER/Inpatient visit concept set for follow-up (F) is hard-coded internally.
#'
#' All inclusion criteria allow events outside the observation period.
#'
#' @param cs_I ConceptSet for the disease of interest (index event). Required.
#' @param cs_S ConceptSet for symptoms, or NULL.
#' @param cs_D ConceptSet for diagnostic tests, or NULL.
#' @param cs_T ConceptSet for treatments, or NULL.
#' @param cs_C ConceptSet for complications, or NULL.
#' @param cs_A ConceptSet for alternative diagnoses (excluded), or NULL.
#' @param phenotypeLabel Character string. The phenotype label (from the Concept
#'   Set Builder). Used in cohort naming. Required.
#' @param templateNumber Integer or character. Template number for naming.
#'   Use `"base_case"` for the base case, or `1`, `2`, ... for scenarios.
#' @param preOp Operator for pre-index evidence: `"any"` (OR) or `"all"` (AND).
#'   Applies to whichever categories are included per `preCombo` (default: both
#'   S and D, i.e. legacy behavior). Default `"any"`.
#' @param preCombo Optional character vector naming a specific subset of
#'   pre-index categories to combine (via `preOp`), from `c("S", "D")`. Pass
#'   `character(0)` to omit pre-index evidence entirely (no pre-index rule),
#'   or e.g. `"D"` to require only diagnostic tests. Default `NULL` (use
#'   whichever of `cs_S`/`cs_D` are supplied, combined via `preOp` — the
#'   original behavior).
#' @param postOp Operator for post-index evidence: `"any"` (OR) or `"all"`
#'   (AND). Applies to whichever categories are included per `postCombo`
#'   (default: all of T, C, F). Default `"any"`.
#' @param postCombo Optional character vector naming a specific subset of
#'   post-index categories to combine (via `postOp`), from `c("T", "C", "F")`,
#'   e.g. `c("T", "F")` for T (and/or) F, ignoring C entirely (even if `cs_C`
#'   is supplied). Pass `character(0)` to omit post-index evidence entirely
#'   (no post-index rule), or e.g. `"F"` to require only follow-up care.
#'   Default `NULL` (use whichever of T/C/F are supplied, combined via
#'   `postOp` — the original behavior).
#' @param excludeA If TRUE, add an exclusion rule: zero records for alternative
#'   diagnoses (A) within -30 to +30 days around index. Default FALSE.
#' @param firstOccurrenceOnly If TRUE (default), index only a person's first-ever
#'   I diagnosis. If FALSE, every qualifying I diagnosis is a candidate index event.
#' @param primaryCriteriaLimit Which qualifying index event(s) to keep per
#'   person: `"First"`, `"All"`, or `"Last"`. Default `"First"`.
#' @param expressionLimit Which qualifying events survive attrition: `"First"`,
#'   `"All"`, or `"Last"`. Default `"First"`.
#' @param eraDays Gap in days below which consecutive episodes are collapsed into
#'   a single era. Default 0 (no collapse).
#' @param exit Exit strategy: `"chronic"` (observation exit), `"acute14d"`
#'   (fixed 14-day exit from event end), or `"acute365d"` (365-day exit).
#'   Default `"chronic"`.
#' @param resolveOverlaps If TRUE (default), apply concept set overlap resolution
#'   before building the cohort.
#'
#' @return A Capr Cohort object.
#' @export
outcomePhenotypeTpl <- function(cs_I,
                                cs_S           = NULL,
                                cs_D           = NULL,
                                cs_T           = NULL,
                                cs_C           = NULL,
                                cs_A           = NULL,
                                phenotypeLabel,
                                templateNumber = "base_case",
                                preOp          = c("any", "all"),
                                preCombo       = NULL,
                                postOp         = c("any", "all"),
                                postCombo      = NULL,
                                excludeA       = FALSE,
                                firstOccurrenceOnly  = TRUE,
                                primaryCriteriaLimit = c("First", "All", "Last"),
                                expressionLimit      = c("First", "All", "Last"),
                                eraDays        = 0L,
                                exit           = c("chronic", "acute14d", "acute365d"),
                                resolveOverlaps = TRUE) {
  if (is.null(cs_I)) stop("cs_I (disease of interest) is required", call. = FALSE)
  if (missing(phenotypeLabel) || !nzchar(phenotypeLabel)) {
    stop("phenotypeLabel is required", call. = FALSE)
  }
  preOp  <- match.arg(preOp)
  postOp <- match.arg(postOp)
  primaryCriteriaLimit <- match.arg(primaryCriteriaLimit)
  expressionLimit      <- match.arg(expressionLimit)
  exit   <- match.arg(exit)

  if (!is.null(preCombo)) {
    preCombo <- unique(preCombo)
    if (length(preCombo) > 0L && !all(preCombo %in% c("S", "D"))) {
      stop('preCombo must be a subset of c("S", "D") (or character(0) to omit pre-index evidence)', call. = FALSE)
    }
  }
  if (!is.null(postCombo)) {
    postCombo <- unique(postCombo)
    if (length(postCombo) > 0L && !all(postCombo %in% c("T", "C", "F"))) {
      stop('postCombo must be a subset of c("T", "C", "F") (or character(0) to omit post-index evidence)', call. = FALSE)
    }
  }

  # ---- cohort name ----
  cohortName <- sprintf("[PheTpl] %s tpl %s", phenotypeLabel, templateNumber)

  # ---- resolve concept set overlaps ----
  if (resolveOverlaps) {
    resolved <- resolveConceptSetOverlaps(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A)
    cs_S <- resolved$cs_S
    cs_D <- resolved$cs_D
    cs_T <- resolved$cs_T
    cs_C <- resolved$cs_C
    cs_A <- resolved$cs_A
  }

  # ---- entry event (condition OR observation) ----
  # Disease code can exist in either condition or observation domain
  if (isTRUE(firstOccurrenceOnly)) {
    indexCondition   <- conditionOccurrence(cs_I, firstOccurrence())
    indexObservation <- observation(cs_I, firstOccurrence())
  } else {
    indexCondition   <- conditionOccurrence(cs_I)
    indexObservation <- observation(cs_I)
  }

  entryDef <- entry(
    indexCondition,
    indexObservation,
    primaryCriteriaLimit = primaryCriteriaLimit
  )

  # ---- pre-index evidence (S, D) ----
  # Symptoms: condition OR observation, -30 to 0
  # Diagnostics: measurement OR procedure OR device, -30 to 0
  preWindow <- eventStarts(-30, 0)

  sCriterion <- makeMultiDomainCriterion(
    cs_S, list(conditionOccurrence, observation), startWindow = preWindow
  )
  dCriterion <- makeMultiDomainCriterion(
    cs_D, list(measurement, procedure, deviceExposure), startWindow = preWindow
  )

  if (!is.null(preCombo)) {
    if (length(preCombo) == 0L) {
      preGroup <- NULL
    } else {
      preParts <- list(S = sCriterion, D = dCriterion)[preCombo]
      preGroup <- combineCriteria(preParts, preOp)
    }
  } else {
    preGroup <- combineCriteria(list(sCriterion, dCriterion), preOp)
  }

  # ---- post-index evidence (T, C, F) ----
  # Treatment: drug OR procedure OR device, 0 to +30
  tCriterion <- makeMultiDomainCriterion(
    cs_T, list(drugExposure, procedure, deviceExposure),
    startWindow = eventStarts(0, 30)
  )
  # Complications: condition OR observation, +1 to +365
  cCriterion <- makeMultiDomainCriterion(
    cs_C, list(conditionOccurrence, observation),
    startWindow = eventStarts(1, 365)
  )
  # Follow-up: second I code within 365d OR ER/inpatient at index
  fCriterion <- makeFCriterion(cs_I)

  if (!is.null(postCombo)) {
    if (length(postCombo) == 0L) {
      postGroup <- NULL
    } else {
      postParts <- list(T = tCriterion, C = cCriterion, F = fCriterion)[postCombo]
      postGroup <- combineCriteria(postParts, postOp)
    }
  } else {
    postGroup <- combineCriteria(
      list(tCriterion, cCriterion, fCriterion), postOp
    )
  }

  # ---- A exclusion (-30 to +30) ----
  aGroup <- NULL
  if (excludeA) {
    aGroup <- makeExclusionCriterion(cs_A)
  }

  # ---- exit strategy ----
  exitStrategy <- switch(exit,
                         chronic    = observationExit(),
                         acute14d   = fixedExit(index = "endDate", offsetDays = 14L),
                         acute365d  = fixedExit(index = "endDate", offsetDays = 365L)
  )

  # ---- assemble attrition rules ----
  ruleList <- list()
  if (!is.null(preGroup)) {
    ruleList[["pre-index evidence (S/D within -30 to 0d)"]] <- preGroup
  }
  if (!is.null(postGroup)) {
    ruleList[["post-index evidence (T/C/F within specified windows)"]] <- postGroup
  }
  if (!is.null(aGroup)) {
    ruleList[["no alternative diagnosis (A excluded -30 to +30d)"]] <- aGroup
  }

  # ---- build cohort ----
  cohortObj <- cohort(
    entry = entryDef,
    attrition = do.call(attrition, c(ruleList, list(expressionLimit = expressionLimit))),
    exit = exit(endStrategy = exitStrategy),
    era = era(eraDays = eraDays)
  )

  # Attach cohort name as an attribute for downstream use

  attr(cohortObj, "cohortName") <- cohortName

  cohortObj
}

# Convenience wrappers ---------------------------------------------------------
# One function per logical pattern.
# Each is a thin call to outcomePhenotypeTpl() with preOp/preCombo/postOp/
# postCombo/excludeA preset.

#' @rdname outcomePhenotypeTpl
#' @export
preAnyOnly_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                           cs_C = NULL, cs_A = NULL,
                           phenotypeLabel, templateNumber = 1L,
                           exit = c("chronic", "acute14d", "acute365d"),
                           firstOccurrenceOnly = TRUE,
                           primaryCriteriaLimit = c("First", "All", "Last"),
                           expressionLimit = c("First", "All", "Last"),
                           eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "any", preCombo = c("S", "D"),
                      postCombo = character(0),
                      excludeA = FALSE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
postAnyOnly_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                            cs_C = NULL, cs_A = NULL,
                            phenotypeLabel, templateNumber = 2L,
                            exit = c("chronic", "acute14d", "acute365d"),
                            firstOccurrenceOnly = TRUE,
                            primaryCriteriaLimit = c("First", "All", "Last"),
                            expressionLimit = c("First", "All", "Last"),
                            eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preCombo = character(0),
                      postOp = "any",
                      excludeA = FALSE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
postFOnly_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                          cs_C = NULL, cs_A = NULL,
                          phenotypeLabel, templateNumber = 3L,
                          exit = c("chronic", "acute14d", "acute365d"),
                          firstOccurrenceOnly = TRUE,
                          primaryCriteriaLimit = c("First", "All", "Last"),
                          expressionLimit = c("First", "All", "Last"),
                          eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preCombo = character(0),
                      postCombo = c("F"),
                      excludeA = FALSE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
postTOnly_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                          cs_C = NULL, cs_A = NULL,
                          phenotypeLabel, templateNumber = 4L,
                          exit = c("chronic", "acute14d", "acute365d"),
                          firstOccurrenceOnly = TRUE,
                          primaryCriteriaLimit = c("First", "All", "Last"),
                          expressionLimit = c("First", "All", "Last"),
                          eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preCombo = character(0),
                      postCombo = c("T"),
                      excludeA = FALSE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
exclusionOnly_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                              cs_C = NULL, cs_A = NULL,
                              phenotypeLabel, templateNumber = 5L,
                              exit = c("chronic", "acute14d", "acute365d"),
                              firstOccurrenceOnly = TRUE,
                              primaryCriteriaLimit = c("First", "All", "Last"),
                              expressionLimit = c("First", "All", "Last"),
                              eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preCombo = character(0),
                      postCombo = character(0),
                      excludeA = TRUE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preDOnly_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                         cs_C = NULL, cs_A = NULL,
                         phenotypeLabel, templateNumber = 6L,
                         exit = c("chronic", "acute14d", "acute365d"),
                         firstOccurrenceOnly = TRUE,
                         primaryCriteriaLimit = c("First", "All", "Last"),
                         expressionLimit = c("First", "All", "Last"),
                         eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preCombo = c("D"),
                      postCombo = character(0),
                      excludeA = FALSE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preAnyOnly_nox_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                               cs_C = NULL, cs_A = NULL,
                               phenotypeLabel, templateNumber = 7L,
                               exit = c("chronic", "acute14d", "acute365d"),
                               firstOccurrenceOnly = TRUE,
                               primaryCriteriaLimit = c("First", "All", "Last"),
                               expressionLimit = c("First", "All", "Last"),
                               eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "any", preCombo = c("S", "D"),
                      postCombo = character(0),
                      excludeA = TRUE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
postAnyOnly_nox_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                                cs_C = NULL, cs_A = NULL,
                                phenotypeLabel, templateNumber = 8L,
                                exit = c("chronic", "acute14d", "acute365d"),
                                firstOccurrenceOnly = TRUE,
                                primaryCriteriaLimit = c("First", "All", "Last"),
                                expressionLimit = c("First", "All", "Last"),
                                eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preCombo = character(0),
                      postOp = "any",
                      excludeA = TRUE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preAny_postAny_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                               cs_C = NULL, cs_A = NULL,
                               phenotypeLabel, templateNumber = 9L,
                               exit = c("chronic", "acute14d", "acute365d"),
                               firstOccurrenceOnly = TRUE,
                               primaryCriteriaLimit = c("First", "All", "Last"),
                               expressionLimit = c("First", "All", "Last"),
                               eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "any", postOp = "any",
                      excludeA = FALSE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preAny_postAny_nox_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                                   cs_C = NULL, cs_A = NULL,
                                   phenotypeLabel, templateNumber = 10L,
                                   exit = c("chronic", "acute14d", "acute365d"),
                                   firstOccurrenceOnly = TRUE,
                                   primaryCriteriaLimit = c("First", "All", "Last"),
                                   expressionLimit = c("First", "All", "Last"),
                                   eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "any", postOp = "any",
                      excludeA = TRUE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preAll_postAny_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                               cs_C = NULL, cs_A = NULL,
                               phenotypeLabel, templateNumber = 11L,
                               exit = c("chronic", "acute14d", "acute365d"),
                               firstOccurrenceOnly = TRUE,
                               primaryCriteriaLimit = c("First", "All", "Last"),
                               expressionLimit = c("First", "All", "Last"),
                               eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "all", postOp = "any",
                      excludeA = FALSE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preAll_postAny_nox_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                                   cs_C = NULL, cs_A = NULL,
                                   phenotypeLabel, templateNumber = 12L,
                                   exit = c("chronic", "acute14d", "acute365d"),
                                   firstOccurrenceOnly = TRUE,
                                   primaryCriteriaLimit = c("First", "All", "Last"),
                                   expressionLimit = c("First", "All", "Last"),
                                   eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "all", postOp = "any",
                      excludeA = TRUE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preAny_postAll_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                               cs_C = NULL, cs_A = NULL,
                               phenotypeLabel, templateNumber = 13L,
                               exit = c("chronic", "acute14d", "acute365d"),
                               firstOccurrenceOnly = TRUE,
                               primaryCriteriaLimit = c("First", "All", "Last"),
                               expressionLimit = c("First", "All", "Last"),
                               eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "any", postOp = "all",
                      excludeA = FALSE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preAny_postAll_nox_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                                   cs_C = NULL, cs_A = NULL,
                                   phenotypeLabel, templateNumber = 14L,
                                   exit = c("chronic", "acute14d", "acute365d"),
                                   firstOccurrenceOnly = TRUE,
                                   primaryCriteriaLimit = c("First", "All", "Last"),
                                   expressionLimit = c("First", "All", "Last"),
                                   eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "any", postOp = "all",
                      excludeA = TRUE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preAll_postTF_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                              cs_C = NULL, cs_A = NULL,
                              phenotypeLabel, templateNumber = 15L,
                              exit = c("chronic", "acute14d", "acute365d"),
                              firstOccurrenceOnly = TRUE,
                              primaryCriteriaLimit = c("First", "All", "Last"),
                              expressionLimit = c("First", "All", "Last"),
                              eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "all", postOp = "all", postCombo = c("T", "F"),
                      excludeA = FALSE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preAll_postFC_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                              cs_C = NULL, cs_A = NULL,
                              phenotypeLabel, templateNumber = 16L,
                              exit = c("chronic", "acute14d", "acute365d"),
                              firstOccurrenceOnly = TRUE,
                              primaryCriteriaLimit = c("First", "All", "Last"),
                              expressionLimit = c("First", "All", "Last"),
                              eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "all", postOp = "all", postCombo = c("F", "C"),
                      excludeA = FALSE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preAll_postTC_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                              cs_C = NULL, cs_A = NULL,
                              phenotypeLabel, templateNumber = 17L,
                              exit = c("chronic", "acute14d", "acute365d"),
                              firstOccurrenceOnly = TRUE,
                              primaryCriteriaLimit = c("First", "All", "Last"),
                              expressionLimit = c("First", "All", "Last"),
                              eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "all", postOp = "all", postCombo = c("T", "C"),
                      excludeA = FALSE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preAll_postTF_nox_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                                  cs_C = NULL, cs_A = NULL,
                                  phenotypeLabel, templateNumber = 18L,
                                  exit = c("chronic", "acute14d", "acute365d"),
                                  firstOccurrenceOnly = TRUE,
                                  primaryCriteriaLimit = c("First", "All", "Last"),
                                  expressionLimit = c("First", "All", "Last"),
                                  eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "all", postOp = "all", postCombo = c("T", "F"),
                      excludeA = TRUE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preAll_postFC_nox_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                                  cs_C = NULL, cs_A = NULL,
                                  phenotypeLabel, templateNumber = 19L,
                                  exit = c("chronic", "acute14d", "acute365d"),
                                  firstOccurrenceOnly = TRUE,
                                  primaryCriteriaLimit = c("First", "All", "Last"),
                                  expressionLimit = c("First", "All", "Last"),
                                  eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "all", postOp = "all", postCombo = c("F", "C"),
                      excludeA = TRUE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preAll_postTC_nox_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                                  cs_C = NULL, cs_A = NULL,
                                  phenotypeLabel, templateNumber = 20L,
                                  exit = c("chronic", "acute14d", "acute365d"),
                                  firstOccurrenceOnly = TRUE,
                                  primaryCriteriaLimit = c("First", "All", "Last"),
                                  expressionLimit = c("First", "All", "Last"),
                                  eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "all", postOp = "all", postCombo = c("T", "C"),
                      excludeA = TRUE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preAll_postTCF_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                               cs_C = NULL, cs_A = NULL,
                               phenotypeLabel, templateNumber = 21L,
                               exit = c("chronic", "acute14d", "acute365d"),
                               firstOccurrenceOnly = TRUE,
                               primaryCriteriaLimit = c("First", "All", "Last"),
                               expressionLimit = c("First", "All", "Last"),
                               eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "all", postOp = "all", postCombo = c("T", "C", "F"),
                      excludeA = FALSE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

#' @rdname outcomePhenotypeTpl
#' @export
preAll_postTCF_nox_Tpl <- function(cs_I, cs_S = NULL, cs_D = NULL, cs_T = NULL,
                                   cs_C = NULL, cs_A = NULL,
                                   phenotypeLabel, templateNumber = 22L,
                                   exit = c("chronic", "acute14d", "acute365d"),
                                   firstOccurrenceOnly = TRUE,
                                   primaryCriteriaLimit = c("First", "All", "Last"),
                                   expressionLimit = c("First", "All", "Last"),
                                   eraDays = 0L) {
  outcomePhenotypeTpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                      phenotypeLabel = phenotypeLabel,
                      templateNumber = templateNumber,
                      preOp = "all", postOp = "all", postCombo = c("T", "C", "F"),
                      excludeA = TRUE, exit = exit,
                      firstOccurrenceOnly = firstOccurrenceOnly,
                      primaryCriteriaLimit = primaryCriteriaLimit,
                      expressionLimit = expressionLimit, eraDays = eraDays)
}

# Batch builder ----------------------------------------------------------------

#' Build all 23 phenotype evaluation templates for a given disease
#'
#' Generates the base_case (first-ever diagnosis, no attrition) plus 22
#' scenario templates with varying specificity:
#'   * Templates 1-8 are single-criterion "primitive" templates (a single
#'     category, or a bare exclusion, with no other requirement):
#'     1: (S|D), 2: (T|C|F), 3: F, 4: T, 5: !A, 6: D, 7: (S|D)^!A,
#'     8: (T|C|F)^!A.
#'   * Templates 9-14 combine S/D and T/C/F with "any"/"all" operators
#'     (with/without excluding A).
#'   * Templates 15-22 always require S AND D pre-index, paired with
#'     specific AND-combinations of post-index categories (T^F, F^C, T^C, or
#'     T^C^F), with/without excluding A.
#'
#' @param cs_I ConceptSet for disease of interest. Required.
#' @param cs_S ConceptSet for symptoms, or NULL.
#' @param cs_D ConceptSet for diagnostic tests, or NULL.
#' @param cs_T ConceptSet for treatments, or NULL.
#' @param cs_C ConceptSet for complications, or NULL.
#' @param cs_A ConceptSet for alternative diagnoses, or NULL.
#' @param phenotypeLabel Character. The phenotype label from the Concept Set Builder.
#' @param exit Exit strategy. Default `"chronic"`.
#'
#' @return A named list of 23 Capr Cohort objects.
#' @export
buildAllTemplates <- function(cs_I,
                              cs_S = NULL,
                              cs_D = NULL,
                              cs_T = NULL,
                              cs_C = NULL,
                              cs_A = NULL,
                              phenotypeLabel,
                              exit = "chronic") {
  if (missing(phenotypeLabel) || !nzchar(phenotypeLabel)) {
    stop("phenotypeLabel is required", call. = FALSE)
  }

  # Base case: first-ever diagnosis, no attrition rules
  baseCaseName <- sprintf("[PheTpl] %s tpl base_case", phenotypeLabel)
  baseCaseEntry <- entry(
    conditionOccurrence(cs_I, firstOccurrence()),
    observation(cs_I, firstOccurrence()),
    primaryCriteriaLimit = "First"
  )

  exitStrategy <- switch(exit,
                         chronic    = observationExit(),
                         acute14d   = fixedExit(index = "endDate", offsetDays = 14L),
                         acute365d  = fixedExit(index = "endDate", offsetDays = 365L)
  )

  baseCaseCohort <- cohort(
    entry = baseCaseEntry,
    attrition = attrition(expressionLimit = "First"),
    exit = exit(endStrategy = exitStrategy),
    era = era(eraDays = 0L)
  )
  attr(baseCaseCohort, "cohortName") <- baseCaseName

  # 22 scenario templates
  templates <- list(
    base_case = baseCaseCohort,
    tpl_1 = preAnyOnly_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                           phenotypeLabel = phenotypeLabel,
                           templateNumber = 1L, exit = exit),
    tpl_2 = postAnyOnly_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                            phenotypeLabel = phenotypeLabel,
                            templateNumber = 2L, exit = exit),
    tpl_3 = postFOnly_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                          phenotypeLabel = phenotypeLabel,
                          templateNumber = 3L, exit = exit),
    tpl_4 = postTOnly_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                          phenotypeLabel = phenotypeLabel,
                          templateNumber = 4L, exit = exit),
    tpl_5 = exclusionOnly_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                              phenotypeLabel = phenotypeLabel,
                              templateNumber = 5L, exit = exit),
    tpl_6 = preDOnly_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                         phenotypeLabel = phenotypeLabel,
                         templateNumber = 6L, exit = exit),
    tpl_7 = preAnyOnly_nox_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                               phenotypeLabel = phenotypeLabel,
                               templateNumber = 7L, exit = exit),
    tpl_8 = postAnyOnly_nox_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                                phenotypeLabel = phenotypeLabel,
                                templateNumber = 8L, exit = exit),
    tpl_9 = preAny_postAny_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                               phenotypeLabel = phenotypeLabel,
                               templateNumber = 9L, exit = exit),
    tpl_10 = preAny_postAny_nox_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                                    phenotypeLabel = phenotypeLabel,
                                    templateNumber = 10L, exit = exit),
    tpl_11 = preAll_postAny_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                                phenotypeLabel = phenotypeLabel,
                                templateNumber = 11L, exit = exit),
    tpl_12 = preAll_postAny_nox_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                                    phenotypeLabel = phenotypeLabel,
                                    templateNumber = 12L, exit = exit),
    tpl_13 = preAny_postAll_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                                phenotypeLabel = phenotypeLabel,
                                templateNumber = 13L, exit = exit),
    tpl_14 = preAny_postAll_nox_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                                    phenotypeLabel = phenotypeLabel,
                                    templateNumber = 14L, exit = exit),
    tpl_15 = preAll_postTF_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                               phenotypeLabel = phenotypeLabel,
                               templateNumber = 15L, exit = exit),
    tpl_16 = preAll_postFC_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                               phenotypeLabel = phenotypeLabel,
                               templateNumber = 16L, exit = exit),
    tpl_17 = preAll_postTC_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                               phenotypeLabel = phenotypeLabel,
                               templateNumber = 17L, exit = exit),
    tpl_18 = preAll_postTF_nox_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                                   phenotypeLabel = phenotypeLabel,
                                   templateNumber = 18L, exit = exit),
    tpl_19 = preAll_postFC_nox_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                                   phenotypeLabel = phenotypeLabel,
                                   templateNumber = 19L, exit = exit),
    tpl_20 = preAll_postTC_nox_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                                   phenotypeLabel = phenotypeLabel,
                                   templateNumber = 20L, exit = exit),
    tpl_21 = preAll_postTCF_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                                phenotypeLabel = phenotypeLabel,
                                templateNumber = 21L, exit = exit),
    tpl_22 = preAll_postTCF_nox_Tpl(cs_I, cs_S, cs_D, cs_T, cs_C, cs_A,
                                    phenotypeLabel = phenotypeLabel,
                                    templateNumber = 22L, exit = exit)
  )

  templates
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
#' `outcomePhenotypeTpl()`/`buildAllTemplates()`), falling back to the list
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
#'   `buildAllTemplates()`.
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
insertCohortsIntoAtlas <- function(cohortList, baseUrl, skipExisting = TRUE) {
  if (!requireNamespace("ROhdsiWebApi", quietly = TRUE)) {
    stop("Package 'ROhdsiWebApi' is required. Install with: ",
         'remotes::install_github("OHDSI/ROhdsiWebApi")', call. = FALSE)
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' is required to parse the cohort JSON for insertion.",
         call. = FALSE)
  }
  if (missing(baseUrl) || !nzchar(baseUrl)) {
    stop("baseUrl (the WebApi base URL) is required", call. = FALSE)
  }

  results <- list()

  for (nm in names(cohortList)) {
    cohortObj  <- cohortList[[nm]]
    cohortName <- attr(cohortObj, "cohortName") %||% nm

    if (isTRUE(skipExisting)) {
      existing <- ROhdsiWebApi::existsCohortName(cohortName = cohortName, baseUrl = baseUrl)
      if (!isFALSE(existing)) {
        message(sprintf("Skipping '%s' — a cohort with this name already exists in Atlas.",
                         cohortName))
        results[[nm]] <- existing
        next
      }
    }

    cohortJson       <- toCohortJson(cohortObj)
    cohortExpression <- jsonlite::fromJSON(cohortJson, simplifyVector = FALSE)

    message(sprintf("Posting cohort '%s' to Atlas...", cohortName))
    results[[nm]] <- ROhdsiWebApi::postCohortDefinition(
      name             = cohortName,
      cohortDefinition = cohortExpression,
      baseUrl          = baseUrl
    )
  }

  results
}


# Example: Atrial Fibrillation evaluation cohorts ------------------------------

# ---- concept sets (TEST PLACEHOLDERS — overlaps exercise precedence rules) ----

afib_I <- cs(
  c(313217,605092,1340258,4068155,4117112,4119601,4119602,4141360,4154290,4199501,4232691,4232697,37170582,37171038,37172212,37172244,37395821,42539346,44782442,45768480),
  name = "Atrial fibrillation"
)

afib_S <- cs(
  descendants(27674,79908,259153,313217,314665,315078,317376,376961,436817,441417,441542,442555,444070,4034235,4037885,4041664,4059005,4090431,4092743,4114624,4116811,4203638,4223659,4223938,4229392,4262562,4272240,4305080,4310235,4329041,36714126),
  name = "AFib symptoms — palpitations, dyspnea, dizziness"
)

afib_D <- cs(
  descendants(4759705,759706,759707,759708,759709,759710,759711,759712,2001544,2007079,2212089,2313879,2313880,3000551,3001019,3004064,3005162,3005456,3006906,3008486,3015377,3020059,3024675,3027495,3032503,3041230,3047107,4014134,4017355,4062856,4094598,4098039,4154490,4163951,4196969,4219024,4230911,4243005,4245152,4246879,4248132,42529233,42739967,43528023),
  name = "AFib diagnostics — ECG, echocardiogram, Holter"
)

afib_T <- cs(
  descendants(902427,914335,927084,950370,989878,1105775,1112807,1183554,1301025,1307046,1307542,1307863,1309204,1309944,1310149,1313200,1314002,1314577,1322081,1322184,1326303,1328165,1335606,1337860,1338005,1346823,1351461,1353256,1353766,1354860,1360421,1362979,1367571,1370109,2001549,2001551,2008358,2008361,2107050,2107051,2107065,2107066,2107068,2313791,2313792,2313854,2726385,2788044,4049987,4051938,4098410,4144100,19015230,19024063,19026180,19063575,19084670,40163615,40228152,40241331,42627933,43013024,45892847,46234437),
  name = "AFib treatments — anticoagulants, antiarrhythmics, cardioversion"
)

afib_C <- cs(
  descendants(135360,197320,200451,201965,254061,261600,313217,313226,313780,316139,317002,319844,320744,321042,321319,372924,373503,374022,374384,375557,376713,377845,381316,434056,435642,438791,440424,443454,443551,4068155,4110961,4112024,4121341,4124706,4138543,4142895,4159647,4164092,4185607,4188331,4191650,4213731,4237062,4238191,4256228,4274969,4311124,4322024,37309626,42536547,44782781),
  name = "AFib complications — ischemic stroke, heart failure"
)

afib_A <- cs(
  descendants(313217,317302,437892,441872,4007310,4089462,4091901,4103295,4171269,4275423),
  name = "Alternative diagnoses — atrial flutter, SVT"
)

# ---- expected results after resolveConceptSetOverlaps() ----
#
# cs_I:  {100, 101, 102}  — unchanged (highest precedence)
# cs_A:  {300, 301, 302}  — 102 removed (Rule 1)
# cs_S:  {200, 201, 202}  — 100 removed (Rule 1), 300 removed (Rule 2)
# cs_C:  {600, 601, 201}  — 101 removed (Rule 1), 300 removed (Rule 2)
# cs_D:  {400, 401, 402}  — unchanged (different domain)
# cs_T:  {500, 501, 502}  — unchanged (different domain)
#
# Note: 201 remains in both S and C (Rule 3 — overlap allowed)


# ---- build all 15 definitions (base_case + 14 templates) ----

phenotypeLabel <- "Atrial Fibrillation"

afibTemplates <- buildAllTemplates(
  cs_I = afib_I,
  cs_S = afib_S,
  cs_D = afib_D,
  cs_T = afib_T,
  cs_C = afib_C,
  cs_A = afib_A,
  phenotypeLabel = phenotypeLabel,
  exit = "chronic"
)

# ---- write to JSON files ----

dir.create("output", showWarnings = FALSE)
for (nm in names(afibTemplates)) {
  cohortName <- attr(afibTemplates[[nm]], "cohortName") %||% nm
  fileName <- gsub("[^A-Za-z0-9_]", "_", cohortName)
  writeCohort(afibTemplates[[nm]], file.path("output", paste0(fileName, ".json")))
  cat("Wrote:", cohortName, "\n")
}

cat("Wrote", length(afibTemplates), "cohort JSON files to output/\n")


# ---- insert cohort definitions into Atlas (NOT executed) ---------------------
#
# Guarded with `if (FALSE)` so sourcing/running this script never actually
# contacts a WebApi instance. To use: copy this block out (or flip the guard),
# set `webApiBaseUrl` to your Atlas/WebApi instance, and authenticate first if
# required. Requires the ROhdsiWebApi package:
#   remotes::install_github("OHDSI/ROhdsiWebApi")

if (FALSE) {
  webApiBaseUrl <- "http://your-server:8080/WebAPI"

  # Only needed if the WebApi instance requires authentication.
  # authMethod can be "db", "ad", or "windows"; omit webApiPassword to be
  # prompted for it interactively rather than hard-coding it here.
  ROhdsiWebApi::authorizeWebApi(
    baseUrl         = webApiBaseUrl,
    authMethod      = "db",
    webApiUsername  = "your_username"
  )

  atlasInsertResults <- insertCohortsIntoAtlas(
    cohortList   = afibTemplates,
    baseUrl      = webApiBaseUrl,
    skipExisting = TRUE
  )

  print(atlasInsertResults)
}

