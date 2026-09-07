# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b3_unit_tests.R
# Tests unitarios de B3 (Diagnostics): KS, AD, CvM, chi-cuadrado, AIC/AICc/BIC,
# sobredispersión y estructura del objeto `diagnostics`. Referencias calculadas
# de forma independiente con SciPy (KS/CvM cruzados; CDFs propias verificadas).
# Autor: BMK — Última actualización: 2026-07-25
# ============================================================
#
#   Rscript tests/b3_unit_tests.R      # desde la raíz de la herramienta
#   Rscript b3_unit_tests.R            # desde la carpeta tests/

.locate_script <- function() {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    return(normalizePath(sub("^--file=", "", file_arg[1]), mustWork = FALSE))
  }
  for (i in rev(seq_len(sys.nframe()))) {
    of <- sys.frame(i)$ofile
    if (!is.null(of)) return(normalizePath(of, mustWork = FALSE))
  }
  NULL
}
.tool_root <- local({
  s <- .locate_script()
  if (!is.null(s)) dirname(dirname(s))
  else if (file.exists("R/calc.R")) normalizePath(".")
  else if (file.exists(file.path("..", "R", "calc.R"))) normalizePath("..")
  else stop("No se pudo localizar la raíz de la herramienta.", call. = FALSE)
})
source(file.path(.tool_root, "R", "calc.R"))

check <- function(cond, msg) {
  if (!isTRUE(cond)) stop(sprintf("FALLO: %s", msg), call. = FALSE)
  cat(sprintf("  OK  - %s\n", msg))
}
abstol <- function(actual, ref, tol, msg) {
  ok <- is.finite(actual) && abs(actual - ref) <= tol
  check(ok, sprintf("%s  (%.6f ~ %.6f +/- %g)", msg, actual, ref, tol))
}
rel <- function(actual, ref, reltol, msg) {
  ok <- is.finite(actual) && abs(actual - ref) <= reltol * abs(ref)
  check(ok, sprintf("%s  (%.6g ~ %.6g, rel<=%g)", msg, actual, ref, reltol))
}

cat("== B3 UNIT TESTS (Diagnostics) — distribution-fitting ==\n")

xc <- c(120.3, 340.7, 550.1, 610.4, 800.9, 1200.2, 1500.6, 2100.8, 2600.5, 3400.1, 5200.7, 9800.4)
xd <- c(0, 1, 0, 2, 1, 3, 0, 1, 2, 4, 1, 0, 2, 1, 5)

# ------------------------------------------------------------
# 1. Estructura del objeto diagnostics
# ------------------------------------------------------------
cat("\n-- 1. Estructura --\n")
rc <- dist_fit_analyze(data.frame(loss_amount = xc), "loss_amount")
dg <- rc$diagnostics
check(dg$family == "continuous",                 "diagnostics: familia continua")
check(length(dg$per_fit) == 7L,                  "diagnostics: 7 ajustes diagnosticados")
check(!is.null(dg$control$normal),               "diagnostics: incluye el control Normal")
g <- dg$per_fit$gamma
check(all(c("id","converged","information","gof") %in% names(g)),
      "diagnostics: cada entrada expone information y gof")
check(all(c("aic","aicc","bic") %in% names(g$information)),
      "diagnostics: information con aic/aicc/bic")
check(all(c("ks","cvm","ad") %in% names(g$gof)),
      "diagnostics (continua): gof con ks/cvm/ad")

# ------------------------------------------------------------
# 2. Bondad de ajuste continua (gamma MLE) vs SciPy
# ------------------------------------------------------------
cat("\n-- 2. GoF continua (gamma) --\n")
abstol(g$gof$ks,  0.117133, 1e-3, "gamma KS D (cruzado con scipy)")
abstol(g$gof$cvm, 0.026205, 1e-3, "gamma CvM W^2 (cruzado con scipy)")
abstol(g$gof$ad,  0.182360, 5e-3, "gamma AD A^2")

# ------------------------------------------------------------
# 3. Criterios de información (gamma)
# ------------------------------------------------------------
cat("\n-- 3. AIC/AICc/BIC (gamma) --\n")
rel(g$information$aic,  214.293656, 1e-4, "gamma AIC")
rel(g$information$aicc, 215.626989, 1e-4, "gamma AICc")
rel(g$information$bic,  215.263469, 1e-4, "gamma BIC")

# ------------------------------------------------------------
# 4. Bondad de ajuste discreta (poisson): chi-cuadrado + sobredispersión
# ------------------------------------------------------------
cat("\n-- 4. GoF discreta (poisson) --\n")
rd <- dist_fit_analyze(data.frame(count = xd), "count")
p <- rd$diagnostics$per_fit$poisson
check(rd$diagnostics$family == "discrete",       "diagnostics: familia discreta")
check(all(c("chisq","df","overdispersion") %in% names(p$gof)),
      "diagnostics (discreta): gof con chisq/df/sobredispersión")
# ADR-019: las categorías se agrupan hasta alcanzar la esperanza mínima. Con
# n = 15 el suelo estándar (5) no deja grados de libertad, así que se aplica el
# suelo relajado de Cochran (1) y quedan 5 celdas. Referencias recalculadas con
# la réplica del motor (los valores previos, chisq 2.501493 / df 4, correspondían
# a categorías individuales con esperanzas próximas a 0).
abstol(p$gof$chisq, 1.673333, 1e-3, "poisson chi-cuadrado (categorías agrupadas)")
check(p$gof$df == 3L,                            "poisson df = celdas - 1 - nº params")
check(p$gof$n_cells == 5L,                       "poisson: 5 celdas tras la agrupación")
check(is.character(p$gof$gof_note) && grepl("Cochran", p$gof$gof_note),
      "poisson: se documenta el uso del suelo relajado (n pequeño)")
abstol(p$gof$overdispersion, 1.379710, 1e-4, "poisson sobredispersión (var/media)")
rel(p$information$aic, 52.011068, 1e-4, "poisson AIC")
rel(p$information$bic, 52.719118, 1e-4, "poisson BIC")

cat("\nB3 UNIT TESTS SUPERADOS\n")
