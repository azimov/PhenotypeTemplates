# Build curated hybrid evidence-combination cohorts ---------------------------
#
# Generates a small, ergonomic set of cohorts per-phenotype:
#   - base case (use config as-is)
#   - four single-flag-only cohorts (S-only, D-only, T-only, FU-only)
#   - four threshold cohorts: atLeast(1..4) of the available evidence components
#
# The initial implementation emits a standalone set (no hypernym/index
# specificity crossing, no hospitalization or A-exclusion variants). The
# function returns a cohort definition set data.frame like
# `buildPhenotypeTemplates()`.

#' Build curated evidence-combination cohorts for one phenotype
#'
#' @param cs_I,cs_H,cs_S,cs_D,cs_T,cs_C,cs_A,cs_E Concept sets (see
#'   `outcomePhenotypeTpl()`)
#' @param phenotypeLabel Character label
#' @param config Phenotype config (see `phenotypeConfig()` / `validatePhenotypeConfig()`)
#' @param startCohortId Starting cohortId (first output will be +1)
#' @return data.frame of cohort definitions (cohortId, cohortName, json, sql)
#' @export
buildEvidenceCombinationCohorts <- function(cs_I,
                                            cs_H = NULL,
                                            cs_S = NULL,
                                            cs_D = NULL,
                                            cs_T = NULL,
                                            cs_C = NULL,
                                            cs_A = NULL,
                                            cs_E = NULL,
                                            phenotypeLabel,
                                            config,
                                            startCohortId = 0) {
  config <- validatePhenotypeConfig(config)

  # resolve overlaps
  resolved <- resolveConceptSetOverlaps(cs_I, cs_H, cs_S, cs_D, cs_T, cs_C, cs_A, cs_E)
  cs_H <- resolved$cs_H
  cs_S <- resolved$cs_S
  cs_D <- resolved$cs_D
  cs_T <- resolved$cs_T
  cs_C <- resolved$cs_C
  cs_A <- resolved$cs_A
  cs_E <- resolved$cs_E

  warnLargeConceptSets(list(I = cs_I, H = cs_H, S = cs_S, D = cs_D, T = cs_T, C = cs_C, A = cs_A, E = cs_E))

  exitConfig <- resolvePhenotypeExitStrategy(
    clinicalCourse = config$clinicalCourse,
    recommendedCohortExit = config$recommendedCohortExit,
    minimumInterepisodeDayGap = config$minimumInterepisodeDayGap,
    fixedExitDays = config$fixedExitDays
  )

  demographicCriteria <- greateDemographicCriteria(
    minAge = config$minAge, maxAge = config$maxAge,
    male = config$male, female = config$female
  )

  templates <- list()

  # Base case: use config as given
  templates[["base_case"]] <- outcomePhenotypeTpl(
    cs_I, cs_H, cs_S, cs_D, cs_T, cs_C, cs_A, cs_E,
    phenotypeLabel = phenotypeLabel,
    templateSuffix = "base_case",
    useHypernymAsIndex = FALSE,
    hasDescreteRecordedSymptoms = config$hasDescreteRecordedSymptoms,
    requiresDiagnosticTestOrProcedure = config$requiresDiagnosticTestOrProcedure,
    requiresActiveTreatmentWithin30d = config$requiresActiveTreatmentWithin30d,
    expectsConditionSpecificFollowupOrSequelae1yr = config$expectsConditionSpecificFollowupOrSequelae1yr,
    treatmentFollowUpOp = "any",
    evidenceThreshold = NULL,
    excludeA = FALSE,
    requiresHospitalization = FALSE,
    demographicCriteria = demographicCriteria,
    firstOccurrenceOnly = config$firstOccurrenceOnly,
    primaryCriteriaLimit = config$primaryCriteriaLimit,
    expressionLimit = config$expressionLimit,
    hospitalVisitOverlapWindow = config$hospitalVisitOverlapWindow,
    eraDays = exitConfig$eraDays,
    endStrategy = exitConfig$endStrategy
  )

  # Single-flag only cohorts
  flagNames <- c("hasDescreteRecordedSymptoms", "requiresDiagnosticTestOrProcedure",
                 "requiresActiveTreatmentWithin30d", "expectsConditionSpecificFollowupOrSequelae1yr")
  flagSuffix <- c("S_only", "D_only", "T_only", "FU_only")
  for (i in seq_along(flagNames)) {
    f <- flagNames[i]
    suffix <- flagSuffix[i]

    params <- list(
      hasDescreteRecordedSymptoms = FALSE,
      requiresDiagnosticTestOrProcedure = FALSE,
      requiresActiveTreatmentWithin30d = FALSE,
      expectsConditionSpecificFollowupOrSequelae1yr = FALSE
    )
    params[[f]] <- TRUE

    templates[[suffix]] <- do.call(
      outcomePhenotypeTpl,
      c(list(cs_I, cs_H, cs_S, cs_D, cs_T, cs_C, cs_A, cs_E),
        list(
          phenotypeLabel = phenotypeLabel,
          templateSuffix = suffix,
          useHypernymAsIndex = FALSE,
          treatmentFollowUpOp = "any",
          evidenceThreshold = NULL,
          excludeA = FALSE,
          requiresHospitalization = FALSE,
          demographicCriteria = demographicCriteria,
          firstOccurrenceOnly = firstOccurrenceOnly,
          primaryCriteriaLimit = primaryCriteriaLimit,
          expressionLimit = expressionLimit,
          hospitalVisitOverlapWindow = hospitalVisitOverlapWindow,
          eraDays = exitConfig$eraDays,
          endStrategy = exitConfig$endStrategy
        ),
        params
      )
    )
  }

  # Threshold cohorts: atLeast 1..4 (limited to number of available components)
  # Determine available components
  availableCount <- sum(
    as.integer(!is.null(cs_S) && config$hasDescreteRecordedSymptoms),
    as.integer(!is.null(cs_D) && config$requiresDiagnosticTestOrProcedure),
    as.integer(!is.null(cs_T) && config$requiresActiveTreatmentWithin30d),
    as.integer((!is.null(cs_C) || !is.null(cs_H) || !is.null(cs_I)) && config$expectsConditionSpecificFollowupOrSequelae1yr)
  )

  maxK <- min(4L, max(1L, availableCount))
  for (k in seq_len(maxK)) {
    suffix <- sprintf("atLeast_%d_of_4", k)
    templates[[suffix]] <- outcomePhenotypeTpl(
      cs_I, cs_H, cs_S, cs_D, cs_T, cs_C, cs_A, cs_E,
      phenotypeLabel = phenotypeLabel,
      templateSuffix = suffix,
      useHypernymAsIndex = FALSE,
      # keep booleans as they appear in config so components are constructed
      hasDescreteRecordedSymptoms = config$hasDescreteRecordedSymptoms,
      requiresDiagnosticTestOrProcedure = config$requiresDiagnosticTestOrProcedure,
      requiresActiveTreatmentWithin30d = config$requiresActiveTreatmentWithin30d,
      expectsConditionSpecificFollowupOrSequelae1yr = config$expectsConditionSpecificFollowupOrSequelae1yr,
      treatmentFollowUpOp = "any",
      evidenceThreshold = as.integer(k),
      excludeA = FALSE,
      requiresHospitalization = FALSE,
      demographicCriteria = demographicCriteria,
      firstOccurrenceOnly = firstOccurrenceOnly,
      primaryCriteriaLimit = primaryCriteriaLimit,
      expressionLimit = expressionLimit,
      hospitalVisitOverlapWindow = hospitalVisitOverlapWindow,
      eraDays = exitConfig$eraDays,
      endStrategy = exitConfig$endStrategy
    )
  }

  # Convert templates to cohort definition set
  message("Constructing evidence-combination cohort set")
  cohortId <- startCohortId
  cohortsToCreate <- data.frame()
  lapply(templates, function(tpl) {
    tryCatch(
      {
        cohortId <<- cohortId + 1
        print(attr(tpl, "cohortName"))
        convTpl <- tpl |> toCirce()
        names(convTpl$ConceptSets) <- NULL
        cohortsToCreate <<- cohortsToCreate |>
          rbind(
            data.frame(
              cohortId   = cohortId,
              cohortName = attr(tpl, "cohortName"),
              json = Capr::toCohortJson(tpl),
              sql = CirceR::buildCohortQuery(expression = Capr::toCohortJson(tpl), options = CirceR::createGenerateOptions(generateStats = FALSE))
            )
          )
      },
      error = function(msg) {
        print(msg)
        print(paste(cohortId, "failed to generate sql"))
      }
    )
  })

  cohortsToCreate
}
