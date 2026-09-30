# Metadata lookup & vocabulary translation helpers ------------------------------

#' Clinical course vocabulary translation
#' @noRd
clinicalCourseLookup <- c(
  "PERSISTENT_STABLE"    = "persistent_stable",
  "PERSISTENT_RELAPSING" = "persistent_transient",
  "TRANSIENT_RECURRENT"  = "transient_recurrent",
  "TRANSIENT_SINGLE"     = "transient_single"
)

#' Expected care setting vocabulary translation
#' @noRd
expectedCareSettingLookup <- c(
  "ACUTE_CARE_COMMON"   = "acute_care_common",
  "ACUTE_CARE_EXPECTED" = "acute_care_expected",
  "OUTPATIENT_EXPECTED" = "outpatient_expected"
)

#' Recommended cohort exit vocabulary translation
#' @noRd
recommendedCohortExitLookup <- c(
  "END_OF_CONTINUOUS_OBSERVATION"   = "continuous_observation",
  "END_OF_ERA_WITH_PERSISTENCE_GAP" = "era_persistence",
  "FIXED_WINDOW_FROM_INDEX"         = "fixed_window"
)

#' Infer occurrence/limit settings from a normalized clinical course
#'
#' Maps a normalized `clinicalCourse` (see `phenotypeConfig()`) to the
#' `firstOccurrenceOnly`/`primaryCriteriaLimit`/`expressionLimit`/`hospitalVisitOverlapWindow`
#' settings. These are not stored directly in the clinical definition metadata,
#' so they are derived from the clinical course vocabulary.
#'
#' @param clinicalCourse One of `"persistent_stable"`, `"persistent_transient"`,
#'   `"transient_recurrent"`, `"transient_single"`.
#' @return A list with the four occurrence/limit settings.
#' @noRd
inferPhenotypeOccurrenceSettings <- function(clinicalCourse) {
  setting <- switch(
    clinicalCourse,
    persistent_stable = list(
      firstOccurrenceOnly = TRUE, primaryCriteriaLimit = "First", expressionLimit = "First"
    ),
    persistent_transient = list(
      firstOccurrenceOnly = FALSE, primaryCriteriaLimit = "All", expressionLimit = "First"
    ),
    transient_recurrent = list(
      firstOccurrenceOnly = FALSE, primaryCriteriaLimit = "All", expressionLimit = "All"
    ),
    transient_single = list(
      firstOccurrenceOnly = TRUE, primaryCriteriaLimit = "First", expressionLimit = "First"
    ),
    stop(sprintf("Unknown clinical course: %s", clinicalCourse), call. = FALSE)
  )

  c(setting, list(hospitalVisitOverlapWindow = 99999))
}

#' Look up a single phenotype's row in a clinical definition metadata table
#'
#' Applies `nameOverrides` (metadata condition names that differ from the
#' phenotype's canonical name) before matching, and fails loudly with a
#' clear message if zero or more than one row match — instead of silently
#' returning zero rows that only surface later as a cryptic
#' `match.arg()` error inside `phenotypeConfig()`.
#'
#' @param phenotypeName Canonical phenotype name to look up.
#' @param metadata Metadata data.frame containing `conditionNameCol`.
#' @param nameOverrides Named character vector mapping a canonical phenotype
#'   name to the (possibly different) name used in `metadata`. Optional.
#' @param conditionNameCol Column in `metadata` holding the condition name.
#'   Default `"condition_name"`.
#' @return A single-row data.frame from `metadata`.
#' @export
getMetadataRow <- function(phenotypeName, metadata, nameOverrides = NULL,
                           conditionNameCol = "condition_name") {
  metadataName <- if (!is.null(nameOverrides) && phenotypeName %in% names(nameOverrides)) {
    unname(nameOverrides[phenotypeName])
  } else {
    phenotypeName
  }

  matches <- tolower(metadata[[conditionNameCol]]) == tolower(metadataName)
  row <- metadata[matches, , drop = FALSE]

  if (nrow(row) == 0L) {
    stop(sprintf(
      "getMetadataRow: no metadata row found for phenotype '%s' (looked up as '%s')",
      phenotypeName, metadataName
    ), call. = FALSE)
  }
  if (nrow(row) > 1L) {
    stop(sprintf(
      "getMetadataRow: %d metadata rows found for phenotype '%s' (looked up as '%s'), expected exactly 1",
      nrow(row), phenotypeName, metadataName
    ), call. = FALSE)
  }

  row
}

#' Translate a clinical definition metadata row into a phenotypeConfig() call
#'
#' Applies the `clinicalCourseLookup`/`expectedCareSettingLookup`/
#' `recommendedCohortExitLookup` vocabulary translations and forwards the
#' remaining columns to `phenotypeConfig()`.
#'
#' @param metadataRow Single-row data.frame as returned by `getMetadataRow()`.
#' @return A phenotype config list, see `phenotypeConfig()`.
#' @export
translateMetadataConfig <- function(metadataRow) {
  clinicalCourse <- unname(clinicalCourseLookup[metadataRow$clinical_course])
  expectedCareSetting <- unname(expectedCareSettingLookup[metadataRow$expected_care_setting])
  occurrenceSettings <- inferPhenotypeOccurrenceSettings(clinicalCourse)

  phenotypeConfig(
    clinicalCourse = clinicalCourse,
    expectedCareSetting = expectedCareSetting,
    minAge = metadataRow$min_age_years,
    maxAge = metadataRow$max_age_years,
    minimumInterepisodeDayGap = metadataRow$minimum_interepisode_gap_days,
    recommendedCohortExit = unname(recommendedCohortExitLookup[metadataRow$recommended_cohort_exit]),
    fixedExitDays = metadataRow$recommended_exit_days,
    hasDescreteRecordedSymptoms = metadataRow$has_discrete_recorded_symptoms,
    requiresDiagnosticTestOrProcedure = metadataRow$requires_diagnostic_test_or_procedure,
    requiresActiveTreatmentWithin30d = metadataRow$requires_active_treatment_within_30d,
    expectsConditionSpecificFollowupOrSequelae1yr =
      metadataRow$expects_condition_specific_followup_or_sequelae_1yr,
    firstOccurrenceOnly = occurrenceSettings$firstOccurrenceOnly,
    primaryCriteriaLimit = occurrenceSettings$primaryCriteriaLimit,
    expressionLimit = occurrenceSettings$expressionLimit,
    hospitalVisitOverlapWindow = occurrenceSettings$hospitalVisitOverlapWindow
  )
}
