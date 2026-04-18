box::use(
  utils[head]
)

build_report <- function(values) {
  head(values, 1)
}

run <- function() {
  build_report(c("a", "b"))
}
