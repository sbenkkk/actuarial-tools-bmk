# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b2_2_unit_tests.R
# Tests unitarios de B2.2: Método de los Momentos, L-momentos y selección AUTO.
# Referencias calculadas de forma independiente con NumPy/SciPy sobre datasets
# fijos (continua con decimales, discreta con enteros — CONV-001).
# Autor: BMK — Última actualización: 2026-07-25
# ============================================================
#
#   Rscript tests/b2_2_unit_tests.R      # desde la raíz de la herramienta
#   Rscript b2_2_unit_tests.R            # desde la carpeta tests/

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

cat("== B2.2 UNIT TESTS (MoM + L-momentos + AUTO) — distribution-fitting ==\n")

xc <- c(120.3, 340.7, 550.1, 610.4, 800.9, 1200.2, 1500.6, 2100.8, 2600.5, 3400.1, 5200.7, 9800.4)
xd <- c(0, 1, 0, 2, 1, 3, 0, 1, 2, 4, 1, 0, 2, 1, 5)

# ------------------------------------------------------------
# 1. Método de los Momentos (continua)
# ------------------------------------------------------------
cat("\n-- 1. MoM (continua) --\n")
rm  <- dist_fit_analyze(data.frame(loss_amount = xc), "loss_amount", method = "mom")
fm  <- rm$motor$fits; cm <- rm$motor$control_fits
check(rm$motor$method == "mom",                       "motor: método solicitado = mom")
check(fm$gamma$method == "mom" && fm$gamma$method_reason == "solicitado",
      "cada ajuste registra method='mom' y motivo")
rel(fm$exponential$params$rate, 0.0004251445, 1e-5,   "MoM exponential: rate")
rel(cm$normal$params$mean, 2352.141667, 1e-6,         "MoM normal (control): media")
rel(cm$normal$params$sd,   2654.875773, 1e-6,         "MoM normal (control): sd")
rel(fm$lognormal$params$meanlog, 7.352316, 1e-5,      "MoM lognormal: meanlog")
rel(fm$lognormal$params$sdlog,   0.906383, 1e-5,      "MoM lognormal: sdlog")
rel(fm$gamma$params$shape,   0.784944, 1e-5,          "MoM gamma: shape")
rel(fm$gamma$params$scale,   2996.573494, 1e-5,       "MoM gamma: scale")
rel(fm$weibull$params$shape, 0.887936, 1e-4,          "MoM weibull: shape (uniroot)")
rel(fm$weibull$params$scale, 2218.789286, 1e-4,       "MoM weibull: scale")
rel(fm$loglogistic$params$shape, 2.561352, 1e-4,      "MoM loglogistic: shape (beta>2)")
rel(fm$loglogistic$params$scale, 1805.189267, 1e-4,   "MoM loglogistic: scale")
rel(fm$pareto$params$shape, 9.299893, 1e-5,           "MoM pareto: shape (CV^2>1)")
rel(fm$pareto$params$scale, 19522.523965, 1e-5,       "MoM pareto: scale")
check(!isTRUE(fm$burr$converged) && fm$burr$method_reason == "método no disponible",
      "MoM burr: marcado no disponible (sin MoM en v1)")

# ------------------------------------------------------------
# 2. L-momentos (continua; solo donde procede)
# ------------------------------------------------------------
cat("\n-- 2. L-momentos --\n")
rl <- dist_fit_analyze(data.frame(loss_amount = xc), "loss_amount", method = "lmom")
fl <- rl$motor$fits; cl <- rl$motor$control_fits
check(rl$motor$method == "lmom",                      "motor: método solicitado = lmom")
rel(fl$exponential$params$rate, 0.0004251445, 1e-5,   "Lmom exponential: rate")
rel(cl$normal$params$mean, 2352.141667, 1e-6,         "Lmom normal (control): media = l1")
rel(cl$normal$params$sd,   2475.012932, 1e-5,         "Lmom normal (control): sd = sqrt(pi)*l2")
rel(fl$pareto$params$shape, 3.169180, 1e-4,           "Lmom pareto: alpha (GPD->Lomax)")
rel(fl$pareto$params$scale, 5102.217559, 1e-4,        "Lmom pareto: scale")
check(!isTRUE(fl$gamma$converged) && fl$gamma$method_reason == "método no disponible",
      "Lmom gamma: no disponible en v1 (diferido)")

# ------------------------------------------------------------
# 3. Selección AUTO (opt-in): MLE-first
# ------------------------------------------------------------
cat("\n-- 3. AUTO --\n")
ra <- dist_fit_analyze(data.frame(loss_amount = xc), "loss_amount", method = "auto")
fa <- ra$motor$fits
check(ra$motor$method == "auto",                      "motor: método solicitado = auto")
check(fa$gamma$method == "mle" && isTRUE(fa$gamma$converged),
      "AUTO: gamma se ajusta por MLE (convergió)")
check(grepl("^AUTO", fa$gamma$method_reason),         "AUTO: registra el motivo de la elección")
# Consistencia numérica: AUTO(=MLE) reproduce el MLE de B2.1.
rel(fa$gamma$logLik, -105.146828, 1e-3,               "AUTO gamma: logLik = MLE")

# ------------------------------------------------------------
# 4. MoM (discreta)
# ------------------------------------------------------------
cat("\n-- 4. MoM (discreta) --\n")
rd <- dist_fit_analyze(data.frame(count = xd), "count", method = "mom")
fd <- rd$motor$fits
rel(fd$poisson$params$lambda, 1.533333, 1e-5,         "MoM poisson: lambda")
rel(fd$geometric$params$prob, 0.394737, 1e-4,         "MoM geometric: prob")
rel(fd$negative_binomial$params$mu,   1.533333, 1e-5, "MoM negbin: mu = media")
rel(fd$negative_binomial$params$size, 4.038168, 1e-4, "MoM negbin: size (var>media)")

# ------------------------------------------------------------
# 5. El método por defecto sigue siendo MLE (tests congelados)
# ------------------------------------------------------------
cat("\n-- 5. Default = MLE --\n")
rdef <- dist_fit_analyze(data.frame(loss_amount = xc), "loss_amount")
check(rdef$motor$method == "mle",                     "default: motor$method = 'mle' (sin cambios de contrato)")

cat("\nB2.2 UNIT TESTS SUPERADOS\n")
