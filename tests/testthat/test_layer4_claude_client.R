# Tests for R/layer4_claude_client.R
# call_claude() is tested via:
#   1. Input validation (no API call needed)
#   2. local_mocked_bindings for req_perform + all httr2 response accessors
#      (avoids httr2 version-specific response object internals)


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
    expect_error(call_claude(list()))
  })
})

test_that("call_claude stops when messages is not a list", {
  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    expect_error(call_claude("not a list"))
  })
})

test_that("call_claude stops on temperature < 0", {
  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    expect_error(
      call_claude(list(list(role = "user", content = "hi")), temperature = -0.1)
    )
  })
})

test_that("call_claude stops on temperature > 1", {
  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    expect_error(
      call_claude(list(list(role = "user", content = "hi")), temperature = 1.5)
    )
  })
})


# -- HTTP response mocking -----------------------------------------------------
# We mock req_perform + all httr2 response accessors (resp_status,
# resp_body_json, resp_body_string) so tests are insulated from httr2
# internal response object structure changes across versions.

test_that("call_claude returns text from a successful 200 response", {
  parsed <- list(content = list(list(type = "text", text = "Reserve looks adequate.")))

  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    testthat::local_mocked_bindings(
      req_perform      = function(...) list(),
      resp_status      = function(...) 200L,
      resp_body_json   = function(...) parsed,
      .package         = "httr2"
    )
    result <- call_claude(list(list(role = "user", content = "Assess reserves.")))
  })

  expect_equal(result, "Reserve looks adequate.")
})

test_that("call_claude returns NULL and warns on HTTP 401 error", {
  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-invalid"), {
    testthat::local_mocked_bindings(
      req_perform       = function(...) list(),
      resp_status       = function(...) 401L,
      resp_body_string  = function(...) "Unauthorized",
      .package          = "httr2"
    )
    expect_warning(
      result <- call_claude(list(list(role = "user", content = "hello"))),
      "401"
    )
  })
  expect_null(result)
})

test_that("call_claude returns NULL and warns on HTTP 500 error", {
  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    testthat::local_mocked_bindings(
      req_perform       = function(...) list(),
      resp_status       = function(...) 500L,
      resp_body_string  = function(...) "Internal Server Error",
      .package          = "httr2"
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
  parsed <- list(content = list())

  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    testthat::local_mocked_bindings(
      req_perform    = function(...) list(),
      resp_status    = function(...) 200L,
      resp_body_json = function(...) parsed,
      .package       = "httr2"
    )
    expect_warning(
      result <- call_claude(list(list(role = "user", content = "hello"))),
      "empty content"
    )
  })
  expect_null(result)
})

test_that("call_claude returns NULL when response has no text block", {
  parsed <- list(content = list(list(type = "tool_use", id = "tu_123")))

  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    testthat::local_mocked_bindings(
      req_perform    = function(...) list(),
      resp_status    = function(...) 200L,
      resp_body_json = function(...) parsed,
      .package       = "httr2"
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
  parsed <- list(content = list(list(type = "text", text = "OK")))

  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    testthat::local_mocked_bindings(
      req_perform    = function(...) list(),
      resp_status    = function(...) 200L,
      resp_body_json = function(...) parsed,
      req_body_json  = function(req, body, ...) { captured_body <<- body; req },
      .package       = "httr2"
    )
    call_claude(
      messages      = list(list(role = "user", content = "hi")),
      system_prompt = "You are an actuary."
    )
  })

  expect_false(is.null(captured_body$system))
  expect_equal(captured_body$system, "You are an actuary.")
})

test_that("call_claude uses temperature=0 by default", {
  captured_body <- NULL
  parsed <- list(content = list(list(type = "text", text = "OK")))

  withr::with_envvar(c(ANTHROPIC_API_KEY = "sk-ant-test"), {
    testthat::local_mocked_bindings(
      req_perform    = function(...) list(),
      resp_status    = function(...) 200L,
      resp_body_json = function(...) parsed,
      req_body_json  = function(req, body, ...) { captured_body <<- body; req },
      .package       = "httr2"
    )
    call_claude(list(list(role = "user", content = "hi")))
  })

  expect_equal(captured_body$temperature, 0)
})
