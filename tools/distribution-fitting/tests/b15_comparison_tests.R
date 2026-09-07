# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b15_comparison_tests.R
# Tests productivos de B15: comparación DESCRIPTIVA analítico vs bootstrap.
#
# B15 no hace inferencia nueva: consume B14 —que consume B12 y B13—, organiza
# y describe. No introduce puntuaciones de acuerdo, etiquetas de estabilidad,
# umbrales ni selección automática de método.
#
# Autor: BMK — Última actualización: 2026-09-03
# ============================================================
#
#   Rscript tools/distribution-fitting/tests/b15_comparison_tests.R

.locate_script <- function() {
  fa <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(fa) > 0) return(normalizePath(sub("^--file=", "", fa[1]), mustWork = FALSE))
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
  else stop("No se pudo localizar la raiz de la herramienta.", call. = FALSE)
})
source(file.path(.tool_root, "R", "calc.R"))

check <- function(cond, msg) {
  if (!isTRUE(cond)) stop(sprintf("FALLO: %s", msg), call. = FALSE)
  cat(sprintf("  OK  - %s\n", msg))
}

cat("== B15 — COMPARACIÓN DESCRIPTIVA ANALÍTICO vs BOOTSTRAP ==\n")

SEED <- 20260903L

# ---- material REAL, no sintético: dos parámetros para probar el orden -------
set.seed(21L)
xn <- stats::rnorm(500L, 100, 15)
fn <- .estimate("normal", xn, "mle")
PE <- list(params = fn$params, estimator = "mle", distribution = "normal")
ANA <- .mle_uncertainty(c(list(id = "normal", method = "mle", converged = TRUE,
                               message = NA_character_), fn), xn)
BOO <- .bootstrap_estimator(xn, .bootstrap_adapter_fit("normal", "mle"),
                            B = 120L, seed = SEED, theta_hat = fn$params,
                            estimator = "mle", distribution = "normal")
check(isTRUE(ANA$valid) && isTRUE(BOO$valid), "material de partida: B12 y B13 válidos")

V_both <- .validate_estimator(PE, ANA, BOO)
check(identical(V_both$comparability$sample_identity_verified, TRUE),
      "B14 verifica la identidad de muestra sobre el material real (OD-18)")

# ------------------------------------------------------------
# A-F. ESTADOS DE COMPARACIÓN
# ------------------------------------------------------------
cat("\n-- A-F. Estados --\n")

cA <- .compare_uncertainty(V_both)
check(identical(cA$comparison_status, "available"),
      "A. analítico + bootstrap + misma huella -> available")
check(isTRUE(cA$sample_identity_verified), "A.2 identidad verificada propagada")

cB <- .compare_uncertainty(.validate_estimator(PE, ANA, NULL))
check(identical(cB$comparison_status, "analytic_only"), "B. solo analítico")

cC <- .compare_uncertainty(.validate_estimator(PE, NULL, BOO))
check(identical(cC$comparison_status, "bootstrap_only"), "C. solo bootstrap")

cD <- .compare_uncertainty(.validate_estimator(PE, NULL, NULL))
check(identical(cD$comparison_status, "point_only"), "D. ninguna vía -> point_only")

# E. ambas vías pero identidad NO verificable (huella legacy ausente).
ana_legacy <- ANA; ana_legacy$sample <- NULL
V_leg <- .validate_estimator(PE, ana_legacy, BOO)
cE <- .compare_uncertainty(V_leg)
check(identical(cE$comparison_status, "not_comparable"),
      "E. ambas vías sin identidad verificable -> not_comparable")
check(identical(V_leg$analytic$status, "complete") &&
      identical(V_leg$bootstrap$status, "complete"),
      "E.2 not_comparable NO implica que ninguna vía sea incorrecta")
check(!isTRUE(cE$sample_identity_verified) &&
      identical(cE$sample_identity_status, "not_verifiable"),
      "E.3 el motivo se propaga desde B14")

# F. incompatibilidad contractual real detectada por B14.
boo_bad <- BOO; boo_bad$parameter_names <- c("otro1", "otro2")
cF <- .compare_uncertainty(.validate_estimator(PE, ANA, boo_bad))
check(identical(cF$comparison_status, "incompatible"),
      "F. incompatibilidad contractual de B14 -> incompatible")
check(any(grepl("contract incompatibility", cF$diagnostics)),
      "F.2 el diagnóstico cita la incompatibilidad de B14")

# Catálogo cerrado: no se inventan estados.
for (o in list(cA, cB, cC, cD, cE, cF)) {
  check(o$comparison_status %in% DFIT_COMPARISON_STATUS,
        sprintf("A-F catálogo cerrado: '%s'", o$comparison_status))
}
check(length(DFIT_COMPARISON_STATUS) == 6L, "A-F el catálogo tiene 6 estados, sin ampliar")

# `same_sample_n` NO se usa como prueba de identidad.
check(identical(V_leg$comparability$same_sample_n, TRUE) &&
      identical(cE$comparison_status, "not_comparable"),
      "E.4 same_sample_n = TRUE NO basta para 'available'")

# ------------------------------------------------------------
# G-H. ORDEN E IDENTIDAD DE PARÁMETROS
# ------------------------------------------------------------
cat("\n-- G-H. Parámetros --\n")

check(identical(cA$parameters$parameter, c("mean", "sd")),
      "G. orden oficial de parámetros preservado")
check(identical(cA$parameters$parameter, names(V_both$parameters)),
      "G.2 el orden es el del objeto B14, no un reordenamiento propio")
check(nrow(cA$parameters) == 2L, "G.3 una fila por parámetro")
check(identical(cF$comparison_status, "incompatible"),
      "H. nombres discrepantes -> incompatible, sin reordenar en silencio")

# ------------------------------------------------------------
# I-J. VALORES COPIADOS EXACTAMENTE
# ------------------------------------------------------------
cat("\n-- I-J. Copia exacta --\n")

for (j in seq_len(2L)) {
  nm <- cA$parameters$parameter[j]
  p  <- V_both$parameters[[nm]]
  check(identical(cA$parameters$analytic_se[j], p$analytic$se) &&
        identical(cA$parameters$analytic_ci_lower[j], p$analytic$ci_lower) &&
        identical(cA$parameters$analytic_ci_upper[j], p$analytic$ci_upper),
        sprintf("I. %s: SE/IC analíticos copiados EXACTAMENTE desde B12/B14", nm))
  check(identical(cA$parameters$analytic_se[j], ANA$parameters[[nm]]$se),
        sprintf("I.2 %s: coinciden con el bloque original de B12", nm))
  check(identical(cA$parameters$bootstrap_se[j], p$bootstrap$se) &&
        identical(cA$parameters$bootstrap_ci_lower[j], p$bootstrap$ci_lower),
        sprintf("J. %s: SE/IC bootstrap copiados EXACTAMENTE desde B13/B14", nm))
  check(identical(cA$parameters$bootstrap_se[j], unname(BOO$se[[nm]])),
        sprintf("J.2 %s: coinciden con el bloque original de B13", nm))
}
check(all(cA$parameters$analytic_available) && all(cA$parameters$bootstrap_available),
      "I-J ambas vías marcadas como disponibles")

# ------------------------------------------------------------
# K. ESTIMACIÓN PUNTUAL INTACTA
# ------------------------------------------------------------
cat("\n-- K. Estimación puntual --\n")

check(identical(cA$parameters$estimate, unname(unlist(fn$params))),
      "K. el point estimate es EXACTAMENTE el oficial")
check(!identical(cA$parameters$estimate[1], mean(BOO$replicates[, "mean"])),
      "K.2 no se sustituye por la media bootstrap")
check(!any(grepl("bias", names(cA$parameters))),
      "K.3 el sesgo bootstrap no entra en la tabla de B15")

# ------------------------------------------------------------
# L. NIVELES DE CONFIANZA
# ------------------------------------------------------------
cat("\n-- L. Niveles de confianza --\n")

check(identical(cA$confidence_levels$analytic, ANA$confidence_level) &&
      identical(cA$confidence_levels$bootstrap, BOO$confidence_level),
      "L. niveles propagados verbatim")
check(isTRUE(cA$confidence_levels$same), "L.2 diagnóstico de B14 propagado")
boo90 <- BOO; boo90$confidence_level <- 0.90
V90 <- .validate_estimator(PE, ANA, boo90)
c90 <- .compare_uncertainty(V90)
check(identical(c90$confidence_levels$analytic, 0.95) &&
      identical(c90$confidence_levels$bootstrap, 0.90),
      "L.3 niveles distintos: se preservan AMBOS, sin armonizar")
check(identical(c90$confidence_levels$same, FALSE) &&
      any(grepl("confidence levels differ", c90$diagnostics)),
      "L.4 se respeta el diagnóstico de B14")
check(identical(c90$parameters$analytic_ci_lower, cA$parameters$analytic_ci_lower),
      "L.5 los intervalos NO se recalculan para igualar niveles")

# ------------------------------------------------------------
# M. CONTADORES BOOTSTRAP
# ------------------------------------------------------------
cat("\n-- M. Contadores bootstrap --\n")

for (f in c("B_requested", "B_success", "B_failed", "success_rate")) {
  check(identical(cA$bootstrap_counts[[f]], BOO[[f]]),
        sprintf("M. %s preservado", f))
}
check(any(grepl("r.plicas v.lidas", cA$limitations)),
      "M.2 la advertencia neutral de OD-17 se propaga desde B14")
lim_txt <- paste(cA$limitations, collapse = " ")
for (w in c("estrech", "ensanch", "subestim", "sobreestim")) {
  check(!grepl(w, lim_txt), sprintf("M.3 sin dirección de sesgo ('%s')", w))
}

# ------------------------------------------------------------
# N. SIN MÉTRICAS AUTOMÁTICAS
# ------------------------------------------------------------
cat("\n-- N. Ninguna métrica automática --\n")

body_txt <- deparse(.compare_uncertainty)
prohibidos <- c("agreement", "concordance", "stability", "score", "threshold",
                "umbral", "overlap", "semaforo", "traffic",
                "good", "moderate", "poor", "reliable", "unstable",
                "recommend", "bca", "bootstrap_t", "coverage")
for (w in prohibidos) {
  check(!any(grepl(w, body_txt, ignore.case = TRUE)),
        sprintf("N. el código de B15 no menciona '%s'", w))
  check(!any(grepl(w, c(names(cA), names(cA$parameters)), ignore.case = TRUE)),
        sprintf("N.2 la salida de B15 no expone ningún campo '%s'", w))
}
# Tampoco se calculan cocientes ni diferencias entre vías.
for (op in c("se_ratio", "ci_width", "relative_diff", "difference")) {
  check(!any(grepl(op, names(cA$parameters), ignore.case = TRUE)),
        sprintf("N.3 la tabla no contiene '%s'", op))
}
check(ncol(cA$parameters) == 12L,
      "N.4 la tabla tiene exactamente las 12 columnas descriptivas")
for (o in list(cA, cB, cC, cD, cE)) {
  txt <- paste(o$diagnostics, collapse = " ")
  for (w in c("agree", "reliable", "stable", "sufficiently", "better")) {
    check(!grepl(w, txt, ignore.case = TRUE),
          sprintf("N.5 los diagnósticos no interpretan calidad ('%s')", w))
  }
}

# ------------------------------------------------------------
# CASOS DE UNA SOLA VÍA (§5): la tabla sigue siendo útil
# ------------------------------------------------------------
cat("\n-- Una sola vía --\n")

check(nrow(cB$parameters) == 2L && all(cB$parameters$analytic_available) &&
      !any(cB$parameters$bootstrap_available),
      "S1. analytic_only: tabla con SE/IC analíticos y bootstrap no disponible")
check(all(is.na(cB$parameters$bootstrap_se)),
      "S2. campos bootstrap a NA, no omitidos")
check(any(grepl("bootstrap uncertainty not calculated", cB$diagnostics)),
      "S3. diagnóstico descriptivo y contractual")

set.seed(23L)
xg  <- stats::rgamma(400L, shape = 2, scale = 500)
fpm <- .pm_fit("gamma", xg)
PEpm <- list(params = fpm$params, estimator = "pm", distribution = "gamma")
BOOpm <- .bootstrap_estimator(xg, .bootstrap_adapter_pm("gamma"), B = 80L,
                              seed = SEED, theta_hat = fpm$params,
                              estimator = "pm", distribution = "gamma")
cPM <- .compare_uncertainty(.validate_estimator(PEpm, NULL, BOOpm))
check(identical(cPM$comparison_status, "bootstrap_only"),
      "S4. PM: sin vía analítica aplicable -> bootstrap_only")
check(all(is.na(cPM$parameters$analytic_se)) &&
      !any(cPM$parameters$analytic_available),
      "S5. PM: campos analíticos a NA")
check(any(grepl("not applicable for estimator 'pm'", cPM$diagnostics)),
      "S6. PM: el diagnóstico distingue 'no aplicable' de 'fallido'")
check(identical(cPM$parameters$parameter, c("shape", "scale")),
      "S7. PM: orden de parámetros preservado")

# ------------------------------------------------------------
# O-R. AISLAMIENTO
# ------------------------------------------------------------
cat("\n-- O-R. Aislamiento --\n")

ANA2 <- .mle_uncertainty(c(list(id = "normal", method = "mle", converged = TRUE,
                                message = NA_character_), fn), xn)
check(identical(ANA2, ANA), "O. B12 idéntico antes y después de B15")
BOO2 <- .bootstrap_estimator(xn, .bootstrap_adapter_fit("normal", "mle"),
                             B = 120L, seed = SEED, theta_hat = fn$params,
                             estimator = "mle", distribution = "normal")
check(identical(BOO2$replicates, BOO$replicates) && identical(BOO2$ci, BOO$ci) &&
      identical(BOO2$se, BOO$se),
      "P. B13 idéntico antes y después de B15")
check(identical(.validate_estimator(PE, ANA, BOO), V_both),
      "P.2 B14 idéntico antes y después de B15")

set.seed(29L)
df <- data.frame(coste = stats::rgamma(600L, shape = 2, scale = 500))
res <- dist_fit_analyze(df, "coste")
check(identical(res$motor$method, "mle") && !is.null(res$assessment) &&
      !is.null(res$decision_engine),
      "Q. AUTO, Assessment y Decision Engine intactos")
check(all(vapply(res$motor$fits, function(f) is.null(f$comparison), TRUE)) &&
      all(vapply(res$motor$fits, function(f) is.null(f$validation), TRUE)),
      "Q.2 el análisis por defecto no añade estructuras de B14/B15")
check(inherits(try(.motor(res$sample, res$candidates, method = "pm"), silent = TRUE),
               "try-error"),
      "Q.3 PM sigue fuera del ranking")
check(identical(DFIT_SCHEMA_VERSION, "1.1.0"), "R. schema sigue en 1.1.0")

# ------------------------------------------------------------
# PUREZA Y AVISOS
# ------------------------------------------------------------
cat("\n-- Pureza y avisos --\n")

check(identical(.compare_uncertainty(V_both), cA),
      "Z1. función determinista: misma entrada -> salida identical()")
for (fn_ in c("\\.estimate\\(", "\\.mle_uncertainty\\(", "\\.bootstrap_estimator\\(",
              "\\.pm_fit\\(", "\\.validate_estimator\\(", "\\.data_fingerprint\\(",
              "\\bsd\\(", "\\bquantile\\(", "\\bchol\\(", "\\bsolve\\(",
              "\\boptim\\(", "\\bsample\\(", "\\bqnorm\\(")) {
  check(!any(grepl(fn_, body_txt)),
        sprintf("Z2. B15 no recalcula: ausencia de %s",
                gsub("\\\\b|\\\\\\(|\\\\", "", fn_)))
}
r_null <- .compare_uncertainty(NULL)
check(is.list(r_null) && identical(r_null$comparison_status, "incompatible"),
      "Z3. entrada nula -> objeto auditable, sin error")

cap <- list()
withCallingHandlers({
  invisible(.compare_uncertainty(V_both))
  invisible(.compare_uncertainty(.validate_estimator(PE, NULL, NULL)))
  invisible(.compare_uncertainty(V_leg))
  invisible(.compare_uncertainty(.validate_estimator(PEpm, NULL, BOOpm)))
}, warning = function(w) { cap[[length(cap) + 1L]] <<- conditionMessage(w)
                           invokeRestart("muffleWarning") })
if (length(cap) > 0L) {
  cat("     avisos observados (CLASIFICAR):\n")
  for (m in unique(unlist(cap))) cat(sprintf("       - %s\n", m))
}
check(length(cap) == 0L, "Z4. sin avisos en el camino nominal")

cat("\nB15 — COMPARACIÓN DESCRIPTIVA VERIFICADA\n")
