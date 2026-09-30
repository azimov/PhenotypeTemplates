test_that("acute_care_expected returns only TRUE", {
  expect_equal(resolveHospitalizationVariants("acute_care_expected"), TRUE)
})

test_that("acute_care_common returns both TRUE and FALSE", {
  expect_equal(resolveHospitalizationVariants("acute_care_common"), c(TRUE, FALSE))
})

test_that("outpatient_expected returns only FALSE", {
  expect_equal(resolveHospitalizationVariants("outpatient_expected"), FALSE)
})

test_that("an invalid care setting errors", {
  expect_error(resolveHospitalizationVariants("bogus_setting"))
})
