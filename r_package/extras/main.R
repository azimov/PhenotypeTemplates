
# ============================================================
# REQUIRMENTS
# 1. ClinicalDefinitionsMetaData.csv - a csv file with the headings:
# source_phenotype,source_definition,condition_name,clinical_rationale,is_pharmacovigilance_outcome,clinical_course,expected_care_setting,sex_constraint,min_age_years,max_age_years,minimum_interepisode_gap_days,recommended_cohort_exit,recommended_exit_days,has_discrete_recorded_symptoms,requires_diagnostic_test_or_procedure,requires_active_treatment_within_30d,expects_condition_specific_followup_or_sequelae_1yr,confidence

# 2. Databricks tables:
# * scratch.scratch_all.phenotype_to_concept_set
# * scratch.scratch_all.concept_set_expression

# ============================================================
library(PhenotypeTemplates)

# ============================================================
# CONNECTION SETUP
# ============================================================

dbConfig <- yaml::read_yaml(path.expand("~/.config/ohdsi/databricks_connection.yml"))
password <- Sys.getenv("DATABRICKS_TOKEN")

if (is.null(password) || password == "")
  cli::cli_abort("DATABRICKS_TOKEN ENVIRONMENT VARIABLE NOT SET")

databricksConnectionString <- glue::glue("jdbc:databricks://{Sys.getenv('DATABRICKS_HOST')}/default;transportMode=http;ssl=1;AuthMech=3;httpPath={Sys.getenv('DATABRICKS_HTTP_PATH')}")
connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms = "spark",
  connectionString = databricksConnectionString,
  user = "token",
  password = password
)

cdmSettings <- dbConfig$cdms$optum_dod_v4020

cdmDatabaseSchema <- cdmSettings$cdm_schema
resultsDatabaseSchema <- cdmSettings$results_schema
cohortDatabaseSchema <- resultsDatabaseSchema

options(sqlRenderTempEmulationSchema = 'scratch.scratch_jgilber2')

# ============================================================
# LOAD METADATA
#
# condition_name is the join key to phenotype_to_concept_set.phenotype.
# There is currently no curated "selected phenotypes" list (unlike
# code_to_run_azza.R's SelectedPhenotypeS.txt) -- until one exists, every
# phenotype that has both metadata and stored concept sets is built.
# ============================================================

phenotypesToBuild <- c("Acute liver failure")

metadata <- read.csv(
  file.path("extras", "ClinicalDefinitionMetadata.csv"),
  stringsAsFactors = FALSE
) |> dplyr::filter(source_phenotype %in% phenotypesToBuild)

# ============================================================
# LOAD CONCEPT SETS FROM DATABASE
# ============================================================

conn <- DatabaseConnector::connect(connectionDetails)

phenotypeToConceptSet <- DatabaseConnector::querySql(
  connection = conn,
  sql = "SELECT * FROM scratch.scratch_all.phenotype_to_concept_set;",
  snakeCaseToCamelCase = TRUE
) |> dplyr::tibble()

conceptSetExpression <- DatabaseConnector::querySql(
  connection = conn,
  sql = "SELECT * FROM scratch.scratch_all.concept_set_expression;",
  snakeCaseToCamelCase = TRUE
) |> dplyr::tibble()

DatabaseConnector::disconnect(conn)

target_phenotypes <- intersect(
  tolower(unique(phenotypeToConceptSet$phenotype)),
  tolower(metadata$condition_name)
)

# ============================================================
# BUCKET CONCEPT SETS BY TEMPLATE CATEGORY (I/H/S/D/T/C/A/E)
# ============================================================

categoryToBucket <- c(
  "disease_of_interest"      = "I",
  "disease_of-interest"      = "I",
  "hypernym"                 = "H",
  "clinical_presentation"    = "S",
  "diagnostic_procedure"     = "D",
  "measurement"              = "D",
  "treatment_procedure"      = "T",
  "drug"                     = "T",
  "progression_complication" = "C",
  "alternative_diagnosis"    = "A",
  "etiology"                 = "E"
)

phenotypeToConceptSetBucketed <- phenotypeToConceptSet |>
  dplyr::filter(category != "risk_factor") |>
  dplyr::mutate(bucket = unname(categoryToBucket[category]))

# ============================================================
# BUILD phenotypeConfig() OBJECTS FROM METADATA
# (see extras/pharmacovigilance_configs.R for the original,
# pharmacovigilance-outcome-only version of these helpers)
# ============================================================

str_to_logical <- function(x) {
  if (is.na(x) || x == "" || tolower(x) == "null") return(FALSE)
  tolower(x) %in% c("true", "yes", "t", "y", "1")
}

str_to_numeric <- function(x) {
  if (is.na(x) || x == "" || tolower(x) == "null") return(NULL)
  tryCatch(as.numeric(x), warning = function(w) NULL, error = function(e) NULL)
}

parse_sex_constraint <- function(sex_str) {
  sex_str <- toupper(trimws(sex_str))
  list(male = sex_str == "MALE_ONLY", female = sex_str == "FEMALE_ONLY")
}

# Metadata vocabulary differs from phenotypeConfig()'s expected values.
clinicalCourseLookup <- c(
  "PERSISTENT_STABLE"    = "persistent_stable",
  "PERSISTENT_RELAPSING" = "persistent_transient",
  "TRANSIENT_RECURRENT"  = "transient_recurrent",
  "TRANSIENT_SINGLE"     = "transient_single"
)

expectedCareSettingLookup <- c(
  "ACUTE_CARE_COMMON"   = "acute_care_common",
  "ACUTE_CARE_EXPECTED" = "acute_care_expected",
  "OUTPATIENT_EXPECTED" = "outpatient_expected"
)

recommendedCohortExitLookup <- c(
  "END_OF_CONTINUOUS_OBSERVATION"   = "continuous_observation",
  "END_OF_ERA_WITH_PERSISTENCE_GAP" = "era_persistence",
  "FIXED_WINDOW_FROM_INDEX"         = "fixed_window"
)

buildConfigFromMetadataRow <- function(row) {
  sexConstraint <- parse_sex_constraint(row$sex_constraint)
  clinicalCourse <- unname(clinicalCourseLookup[toupper(trimws(row$clinical_course))])
  occurrenceSettings <- PhenotypeTemplates:::inferPhenotypeOccurrenceSettings(clinicalCourse)

  phenotypeConfig(
    clinicalCourse = clinicalCourse,
    expectedCareSetting = unname(expectedCareSettingLookup[toupper(trimws(row$expected_care_setting))]),
    minAge = str_to_numeric(row$min_age_years),
    maxAge = str_to_numeric(row$max_age_years),
    male = sexConstraint$male,
    female = sexConstraint$female,
    minimumInterepisodeDayGap = str_to_numeric(row$minimum_interepisode_gap_days),
    recommendedCohortExit = if (!is.na(row$recommended_cohort_exit) && row$recommended_cohort_exit != "")
      unname(recommendedCohortExitLookup[toupper(trimws(row$recommended_cohort_exit))]) else NULL,
    fixedExitDays = str_to_numeric(row$recommended_exit_days),
    hasDescreteRecordedSymptoms = str_to_logical(row$has_discrete_recorded_symptoms),
    requiresDiagnosticTestOrProcedure = str_to_logical(row$requires_diagnostic_test_or_procedure),
    requiresActiveTreatmentWithin30d = str_to_logical(row$requires_active_treatment_within_30d),
    expectsConditionSpecificFollowupOrSequelae1yr = str_to_logical(row$expects_condition_specific_followup_or_sequelae_1yr),
    firstOccurrenceOnly = occurrenceSettings$firstOccurrenceOnly,
    primaryCriteriaLimit = occurrenceSettings$primaryCriteriaLimit,
    expressionLimit = occurrenceSettings$expressionLimit,
    hospitalVisitOverlapWindow = occurrenceSettings$hospitalVisitOverlapWindow
  )
}

# ============================================================
# BUILD PHENOTYPE TEMPLATES FOR EVERY TARGET PHENOTYPE
#
# For each bucket, the concept set expressions stored for that phenotype
# are combined with unionConceptsets() (exclusion-aware) rather than the
# webApi-resolved, exclusion-blind path used in code_to_run_azza.R.
# ============================================================

phenotypeTemplates <- list()

for (phenotypeName in target_phenotypes) {

  metadataRow <- metadata[tolower(metadata$condition_name) == phenotypeName, ][1, ]

  phenotypeData <- phenotypeToConceptSetBucketed |>
    dplyr::filter(tolower(phenotype) == phenotypeName)

  bucketCs <- list()
  for (bucketName in unique(stats::na.omit(phenotypeData$bucket))) {

    conceptSetNames <- unique(phenotypeData$conceptSetName[phenotypeData$bucket == bucketName])

    bucketExpressions <- conceptSetExpression |>
      dplyr::filter(conceptSetName %in% conceptSetNames) |>
      dplyr::pull(conceptSetExpression)

    browser(expr = bucketName == "H")

    outputFolder <- tempdir()
    unionConceptsets(
      conceptsetName = paste(phenotypeName, bucketName),
      conceptSetExpressions = as.list(bucketExpressions),
      connectionDetails = connectionDetails,
      vocabularyDatabaseSchema = cdmDatabaseSchema,
      outputFolder = outputFolder
    )
    bucketCs[[bucketName]] <- Capr::readConceptSet(
      file.path(outputFolder, paste0(paste(phenotypeName, bucketName), ".json")),
      name = paste(phenotypeName, bucketName)
    )
  }

  print(paste("Building", phenotypeName))
  phenotypeTemplates[[phenotypeName]] <- buildPhenotypeTemplates(
    cs_I = bucketCs[["I"]],
    cs_H = bucketCs[["H"]],
    cs_S = bucketCs[["S"]],
    cs_D = bucketCs[["D"]],
    cs_T = bucketCs[["T"]],
    cs_C = bucketCs[["C"]],
    cs_A = bucketCs[["A"]],
    cs_E = bucketCs[["E"]],
    phenotypeLabel = phenotypeName,
    config = buildConfigFromMetadataRow(metadataRow)
  )
}

allTemplatesCds <- do.call(rbind, phenotypeTemplates)

unlink("inst", recursive = TRUE)
CohortGenerator::saveCohortDefinitionSet(allTemplatesCds)

# # Insert into atlas for review
# authWebApi("https://epi.jnj.com:8443/WebAPI")
# insertCohortsIntoAtlas(allTemplatesCds, "https://epi.jnj.com:8443/WebAPI")


# # ---- instantiate cohorts on Databricks using CohortGenerator ----------------
# #
# # Guarded with `if (FALSE)` so sourcing/running this script does not
# # automatically instantiate cohorts. To use: flip the guard and run.
# #
# # Requires the CohortGenerator package:
# #   remotes::install_github("OHDSI/CohortGenerator")

# library(CohortGenerator)
# library(yaml)

# # Load Databricks connection config
# dbConfig <- yaml::read_yaml(path.expand("~/.config/ohdsi/databricks_connection.yml"))
# dbConn <- dbConfig$databricks
# password <- Sys.getenv("DATABRICKS_TOKEN")

# if (is.null(password) || password == "")
#   cli::cli_abort("DATABRICKS_TOKEN ENVIRONMENT VARIABLE NOT SET")

# databricksConnectionString <- glue::glue("jdbc:databricks://{Sys.getenv('DATABRICKS_HOST')}/default;transportMode=http;ssl=1;AuthMech=3;httpPath={Sys.getenv('DATABRICKS_HTTP_PATH')}")
# # Create connection string for CohortGenerator with Databricks
# connectionDetails <- DatabaseConnector::createConnectionDetails(
#   dbms = "spark",
#   connectionString = databricksConnectionString,
#   user = "token",
#   password = password
# )

# cdmSettings <- dbConfig$cdms$optum_dod_v4020 

# # CDM and results schemas
# cdmDatabaseSchema <- cdmSettings$cdm_schema
# resultsDatabaseSchema <- cdmSettings$results_schema
# cohortDatabaseSchema <- resultsDatabaseSchema

# # Create the cohort table
# cat("Creating cohort tables in", cohortDatabaseSchema, "...\n")
# cohortTableNames <- CohortGenerator::getCohortTableNames(cohortTable = "pheval_tpls_alf")

# # Instantiate (generate) the cohorts
# cat("Instantiating", length(allTemplatesCds), "phenotype templates on Databricks...\n")
# CohortGenerator::runCohortGeneration(
#   connectionDetails,
#   cdmDatabaseSchema,
#   tempEmulationSchema = resultsDatabaseSchema,
#   cohortDatabaseSchema = resultsDatabaseSchema,
#   cohortTableNames = cohortTableNames,
#   cohortDefinitionSet = allTemplatesCds,
#   occurrenceType = "all",
#   detectOnDescendants = FALSE,
#   stopOnError = TRUE,
#   outputFolder = "results_alf_R",
#   databaseId = 1,
#   minCellCount = 5,
#   incremental = TRUE
# )
