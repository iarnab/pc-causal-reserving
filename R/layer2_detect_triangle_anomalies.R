# ==============================================================================
# R/layer_2_anomaly/detect_triangle_anomalies.R
# Triangle Anomaly Detection
#
# Detects anomalies in Schedule P development data:
#   - ATA Z-score flags: development periods where factors deviate from the
#     all-year average by more than z_threshold standard deviations.
#   - Diagonal effects: systematic high/low development on the most-recent
#     calendar-year diagonal, indicative of a claims operations change or
#     macro event.
#
# Required packages: dplyr, anomalize
# Do NOT call library() here — loaded by app.R.
#
# Usage:
#   source("R/layer_2_anomaly/detect_triangle_anomalies.R")
#   ata_df      <- compute_ata_factors(triangle_df)
#   zscore_flags <- detect_ata_zscore(ata_df)
#   diag_flags  <- detect_diagonal_effect(triangle_df)
#   anomalies   <- combine_anomaly_signals(zscore_flags, diag_flags)
# ==============================================================================


# -- ATA Z-score detection -----------------------------------------------------

#' Detect ATA factors that deviate significantly from the column mean
#'
#' For each (lob, from_lag) column in the ATA matrix, computes the mean and
#' standard deviation of paid ATA factors across all accident years. Flags
#' any accident year where |z-score| > z_threshold.
#'
#' @param ata_df      A data.frame from compute_ata_factors(). Required columns:
#'   lob, accident_year, from_lag, to_lag, ata_paid.
#' @param z_threshold Numeric scalar: flag threshold (default 2.5σ).
#' @return A data.frame with columns: lob, accident_year, development_lag
#'   (= from_lag), rule_id, severity, observed, expected, message.
#'   Zero rows if no anomalies found.
detect_ata_zscore <- function(ata_df, z_threshold = 2.5) {
  stopifnot(is.data.frame(ata_df), is.numeric(z_threshold), z_threshold > 0)

  required <- c("lob", "accident_year", "from_lag", "ata_paid")
  missing  <- setdiff(required, names(ata_df))
  if (length(missing) > 0L) {
    stop(glue::glue("detect_ata_zscore: missing columns: {paste(missing, collapse=', ')}"))
  }

  flags <- do.call(rbind, lapply(
    split(ata_df, list(ata_df$lob, ata_df$from_lag)),
    function(grp) {
      if (nrow(grp) < 3L) return(NULL)   # need >= 3 obs for a meaningful z-score

      col_mean <- mean(grp$ata_paid, na.rm = TRUE)
      col_sd   <- sd(grp$ata_paid,   na.rm = TRUE)
      if (is.na(col_sd) || col_sd == 0) return(NULL)

      z_scores <- (grp$ata_paid - col_mean) / col_sd
      flagged  <- abs(z_scores) > z_threshold

      if (!any(flagged, na.rm = TRUE)) return(NULL)

      grp_flagged <- grp[flagged, ]
      z_flagged   <- z_scores[flagged]

      data.frame(
        lob             = grp_flagged$lob,
        accident_year   = grp_flagged$accident_year,
        development_lag = grp_flagged$from_lag,
        rule_id         = "ATA_ZSCORE",
        severity        = ifelse(abs(z_flagged) > 3.0, "error", "warning"),
        observed        = grp_flagged$ata_paid,
        expected        = col_mean,
        message         = glue::glue(
          "ATA factor {round(grp_flagged$ata_paid, 3)} deviates ",
          "{round(z_flagged, 2)}\u03c3 from column mean {round(col_mean, 3)}"
        ),
        stringsAsFactors = FALSE
      )
    }
  ))

  if (is.null(flags)) {
    return(data.frame(
      lob=character(), accident_year=integer(), development_lag=integer(),
      rule_id=character(), severity=character(), observed=numeric(),
      expected=numeric(), message=character(), stringsAsFactors=FALSE
    ))
  }

  rownames(flags) <- NULL
  flags
}


# -- Diagonal effect detection -------------------------------------------------

#' Test whether the most-recent diagonal shows a systematic shift
#'
#' Regresses the paid ATA factor on a binary "most-recent diagonal" indicator
#' for each (lob, from_lag). A significant positive or negative coefficient
#' indicates a calendar-year effect on the latest diagonal.
#'
#' @param triangle_df A data.frame with columns: lob, accident_year,
#'   development_lag, cumulative_paid_loss (long format, upper triangle only).
#' @return A data.frame with columns: lob, from_lag, coefficient, p_value,
#'   direction, flagged (logical). One row per (lob, from_lag) pair tested.
detect_diagonal_effect <- function(triangle_df) {
  stopifnot(is.data.frame(triangle_df))

  required <- c("lob", "accident_year", "development_lag", "cumulative_paid_loss")
  missing  <- setdiff(required, names(triangle_df))
  if (length(missing) > 0L) {
    stop(glue::glue("detect_diagonal_effect: missing columns: {paste(missing, collapse=', ')}"))
  }

  ata_df <- compute_ata_factors(triangle_df)
  if (nrow(ata_df) == 0L) {
    return(data.frame(lob=character(), from_lag=integer(), coefficient=numeric(),
                      p_value=numeric(), direction=character(), flagged=logical(),
                      stringsAsFactors=FALSE))
  }

  # Most-recent diagonal: calendar_year = accident_year + development_lag - 1
  ata_df$calendar_year <- ata_df$accident_year + ata_df$from_lag - 1L
  max_cy <- max(ata_df$calendar_year, na.rm = TRUE)
  ata_df$is_latest_diagonal <- as.integer(ata_df$calendar_year == max_cy)

  results <- do.call(rbind, lapply(
    split(ata_df, list(ata_df$lob, ata_df$from_lag)),
    function(grp) {
      if (nrow(grp) < 4L || sum(grp$is_latest_diagonal) == 0L) return(NULL)

      fit <- tryCatch(
        lm(ata_paid ~ is_latest_diagonal, data = grp),
        error = function(e) NULL
      )
      if (is.null(fit)) return(NULL)

      coef_val <- coef(fit)[["is_latest_diagonal"]]
      p_val    <- summary(fit)$coefficients["is_latest_diagonal", "Pr(>|t|)"]

      data.frame(
        lob         = grp$lob[[1L]],
        from_lag    = grp$from_lag[[1L]],
        coefficient = coef_val,
        p_value     = p_val,
        direction   = ifelse(coef_val > 0, "adverse", "favourable"),
        flagged     = p_val < 0.10,   # 10% significance for actuarial flagging
        stringsAsFactors = FALSE
      )
    }
  ))

  if (is.null(results)) {
    return(data.frame(lob=character(), from_lag=integer(), coefficient=numeric(),
                      p_value=numeric(), direction=character(), flagged=logical(),
                      stringsAsFactors=FALSE))
  }
  rownames(results) <- NULL
  results
}


# -- Signal aggregator ---------------------------------------------------------

#' Combine ATA z-score flags and diagonal effect flags into a unified table
#'
#' Converts diagonal effect flags to the same format as z-score flags and
#' row-binds them. Deduplicates by (lob, accident_year, development_lag, rule_id).
#'
#' @param zscore_flags  data.frame from detect_ata_zscore().
#' @param diagonal_flags data.frame from detect_diagonal_effect().
#' @return A unified data.frame with columns: lob, accident_year,
#'   development_lag, rule_id, severity, observed, expected, message.
combine_anomaly_signals <- function(zscore_flags, diagonal_flags) {
  stopifnot(is.data.frame(zscore_flags), is.data.frame(diagonal_flags))

  # Convert diagonal effect flags to the standard format
  diag_std <- if (nrow(diagonal_flags) > 0L && any(diagonal_flags$flagged)) {
    flagged_rows <- diagonal_flags[diagonal_flags$flagged, ]
    data.frame(
      lob             = flagged_rows$lob,
      accident_year   = NA_integer_,   # diagonal effects are calendar-year events
      development_lag = flagged_rows$from_lag,
      rule_id         = "DIAGONAL_EFFECT",
      severity        = ifelse(flagged_rows$p_value < 0.05, "warning", "info"),
      observed        = flagged_rows$coefficient,
      expected        = 0,
      message         = glue::glue(
        "{flagged_rows$direction} diagonal effect at development lag ",
        "{flagged_rows$from_lag} (coef={round(flagged_rows$coefficient, 3)}, ",
        "p={round(flagged_rows$p_value, 3)})"
      ),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(lob=character(), accident_year=integer(), development_lag=integer(),
               rule_id=character(), severity=character(), observed=numeric(),
               expected=numeric(), message=character(), stringsAsFactors=FALSE)
  }

  combined <- rbind(zscore_flags, diag_std)

  # Deduplicate
  dup_key <- paste(combined$lob, combined$accident_year,
                   combined$development_lag, combined$rule_id)
  combined[!duplicated(dup_key), ]
}
