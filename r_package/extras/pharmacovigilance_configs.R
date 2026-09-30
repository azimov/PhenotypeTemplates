#' Pharmacovigilance Outcome Configurations
#'
#' This file generates phenotypeConfig() objects for all clinical definitions
#' marked as pharmacovigilance outcomes (is_pharmacovigilance_outcome == "YES")
#' from ClinicalDefinitionMetadata.csv
#'
#' @details
#' Configurations are dynamically generated from the metadata CSV to ensure
#' consistency between clinical definitions and phenotype template parameters.
library(PhenotypeTemplates)
# Read metadata file
metadata_path <- "inst/setttings/ClinicalDefinitionMetadata.csv"
metadata <- read.csv(metadata_path, stringsAsFactors = FALSE)

# Filter to YES outcomes only
pv_outcomes <- metadata[tolower(metadata$is_pharmacovigilance_outcome) == "yes", ]

# Helper function: convert CSV string to logical
str_to_logical <- function(x) {
  if (is.na(x) || x == "" || tolower(x) == "null") return(FALSE)
  tolower(x) %in% c("true", "yes", "t", "y", "1")
}

# Helper function: convert CSV numeric (allowing NULL/"")
str_to_numeric <- function(x) {
  if (is.na(x) || x == "" || tolower(x) == "null") return(NULL)
  tryCatch(as.numeric(x), warning = function(w) NULL, error = function(e) NULL)
}

# Helper function: normalize sex constraint
parse_sex_constraint <- function(sex_str) {
  sex_str <- toupper(trimws(sex_str))
  list(
    male = sex_str == "MALE_ONLY",
    female = sex_str == "FEMALE_ONLY"
  )
}

# Helper function: normalize clinical course
normalize_clinical_course <- function(course_str) {
  course_str <- tolower(trimws(course_str))
  # Map to standard format
  switch(course_str,
    "persistent_stable" = "persistent_stable",
    "persistent_transient" = "persistent_transient",
    "transient_recurrent" = "transient_recurrent",
    "transient_single" = "transient_single",
    course_str  # default: return as-is
  )
}

# Helper function: normalize expected care setting
normalize_care_setting <- function(setting_str) {
  setting_str <- tolower(trimws(setting_str))
  switch(setting_str,
    "acute_care_expected" = "acute_care_expected",
    "acute_care_common" = "acute_care_common",
    "outpatient_expected" = "outpatient_expected",
    setting_str  # default: return as-is
  )
}

# Generate config objects
pv_configs <- list()

for (i in seq_len(nrow(pv_outcomes))) {
  row <- pv_outcomes[i, ]
  
  condition_name <- trimws(row$condition_name)
  config_name <- tolower(gsub(" ", "_", gsub("[^a-zA-Z0-9 ]", "", condition_name)))
  
  sex_constraint <- parse_sex_constraint(row$sex_constraint)
  
  # Create config
  config <- phenotypeConfig(
    clinicalCourse = normalize_clinical_course(row$clinical_course),
    expectedCareSetting = normalize_care_setting(row$expected_care_setting),
    minAge = str_to_numeric(row$min_age_years),
    maxAge = str_to_numeric(row$max_age_years),
    male = sex_constraint$male,
    female = sex_constraint$female,
    minimumInterepisodeDayGap = str_to_numeric(row$minimum_interepisode_gap_days),
    recommendedCohortExit = if (!is.na(row$recommended_cohort_exit) && row$recommended_cohort_exit != "") 
                              trimws(row$recommended_cohort_exit) else NULL,
    fixedExitDays = str_to_numeric(row$recommended_exit_days),
    hasDescreteRecordedSymptoms = str_to_logical(row$has_discrete_recorded_symptoms),
    requiresDiagnosticTestOrProcedure = str_to_logical(row$requires_diagnostic_test_or_procedure),
    requiresActiveTreatmentWithin30d = str_to_logical(row$requires_active_treatment_within_30d),
    expectsConditionSpecificFollowupOrSequelae1yr = str_to_logical(row$expects_condition_specific_followup_or_sequelae_1yr)
  )
  
  pv_configs[[config_name]] <- config
  
  cat(sprintf("✓ %s: %s | %s | %s\n",
              config_name, 
              row$clinical_course,
              row$expected_care_setting,
              row$confidence))
}

cat(sprintf("\n✅ Generated %d pharmacovigilance outcome configurations\n", length(pv_configs)))

# Export a named list of all configs for reference
# Usage: config <- pv_configs$acute_liver_failure
pv_configs
