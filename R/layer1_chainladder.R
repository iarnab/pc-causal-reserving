# ==============================================================================
# R/layer1_chainladder.R
# Chain-Ladder Reserve Estimation - Baseline Actuarial Model
#
# Implements the volume-weighted chain-ladder method with single-outlier
# exclusion per development column. Returns accident-year ultimates and IBNR
# estimates that serve as the benchmark against which causal narrative
# estimates are compared.
#
# Required packages: tidyr, glue  (loaded by app.R)
# Do NOT call library() here.
# ==============================================================================


# -- Internal helpers ----------------------------------------------------------

#' Compute volume-weighted ATA factors with single-outlier exclusion
#'
#' For each from_lag -> to_lag transition, collects all accident years that
#' have positive finite losses at both lags, drops the single observation
#' whose individual ATA deviates most from the column median, then computes
#' sum(to) / sum(from) on the remaining observations.
#'
#' @param tri_wide data.frame: rows = accident years, columns include
#'   character lag names plus "accident_year".
#' @param lags Integer vector of development lags, sorted ascending.
#' @return Named numeric vector length(lags) - 1.
#'   Names: "<from_lag>_to_<to_lag>".
compute_vw_ata <- function(tri_wide, lags) {
  n_lags    <- length(lags)
  ata_names <- paste0(lags[-n_lags], "_to_", lags[-1L])
  atas      <- setNames(numeric(n_lags - 1L), ata_names)

  for (i in seq_len(n_lags - 1L)) {
    lag_from  <- as.character(lags[i])
    lag_to    <- as.character(lags[i + 1L])
    from_vals <- tri_wide[[lag_from]]
    to_vals   <- tri_wide[[lag_to]]

    idx   <- is.finite(from_vals) & from_vals > 0 &
             is.finite(to_vals)   & to_vals   > 0
    n_obs <- sum(idx)

    if (n_obs == 0L) {
      atas[i] <- 1.0
      next
    }
    if (n_obs == 1L) {
      atas[i] <- to_vals[idx] / from_vals[idx]
      next
    }

    fv       <- from_vals[idx]
    tv       <- to_vals[idx]
    raw_atas <- tv / fv
    exclude  <- which.max(abs(raw_atas - median(raw_atas)))
    fv       <- fv[-exclude]
    tv       <- tv[-exclude]
    atas[i]  <- sum(tv) / sum(fv)
  }

  atas
}


# -- Main entry point ----------------------------------------------------------

#' Compute chain-ladder reserves from a paid loss development triangle
#'
#' Projects the lower-right triangle using volume-weighted average ATA factors
#' (with the single most-extreme ATA excluded per development column).
#' Cumulative development factors (CDFs) are computed by chaining the ATAs
#' from each lag to the last observed lag, then multiplying by tail_factor.
#'
#' The CAS Schedule P datasets are full rectangles (all cells historically
#' observed). Pass \code{eval_year} to cut the diagonal so that only the
#' upper-left triangle (data as of that year-end) is used for factor fitting
#' and the lower-right is projected. Without \code{eval_year} all available
#' lags per accident year are used (suitable when the caller has already
#' trimmed the triangle).
#'
#' @param triangle_df data.frame with columns:
#'   accident_year (integer), development_lag (integer),
#'   cumulative_paid_loss (numeric).
#' @param eval_year Integer calendar year of evaluation (year-end). For each
#'   accident year ay, only lags up to eval_year - ay + 1 are retained.
#'   NULL (default) derives eval_year from the data as
#'   min(accident_year) + max(development_lag) - 1, which equals the
#'   calendar year of the last full diagonal.
#' @param tail_factor Numeric >= 1.0. Applied beyond the last observed lag.
#'   Default 1.0 assumes full development within the data.
#'
#' @return data.frame with one row per accident year and columns:
#'   accident_year, latest_lag, current_loss, ldf, ultimate_loss, ibnr.
#'   Attributes: ata_factors (named vector), cdf (named vector),
#'   eval_year (integer or NA).
compute_chainladder_reserve <- function(triangle_df,
                                        eval_year   = NULL,
                                        tail_factor = 1.0) {
  stopifnot(is.data.frame(triangle_df))
  if (!is.numeric(tail_factor) ||
      length(tail_factor) != 1L ||
      tail_factor < 1.0) {
    stop("tail_factor must be a numeric scalar >= 1.0")
  }
  required <- c("accident_year", "development_lag", "cumulative_paid_loss")
  missing  <- setdiff(required, names(triangle_df))
  if (length(missing) > 0L) {
    stop(glue::glue(
      "triangle_df missing columns: {paste(missing, collapse = ', ')}"
    ))
  }

  df <- triangle_df[
    is.finite(triangle_df$cumulative_paid_loss) &
    triangle_df$cumulative_paid_loss > 0L, ]

  if (nrow(df) == 0L) {
    stop("No valid (finite, positive) cumulative_paid_loss values.")
  }

  # Derive eval_year from the data when not supplied:
  #   eval_year = min(accident_year) + max(development_lag) - 1
  # This is the calendar year of the last full diagonal, e.g. for a
  # 1998-2007 dataset: 1998 + 10 - 1 = 2007.
  if (is.null(eval_year)) {
    eval_year <- as.integer(
      min(df$accident_year) + max(df$development_lag) - 1L
    )
    message(glue::glue("eval_year not supplied — derived from data: {eval_year}"))
  } else {
    eval_year <- as.integer(eval_year)
    if (is.na(eval_year)) stop("eval_year must be a valid integer year.")
  }

  df <- df[df$development_lag <= (eval_year - df$accident_year + 1L), ]
  if (nrow(df) == 0L) {
    stop(glue::glue(
      "No data remains after applying eval_year = {eval_year}. ",
      "Check that accident years are <= eval_year."
    ))
  }

  lags <- sort(unique(as.integer(df$development_lag)))
  ays  <- sort(unique(as.integer(df$accident_year)))

  tri_wide <- tidyr::pivot_wider(
    df[, c("accident_year", "development_lag", "cumulative_paid_loss")],
    names_from  = "development_lag",
    values_from = "cumulative_paid_loss"
  )
  tri_wide <- as.data.frame(tri_wide)

  # Step 1: volume-weighted ATA factors (one outlier excluded per column)
  ata_factors <- compute_vw_ata(tri_wide, lags)

  # Step 2: cumulative development factors
  # CDF[last_lag] = tail_factor; CDF[i] = ATA[i] * CDF[i+1]
  n_lags      <- length(lags)
  cdf         <- setNames(numeric(n_lags), as.character(lags))
  cdf[n_lags] <- tail_factor
  if (n_lags > 1L) {
    for (i in seq(n_lags - 1L, 1L)) {
      cdf[i] <- ata_factors[i] * cdf[i + 1L]
    }
  }

  # Step 3: project each accident year to ultimate
  results <- lapply(ays, function(ay) {
    row      <- tri_wide[tri_wide$accident_year == ay, , drop = FALSE]
    lag_cols <- as.character(lags)
    observed <- lag_cols[!is.na(row[, lag_cols, drop = FALSE])]
    if (length(observed) == 0L) return(NULL)

    latest_lag   <- as.integer(observed[length(observed)])
    current_loss <- row[[as.character(latest_lag)]]
    ldf_val      <- cdf[as.character(latest_lag)]

    data.frame(
      accident_year = ay,
      latest_lag    = latest_lag,
      current_loss  = current_loss,
      ldf           = ldf_val,
      ultimate_loss = current_loss * ldf_val,
      ibnr          = current_loss * (ldf_val - 1.0),
      stringsAsFactors = FALSE
    )
  })

  result_df           <- do.call(rbind, Filter(Negate(is.null), results))
  rownames(result_df) <- NULL

  attr(result_df, "ata_factors") <- ata_factors
  attr(result_df, "cdf")         <- cdf
  attr(result_df, "eval_year")   <- eval_year %||% NA_integer_

  result_df
}
