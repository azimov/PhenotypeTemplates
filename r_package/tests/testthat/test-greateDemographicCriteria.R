test_that("maxAge produces Capr::lte(maxAge), not minAge (regression test)", {
  demography <- greateDemographicCriteria(minAge = 18, maxAge = 65)

  expect_length(demography, 2)
  # the age(lte(...)) criterion must be built from maxAge, not minAge
  ageUpper <- demography[[2]]
  expect_equal(ageUpper@op, "lte")
  expect_equal(ageUpper@value, 65)
})

test_that("minAge alone produces a single gte criterion", {
  demography <- greateDemographicCriteria(minAge = 40)

  expect_length(demography, 1)
  expect_equal(demography[[1]]@op, "gte")
  expect_equal(demography[[1]]@value, 40)
})

test_that("male/female flags add gender criteria", {
  demography <- greateDemographicCriteria(male = TRUE, female = TRUE)

  expect_length(demography, 2)
})

test_that("no arguments produces an empty list", {
  demography <- greateDemographicCriteria()

  expect_length(demography, 0)
})
