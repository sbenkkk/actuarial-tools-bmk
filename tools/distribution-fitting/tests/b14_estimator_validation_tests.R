# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b14_estimator_validation_tests.R
# Tests productivos de B14.1: capa de validación del estimador.
#
# Verifica el contrato congelado en ADR-037:
#   B14 NO calcula inferencia: consume y organiza B12/B13 y valida coherencia.
#   Estado global DERIVADO de todos los ejes (I13); nunca de uno solo.
#   I15  bootstrap$valid == TRUE  <=>  global in {uncertainty_bootstrap, uncertainty_both}
#   OD-17 propagado verbatim; OD-18 nunca verificado por omisión (I16).
#
# Autor: BMK — Última actualización: 2026-09-03
# ============================================================
#
#   Rscript tools/distribution-fitting/tests/b14_estimator_validation_tests.R

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

cat("== B14.1 — CAPA DE VALIDACIÓN DEL ESTIMADOR ==\n")

SEED <- 20260903L

# ---- material real: se construye UNA vez y se reutiliza -------------------
set.seed(11L)
xe  <- stats::rexp(400L, 0.02)
fe  <- .estimate("exponential", xe, "mle")
PE  <- list(params = fe$params, estimator = "mle", distribution = "exponential")
ANA <- .mle_uncertainty(c(list(id = "exponential", method = "mle", converged = TRUE,
                               message = NA_character_), fe), xe)
BOO <- .bootstrap_estimator(xe, .bootstrap_adapter_fit("exponential", "mle"),
                            B = 100L, seed = SEED, theta_hat = fe$params,
                            estimator = "mle", distribution = "exponential")
check(isTRUE(ANA$valid) && isTRUE(BOO$valid), "material de partida: B12 y B13 válidos")

# Fabricadores de bloques bootstrap sintéticos, coherentes con el contrato B13.
mk_boot <- function(Bs, Bq = 100L, valid = NULL, names_ = "rate") {
  Bf <- Bq - Bs
  list(method = "nonparametric_bootstrap",
       status = if (Bs == 0L) "failed" else if (Bs >= 2L && Bf > 0L) "partial"
                else if (Bs >= 2L) "complete" else "partial",
       valid = if (is.null(valid)) (Bs >= 2L) else valid,
       reason = NA_character_,
       B_requested = Bq, B_success = Bs, B_failed = Bf,
       success_rate = Bs / Bq, seed = SEED, confidence_level = 0.95,
       quantile_type = 7L, estimator = "mle", distribution = "exponential",
       parameter_names = names_,
       # Identidad OD-18 COMPLETA y REAL: misma huella SHA-256 que el bloque
       # analítico, estado `complete` y algoritmo declarado. Los bloques
       # sintéticos deben ser coherentes con OD-18 para no contaminar con
       # `not_verifiable` los tests que no van de identidad de muestra.
       data_fingerprint = ANA$sample$fingerprint, fingerprint_algo = "sha256",
       fingerprint_status = "complete",
       n = length(xe),
       replicates = if (Bs > 0L) matrix(1, nrow = Bs, ncol = length(names_),
                                        dimnames = list(NULL, names_)) else NULL,
       se   = if (Bs >= 2L) stats::setNames(rep(0.001, length(names_)), names_) else NULL,
       bias = if (Bs >= 1L) stats::setNames(rep(1e-5, length(names_)), names_) else NULL,
       ci   = if (Bs >= 1L) matrix(c(0.018, 0.022), nrow = length(names_), ncol = 2L,
                                   dimnames = list(names_, c("lower", "upper"))) else NULL,
       ci_degenerate = (Bs < 2L),
       failures = list(counts = c(optimizer_failure = Bf), examples = list()),
       summaries_conditional_on_success = TRUE, warnings = character(0))
}

# ------------------------------------------------------------
# A. FUNCIÓN PURA Y SHINY-FREE
# ------------------------------------------------------------
cat("\n-- A. Pureza --\n")

v1 <- .validate_estimator(PE, ANA, BOO)
set.seed(999L); v2 <- .validate_estimator(PE, ANA, BOO)
set.seed(1L); invisible(stats::runif(5L)); v3 <- .validate_estimator(PE, ANA, BOO)
check(identical(v1, v2) && identical(v1, v3),
      "A.1 misma entrada -> salida identical(), independiente del RNG (I11)")
body_txt <- deparse(.validate_estimator)
for (fn in c("\\.estimate\\(", "\\.mle_uncertainty\\(", "\\.bootstrap_estimator\\(",
             "\\.pm_fit\\(", "\\.motor\\(")) {
  check(!any(grepl(fn, body_txt)),
        sprintf("A.2 el validador NO invoca %s", gsub("\\\\", "", fn)))
}
for (fn in c("\\bsd\\(", "\\bquantile\\(", "\\bchol\\(", "\\bsolve\\(", "\\boptim\\(",
             "\\bsample\\(", "\\bqnorm\\(")) {
  check(!any(grepl(fn, body_txt)),
        sprintf("A.3 no recalcula: ausencia de %s", gsub("\\\\[b(]", "", fn)))
}
check(!any(grepl("shiny|reactive|session", body_txt, ignore.case = TRUE)),
      "A.4 Shiny-free")

# ------------------------------------------------------------
# B. ESTIMACIÓN PUNTUAL INMUTABLE
# ------------------------------------------------------------
cat("\n-- B. Estimación puntual --\n")

check(identical(v1$point_estimate, fe$params),
      "B.1 point_estimate copiado VERBATIM (valores, nombres y orden)")
check(identical(names(v1$parameters), names(unlist(fe$params))),
      "B.2 los parámetros conservan nombres y orden")
check(v1$parameters$rate$estimate == unname(unlist(fe$params))[1],
      "B.3 el `estimate` por parámetro es el oficial, no la media bootstrap")
check(v1$parameters$rate$estimate != mean(BOO$replicates[, "rate"]),
      "B.4 el estimate NO es la media bootstrap: sin sustitución ni corrección")
before <- fe$params; invisible(.validate_estimator(PE, ANA, BOO))
check(identical(before, fe$params), "B.5 la entrada no se modifica")

# ------------------------------------------------------------
# C. ESTADOS ANALÍTICOS
# ------------------------------------------------------------
cat("\n-- C. Estados analíticos --\n")

check(identical(v1$analytic$status, "complete"), "C.1 MLE con B12 válido -> complete")
check(identical(.validate_estimator(PE, NULL, BOO)$analytic$status, "not_requested"),
      "C.2 sin bloque analítico -> not_requested")
ANA_F <- .mle_uncertainty(list(id = "normal", method = "mle", converged = FALSE,
                               params = list(mean = 1, sd = 2),
                               message = "optimo en la frontera numerica"), xe)
check(identical(.validate_estimator(PE, ANA_F, BOO)$analytic$status, "not_available"),
      "C.3 bloque B12 no disponible -> se propaga su estado real, no se inventa")
for (m in c("mom", "lmom", "pm")) {
  pe_m <- list(params = fe$params, estimator = m, distribution = "exponential")
  r <- .validate_estimator(pe_m, NULL, NULL)
  check(identical(r$analytic$status, "not_applicable") &&
        grepl("no está definida", r$analytic$reason),
        sprintf("C.4 estimador '%s' -> not_applicable (NO failed)", m))
}
check(identical(.validate_estimator(PE, ANA, BOO)$parameters$rate$analytic$se,
                ANA$parameters$rate$se) &&
      identical(v1$parameters$rate$analytic$ci_lower, ANA$parameters$rate$ci_lower) &&
      identical(v1$parameters$rate$analytic$transform, ANA$parameters$rate$transform) &&
      identical(v1$parameters$rate$analytic$support, ANA$parameters$rate$support),
      "C.5 se, ci y transform/support se MAPEAN de B12 sin alterarlos")

# ------------------------------------------------------------
# D. ESTADOS BOOTSTRAP
# ------------------------------------------------------------
cat("\n-- D. Estados bootstrap --\n")

st <- function(Bs, Bq = 100L) .validate_estimator(PE, NULL, mk_boot(Bs, Bq))$bootstrap$status
check(identical(st(0L),   "failed"),       "D.1 B_success = 0 -> failed")
check(identical(st(1L),   "insufficient"), "D.2 B_success = 1 -> insufficient")
check(identical(st(60L),  "partial"),      "D.3 B_success >= 2 con fallos -> partial")
check(identical(st(100L), "complete"),     "D.4 B_success = B_requested >= 2 -> complete")
check(identical(.validate_estimator(PE, NULL, NULL)$bootstrap$status, "not_requested"),
      "D.5 sin bloque bootstrap -> not_requested")

r1 <- .validate_estimator(PE, NULL, mk_boot(1L))
check(isTRUE(r1$parameters$rate$bootstrap$bias_available) &&
      isTRUE(r1$parameters$rate$bootstrap$ci_degenerate) &&
      !isTRUE(r1$parameters$rate$bootstrap$se_available),
      "D.6 B_success = 1 -> bias_available TRUE, ci_degenerate TRUE, se_available FALSE")
check(identical(r1$bootstrap$valid, FALSE),
      "D.7 B_success = 1 -> bootstrap$valid sigue siendo FALSE (contrato B13)")

# `success_rate` NO altera la clasificación: no hay umbral (OD-11 abierta).
b_low <- mk_boot(5L, 100L)
check(identical(.validate_estimator(PE, NULL, b_low)$bootstrap$status, "partial") &&
      b_low$success_rate == 0.05,
      "D.8 success_rate = 0,05 sigue siendo `partial`: SIN umbral")

# ------------------------------------------------------------
# E. TABLA DE VERDAD DEL ESTADO GLOBAL
# ------------------------------------------------------------
cat("\n-- E. Estado global --\n")

g <- function(a, b) .validate_estimator(PE, a, b)$status
check(identical(g(ANA,  NULL),          "uncertainty_analytic"),  "E.1 a_ok, !b_ok")
check(identical(g(NULL, mk_boot(100L)), "uncertainty_bootstrap"), "E.2 !a_ok, b_ok")
check(identical(g(ANA,  mk_boot(100L)), "uncertainty_both"),      "E.3 a_ok, b_ok")
check(identical(g(NULL, NULL),          "point_only"),            "E.4 !a_ok, !b_ok")
check(identical(g(ANA_F, NULL),         "point_only"),            "E.5 analítico fallido, sin bootstrap")
check(identical(g(NULL, mk_boot(0L)),   "point_only"),            "E.6 B_success = 0")
check(identical(g(NULL, mk_boot(1L)),   "point_only"),            "E.7 B_success = 1")
check(identical(g(NULL, mk_boot(60L)),  "uncertainty_bootstrap"), "E.8 partial aporta incertidumbre")
pe_pm <- list(params = fe$params, estimator = "pm", distribution = "exponential")
check(identical(.validate_estimator(pe_pm, NULL, NULL)$status, "point_only"),
      "E.9 PM sin bootstrap -> point_only (analítico not_applicable)")
check(identical(.validate_estimator(list(params = NULL, estimator = "mle",
                                         distribution = "exponential"),
                                    ANA, BOO)$status, "no_point_estimate"),
      "E.10 sin estimación puntual -> no_point_estimate")

# ------------------------------------------------------------
# F. CASO CRÍTICO: analítico completo + bootstrap insuficiente
# ------------------------------------------------------------
cat("\n-- F. Caso crítico --\n")

vf <- .validate_estimator(PE, ANA, mk_boot(1L))
check(identical(vf$analytic$status, "complete"), "F.1 el eje analítico sigue completo")
check(identical(vf$bootstrap$status, "insufficient"), "F.2 el eje bootstrap es insufficient")
check(identical(vf$status, "uncertainty_analytic"),
      "F.3 GLOBAL = uncertainty_analytic: un bootstrap insuficiente NO elimina la incertidumbre analítica")
check(is.finite(vf$parameters$rate$analytic$se) &&
      isTRUE(vf$parameters$rate$analytic$available),
      "F.4 el SE analítico sigue publicándose")
# Simétrico: bootstrap válido + analítico fallido no degrada al bootstrap.
vg <- .validate_estimator(PE, ANA_F, mk_boot(100L))
check(identical(vg$status, "uncertainty_bootstrap"),
      "F.5 simétrico: analítico fallido no elimina la incertidumbre bootstrap")

# ------------------------------------------------------------
# G. INVARIANTE I15
# ------------------------------------------------------------
cat("\n-- G. I15 --\n")

for (Bs in c(0L, 1L, 2L, 60L, 100L)) {
  for (a in list(NULL, ANA)) {
    b <- mk_boot(Bs); r <- .validate_estimator(PE, a, b)
    lhs <- isTRUE(b$valid)
    rhs <- r$status %in% c("uncertainty_bootstrap", "uncertainty_both")
    check(identical(lhs, rhs),
          sprintf("G.1 I15 con B_success=%d, analítico=%s: valid=%s <=> global=%s",
                  Bs, if (is.null(a)) "no" else "sí", lhs, r$status))
    check(identical(lhs, Bs >= 2L), sprintf("G.2 valid <=> B_success >= 2 (Bs=%d)", Bs))
  }
}
# Input que CONTRADICE I15: no se corrige en silencio.
bad <- mk_boot(1L, valid = TRUE)
rb <- .validate_estimator(PE, NULL, bad)
check(identical(rb$status, "incompatible") &&
      any(grepl("I15", rb$diagnostics$incompatibilities)),
      "G.3 input que viola I15 -> incompatible, sin corrección silenciosa")
check(identical(rb$bootstrap$valid, TRUE),
      "G.4 el valor del input se conserva verbatim, no se reescribe")

# ------------------------------------------------------------
# G2. VALIDACIÓN CONTRACTUAL DE LOS CONTADORES BOOTSTRAP
#     (CONTRACT VALIDATION BUG — B14.1, corregido)
# ------------------------------------------------------------
cat("\n-- G2. Contadores bootstrap: contrato --\n")

# `safe` garantiza que NINGÚN caso lance error no capturado: el objetivo del
# bloque es que un contrato roto produzca un objeto auditable, no una excepción.
safe <- function(expr) tryCatch(expr, error = function(e) structure(list(err = e), class = "err"))
ok_obj <- function(r) !inherits(r, "err") && is.list(r) && !is.null(r$status)

roto <- list(
  list("G2.1  falta B_requested",        function(b) { b$B_requested <- NULL; b }),
  list("G2.2  falta B_failed",           function(b) { b$B_failed    <- NULL; b }),
  list("G2.3  B_requested = NA",         function(b) { b$B_requested <- NA_integer_; b }),
  list("G2.4  B_failed = NA",            function(b) { b$B_failed    <- NA_integer_; b }),
  list("G2.5  B_success = NA",           function(b) { b$B_success   <- NA_integer_; b }),
  list("G2.6  contador negativo",        function(b) { b$B_failed    <- -1L; b }),
  list("G2.7  contador no entero",       function(b) { b$B_success   <- 2.5;  b }),
  list("G2.8  B_success > B_requested",  function(b) { b$B_success   <- 200L; b$B_failed <- 0L; b }),
  list("G2.9  Bs + Bf != Bq",            function(b) { b$B_failed    <- 5L;   b }),
  list("G2.10 B_failed = 0 con Bs != Bq", function(b) { b$B_failed   <- 0L;   b$B_success <- 50L; b }),
  list("G2.11 B_success no numérico",    function(b) { b$B_success   <- "muchas"; b }),
  list("G2.12 B_requested infinito",     function(b) { b$B_requested <- Inf;  b })
)
for (cs in roto) {
  b <- cs[[2]](mk_boot(100L))
  r <- safe(.validate_estimator(PE, NULL, b))
  check(ok_obj(r), sprintf("%s -> objeto auditable, SIN error no capturado", cs[[1]]))
  check(identical(r$status, "incompatible"),
        sprintf("%s -> global = incompatible", cs[[1]]))
  check(length(r$diagnostics$incompatibilities) > 0L,
        sprintf("%s -> motivo registrado", cs[[1]]))
  check(!identical(r$bootstrap$status, "complete"),
        sprintf("%s -> bootstrap.status NO finge 'complete'", cs[[1]]))
  check(identical(r$bootstrap$counters_valid, FALSE),
        sprintf("%s -> counters_valid = FALSE", cs[[1]]))
}

# Los valores originales se conservan verbatim; NO se infiere B_failed.
b_sinBf <- mk_boot(100L); b_sinBf$B_failed <- NULL
r_sinBf <- .validate_estimator(PE, NULL, b_sinBf)
check(is.na(r_sinBf$bootstrap$B_failed),
      "G2.15 B_failed ausente -> NA en la salida, NO se infiere B_requested - B_success")
check(identical(r_sinBf$bootstrap$B_requested, 100L) &&
      identical(r_sinBf$bootstrap$B_success, 100L),
      "G2.16 los contadores presentes se conservan verbatim")
check(all(is.na(c(r_sinBf$parameters$rate$bootstrap$se,
                  r_sinBf$parameters$rate$bootstrap$ci_lower))),
      "G2.17 con contadores inválidos NO se mapean se/ci por parámetro")

# El caso crítico que el bug producía: Bs >= 2 con B_failed desconocido.
b_amb <- mk_boot(100L); b_amb$B_failed <- NA_integer_
check(!identical(.validate_estimator(PE, NULL, b_amb)$bootstrap$status, "complete"),
      "G2.18 B_success >= 2 con B_failed no finito NO produce 'complete'")

# Bloque bootstrap que no es lista.
for (bad in list(42, "x", c(1, 2, 3))) {
  r <- safe(.validate_estimator(PE, NULL, bad))
  check(ok_obj(r) && identical(r$status, "incompatible"),
        sprintf("G2.19 bloque no-lista (%s) -> incompatible sin error",
                class(bad)[1]))
}

# 11. Un bloque válido completo SIGUE clasificándose como complete.
r_ok <- .validate_estimator(PE, NULL, mk_boot(100L))
check(identical(r_ok$status, "uncertainty_bootstrap") &&
      identical(r_ok$bootstrap$status, "complete") &&
      identical(r_ok$bootstrap$counters_valid, TRUE) &&
      length(r_ok$diagnostics$incompatibilities) == 0L,
      "G2.20 bloque válido -> complete, sin incompatibilidades (no hay falsos positivos)")
r_par <- .validate_estimator(PE, NULL, mk_boot(60L))
check(identical(r_par$bootstrap$status, "partial") &&
      length(r_par$diagnostics$incompatibilities) == 0L,
      "G2.21 partial legítimo tampoco genera incompatibilidad")
check(isTRUE(.validate_estimator(PE, ANA, BOO)$bootstrap$counters_valid),
      "G2.22 el bloque REAL de B13 pasa la validación contractual")

# `success_rate`: se VALIDA como contrato pero NO condiciona la clasificación.
# Es la distinción que separa «comprobar» de «usar para clasificar» (ADR-037).
for (cs in list(list("G2.23 success_rate incoherente", 0.1),
                list("G2.24 success_rate fuera de [0,1]", 2))) {
  b <- mk_boot(100L); b$success_rate <- cs[[2]]
  r <- safe(.validate_estimator(PE, NULL, b))
  check(ok_obj(r), sprintf("%s -> objeto auditable", cs[[1]]))
  check(any(grepl("success_rate", r$diagnostics$incompatibilities)),
        sprintf("%s -> registrado como incompatibilidad", cs[[1]]))
  check(identical(r$status, "incompatible"), sprintf("%s -> global incompatible", cs[[1]]))
  check(identical(r$bootstrap$status, "complete") &&
        identical(r$bootstrap$counters_valid, TRUE),
        sprintf("%s -> la CLASIFICACIÓN sigue saliendo de B_success/B_failed", cs[[1]]))
}

# ------------------------------------------------------------
# G3. TOLERANCIA DE NIVEL FRENTE A CONFIG CUSTOM
# ------------------------------------------------------------
cat("\n-- G3. config$confidence_level_tol robusta --\n")

for (bad_tol in list(NULL, NA_real_, -1, Inf, NaN, "x", c(1e-12, 1e-9))) {
  cfg <- dfit_default_config(); cfg$confidence_level_tol <- bad_tol
  r <- safe(.validate_estimator(PE, ANA, mk_boot(100L), config = cfg))
  check(ok_obj(r), sprintf("G3.1 tol inválida (%s) -> sin error",
                           paste(format(bad_tol), collapse = ",")))
  check(isTRUE(r$comparability$same_confidence_level),
        "G3.2 se usa el valor por defecto documentado y la comparación funciona")
  check(length(r$diagnostics$config_issues) > 0L,
        "G3.3 el problema de configuración se DECLARA en diagnostics$config_issues")
  check(identical(r$status, "uncertainty_both"),
        "G3.4 un problema de CONFIGURACIÓN no altera el estado global")
}
cfg_ok <- dfit_default_config()
check(length(.validate_estimator(PE, ANA, mk_boot(100L),
                                 config = cfg_ok)$diagnostics$config_issues) == 0L,
      "G3.5 con la configuración por defecto no hay config_issues")
check(DFIT_CONFIDENCE_LEVEL_TOL_DEFAULT == 1e-12 &&
      identical(cfg_ok$confidence_level_tol, DFIT_CONFIDENCE_LEVEL_TOL_DEFAULT),
      "G3.6 config y fallback comparten la misma constante: no pueden divergir")

# ------------------------------------------------------------
# H. IDENTIDAD DE PARÁMETROS
# ------------------------------------------------------------
cat("\n-- H. Identidad de parámetros --\n")

b_wrong <- mk_boot(100L, names_ = "otro")
rh <- .validate_estimator(PE, NULL, b_wrong)
check(identical(rh$status, "incompatible") &&
      identical(rh$comparability$same_parameter_names, FALSE),
      "H.1 nombres distintos -> incompatible, sin reordenar")
# Cardinalidad distinta con la misma longitud NO se asume equivalente.
set.seed(3L); xn <- stats::rnorm(300L, 100, 15)
fn <- .estimate("normal", xn, "mle")
PEn <- list(params = fn$params, estimator = "mle", distribution = "normal")
b_swapped <- mk_boot(100L, names_ = c("sd", "mean"))
b_swapped$distribution <- "normal"
rs <- .validate_estimator(PEn, NULL, b_swapped)
check(identical(rs$status, "incompatible"),
      "H.2 mismo cardinal pero ORDEN distinto -> incompatible")
check(any(grepl("orden", rs$diagnostics$incompatibilities)),
      "H.3 el motivo es auditable")
# Distribución/estimador discrepantes.
b_dist <- mk_boot(100L); b_dist$distribution <- "gamma"
check(identical(.validate_estimator(PE, NULL, b_dist)$status, "incompatible"),
      "H.4 distribución discrepante -> incompatible")

# ------------------------------------------------------------
# I. NIVELES DE CONFIANZA
# ------------------------------------------------------------
cat("\n-- I. Niveles de confianza --\n")

vi_ <- .validate_estimator(PE, ANA, mk_boot(100L))
check(isTRUE(vi_$comparability$same_confidence_level) &&
      identical(vi_$comparability$status, "comparable"),
      "I.1 mismo nivel -> comparable")
b90 <- mk_boot(100L); b90$confidence_level <- 0.90
vd <- .validate_estimator(PE, ANA, b90)
check(identical(vd$comparability$same_confidence_level, FALSE) &&
      identical(vd$comparability$status, "limited"),
      "I.2 niveles distintos -> limited")
check(identical(vd$comparability$analytic_level, 0.95) &&
      identical(vd$comparability$bootstrap_level, 0.90),
      "I.3 los niveles se propagan VERBATIM, sin armonizar")
check(identical(vd$status, "uncertainty_both"),
      "I.4 niveles distintos NO invalidan: ambos siguen siendo válidos")
check(any(grepl("no deben.*comparar|no deben", vd$limitations)),
      "I.5 se registra la limitación de comparabilidad")
# Tolerancia PURAMENTE COMPUTACIONAL, no metodológica.
b_eps <- mk_boot(100L); b_eps$confidence_level <- 0.95 + 1e-15
check(isTRUE(.validate_estimator(PE, ANA, b_eps)$comparability$same_confidence_level),
      "I.6 diferencia de 1e-15 NO produce falsa incompatibilidad")
b_real <- mk_boot(100L); b_real$confidence_level <- 0.95 - 1e-3
check(identical(.validate_estimator(PE, ANA, b_real)$comparability$same_confidence_level,
                FALSE),
      "I.7 una diferencia real de nivel (1e-3) SÍ se detecta")
check(dfit_default_config()$confidence_level_tol == 1e-12,
      "I.8 la tolerancia vive en config y es computacional (1e-12)")

# ------------------------------------------------------------
# J. METADATOS DE MUESTRA (ADR-026)
# ------------------------------------------------------------
cat("\n-- J. Metadatos de muestra --\n")

set.seed(5L)
df <- data.frame(coste = stats::rgamma(500L, shape = 2, scale = 500))
res <- dist_fit_analyze(df, "coste")
vj <- .validate_estimator(PE, NULL, NULL, sample_meta = res$sample)
check(isTRUE(vj$sample$available), "J.1 metadatos disponibles")
check(identical(vj$sample$n_input, res$sample$n_input) &&
      identical(vj$sample$n_used, res$sample$n_used),
      "J.2 n_input y n_used propagados verbatim")
check(identical(vj$sample$support, res$sample$support_label),
      "J.3 adaptación documentada: `support` <- `support_label`")
check(identical(vj$sample$n_excluded_zeros, res$sample$n_excluded_zeros),
      "J.4 exclusiones tomadas de build_analysis_sample(), no de fit$n_excluded")
check(!any(grepl("n_excluded\\)", deparse(.dfit_sample_meta), fixed = FALSE)) &&
      !any(grepl("fit", deparse(.dfit_sample_meta))),
      "J.5 el adaptador NO lee fit$n_excluded (vestigial desde ADR-026)")
check(!isTRUE(.validate_estimator(PE, NULL, NULL)$sample$available),
      "J.6 sin metadatos -> available = FALSE con motivo, no se inventan")

# ------------------------------------------------------------
# K. MUESTRA CONDICIONAL POSITIVA
# ------------------------------------------------------------
cat("\n-- K. Muestra condicional --\n")

set.seed(7L)
dfz <- data.frame(coste = c(rep(0, 200L), stats::rgamma(400L, shape = 2, scale = 500)))
resz <- dist_fit_analyze(dfz, "coste")
check(resz$sample$n_excluded_zeros == 200L, "K.1 la capa 0.5 excluyó los 200 ceros")
vk <- .validate_estimator(PE, NULL, NULL, sample_meta = resz$sample)
check(isTRUE(vk$sample$conditional), "K.2 conditional = TRUE")
check(grepl("condicional", vk$sample$conditional_note),
      "K.3 la nota declara que la inferencia es de la distribución condicional")
check(any(grepl("condicional", vk$limitations)),
      "K.4 la limitación aparece en `limitations`, no solo en la nota")
check(!isTRUE(.validate_estimator(PE, NULL, NULL, sample_meta = res$sample)$sample$conditional),
      "K.5 sin exclusiones -> conditional = FALSE")

# ------------------------------------------------------------
# L. OD-17
# ------------------------------------------------------------
cat("\n-- L. OD-17 --\n")

vl <- .validate_estimator(PE, NULL, BOO)
for (f in c("B_requested", "B_success", "B_failed", "success_rate")) {
  check(identical(vl$bootstrap[[f]], BOO[[f]]),
        sprintf("L.1 %s propagado verbatim", f))
}
check(identical(vl$bootstrap$failures, BOO$failures),
      "L.2 motivos de fallo propagados verbatim")
check(isTRUE(vl$bootstrap$summaries_conditional_on_success),
      "L.3 summaries_conditional_on_success = TRUE")
check(any(grepl("réplicas válidas", vl$limitations)),
      "L.4 la limitación de OD-17 aparece en `limitations`")
lim_txt <- paste(vl$limitations, collapse = " ")
for (w in c("estrech", "ensanch", "subestim", "sobreestim")) {
  check(!grepl(w, lim_txt), sprintf("L.5 NO se infiere dirección del sesgo ('%s')", w))
}
check(any(grepl("dirección y magnitud", lim_txt)),
      "L.6 se usa la formulación neutral congelada")

# ------------------------------------------------------------
# M. OD-18
# ------------------------------------------------------------
cat("\n-- M. OD-18 --\n")

cat("     OD-18: identidad de muestra entre vías de inferencia\n")

# ---- T8: el MISMO vector por B12 y B13 produce la MISMA huella --------------
check(is.list(ANA$sample) && !is.na(ANA$sample$fingerprint),
      "T8.1 el bloque analítico de B12 expone ahora `sample$fingerprint`")
check(identical(ANA$sample$fingerprint_algo, "sha256") &&
      identical(BOO$fingerprint_algo, "sha256"),
      "T8.2 ambas vías usan el MISMO criterio: SHA-256")
check(identical(ANA$sample$fingerprint, BOO$data_fingerprint),
      "T8.3 el mismo vector por B12 y B13 -> la MISMA huella")
check(identical(ANA$sample$fingerprint, .data_fingerprint(xe)$fingerprint),
      "T8.4 la huella es la del helper único de B13, sin mecanismo paralelo")
check(identical(ANA$sample$n_used, length(xe)), "T8.5 n_used correcto")

# ---- T1: misma n, misma huella -> TRUE --------------------------------------
vm <- .validate_estimator(PE, ANA, BOO)
check(identical(vm$comparability$sample_identity_verified, TRUE),
      "T1.1 misma n + misma huella -> sample_identity_verified = TRUE")
check(identical(vm$comparability$sample_identity_status, "verified"),
      "T1.2 status = verified")
check(identical(vm$comparability$status, "comparable"),
      "T1.3 comparabilidad normal")
check(is.na(vm$comparability$sample_identity_reason),
      "T1.4 sin motivo de fallo cuando se verifica")
check(!any(grepl("identidad|huella", vm$limitations)),
      "T1.5 sin limitación de identidad cuando está verificada")

# Utilidades. Las huellas de los casos VÁLIDOS son SHA-256 REALES obtenidas del
# helper productivo: nunca cadenas de conveniencia tipo "a" / "abc".
fp_of_vec <- function(v) .data_fingerprint(v)$fingerprint
mk_ana <- function(fp, n, status = "complete", algo = "sha256") {
  a <- ANA
  a$sample <- list(n_used = n, fingerprint = fp,
                   fingerprint_algo = algo, fingerprint_status = status)
  a$n <- n; a
}
mk_boo <- function(fp, n, status = "complete", algo = "sha256") {
  b <- BOO
  b$data_fingerprint <- fp; b$fingerprint_algo <- algo
  b$fingerprint_status <- status; b$n <- n; b
}
x1 <- c(1, 2, 3, 4, 5); x2 <- c(1, 2, 3, 4, 6)
f1 <- fp_of_vec(x1); f2 <- fp_of_vec(x2)
check(all(grepl("^[0-9a-f]{64}$", c(f1, f2))),
      "T0.1 las huellas sintéticas son SHA-256 REALES de 64 hexadecimales")

# ---- T7 / caso 9: misma n, muestra REALMENTE distinta -> mismatch -----------
check(length(x1) == length(x2) && !identical(f1, f2),
      "T7.1 dos vectores de igual n con una sola diferencia dan huellas distintas")
v7 <- .validate_estimator(PE, mk_ana(f1, 5L), mk_boo(f2, 5L))
check(identical(v7$comparability$sample_identity_verified, FALSE),
      "T7.2 misma n pero muestra distinta -> FALSE: n NO se usa como proxy")
check(identical(v7$comparability$sample_identity_status, "mismatch"),
      "T7.3 status = mismatch (identidades VÁLIDAS de muestras distintas)")
check(identical(v7$comparability$same_sample_n, TRUE),
      "T7.4 same_sample_n sigue siendo TRUE: es necesaria y no suficiente")

# ---- T2 / caso 2: dos SHA-256 válidos distintos, misma n -> mismatch --------
v2_ <- .validate_estimator(PE, mk_ana(f1, 400L), mk_boo(f2, 400L))
check(identical(v2_$comparability$sample_identity_verified, FALSE) &&
      identical(v2_$comparability$sample_identity_status, "mismatch"),
      "T2.1 huellas válidas distintas -> FALSE / mismatch")
check(grepl("difieren", v2_$comparability$sample_identity_reason),
      "T2.2 diagnóstico explícito de muestras distintas")
check(identical(v2_$comparability$status, "incompatible"),
      "T2.3 comparabilidad = incompatible")
check(identical(v2_$status, "uncertainty_both"),
      "T2.4 el estado GLOBAL no se degrada: cada inferencia sigue siendo utilizable")

# ---- T3: n distinta con huellas válidas -> different_n ----------------------
v3_ <- .validate_estimator(PE, mk_ana(f1, 400L), mk_boo(f1, 399L))
check(identical(v3_$comparability$sample_identity_verified, FALSE) &&
      identical(v3_$comparability$sample_identity_status, "different_n"),
      "T3.1 n distinta -> FALSE aunque la huella coincida")
check(grepl("tama.os de muestra distintos", v3_$comparability$sample_identity_reason),
      "T3.2 diagnóstico explícito")

# ---- T13: la HUELLA debe ser una IDENTIDAD VÁLIDA, no solo una cadena igual --
cat("     T13: validez de la huella, no mera igualdad de cadenas\n")

# Caso 7 del encargo: "abc" idéntico en ambas vías. JAMÁS verified.
v_abc <- .validate_estimator(PE, mk_ana("abc", 400L), mk_boo("abc", 400L))
check(identical(v_abc$comparability$sample_identity_verified, FALSE),
      "T13.1 cadenas iguales pero inválidas ('abc') -> JAMÁS verified")
check(identical(v_abc$comparability$sample_identity_status, "not_verifiable"),
      "T13.2 status = not_verifiable (formato inválido), NO mismatch ni verified")
check(grepl("64 hexadecimales", v_abc$comparability$sample_identity_reason),
      "T13.3 el motivo concreto es el formato")
check(identical(v_abc$status, "uncertainty_both"),
      "T13.4 el global no se degrada")

# Casos 3-6: formato correcto pero identidad no utilizable.
fp_ok <- f1
invalidos <- list(
  list("T13.5 analytic status = failed",
       mk_ana(fp_ok, 400L, status = "failed"),      mk_boo(fp_ok, 400L),
       "anal.tica no est. en estado 'complete'"),
  list("T13.6 bootstrap status = invalid_input",
       mk_ana(fp_ok, 400L),  mk_boo(fp_ok, 400L, status = "invalid_input"),
       "bootstrap no est. en estado 'complete'"),
  list("T13.7 analytic algo != sha256",
       mk_ana(fp_ok, 400L, algo = "md5"),           mk_boo(fp_ok, 400L),
       "anal.tica no declara algoritmo 'sha256'"),
  list("T13.8 bootstrap algo != sha256",
       mk_ana(fp_ok, 400L),  mk_boo(fp_ok, 400L, algo = "md5"),
       "bootstrap no declara algoritmo 'sha256'"),
  list("T13.9 analytic algo ausente",
       mk_ana(fp_ok, 400L, algo = NULL),            mk_boo(fp_ok, 400L),
       "anal.tica no declara algoritmo"),
  list("T13.10 bootstrap status ausente",
       mk_ana(fp_ok, 400L),  mk_boo(fp_ok, 400L, status = NULL),
       "bootstrap no est. en estado 'complete'"),
  list("T13.11 huella de 63 hex",
       mk_ana(substr(fp_ok, 1, 63), 400L),          mk_boo(substr(fp_ok, 1, 63), 400L),
       "64 hexadecimales"),
  list("T13.12 huella en MAYÚSCULAS",
       mk_ana(toupper(fp_ok), 400L),                mk_boo(toupper(fp_ok), 400L),
       "64 hexadecimales")
)
for (cs in invalidos) {
  r <- .validate_estimator(PE, cs[[2]], cs[[3]])
  check(identical(r$comparability$sample_identity_verified, FALSE),
        sprintf("%s -> FALSE", cs[[1]]))
  check(identical(r$comparability$sample_identity_status, "not_verifiable"),
        sprintf("%s -> not_verifiable", cs[[1]]))
  check(grepl(cs[[4]], r$comparability$sample_identity_reason),
        sprintf("%s -> motivo concreto en el reason", cs[[1]]))
  check(identical(r$status, "uncertainty_both"),
        sprintf("%s -> la inferencia individual sigue siendo utilizable", cs[[1]]))
  check(!identical(r$comparability$status, "comparable"),
        sprintf("%s -> comparability NUNCA 'comparable'", cs[[1]]))
}

# Casos 1 y 10 del encargo: todo válido -> verified.
v_ok <- .validate_estimator(PE, mk_ana(fp_ok, 400L), mk_boo(fp_ok, 400L))
check(identical(v_ok$comparability$sample_identity_verified, TRUE) &&
      identical(v_ok$comparability$sample_identity_status, "verified"),
      "T13.13 SHA-256 válido + status complete + algo sha256 + misma n -> verified")
check(identical(v_ok$comparability$status, "comparable"),
      "T13.14 comparabilidad normal")
check(is.na(v_ok$comparability$sample_identity_reason),
      "T13.15 sin motivo cuando se verifica")

# Auditoría propagada, no recalculada.
for (f in c("analytic_sample_fingerprint", "bootstrap_sample_fingerprint",
            "analytic_fingerprint_status", "bootstrap_fingerprint_status",
            "analytic_fingerprint_algo",   "bootstrap_fingerprint_algo",
            "analytic_n_used",             "bootstrap_n_used")) {
  check(f %in% names(v_ok$comparability),
        sprintf("T13.16 `%s` propagado para auditoría", f))
}
check(identical(v_ok$comparability$analytic_sample_fingerprint, fp_ok) &&
      identical(v_ok$comparability$bootstrap_sample_fingerprint, fp_ok),
      "T13.17 las huellas se propagan VERBATIM")
check(!any(grepl("\\.data_fingerprint\\(", deparse(.validate_estimator))),
      "T13.18 B14 NO recalcula huellas: solo las lee")

# ---- T4/T5/T6: huellas ausentes -> FALSE, NO verificable -------------------
ana_sin <- ANA; ana_sin$sample <- NULL
boo_sin <- BOO; boo_sin$data_fingerprint <- NA_character_
casos_falta <- list(
  list("T4 falta huella analítica",  ana_sin, BOO),
  list("T5 falta huella bootstrap",  ANA,     boo_sin),
  list("T6 faltan ambas",            ana_sin, boo_sin)
)
for (cs in casos_falta) {
  r <- .validate_estimator(PE, cs[[2]], cs[[3]])
  check(identical(r$comparability$sample_identity_verified, FALSE),
        sprintf("%s -> FALSE", cs[[1]]))
  check(identical(r$comparability$sample_identity_status, "not_verifiable"),
        sprintf("%s -> status = not_verifiable (NO 'mismatch')", cs[[1]]))
  check(identical(r$status, "uncertainty_both"),
        sprintf("%s -> global intacto: NO es un error fatal", cs[[1]]))
  check(any(grepl("por separado", r$limitations)),
        sprintf("%s -> la limitación aclara que cada vía sigue siendo utilizable", cs[[1]]))
}

# ---- T11 / T12: una sola vía disponible ------------------------------------
v11 <- .validate_estimator(PE, ANA, NULL)
check(identical(v11$comparability$sample_identity_verified, FALSE) &&
      identical(v11$comparability$sample_identity_status, "not_applicable"),
      "T11.1 solo analítica -> identidad no aplicable, verified = FALSE")
check(identical(v11$status, "uncertainty_analytic") &&
      is.finite(v11$parameters$rate$analytic$se),
      "T11.2 la inferencia analítica sigue siendo utilizable")
v12 <- .validate_estimator(PE, NULL, BOO)
check(identical(v12$comparability$sample_identity_verified, FALSE) &&
      identical(v12$comparability$sample_identity_status, "not_applicable"),
      "T12.1 solo bootstrap -> identidad no aplicable, verified = FALSE")
check(identical(v12$status, "uncertainty_bootstrap") &&
      is.finite(v12$parameters$rate$bootstrap$se),
      "T12.2 la inferencia bootstrap sigue siendo utilizable")

# ---- T9 / T10: B12 y B13 no cambian metodológicamente ----------------------
n_e <- length(xe)
check(abs(ANA$observed_information[1, 1] - n_e) / n_e < 1e-4,
      "T9.1 B12 intacto: J_u ~ n para exponencial (referencia analítica)")
check(abs(ANA$se_theta[["rate"]] - fe$params$rate / sqrt(n_e)) /
      (fe$params$rate / sqrt(n_e)) < 1e-4,
      "T9.2 B12 intacto: SE(rate) ~ rate/sqrt(n)")
check(identical(ANA$confidence_level, 0.95) && identical(ANA$status, "complete"),
      "T9.3 B12 intacto: nivel y estado")
BOO2 <- .bootstrap_estimator(xe, .bootstrap_adapter_fit("exponential", "mle"),
                             B = 100L, seed = SEED, theta_hat = fe$params,
                             estimator = "mle", distribution = "exponential")
check(identical(BOO2$replicates, BOO$replicates) && identical(BOO2$ci, BOO$ci) &&
      identical(BOO2$se, BOO$se) && identical(BOO2$quantile_type, 7L),
      "T10.1 B13 intacto: réplicas, IC, SE y type=7 reproducibles")
check(identical(BOO$summaries_conditional_on_success, TRUE),
      "T10.2 B13 intacto: OD-17 sin cambios")

# ---- OD-18 no introduce ninguna métrica de agreement -----------------------
nm_comp <- names(vm$comparability)
for (w in c("agreement", "ratio", "overlap", "diff", "score", "stability")) {
  check(!any(grepl(w, nm_comp, ignore.case = TRUE)),
        sprintf("T.agreement OD-18 no introduce '%s'", w))
}

# ------------------------------------------------------------
# N. SEMÁNTICA DE LA AUSENCIA
# ------------------------------------------------------------
cat("\n-- N. Ausencia explícita --\n")

vn <- .validate_estimator(PE, NULL, NULL)
campos <- c("status", "estimator", "distribution", "point_estimate", "sample",
            "analytic", "bootstrap", "parameters", "comparability",
            "diagnostics", "limitations")
check(all(campos %in% names(vn)), "N.1 todos los campos del contrato existen")
check(!is.null(vn$parameters$rate$analytic) && !is.null(vn$parameters$rate$bootstrap),
      "N.2 los sub-bloques existen aunque las vías no se hayan calculado")
check(is.na(vn$parameters$rate$analytic$se) &&
      is.na(vn$parameters$rate$bootstrap$se),
      "N.3 la ausencia es NA, no omisión del campo")
check(identical(vn$parameters$rate$analytic$status, "not_requested") &&
      identical(vn$parameters$rate$bootstrap$status, "not_requested"),
      "N.4 cada ausencia lleva su status")
check(identical(.validate_estimator(PE, NULL, mk_boot(0L))$parameters$rate$bootstrap$status,
                "failed") &&
      identical(.validate_estimator(PE, NULL, mk_boot(1L))$parameters$rate$bootstrap$status,
                "insufficient"),
      "N.5 `not_requested`, `failed` e `insufficient` se distinguen")

# ------------------------------------------------------------
# O. LIMITACIONES SIN JUICIO DE CALIDAD
# ------------------------------------------------------------
cat("\n-- O. Limitaciones --\n")

todas <- paste(c(v1$limitations, vf$limitations, vk$limitations, vd$limitations),
               collapse = " ")
for (w in c("unstable", "inestable", "poor", "mala calidad", "reliable", "fiable",
            "unreliable", "high", "medium", "low", "score")) {
  check(!grepl(w, todas, ignore.case = TRUE),
        sprintf("O.1 sin etiqueta de calidad: '%s'", w))
}
check(is.character(v1$limitations), "O.2 `limitations` es un vector de texto")
check(!any(grepl("quality|calidad", names(unlist(v1)), ignore.case = TRUE)),
      "O.3 no existe ningún campo de score de calidad")

# ------------------------------------------------------------
# P-S. AISLAMIENTO
# ------------------------------------------------------------
cat("\n-- P-S. Aislamiento --\n")

check(all(vapply(res$motor$fits, function(f) is.null(f$validation), TRUE)),
      "P.1 el análisis por defecto NO añade fit$validation")
check(all(vapply(res$motor$fits, function(f) is.null(f$inference), TRUE)) &&
      all(vapply(res$motor$fits, function(f) is.null(f$bootstrap), TRUE)),
      "P.2 tampoco inference ni bootstrap: contrato serializado intacto")
check(identical(res$motor$method, "mle") && !is.null(res$assessment) &&
      !is.null(res$decision_engine),
      "P.3 AUTO, Assessment y Decision Engine intactos")
check(inherits(try(.motor(res$sample, res$candidates, method = "pm"), silent = TRUE),
               "try-error"),
      "P.4 .motor sigue rechazando method = 'pm'")
check(identical(DFIT_SCHEMA_VERSION, "1.1.0"), "Q.1 schema sin cambios")
u_again <- .mle_uncertainty(c(list(id = "exponential", method = "mle", converged = TRUE,
                                   message = NA_character_), fe), xe)
check(identical(u_again, ANA), "R.1 la inferencia analítica de B12 no ha cambiado")
b_again <- .bootstrap_estimator(xe, .bootstrap_adapter_fit("exponential", "mle"),
                                B = 100L, seed = SEED, theta_hat = fe$params,
                                estimator = "mle", distribution = "exponential")
check(identical(b_again$replicates, BOO$replicates) && identical(b_again$ci, BOO$ci),
      "S.1 el bootstrap de B13 no ha cambiado")

# ------------------------------------------------------------
# T. AVISOS
# ------------------------------------------------------------
cat("\n-- T. Avisos --\n")
cap <- list()
withCallingHandlers({
  invisible(.validate_estimator(PE, ANA, BOO))
  invisible(.validate_estimator(PE, NULL, NULL))
  invisible(.validate_estimator(PE, ANA, mk_boot(1L)))
  invisible(.validate_estimator(PE, ANA_F, mk_boot(0L)))
  invisible(.validate_estimator(pe_pm, NULL, BOO))
  invisible(.validate_estimator(PE, ANA, BOO, sample_meta = resz$sample))
}, warning = function(w) { cap[[length(cap) + 1L]] <<- conditionMessage(w)
                           invokeRestart("muffleWarning") })
if (length(cap) > 0L) {
  cat("     avisos observados (CLASIFICAR):\n")
  for (m in unique(unlist(cap))) cat(sprintf("       - %s\n", m))
}
check(length(cap) == 0L, "T.1 sin avisos en el camino nominal")
check(!any(grepl("suppressWarnings", body_txt)),
      "T.2 el validador no usa suppressWarnings")

cat("\nB14.1 — CAPA DE VALIDACIÓN DEL ESTIMADOR VERIFICADA\n")
