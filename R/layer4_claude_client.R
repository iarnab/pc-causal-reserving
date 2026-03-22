# ==============================================================================
# R/layer_5_llm/claude_client.R
# Anthropic Claude API Client
#
# Thin httr2 wrapper around the Anthropic Messages API. Handles authentication,
# request construction, timeout, retry, and error reporting. Implements retry
# with exponential backoff (max 3 attempts) for transient errors (429, 5xx).
#
# Authentication: reads ANTHROPIC_API_KEY from the environment (set in
# .Renviron). Never hardcoded.
#
# Required packages: httr2, jsonlite
# Do NOT call library() here — packages are loaded in app.R.
#
# Reference: https://docs.anthropic.com/en/api/messages
#
# Usage:
#   source("R/layer_5_llm/claude_client.R")
#   response <- call_claude(
#     messages      = list(list(role = "user", content = "Explain the ATA factor.")),
#     system_prompt = "You are an expert P&C reserve actuary."
#   )
#   cat(response)
# ==============================================================================

# -- Constants -----------------------------------------------------------------

ANTHROPIC_API_URL     <- "https://api.anthropic.com/v1/messages"
ANTHROPIC_API_VERSION <- "2023-06-01"
DEFAULT_MODEL         <- "claude-opus-4-6"
DEFAULT_MAX_TOKENS    <- 1024L
REQUEST_TIMEOUT_SECS  <- 60L
REQUEST_MAX_TRIES     <- 3L   # max retry attempts for transient HTTP errors (429, 5xx)


# -- API client ----------------------------------------------------------------

#' Call the Claude API (Anthropic Messages endpoint)
#'
#' Sends a POST request to the Anthropic Messages API and returns the text
#' content of the first response block. Returns NULL (with a warning) on HTTP
#' errors, connection errors, or malformed responses.
#'
#' @param messages     A list of message objects. Each element must be a named
#'   list with keys \code{role} ("user" or "assistant") and \code{content}
#'   (character). Example:
#'   \code{list(list(role = "user", content = "Hello"))}
#' @param model        Character model ID (default: "claude-opus-4-6").
#' @param max_tokens   Integer maximum tokens for the response (default: 1024).
#' @param system_prompt Character system prompt, or NULL for no system prompt.
#' @param temperature   Numeric in [0, 1]. Default 0 gives deterministic,
#'   reproducible responses appropriate for factual actuarial analysis.
#' @return Character string containing the response text, or NULL on failure.
call_claude <- function(messages,
                        model         = DEFAULT_MODEL,
                        max_tokens    = DEFAULT_MAX_TOKENS,
                        system_prompt = NULL,
                        temperature   = 0) {

  stopifnot(is.list(messages), length(messages) >= 1L)
  stopifnot(is.numeric(temperature), length(temperature) == 1L,
            temperature >= 0, temperature <= 1)

  api_key <- Sys.getenv("ANTHROPIC_API_KEY")
  if (!nzchar(api_key)) {
    stop(paste0(
      "ANTHROPIC_API_KEY is not set. ",
      "Add it to .Renviron and restart R:\n",
      "  ANTHROPIC_API_KEY=sk-ant-..."
    ))
  }

  body <- list(
    model       = model,
    max_tokens  = as.integer(max_tokens),
    temperature = temperature,
    messages    = messages
  )
  if (!is.null(system_prompt) && nzchar(system_prompt)) {
    body$system <- as.character(system_prompt)
  }

  req <- httr2::request(ANTHROPIC_API_URL) |>
    httr2::req_headers(
      "x-api-key"         = api_key,
      "anthropic-version" = ANTHROPIC_API_VERSION,
      "content-type"      = "application/json"
    ) |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(REQUEST_TIMEOUT_SECS) |>
    httr2::req_retry(
      max_tries    = REQUEST_MAX_TRIES,
      is_transient = function(resp) {
        httr2::resp_status(resp) %in% c(429L, 500L, 502L, 503L, 504L)
      },
      backoff = function(attempt) min(2^attempt, 30)
    ) |>
    httr2::req_error(is_error = function(resp) FALSE)   # handle errors manually

  resp <- tryCatch(
    httr2::req_perform(req),
    error = function(e) {
      warning(glue::glue(
        "Claude API connection error: {conditionMessage(e)}"
      ))
      return(NULL)
    }
  )

  if (is.null(resp)) return(NULL)

  status <- httr2::resp_status(resp)

  if (status != 200L) {
    body_text <- tryCatch(httr2::resp_body_string(resp), error = function(e) "")
    warning(glue::glue(
      "Claude API error (HTTP {status}): {body_text}"
    ))
    return(NULL)
  }

  parsed <- tryCatch(
    httr2::resp_body_json(resp),
    error = function(e) {
      warning(glue::glue("Failed to parse Claude API response: {conditionMessage(e)}"))
      return(NULL)
    }
  )

  if (is.null(parsed)) return(NULL)

  content_blocks <- parsed$content
  if (!is.list(content_blocks) || length(content_blocks) == 0L) {
    warning("Claude API returned an empty content array.")
    return(NULL)
  }

  text_block <- Filter(function(b) identical(b$type, "text"), content_blocks)
  if (length(text_block) == 0L) {
    warning("Claude API response contained no text content block.")
    return(NULL)
  }

  as.character(text_block[[1L]]$text)
}
