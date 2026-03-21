test_that("build_reserving_dag returns a dagitty object", {
  dag <- build_reserving_dag()
  expect_s3_class(dag, "dagitty")
})

test_that("all 5 layers have at least one node in the DAG", {
  dag   <- build_reserving_dag()
  nodes <- get_reserving_dag_nodes()
  dag_node_names <- names(dagitty::coordinates(dag))

  for (layer in names(nodes)) {
    layer_nodes <- nodes[[layer]]
    expect_true(
      any(layer_nodes %in% dag_node_names),
      info = glue::glue("Layer {layer} has no nodes in the DAG")
    )
  }
})

test_that("get_dag_paths returns non-empty result for L1 -> L5", {
  dag   <- build_reserving_dag()
  paths <- get_dag_paths(dag, "medical_cpi", "ultimate_loss")
  expect_true(nrow(paths) >= 1L)
  expect_true("paths" %in% names(paths))
})

test_that("get_dag_paths returns empty data.frame for non-existent path", {
  dag   <- build_reserving_dag()
  # ultimate_loss does not cause medical_cpi (reverse direction)
  paths <- get_dag_paths(dag, "ultimate_loss", "medical_cpi")
  expect_equal(nrow(paths), 0L)
})

test_that("query_do_calculus returns a list with required fields", {
  dag    <- build_reserving_dag()
  result <- query_do_calculus(dag, "tort_reform", "ultimate_loss")
  expect_true(is.list(result))
  expect_true(all(c("adjustment_set","paths","identifiable") %in% names(result)))
  expect_true(is.logical(result$identifiable))
  expect_true(is.character(result$adjustment_set))
})

test_that("extract_active_subgraph returns nodes and edges", {
  dag    <- build_reserving_dag()
  result <- extract_active_subgraph(dag, c("medical_cpi", "tort_reform"))
  expect_true(is.list(result))
  expect_true(all(c("nodes","edges") %in% names(result)))
  expect_true(length(result$nodes) >= 2L)
})
