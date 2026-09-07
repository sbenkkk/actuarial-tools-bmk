# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b4_unit_tests.R
# Tests unitarios de B4 (Assessment): normalización, pilares, score compuesto,
# ranking relativo, desempates y recomendación Nivel 1. Referencias replicadas
# de forma independiente con NumPy/SciPy. Alcance B4: A+B; categorías absolutas,
# EVT, estabilidad y Nivel 2 quedan diferidos.
# Autor: BMK — Última actualización: 2026-07-25
# ============================================================
#
#   Rscript tests/b4_unit_tests.R      # desde la raíz de la herramienta
#   Rscript b4_unit_tests.R            # desde la carpeta tests/

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
  check(ok, sprintf("%s  (%.4f ~ %.4f +/- %g)", msg, actual, ref, tol))
}
by_id <- function(ranking, id) Filter(function(e) e$id == id, ranking)[[1]]

cat("== B4 UNIT TESTS (Assessment) — distribution-fitting ==\n")

xc <- c(120.3, 340.7, 550.1, 610.4, 800.9, 1200.2, 1500.6, 2100.8, 2600.5, 3400.1, 5200.7, 9800.4)
xd <- c(0, 1, 0, 2, 1, 3, 0, 1, 2, 4, 1, 0, 2, 1, 5)

# ------------------------------------------------------------
# 1. Estructura y pesos
# ------------------------------------------------------------
cat("\n-- 1. Estructura --\n")
ac <- dist_fit_analyze(data.frame(loss_amount = xc), "loss_amount")$assessment
check(abs(ac$weights$A - 0.7) < 1e-9 && abs(ac$weights$B - 0.3) < 1e-9,
      "assessment: pesos A=0.7, B=0.3 (decision_engine)")
check(length(ac$ranking) == 7L,                 "assessment: 7 candidatas en el ranking")
check(length(ac$excluded) == 0L,                "assessment: sin excluidas (todas convergen)")
check(is.character(ac$deferred$absolute_categories),
      "assessment: categorías absolutas marcadas como diferidas")
check(!is.null(ac$control_check),               "assessment: control (Normal) evaluado")
check(ac$decision_engine_version == "0.2",      "assessment: decision_engine_version (0.2, ADR-021)")

# ------------------------------------------------------------
# 2. Ranking relativo y recomendación (continua)
# ------------------------------------------------------------
cat("\n-- 2. Ranking continua --\n")
check(ac$ranking[[1]]$id == "lognormal" && ac$ranking[[1]]$rank == 1L,
      "ranking: mejor ajuste = lognormal (top)")
check(ac$ranking[[1]]$composite > 80,           "ranking: composite del top > 80")
check(ac$recommendation$level1$id == "lognormal",
      "recomendación Nivel 1 = lognormal")
# ADR-021: la confianza se decide por ΔAIC, no por la separación del compuesto.
# Aquí lognormal gana por compuesto pero NO es la mejor por AIC (ΔAIC = -1.33):
# con |ΔAIC| < 2 los modelos son indistinguibles -> confianza baja. La separación
# del compuesto (~9.5) se conserva como dato descriptivo.
check(ac$recommendation$level1$confidence == "baja",
      "confianza = baja (ΔAIC = -1.33: lognormal y loglogística indistinguibles)")
abstol(ac$recommendation$level1$delta_aic, -1.3350, 1e-2, "ΔAIC con la siguiente candidata")
abstol(ac$recommendation$level1$composite_separation, 9.4637, 1e-2,
       "separación del compuesto (descriptiva, ya no decide)")
# Exponencial: peor ajuste (A=0) y mejor parsimonia (B=100) -> composite exacto 30.
ex <- by_id(ac$ranking, "exponential")
abstol(ex$pillar_scores$A, 0.0, 0.5, "exponential: pilar A = 0 (peor ajuste)")
abstol(ex$composite, 30.0, 0.1, "exponential: composite = 0.7*0 + 0.3*100 = 30")

# ------------------------------------------------------------
# 3. Ranking relativo (discreta)
# ------------------------------------------------------------
cat("\n-- 3. Ranking discreta --\n")
ad <- dist_fit_analyze(data.frame(count = xd), "count")$assessment
check(ad$family == "discrete",                  "assessment: familia discreta")
check(length(ad$ranking) == 3L,                 "assessment: 3 candidatas discretas")
check(ad$ranking[[1]]$id == "negative_binomial",
      "ranking discreta: top = binomial negativa (sobredispersión)")
abstol(ad$ranking[[1]]$composite, 70.0, 0.5, "negbin: composite = 70")
abstol(by_id(ad$ranking, "poisson")$composite, 30.0, 0.5, "poisson: composite = 30")
# ADR-021: con n = 15 la binomial negativa gana por compuesto, pero por AIC la
# Poisson es ligeramente mejor (ΔAIC = -1.13). Son indistinguibles: confianza
# baja. La regla anterior daba "alta" leyendo una separación de compuesto (~40)
# que solo reflejaba la escala min-máx de tres candidatas, no la evidencia.
check(ad$recommendation$level1$confidence == "baja",
      "confianza = baja (ΔAIC = -1.13: negbin y Poisson indistinguibles con n=15)")

# ------------------------------------------------------------
# 4. Piezas diferidas explícitas (alcance B4)
# ------------------------------------------------------------
cat("\n-- 4. Diferidos --\n")
check(all(c("absolute_categories","evt_detection","level2_use_case","stability")
          %in% names(ac$deferred)),
      "assessment: EVT, Nivel 2 y estabilidad marcados como diferidos")

cat("\nB4 UNIT TESTS SUPERADOS\n")
