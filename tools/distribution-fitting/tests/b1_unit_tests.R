# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b1_unit_tests.R
# Tests unitarios de B1 (manual, no testthat): profiler, detector y selector.
# Datasets pequeños y deterministas. calc.R es puro (sin Shiny ni framework).
# Autor: BMK — Última actualización: 2026-07-25
# ============================================================
#
# Ejecutable con independencia del working directory (localiza su propia ruta):
#   Rscript tests/b1_unit_tests.R      # desde la raíz de la herramienta
#   Rscript b1_unit_tests.R            # desde la carpeta tests/
#   source("tests/b1_unit_tests.R")    # en una sesión de R

# --- Carga robusta de calc.R (independiente del working directory) -----------
# Localiza la ruta de ESTE script y resuelve la raíz de la herramienta desde su
# ubicación, no desde el directorio de trabajo. Cubre Rscript (argumento
# --file=) y source() (campo ofile de los frames de llamada).
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

# Raíz de la herramienta: el script vive en <raíz>/tests/, luego la raíz es el
# directorio padre de la carpeta del script. Fallbacks por si no hay ruta (p. ej.
# pegar el código en una consola): probar el wd y su carpeta padre.
.tool_root <- local({
  script <- .locate_script()
  if (!is.null(script)) {
    dirname(dirname(script))
  } else if (file.exists("R/calc.R")) {
    normalizePath(".")
  } else if (file.exists(file.path("..", "R", "calc.R"))) {
    normalizePath("..")
  } else {
    stop("No se pudo localizar la raíz de la herramienta para cargar R/calc.R.",
         call. = FALSE)
  }
})

source(file.path(.tool_root, "R", "calc.R"))

check <- function(cond, msg) {
  if (!isTRUE(cond)) stop(sprintf("FALLO: %s", msg), call. = FALSE)
  cat(sprintf("  OK  - %s\n", msg))
}
within_tol <- function(actual, ref, tol, msg) {
  ok <- is.finite(actual) && abs(actual - ref) <= tol
  check(ok, sprintf("%s  (%.6f ~ %.6f +/- %g)", msg, actual, ref, tol))
}
TOL <- 1e-6

cat("== B1 UNIT TESTS — distribution-fitting ==\n")

# ------------------------------------------------------------
# 1. PROFILER
# ------------------------------------------------------------
cat("\n-- 1. Profiler --\n")

# Dataset continuo con un NA.
xa <- c(2.5, 3.1, NA, 10.2, 4.4)
pa <- profile_dataset(xa, "loss_amount")

check(pa$variable == "loss_amount",           "profiler: conserva el nombre de la variable")
check(pa$n == 5L,                             "profiler: n cuenta también los NA (5)")
check(pa$n_valid == 4L,                       "profiler: n_valid excluye NA (4)")
within_tol(pa$pct_na, 0.2, TOL,               "profiler: pct_na = 1/5")
within_tol(pa$pct_zeros, 0, TOL,              "profiler: pct_zeros = 0")
within_tol(pa$pct_negatives, 0, TOL,          "profiler: pct_negatives = 0")
within_tol(pa$min, 2.5, TOL,                  "profiler: min")
within_tol(pa$max, 10.2, TOL,                 "profiler: max")
within_tol(pa$mean, 5.05, TOL,                "profiler: media")
within_tol(pa$median, 3.75, TOL,              "profiler: mediana")
within_tol(pa$sd, 3.5237292, 1e-6,            "profiler: desviación típica (muestral)")
within_tol(pa$cv, 3.5237292 / 5.05, 1e-6,     "profiler: coeficiente de variación")
check(pa$n_unique == 4L,                       "profiler: nº de valores únicos")
check(pa$support == "positive",                "profiler: soporte positivo (>0)")
check(pa$variable_type == "continuous",        "profiler: tipo continuo (valores no enteros)")

# Asimetría y curtosis sobre conjunto simétrico conocido.
ps <- profile_dataset(c(1, 2, 3, 4, 5), "x")
within_tol(ps$skewness, 0, 1e-9,              "profiler: asimetría = 0 (conjunto simétrico)")
within_tol(ps$kurtosis, -1.3, TOL,            "profiler: exceso de curtosis = -1.3")

pr <- profile_dataset(c(1, 1, 1, 1, 10), "x")
check(pr$skewness > 0,                         "profiler: asimetría > 0 (sesgo a la derecha)")

# ------------------------------------------------------------
# 2. VARIABLE TYPE DETECTOR
# ------------------------------------------------------------
cat("\n-- 2. Detector --\n")

check(detect_variable_type(c(2.5, 3.1, 4.4)) == "continuous",
      "detector: valores no enteros -> continua")
check(detect_variable_type(c(0, 1, 2, 2, 3, 5)) == "discrete",
      "detector: enteros no negativos -> discreta")
check(detect_variable_type(c(-1, 0, 2, 3)) == "continuous",
      "detector: enteros con negativo -> continua (no es recuento)")
check(detect_variable_type(c(1000, 2000, 3000)) == "discrete",
      "detector: enteros grandes, pocos únicos -> discreta")

# Refinamiento 'pocos valores distintos', CALIBRADO a 50 en ADR-020.
cfg <- dfit_default_config(); cfg$discrete_max_unique <- 3
check(detect_variable_type(c(0, 1, 2, 3, 4, 5), cfg) == "continuous",
      "detector: discrete_max_unique=3 reclasifica 6 únicos como continua")
check(detect_variable_type(c(0, 1, 2, 3, 4, 5)) == "discrete",
      "detector: por defecto (50) los mismos datos son discretos")

# ADR-020: una severidad en euros redondeada a entero cumple la regla §3.3 pero
# NO es un recuento. Con 200 valores casi todos distintos debe salir continua.
set.seed(20)
importes <- round(stats::rlnorm(200, meanlog = 9, sdlog = 0.8))
check(length(unique(importes)) > dfit_default_config()$discrete_max_unique,
      "detector: el caso de prueba supera el umbral de valores distintos")
check(detect_variable_type(importes) == "continuous",
      "detector (ADR-020): enteros con >50 valores distintos -> continua")
cfg_off <- dfit_default_config(); cfg_off$discrete_max_unique <- Inf
check(detect_variable_type(importes, cfg_off) == "discrete",
      "detector: con el umbral desactivado (Inf) vuelve al comportamiento anterior")

# ------------------------------------------------------------
# 3. CANDIDATE DISTRIBUTION SELECTOR
# ------------------------------------------------------------
cat("\n-- 3. Selector --\n")

cont <- select_candidate_distributions("continuous")
check(cont$family == "continuous",             "selector: familia continua")
check(identical(cont$distributions,
      c("exponential", "gamma", "weibull", "lognormal", "loglogistic", "pareto", "burr")),
      "selector: 7 candidatas continuas del §4.1 en orden")
check(identical(cont$control, "normal"),       "selector: Normal como control (§4.3)")

disc <- select_candidate_distributions("discrete")
check(disc$family == "discrete",               "selector: familia discreta")
check(identical(disc$distributions,
      c("poisson", "negative_binomial", "geometric")),
      "selector: 3 candidatas discretas del §4.2 en orden")
check(is.null(disc$control),                   "selector: sin control en discreta")

# ------------------------------------------------------------
# 4. ORCHESTRATOR (cableado: capas posteriores = stubs)
# ------------------------------------------------------------
cat("\n-- 4. Orchestrator (wiring) --\n")

df  <- data.frame(loss_amount = c(2.5, 3.1, 10.2, 4.4, 7.0))
res <- dist_fit_analyze(df, "loss_amount")

check(res$profile$variable_type == "continuous",   "orchestrator: perfila y enruta a continua")
check(res$candidates$family == "continuous",       "orchestrator: selecciona familia continua")
check(res$meta$block == "B2.1",                     "orchestrator: meta marca el bloque implementado (B2.1)")
check(res$meta$decision_engine_version == "0.2",    "orchestrator: expone decision_engine_version (0.2, ADR-021)")
check(res$motor$method == "mle" && length(res$motor$fits) == 7L,
      "orchestrator: el motor MLE ajusta las 7 candidatas continuas (B2)")
check(res$view_model$status == "pending" && res$view_model$block == "B6",
      "orchestrator: capa view_model sigue como stub pendiente (B6)")

# Modo manual: forzar familia discreta sobre datos continuos.
res_m <- dist_fit_analyze(df, "loss_amount", mode = "manual", family = "discrete")
check(res_m$candidates$family == "discrete",        "orchestrator: modo manual fuerza la familia")

cat("\nB1 UNIT TESTS SUPERADOS\n")
