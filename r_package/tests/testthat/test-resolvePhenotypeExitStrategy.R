test_that("persistent_stable defaults to continuous_observation with no era collapse", {
  res <- resolvePhenotypeExitStrategy("persistent_stable")

  expect_equal(res$eraDays, 0L)
  expect_s4_class(res$endStrategy, "ObservationExit")
})

test_that("persistent_transient requires minimumInterepisodeDayGap and uses era_persistence", {
  expect_error(resolvePhenotypeExitStrategy("persistent_transient"), "minimumInterepisodeDayGap")

  res <- resolvePhenotypeExitStrategy("persistent_transient", minimumInterepisodeDayGap = 90)
  expect_equal(res$eraDays, 90L)
  expect_s4_class(res$endStrategy, "ObservationExit")
})

test_that("transient_recurrent requires minimumInterepisodeDayGap and uses era_persistence", {
  expect_error(resolvePhenotypeExitStrategy("transient_recurrent"), "minimumInterepisodeDayGap")

  res <- resolvePhenotypeExitStrategy("transient_recurrent", minimumInterepisodeDayGap = 30)
  expect_equal(res$eraDays, 30L)
})

test_that("transient_single requires fixedExitDays and uses fixed_window", {
  expect_error(resolvePhenotypeExitStrategy("transient_single"), "fixedExitDays")

  res <- resolvePhenotypeExitStrategy("transient_single", fixedExitDays = 14)
  expect_equal(res$eraDays, 0L)
  expect_s4_class(res$endStrategy, "FixedDurationExit")
})

test_that("explicit recommendedCohortExit overrides the clinicalCourse default", {
  res <- resolvePhenotypeExitStrategy(
    "persistent_stable", recommendedCohortExit = "fixed_window", fixedExitDays = 7
  )
  expect_s4_class(res$endStrategy, "FixedDurationExit")
})

test_that("explicit minimumInterepisodeDayGap overrides even for continuous_observation", {
  res <- resolvePhenotypeExitStrategy("persistent_stable", minimumInterepisodeDayGap = 5)
  expect_equal(res$eraDays, 5L)
})

test_that("NA minimumInterepisodeDayGap is treated as missing for continuous_observation", {
  res <- resolvePhenotypeExitStrategy("persistent_stable", minimumInterepisodeDayGap = NA)
  expect_equal(res$eraDays, 0L)
  expect_s4_class(res$endStrategy, "ObservationExit")
})

test_that("NA minimumInterepisodeDayGap still errors for era_persistence", {
  expect_error(
    resolvePhenotypeExitStrategy("transient_recurrent", minimumInterepisodeDayGap = NA),
    "minimumInterepisodeDayGap"
  )
})

test_that("NA fixedExitDays still errors for fixed_window", {
  expect_error(
    resolvePhenotypeExitStrategy("transient_single", fixedExitDays = NA),
    "fixedExitDays"
  )
})
