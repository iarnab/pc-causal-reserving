# Tests for R/layer4_claude_client.R
# call_claude() is tested via:
#   1. Input validation (no API call needed)
#   2. local_mocked_bindings to simulate httr2 HTTP responses


# -- Input validation ----------------------------------------------------------

test_that("call_claude stops when ANTHROPIC_API_KEY is not set", {
  withr::with_envvar(c(ANTHROPIC_API_KEY = ""), {
    expect_error(
      call_claude(list(list(role = "user", content = "hello"))),
      "ANTHROPIC_API_KEY"
    )
  })
})

test_that("call_claude stops on empty messages list", {
  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    expect_error(
      call_claude(list()),
      regexp = NULL   # stopifnot fires; any error is acceptable
    )
  })
})

test_that("call_claude stops when messages is not a list", {
  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    expect_error(
      call_claude("not a list"),
      regexp = NULL
    )
  })
})

test_that("call_claude stops on temperature < 0", {
  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    expect_error(
      call_claude(list(list(role = "user", content = "hi")), temperature = -0.1),
      regexp = NULL
    )
  })
})

test_that("call_claude stops on temperature > 1", {
  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    expect_error(
      call_claude(list(list(role = "user", content = "hi")), temperature = 1.5),
      regexp = NULL
    )
  })
})


# -- HTTP response mocking -----------------------------------------------------

# Build a minimal httr2-compatible response object
make_httr2_resp <- function(status, body_json = NULL, body_text = NULL) {
  body_bytes <- if (!is.null(body_json)) {
    charToRaw(jsonlite::toJSON(body_json, auto_unbox = TRUE))
  } else if (!is.null(body_text)) {
    charToRaw(body_text)
  } else {
    raw(0)
  }
  structure(
    list(
      method      = "POST",
      url         = "https://api.anthropic.com/v1/messages",
      status_code = status,
      headers     = list(`content-type` = "application/json"),
      body        = body_bytes
    ),
    class = "httr2_response"
  )
}

test_that("call_claude returns text from a successful 200 response", {
  fake_resp <- make_httr2_resp(200L, body_json = list(
    content = list(list(type = "text", text = "Reserve looks adequate."))
  ))

  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    testthat::local_mocked_bindings(
      req_perform = function(...) fake_resp,
      .package    = "httr2"
    )
    result <- call_claude(list(list(role = "user", content = "Assess reserves.")))
  })

  expect_equal(result, "Reserve looks adequate.")
})

test_that("call_claude returns NULL and warns on HTTP 4xx error", {
  fake_resp <- make_httr2_resp(401L, body_text = "Unauthorized")

  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-invalid"), {
    testthat::local_mocked_bindings(
      req_perform = function(...) fake_resp,
      .package    = "httr2"
    )
    expect_warning(
      result <- call_claude(list(list(role = "user", content = "hello"))),
      "401"
    )
  })

  expect_null(result)
})

test_that("call_claude returns NULL and warns on HTTP 500 error", {
  fake_resp <- make_httr2_resp(500L, body_text = "Internal Server Error")

  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    testthat::local_mocked_bindings(
      req_perform = function(...) fake_resp,
      .package    = "httr2"
    )
    expect_warning(
      result <- call_claude(list(list(role = "user", content = "hello"))),
      "500"
    )
  })

  expect_null(result)
})

test_that("call_claude returns NULL and warns on connection error", {
  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    testthat::local_mocked_bindings(
      req_perform = function(...) stop("Could not connect"),
      .package    = "httr2"
    )
    expect_warning(
      result <- call_claude(list(list(role = "user", content = "hello"))),
      "connection error"
    )
  })

  expect_null(result)
})

test_that("call_claude returns NULL when content array is empty", {
  fake_resp <- make_httr2_resp(200L, body_json = list(content = list()))

  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    testthat::local_mocked_bindings(
      req_perform = function(...) fake_resp,
      .package    = "httr2"
    )
    expect_warning(
      result <- call_claude(list(list(role = "user", content = "hello"))),
      "empty content"
    )
  })

  expect_null(result)
})

test_that("call_claude returns NULL when response has no text block", {
  fake_resp <- make_httr2_resp(200L, body_json = list(
    content = list(list(type = "tool_use", id = "tu_123"))
  ))

  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    testthat::local_mocked_bindings(
      req_perform = function(...) fake_resp,
      .package    = "httr2"
    )
    expect_warning(
      result <- call_claude(list(list(role = "user", content = "hello"))),
      "no text"
    )
  })

  expect_null(result)
})

test_that("call_claude appends system prompt to request body when provided", {
  captured_body <- NULL
  fake_resp <- make_httr2_resp(200L, body_json = list(
    content = list(list(type = "text", text = "OK"))
  ))

  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    testthat::local_mocked_bindings(
      req_perform = function(...) fake_resp,
      req_body_json = function(req, body, ...) {
        captured_body <<- body
        req
      },
      .package = "httr2"
    )
    call_claude(
      messages      = list(list(role = "user", content = "hi")),
      system_prompt = "You are an actuary."
    )
  })

  expect_true(!is.null(captured_body$system))
  expect_equal(captured_body$system, "You are an actuary.")
})

test_that("call_claude uses temperature=0 by default", {
  captured_body <- NULL
  fake_resp <- make_httr2_resp(200L, body_json = list(
    content = list(list(type = "text", text = "OK"))
  ))

  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    testthat::local_mocked_bindings(
      req_perform = function(...) fake_resp,
      req_body_json = function(req, body, ...) {
        captured_body <<- body
        req
      },
      .package = "httr2"
    )
    call_claude(list(list(role = "user", content = "hi")))
  })

  expect_equal(captured_body$temperature, 0)
})
