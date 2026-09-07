# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b2_unit_tests.R
# Tests unitarios de B2.1 (motor MLE): recuperación de parámetros y logLik.
# Los valores de referencia se han calculado de forma independiente con scipy
# (fórmulas verificadas a precisión de máquina). Datasets fijos y deterministas.
# Autor: BMK — Última actualización: 2026-07-25
# ============================================================
#
# Ejecutable con independencia del working directory:
#   Rscript tests/b2_unit_tests.R      # desde la raíz de la herramienta
#   Rscript b2_unit_tests.R            # desde la carpeta tests/

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
rel <- function(actual, ref, reltol, msg) {
  ok <- is.finite(actual) && abs(actual - ref) <= reltol * abs(ref)
  check(ok, sprintf("%s  (%.6g ~ %.6g, rel<=%g)", msg, actual, ref, reltol))
}
abstol <- function(actual, ref, tol, msg) {
  ok <- is.finite(actual) && abs(actual - ref) <= tol
  check(ok, sprintf("%s  (%.6f ~ %.6f +/- %g)", msg, actual, ref, tol))
}

cat("== B2.1 UNIT TESTS (motor MLE) — distribution-fitting ==\n")

# Datasets fijos (idénticos a los usados con scipy para las referencias).
# Continua INEQUÍVOCA: valores no enteros, para no depender de la lógica de
# detección de tipo (una continua no se prueba solo con enteros).
xc <- c(120.3, 340.7, 550.1, 610.4, 800.9, 1200.2, 1500.6, 2100.8, 2600.5, 3400.1, 5200.7, 9800.4)
# Discreta: recuentos (enteros no negativos).
xd <- c(0, 1, 0, 2, 1, 3, 0, 1, 2, 4, 1, 0, 2, 1, 5)

res_c <- dist_fit_analyze(data.frame(loss_amount = xc), "loss_amount")
fits  <- res_c$motor$fits
ctrl  <- res_c$motor$control_fits

# ------------------------------------------------------------
# 1. Estructura del motor
# ------------------------------------------------------------
cat("\n-- 1. Estructura --\n")
check(res_c$motor$method == "mle",                 "motor: método MLE")
check(res_c$motor$family == "continuous",          "motor: familia continua")
check(length(fits) == 7L,                          "motor: 7 ajustes de candidatas")
check(identical(names(fits),
      c("exponential","gamma","weibull","lognormal","loglogistic","pareto","burr")),
      "motor: ids de candidatas en orden")
check(!is.null(ctrl$normal) && ctrl$normal$role == "control",
      "motor: Normal ajustada como control")
f <- fits$gamma
check(all(c("id","label","method","params","logLik","converged","n_used","n_excluded")
          %in% names(f)),
      "motor: cada ajuste expone los campos del contrato")

# ------------------------------------------------------------
# 2. Parámetros en forma cerrada (exacto)
# ------------------------------------------------------------
cat("\n-- 2. Formas cerradas --\n")
rel(fits$exponential$params$rate, 0.0004251445, 1e-5, "exponential: rate = 1/media")
rel(fits$lognormal$params$meanlog, 7.152219, 1e-5,   "lognormal: meanlog")
rel(fits$lognormal$params$sdlog,   1.178469, 1e-5,   "lognormal: sdlog")
rel(ctrl$normal$params$mean, 2352.141667, 1e-6,      "normal (control): media")
rel(ctrl$normal$params$sd,   2654.875773, 1e-6,      "normal (control): sd (poblacional)")

# ------------------------------------------------------------
# 3. logLik frente a referencia scipy (todas las continuas)
# ------------------------------------------------------------
cat("\n-- 3. logLik vs scipy --\n")
abstol(fits$exponential$logLik, -105.156978, 0.02, "logLik exponential")
abstol(fits$gamma$logLik,       -105.146828, 0.05, "logLik gamma")
abstol(fits$weibull$logLik,     -105.109709, 0.05, "logLik weibull")
abstol(fits$lognormal$logLik,   -104.824476, 0.02, "logLik lognormal")
abstol(fits$loglogistic$logLik, -105.076032, 0.10, "logLik loglogistic")
abstol(fits$pareto$logLik,      -105.028853, 0.15, "logLik pareto (cresta plana)")
abstol(ctrl$normal$logLik,      -111.637100, 0.02, "logLik normal (control)")

# ------------------------------------------------------------
# 4. Parámetros optim bien identificados + candidatas robustas
# ------------------------------------------------------------
cat("\n-- 4. Parámetros optim --\n")
rel(fits$gamma$params$shape,       0.950629, 0.02, "gamma: shape")
rel(fits$gamma$params$scale,    2474.299479, 0.02, "gamma: scale")
rel(fits$weibull$params$shape,     0.936041, 0.03, "weibull: shape")
rel(fits$weibull$params$scale,  2275.603363, 0.03, "weibull: scale")
rel(fits$loglogistic$params$shape, 1.458080, 0.05, "loglogistic: shape")
rel(fits$loglogistic$params$scale, 1307.427045, 0.05, "loglogistic: scale")
# Pareto (cresta) y Burr (débilmente identificada con n pequeño): solo sanidad.
check(is.finite(fits$pareto$logLik) && fits$pareto$params$shape > 0,
      "pareto: ajuste finito con parámetros positivos")
check(is.finite(fits$burr$logLik) && fits$burr$params$shape1 > 0 &&
        fits$burr$params$shape2 > 0 && fits$burr$converged,
      "burr: ajuste finito, parámetros positivos, converge")

# ------------------------------------------------------------
# 5. Familia discreta
# ------------------------------------------------------------
cat("\n-- 5. Discreta --\n")
res_d <- dist_fit_analyze(data.frame(count = xd), "count")
fd <- res_d$motor$fits
check(res_d$motor$family == "discrete",            "discreta: familia detectada")
check(identical(names(fd), c("poisson","negative_binomial","geometric")),
      "discreta: 3 candidatas")
rel(fd$poisson$params$lambda, 1.533333, 1e-5,      "poisson: lambda = media")
rel(fd$geometric$params$prob, 0.394737, 1e-4,      "geometric: prob = 1/(1+media)")
rel(fd$negative_binomial$params$mu, 1.533333, 1e-5, "negbin: mu = media")
rel(fd$negative_binomial$params$size, 3.790948, 0.03, "negbin: size (MLE)")
abstol(fd$poisson$logLik,           -25.005534, 0.02, "logLik poisson")
abstol(fd$geometric$logLik,         -25.491154, 0.02, "logLik geometric")
abstol(fd$negative_binomial$logLik, -24.570337, 0.02, "logLik negbin")

# ------------------------------------------------------------
# 6. Tratamiento de ceros (§3.5) — CONTRATO ACTUALIZADO POR ADR-026
# ------------------------------------------------------------
# Contrato anterior: cada distribución recortaba la muestra según su propio
# soporte, de modo que la exponencial conservaba los ceros mientras las
# estrictamente positivas los excluían. Ese contrato es exactamente el que hacía
# que el ranking comparase AIC/BIC y bondad de ajuste entre muestras distintas
# (hallazgo H2). ADR-026 lo sustituye: la muestra se restringe UNA vez, antes del
# Motor, a la intersección de soportes de las candidatas. Este test se alinea con
# el contrato nuevo; no se relaja para hacerlo pasar.
cat("\n-- 6. Ceros: muestra común (ADR-026) --\n")
xz <- c(0, 120.3, 340.7, 800.9, 2100.8, 5200.7)   # un cero + continuos no enteros
res_z <- dist_fit_analyze(data.frame(loss_amount = xz), "loss_amount")
fz <- res_z$motor$fits
check(res_z$sample$n_input == 6L && res_z$sample$n_used == 5L &&
        res_z$sample$n_excluded_zeros == 1L && isTRUE(res_z$sample$requires_positive),
      "ceros: la exclusión se registra UNA vez en analysis$sample (1 cero de 6)")
check(length(unique(vapply(fz, function(f) f$n_used, numeric(1)))) == 1L &&
        fz$exponential$n_used == 5L,
      "ceros: las 7 candidatas comparten muestra; la exponencial ya NO conserva el 0")
check(res_z$motor$control_fits$normal$n_used == 5L,
      "ceros: el control Normal usa la misma muestra común que las candidatas")
check(all(vapply(fz, function(f) f$n_excluded$zeros, numeric(1)) == 0L),
      "ceros: fit$n_excluded queda vestigial (0), se conserva por compatibilidad")

cat("\nB2.1 UNIT TESTS SUPERADOS\n")
