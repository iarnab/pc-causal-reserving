test_that("detect_ata_zscore flags a known outlier", {
  set.seed(42)
  # Construct ATA data where AY 1995 has an extreme outlier at lag 1->2
  ata_df <- data.frame(
    lob           = "WC",
    accident_year = 1988:1997,
    from_lag      = 1L,
    to_lag        = 2L,
    ata_paid      = c(1.5, 1.5, 1.5, 1.5, 1.5, 1.5, 1.5, 5.5, 1.5, 1.5),  # AY 1995 = outlier
    ata_incurred  = c(1.4, 1.4, 1.4, 1.4, 1.4, 1.4, 1.4, 5.0, 1.4, 1.4),
    stringsAsFactors = FALSE
  )
  flags <- detect_ata_zscore(ata_df, z_threshold = 2.5)
  expect_true(nrow(flags) >= 1L)
  expect_true(1995L %in% flags$accident_year)
  expect_equal(flags$rule_id[[1L]], "ATA_ZSCORE")
})

test_that("detect_ata_zscore returns zero rows for uniform triangle", {
  ata_df <- data.frame(
    lob           = "WC",
    accident_year = 1988:1997,
    from_lag      = 1L,
    to_lag        = 2L,
    ata_paid      = rep(1.5, 10L),
    ata_incurred  = rep(1.4, 10L),
    stringsAsFactors = FALSE
  )
  flags <- detect_ata_zscore(ata_df)
  expect_equal(nrow(flags), 0L)
})

test_that("detect_ata_zscore errors on missing columns", {
  bad_df <- data.frame(lob = "WC", from_lag = 1L, ata_paid = 1.5)
  expect_error(detect_ata_zscore(bad_df), "missing columns")
})

test_that("detect_diagonal_effect returns a data.frame with required fields", {
  tri_df <- data.frame(
    lob                      = "WC",
    accident_year            = rep(1988:1997, each = 5L),
    development_lag          = rep(1:5, times = 10L),
    cumulative_paid_loss     = runif(50L, 100, 500),
    cumulative_incurred_loss = runif(50L, 110, 550),
    earned_premium           = 1000,
    stringsAsFactors = FALSE
  )
  result <- detect_diagonal_effect(tri_df)
  expect_true(is.data.frame(result))
  expect_true(all(c("lob","from_lag","coefficient","p_value","direction","flagged") %in% names(result)))
})

test_that("combine_anomaly_signals returns columned data.frame when both inputs are empty", {
  # Regression test: analysis_r() used to return data.frame() (0 columns) when
  # ata_df had 0 rows, causing reactable::reactable() to throw
  # "data must have at least one column".
  empty_z <- data.frame(lob=character(), accident_year=integer(), development_lag=integer(),
                        rule_id=character(), severity=character(), observed=numeric(),
                        expected=numeric(), message=character(), stringsAsFactors=FALSE)
  empty_d <- data.frame(lob=character(), from_lag=integer(), coefficient=numeric(),
                        p_value=numeric(), direction=character(), flagged=logical(),
                        stringsAsFactors=FALSE)
  result <- combine_anomaly_signals(empty_z, empty_d)
  expect_true(is.data.frame(result))
  expect_equal(nrow(result), 0L)
  expect_true(all(c("lob","accident_year","development_lag","rule_id",
                    "severity","observed","expected","message") %in% names(result)))
})

test_that("combine_anomaly_signals deduplicates correctly", {
  z_flags <- data.frame(
    lob = "WC", accident_year = 1993L, development_lag = 2L,
    rule_id = "ATA_ZSCORE", severity = "warning", observed = 2.1,
    expected = 1.5, message = "test", stringsAsFactors = FALSE
  )
  # Duplicate the same row
  combined <- combine_anomaly_signals(rbind(z_flags, z_flags),
                                       data.frame(lob=character(), from_lag=integer(),
                                                  coefficient=numeric(), p_value=numeric(),
                                                  direction=character(), flagged=logical(),
                                                  stringsAsFactors=FALSE))
  expect_equal(nrow(combined), 1L)
})
