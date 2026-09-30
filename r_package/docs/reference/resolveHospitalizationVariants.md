# Resolve which requiresHospitalization variants to emit for a care setting

Resolve which requiresHospitalization variants to emit for a care
setting

## Usage

``` r
resolveHospitalizationVariants(expectedCareSetting)
```

## Arguments

- expectedCareSetting:

  One of \`"acute_care_expected"\`, \`"acute_care_common"\`,
  \`"outpatient_expected"\`.

## Value

A logical vector of \`requiresHospitalization\` values to cross (length
1 for expected/outpatient, length 2 for common).
