#setwd("C:/Users/AShoaibi/Documents/GitHub/phenotype_templating")
# ============================================================
# PROJECT INITIALIZATION
# ============================================================

# Activate project environment
if (requireNamespace("renv", quietly = TRUE)) {
  renv::activate()
}

# Java required for rJava / CirceR
Sys.setenv(
  JAVA_HOME = dirname(dirname(Sys.which("java")))
)
# ============================================================
# JAVA SETUP REQUIRED FOR rJava AND CirceR
# Run after renv activation or any R-session restart
# ============================================================

java_home <- dirname(dirname(Sys.which("java")))

if (!nzchar(java_home) || !file.exists(
  file.path(java_home, "bin", "server", "jvm.dll")
)) {
  stop("A valid Java JDK installation was not found.")
}

Sys.setenv(JAVA_HOME = java_home)

library(rJava)
library(CirceR)

# Load Java stack first
library(rJava)
library(CirceR)

# Load phenotype packages
library(Capr)
library(ROhdsiWebApi)
library(PhenotypeTemplates)
# ======================================================================================
# get inputs 1. txt of the selected 14 phenotype names( created a text file from BB)
# metadara (downladed)
# ======================================================================================
target_phenotypes <- readLines(
  "C:/Users/AShoaibi/Downloads/SelectedPhenotypeS.txt"
)

metadata <- read.csv(
  "C:/Users/AShoaibi/Downloads/ClinicalDefinitionMetadata.csv",
  stringsAsFactors = FALSE
)

# ============================================================
# PHENOTYPE NAME OVERRIDES
#
# Used only when the target phenotype name differs from the
# metadata naming convention.
# ============================================================

phenotype_name_overrides <- c(
  "Pulmonary arterial hypertension" =
    "Pulmonary arterial hypertension (idiopathic/heritable forms only)"
)
target_phenotypes_metadata <- ifelse(
  target_phenotypes %in% names(phenotype_name_overrides),
  phenotype_name_overrides[target_phenotypes],
  target_phenotypes
)
target_metadata <- metadata[
  tolower(metadata$condition_name) %in%
    tolower(target_phenotypes_metadata),
]
missing_metadata <- setdiff(
  tolower(target_phenotypes_metadata),
  tolower(target_metadata$condition_name)
)

missing_metadata

# ======================================================================================
# get inputs 3. concept set from Databricks
# ======================================================================================

library(DatabaseConnector)

connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms = "spark",
  user = "token",
  password = Sys.getenv("DATABRICKS_TOKEN"),
  connectionString = paste(
    "jdbc:databricks://",
    Sys.getenv("DATABRICKS_HOST"),
    ":443/default;transportMode=http;ssl=1;AuthMech=3;httpPath=",
    Sys.getenv("DATABRICKS_HTTP_PATH"),
    ";EnableArrow=0;",
    sep = ""
  )
)

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

#inspect one phenotype
alfConcepts <- phenotypeToConceptSet |>
  dplyr::filter(
    phenotype == "Acute liver failure"
  )

dplyr::count(
  alfConcepts,
  category,
  sort = TRUE
)
# ======================================================================================
# creating the config from the meta data for one phenotype as a test 
# ======================================================================================
getPhenotypeConfig <- function(phenotypeName, metadata) {
  
  row <- metadata |>
    dplyr::filter(
      tolower(condition_name) == tolower(phenotypeName)
    )
  
  row
}
getPhenotypeConfig(
  "Acute liver failure",
  target_metadata
)
phenotypeConfigs <- lapply(
  target_phenotypes,
  function(p) {
    target_metadata |>
      dplyr::filter(
        tolower(condition_name) == tolower(p)
      )
  }
)

names(phenotypeConfigs) <- target_phenotypes
phenotypeConfigs[["Acute liver failure"]]
phenotypeConfigs[["Crohn's disease"]]
phenotypeConfigs[["Confusion"]]
# ============================================================
# BUILD PHENOTYPE CONFIGURATION OBJECTS
#
# PURPOSE:
# Create phenotypeConfig() objects for all target phenotypes
# using the phenotype metadata table as the source of truth.
#
# IMPORTANT:
# Metadata vocabulary is used directly (e.g. TRANSIENT_SINGLE,
# TRANSIENT_RECURRENT, ACUTE_CARE_COMMON, etc.).
#
# No translation to legacy proof-of-concept values is performed.
#
# INPUTS:
#   target_phenotypes
#   target_metadata
#
# OUTPUT:
#   phenotypeConfigs
#     Named list of phenotypeConfig() objects indexed by
#     phenotype name.
# ============================================================
# ============================================================
# BUILD PHENOTYPE CONFIGURATION OBJECTS
#
# IMPORTANT:
# Metadata is the source of truth.
#
# buildPhenotypeTemplates() currently expects legacy
# clinical course terminology, therefore a temporary
# translation layer is required.
# ============================================================
clinicalCourseLookup <- c(
  "PERSISTENT_STABLE"    = "persistent_stable",
  "PERSISTENT_RELAPSING" = "persistent_transient",
  "TRANSIENT_RECURRENT"  = "transient_recurrent",
  "TRANSIENT_SINGLE"     = "transient_single"
)

expectedCareSettingLookup <- c(
  "ACUTE_CARE_COMMON"    = "acute_care_common",
  "ACUTE_CARE_EXPECTED"  = "acute_care_expected",
  "OUTPATIENT_EXPECTED"  = "outpatient_expected"
)

recommendedCohortExitLookup <- c(
  "END_OF_CONTINUOUS_OBSERVATION"   = "continuous_observation",
  "END_OF_ERA_WITH_PERSISTENCE_GAP" = "era_persistence",
  "FIXED_WINDOW_FROM_INDEX"         = "fixed_window"
)

phenotypeConfigs <- list()

for (phenotypeName in target_phenotypes) {
  
  metadataPhenotypeName <- ifelse(
    phenotypeName %in% names(phenotype_name_overrides),
    phenotype_name_overrides[phenotypeName],
    phenotypeName
  )
  
  metadataRow <- target_metadata |>
    dplyr::filter(
      tolower(condition_name) ==
        tolower(metadataPhenotypeName)
    )
  
  phenotypeConfigs[[phenotypeName]] <- phenotypeConfig(
    
    clinicalCourse =
      unname(
        clinicalCourseLookup[
          metadataRow$clinical_course
        ]
      ),
    
    expectedCareSetting =
      unname(
        expectedCareSettingLookup[
          metadataRow$expected_care_setting
        ]
      ),
    
    minAge =
      metadataRow$min_age_years,
    
    maxAge =
      metadataRow$max_age_years,
    
    minimumInterepisodeDayGap =
      metadataRow$minimum_interepisode_gap_days,
    
    recommendedCohortExit =
      unname(
        recommendedCohortExitLookup[
          metadataRow$recommended_cohort_exit
        ]
      ),
    
    fixedExitDays =
      metadataRow$recommended_exit_days,
    
    hasDescreteRecordedSymptoms =
      metadataRow$has_discrete_recorded_symptoms,
    
    requiresDiagnosticTestOrProcedure =
      metadataRow$requires_diagnostic_test_or_procedure,
    
    requiresActiveTreatmentWithin30d =
      metadataRow$requires_active_treatment_within_30d,
    
    expectsConditionSpecificFollowupOrSequelae1yr =
      metadataRow$expects_condition_specific_followup_or_sequelae_1yr
  )
}
# ============================================================
# QC: Verify all phenotype configs were created
# ============================================================

length(phenotypeConfigs)

unique(
  unlist(
    lapply(
      phenotypeConfigs,
      function(x) x$recommendedCohortExit
    )
  )
)

phenotypeConfigs[["Acute liver failure"]]
# ============================================================
# BUILD PHENOTYPE-BUCKET CONCEPT SET COLLECTIONS
#
# PURPOSE:
# Create phenotype-specific concept set collections grouped
# by template bucket (I/H/S/D/T/C/A/E).
#
# Metadata remains the source of truth for configuration.
#
# Bucketed concept sets will be used to:
#   1. Retrieve Atlas concept set expressions
#   2. Resolve concept sets through WebAPI
#   3. Build exact Capr concept sets
#   4. Generate phenotype templates
#
# INPUT:
#   targetConceptSetDataBucketed
#
# OUTPUT:
#   phenotypeBucketConceptSets
#
# STRUCTURE:
#   phenotypeBucketConceptSets[[phenotype]][[bucket]]
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

targetConceptSetDataBucketed <- targetConceptSetData |>
  dplyr::filter(category != "risk_factor") |>
  dplyr::mutate(
    bucket = unname(categoryToBucket[category])
  )


phenotypeBucketConceptSets <- list()

for (phenotypeName in target_phenotypes) {
  
  phenotypeData <- targetConceptSetDataBucketed |>
    dplyr::filter(
      tolower(phenotype) ==
        tolower(phenotypeName)
    )
  
  phenotypeBucketConceptSets[[phenotypeName]] <-
    split(
      x = phenotypeData$conceptSetName,
      f = phenotypeData$bucket
    ) |>
    lapply(unique)
}

# ============================================================
# QC: VERIFY BUCKET STRUCTURE
# ============================================================

names(
  phenotypeBucketConceptSets[["Acute liver failure"]]
)

length(
  phenotypeBucketConceptSets[["Acute liver failure"]][["I"]]
)
# ============================================================
# RETRIEVE CONCEPT SET EXPRESSIONS FOR PHENOTYPE BUCKETS
#
# PURPOSE:
# Retrieve Atlas concept set expressions for all concept sets
# assigned to phenotype template buckets.
#
# Metadata remains the source of truth for phenotype
# configuration.
#
# Concept Set Data remains the source of truth for bucket
# assignment.
#
# INPUTS:
#   phenotypeBucketConceptSets
#   conceptSetExpression
#
# OUTPUT:
#   phenotypeBucketExpressions
#
# STRUCTURE:
#   phenotypeBucketExpressions[[phenotype]][[bucket]]
#
# Each bucket contains the concept set expression records
# required for WebAPI concept resolution.
# ============================================================
phenotypeBucketExpressions <- list()

for (phenotypeName in names(phenotypeBucketConceptSets)) {
  
  phenotypeBucketExpressions[[phenotypeName]] <- list()
  
  for (
    bucketName in names(
      phenotypeBucketConceptSets[[phenotypeName]]
    )
  ) {
    
    bucketConceptSets <-
      phenotypeBucketConceptSets[[phenotypeName]][[bucketName]]
    
    phenotypeBucketExpressions[[phenotypeName]][[bucketName]] <-
      conceptSetExpression |>
      dplyr::filter(
        conceptSetName %in% bucketConceptSets
      )
  }
}
names(
  phenotypeBucketExpressions[["Acute liver failure"]]
)
nrow(
  phenotypeBucketExpressions[["Acute liver failure"]][["I"]]
)
# ============================================================
# RESOLVE PHENOTYPE BUCKET CONCEPT SETS THROUGH WEBAPI
# ============================================================
# ============================================================
# RESOLVE PHENOTYPE BUCKET CONCEPT SETS THROUGH WEBAPI
#
# PURPOSE:
# Resolve Atlas concept set expressions through WebAPI and
# return explicit concept membership for every phenotype
# bucket.
#
# Metadata remains the source of truth for configuration.
#
# Concept Set Data remains the source of truth for bucket
# assignment.
#
# INPUT:
#   phenotypeBucketExpressions
#   webApiUrl
#   vocabularySourceKey
#
# OUTPUT:
#   phenotypeBucketResolved
#
# STRUCTURE:
#   phenotypeBucketResolved[[phenotype]][[bucket]]
#
# Each bucket contains all resolved concepts required to build
# exact Capr concept sets.
# ============================================================

# ============================================================
# AUTHENTICATE TO WEBAPI
# ============================================================

webApiUrl <- "https://epi.jnj.com:8443/WebAPI"
vocabularySourceKey <- "v20260829"

ROhdsiWebApi::authorizeWebApi(
  baseUrl = webApiUrl,
  authMethod = "windows"
)
# ============================================================
# CONVERT BUCKET EXPRESSIONS TO ATLAS OBJECTS
#
# PURPOSE:
# Convert Atlas JSON concept set expressions into WebAPI-
# compatible Atlas objects prior to concept resolution.
#
# IMPORTANT:
# jsonlite::fromJSON() converts nested Atlas objects into
# data.frame structures.
#
# ROhdsiWebApi::resolveConceptSet() requires Atlas-style
# nested list objects.
#
# This conversion step was previously validated in the ALF
# proof-of-concept workflow.
# ============================================================
convertToAtlasExpression <- function(cs) {
  
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
phenotypeBucketAtlasObjects <- list()

for (phenotypeName in names(phenotypeBucketExpressions)) {
  
  phenotypeBucketAtlasObjects[[phenotypeName]] <- list()
  
  for (bucketName in names(
    phenotypeBucketExpressions[[phenotypeName]]
  )) {
    
    bucketExpressions <-
      phenotypeBucketExpressions[[phenotypeName]][[bucketName]]
    
    phenotypeBucketAtlasObjects[[phenotypeName]][[bucketName]] <-
      lapply(
        bucketExpressions$conceptSetExpression,
        function(x) {
          
          jsonlite::fromJSON(x) |>
            convertToAtlasExpression()
          
        }
      )
  }
}
resolveConceptSetList <- function(
    conceptSetList,
    webApiUrl,
    vocabularySourceKey = "v20260829"
) {
  
  lapply(
    conceptSetList,
    ROhdsiWebApi::resolveConceptSet,
    baseUrl = webApiUrl,
    vocabularySourceKey = vocabularySourceKey
  )
}

# ============================================================
# RESOLVE PHENOTYPE BUCKET CONCEPT SETS
#
# PURPOSE:
# Resolve Atlas concept set expressions through WebAPI and
# obtain explicit concept membership for every phenotype
# bucket.
#
# IMPORTANT:
# Atlas JSON expressions must first be converted into
# WebAPI-compatible Atlas objects using
# convertToAtlasExpression().
#
# This workflow was validated in the original ALF
# proof-of-concept and is reused unchanged.
#
# INPUT:
#   phenotypeBucketAtlasObjects
#   webApiUrl
#   vocabularySourceKey
#
# OUTPUT:
#   phenotypeBucketResolved
#
# STRUCTURE:
#   phenotypeBucketResolved[[phenotype]][[bucket]]
# ============================================================
phenotypeBucketResolved <- list()

for (phenotypeName in names(phenotypeBucketAtlasObjects)) {
  
  phenotypeBucketResolved[[phenotypeName]] <- list()
  
  for (
    bucketName in names(
      phenotypeBucketAtlasObjects[[phenotypeName]]
    )
  ) {
    
    phenotypeBucketResolved[[phenotypeName]][[bucketName]] <-
      resolveConceptSetList(
        conceptSetList =
          phenotypeBucketAtlasObjects[[phenotypeName]][[bucketName]],
        webApiUrl = webApiUrl,
        vocabularySourceKey = vocabularySourceKey
      )
  }
}
saveRDS(
  phenotypeBucketResolved,
  "phenotypeBucketResolved.rds"
)
# ============================================================
# COLLAPSE RESOLVED CONCEPT SETS TO BUCKET-LEVEL CONCEPT LISTS
# ============================================================
# ============================================================
# COLLAPSE RESOLVED CONCEPT SETS TO BUCKET-LEVEL CONCEPT LISTS
#
# PURPOSE:
# Collapse resolved concept sets into unique bucket-level
# concept lists for each phenotype.
#
# This mirrors the validated ALF workflow:
#
# resolved_I -> cs_I
# resolved_H -> cs_H
# resolved_S -> cs_S
# ...
#
# but is applied to all phenotypes.
#
# INPUT:
#   phenotypeBucketResolved
#
# OUTPUT:
#   phenotypeBucketConceptIds
#
# STRUCTURE:
#   phenotypeBucketConceptIds[[phenotype]][[bucket]]
# ============================================================
phenotypeBucketConceptIds <- list()

for (phenotypeName in names(phenotypeBucketResolved)) {
  
  phenotypeBucketConceptIds[[phenotypeName]] <- list()
  
  for (
    bucketName in names(
      phenotypeBucketResolved[[phenotypeName]]
    )
  ) {
    
    phenotypeBucketConceptIds[[phenotypeName]][[bucketName]] <-
      unique(
        unlist(
          phenotypeBucketResolved[[phenotypeName]][[bucketName]]
        )
      )
  }
}
# ============================================================
# CONVERT RESOLVED BUCKET CONCEPTS TO EXACT CAPR CONCEPT SETS
#
# PURPOSE:
# Build exact Capr ConceptSets from WebAPI-resolved concept
# IDs.
#
# IMPORTANT:
# WebAPI has already performed descendant expansion.
#
# Therefore Capr concept sets must be constructed using the
# exact resolved concepts only.
#
# Descendants must NOT be expanded again.
#
# INPUT:
#   phenotypeBucketConceptIds
#
# OUTPUT:
#   phenotypeBucketCaprConceptSets
#
# STRUCTURE:
#   phenotypeBucketCaprConceptSets[[phenotype]][[bucket]]
# ============================================================
makeExactCaprConceptSet <- function(conceptIds, name) {
  
  items <- lapply(
    unique(as.integer(conceptIds)),
    function(id) {
      
      Capr::cs(
        id,
        name = paste0(name, "_tmp")
      )@Expression[[1]]
      
    }
  )
  
  do.call(
    Capr::cs,
    c(
      unname(items),
      list(name = name)
    )
  )
}
phenotypeBucketCaprConceptSets <- list()

for (phenotypeName in names(phenotypeBucketConceptIds)) {
  
  phenotypeBucketCaprConceptSets[[phenotypeName]] <- list()
  
  for (
    bucketName in names(
      phenotypeBucketConceptIds[[phenotypeName]]
    )
  ) {
    
    phenotypeBucketCaprConceptSets[[phenotypeName]][[bucketName]] <-
      makeExactCaprConceptSet(
        conceptIds =
          phenotypeBucketConceptIds[[phenotypeName]][[bucketName]],
        name =
          paste0(
            gsub("[^A-Za-z0-9]", "_", phenotypeName),
            "_",
            bucketName
          )
      )
  }
}
saveRDS(
  phenotypeBucketCaprConceptSets,
  "phenotypeBucketCaprConceptSets.rds"
)
# ============================================================
# GENERATE PHENOTYPE TEMPLATES
#
# PURPOSE:
# Generate phenotype templates using metadata-derived
# configuration objects and exact Capr concept sets.
#
# Metadata remains the source of truth for phenotype
# configuration.
#
# Resolved concept IDs remain the source of truth for
# phenotype concept membership.
#
# INPUTS:
#   phenotypeConfigs
#   phenotypeBucketCaprConceptSets
#
# OUTPUT:
#   phenotypeTemplates
# ============================================================

# extra steps to fix the issue with gap era
phenotypeConfigs[["Multiple myeloma"]]$minimumInterepisodeDayGap <- 0

phenotypeConfigs[["Pulmonary arterial hypertension"]]$minimumInterepisodeDayGap <- 0

#________________________________________________________________________________
phenotypeTemplates <- list()

for (phenotypeName in target_phenotypes) {
  
  bucketSets <-
    phenotypeBucketCaprConceptSets[[phenotypeName]]
  
  phenotypeTemplates[[phenotypeName]] <-
    PhenotypeTemplates::buildPhenotypeTemplates(
      cs_I = bucketSets[["I"]],
      cs_H = bucketSets[["H"]],
      cs_S = bucketSets[["S"]],
      cs_D = bucketSets[["D"]],
      cs_T = bucketSets[["T"]],
      cs_C = bucketSets[["C"]],
      cs_A = bucketSets[["A"]],
      cs_E = bucketSets[["E"]],
      phenotypeLabel = phenotypeName,
      config = phenotypeConfigs[[phenotypeName]]
    )
}
#save templates:
saveRDS(
  phenotypeTemplates,
  "phenotypeTemplates_20260920.rds"
)
#combine the successful phenotype data frames into a single cohort list
cohortList <- do.call(
  rbind,
  phenotypeTemplates[
    sapply(phenotypeTemplates, nrow) > 0
  ]
)
#publsih in Atlas
PhenotypeTemplates::insertCohortsIntoAtlas(
  cohortList = cohortList,
  baseUrl = webApiUrl
)

