# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b16_ui_tests.R
# Tests de B16.1: vista de incertidumbre, integración, reproducibilidad y export.
#
# Cubre la capa `build_uncertainty_view()` (calc.R §3f) y el comportamiento
# reactivo del módulo (navegación, disparo del bootstrap, identidad del
# resultado, congelación de metadatos, PM alternativo, exportación).
#
# Autor: BMK — Última actualización: 2026-09-03
# ============================================================
#
#   Rscript tools/distribution-fitting/tests/b16_ui_tests.R

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
.old_wd <- setwd(.tool_root)
on.exit(setwd(.old_wd), add = TRUE)

library(shiny)
library(bslib)
source("../../shared/load_shared.R")
source("R/calc.R")
source("R/mod_tool.R")
manifest <- yaml::read_yaml("manifest.yml")

check <- function(cond, msg) {
  if (!isTRUE(cond)) stop(sprintf("FALLO: %s", msg), call. = FALSE)
  cat(sprintf("  OK  - %s\n", msg))
}

cat("== B16.1 — VISTA DE INCERTIDUMBRE ==\n")

SEED <- 20260903L
set.seed(31L)
df <- data.frame(coste = stats::rgamma(500L, shape = 2, scale = 500))
AN <- dist_fit_analyze(df, "coste", method = "mle")
DIST <- AN$assessment$ranking[[1]]$id
FIT  <- AN$motor$fits[[DIST]]
PE   <- list(params = FIT$params, estimator = "mle", distribution = DIST)
ANA  <- .mle_uncertainty(FIT, AN$sample$x, confidence_level = 0.95)
BOO  <- .bootstrap_estimator(AN$sample$x,
                             .bootstrap_adapter_fit(DIST, "mle",
                                                    family = AN$candidates$family,
                                                    resolution = AN$sample$resolution),
                             B = 60L, seed = SEED, theta_hat = FIT$params,
                             estimator = "mle", distribution = DIST)
check(isTRUE(BOO$valid), "material de partida: bootstrap válido")

# ------------------------------------------------------------
# E. INCERTIDUMBRE ANALÍTICA
# ------------------------------------------------------------
cat("\n-- E. Analítica --\n")

uv_a <- build_uncertainty_view(AN, PE, analytic = ANA, bootstrap = NULL,
                               manifest = manifest)
check(identical(uv_a$analytic$status, "complete"),
      "E.1 MLE con B12 válido -> analítica completa, sin bootstrap")
check(nrow(uv_a$analytic$table) == length(FIT$params) &&
      all(is.finite(uv_a$analytic$table$se)),
      "E.2 tabla analítica con SE finitos")
check(identical(uv_a$analytic$table$estimacion, unname(unlist(FIT$params))),
      "E.3 la estimación mostrada es la oficial")
check(identical(uv_a$bootstrap$status, "not_requested"),
      "E.4 sin bootstrap: estado not_requested")
check(all(is.na(uv_a$bootstrap$table$se)),
      "E.5 no se fabrican SE bootstrap")

# Ajuste sin inferencia analítica utilizable: no se inventa nada.
bad_fit <- list(id = DIST, method = "mle", converged = FALSE,
                params = FIT$params, message = "optimo en la frontera numerica")
ana_bad <- .mle_uncertainty(bad_fit, AN$sample$x)
uv_bad <- build_uncertainty_view(AN, PE, analytic = ana_bad, manifest = manifest)
check(!identical(uv_bad$analytic$status, "complete") &&
      all(is.na(uv_bad$analytic$table$se)),
      "E.6 analítica no disponible -> sin SE/CI fabricados")
check(!is.na(uv_bad$analytic$reason), "E.7 el motivo es auditable, no se oculta")

# ------------------------------------------------------------
# ESTRUCTURA, COMPARACIÓN Y RÉPLICAS
# ------------------------------------------------------------
cat("\n-- Estructura --\n")

uv <- build_uncertainty_view(AN, PE, analytic = ANA, bootstrap = BOO,
                             manifest = manifest)
for (f in c("context", "point_estimate", "analytic", "bootstrap", "validation",
            "comparison", "reproducibility", "diagnostics", "limitations",
            "export_table")) {
  check(f %in% names(uv), sprintf("S.1 el payload contiene `%s`", f))
}
check(identical(uv$comparison$comparison_status, "available"),
      "S.2 misma muestra en ambas vías -> comparación disponible (OD-18)")
check(identical(uv$point_estimate, FIT$params),
      "S.3 point estimate verbatim")
check(is.null(uv$bootstrap$replicates) &&
      !any(grepl("replicat", names(uv$bootstrap), ignore.case = TRUE)),
      "S.4 las réplicas NO viajan en la estructura de la vista")
check(!any(grepl("replicat", names(uv$export_table), ignore.case = TRUE)),
      "S.5 las réplicas NO aparecen en la tabla de exportación")

# Gráfico: dataset, no dibujo.
pl <- build_bootstrap_plot_data(BOO, FIT$params, names(FIT$params)[1])
check(isTRUE(pl$available) && length(pl$replicates) == BOO$B_success,
      "S.6 dataset del gráfico con todas las réplicas válidas")
check(identical(pl$theta_hat, unname(unlist(FIT$params))[1]),
      "S.7 theta_hat del gráfico = estimación puntual oficial")
check(identical(pl$ci_lower, unname(BOO$ci[names(FIT$params)[1], "lower"])),
      "S.8 los límites del IC provienen de B13, sin recalcular")
check(!isTRUE(build_bootstrap_plot_data(NULL, FIT$params, "shape")$available),
      "S.9 sin bootstrap -> dataset no disponible, sin error")

# ------------------------------------------------------------
# R. IDENTIDAD DE MUESTRA EN EL PASAPORTE — NO DEPENDE DEL BOOTSTRAP
# ------------------------------------------------------------
# Regresión del bug contractual detectado en B17: el passport tomaba la huella
# solo de los metadatos del bootstrap, de modo que un resultado analítico válido
# sin bootstrap ejecutado se publicaba con `fingerprint = NA` pese a que B12 sí
# huella la muestra.
cat("\n-- R. Huella en el pasaporte --\n")

FP_RE <- "^[0-9a-f]{64}$"
fp_muestra <- .data_fingerprint(AN$sample$x)$fingerprint

# R1. MLE analítico SIN bootstrap.
d1 <- uv_a$reproducibility$data
check(!is.na(d1$fingerprint), "R1.1 con analítica y sin bootstrap la huella NO es NA")
check(is.character(d1$fingerprint) && nchar(d1$fingerprint) == 64L &&
      grepl(FP_RE, d1$fingerprint),
      "R1.2 64 caracteres hexadecimales en minúsculas")
check(identical(d1$fingerprint_algo, "sha256"), "R1.3 algoritmo sha256")
check(identical(d1$fingerprint_status, "complete"), "R1.4 estado complete")
check(identical(d1$fingerprint, ANA$sample$fingerprint),
      "R1.5 coincide EXACTAMENTE con la huella que produjo B12")
check(identical(d1$fingerprint, fp_muestra),
      "R1.6 y con la del helper único sobre la misma muestra")
check(identical(d1$fingerprint_source, "analytic"),
      "R1.7 la fuente de la identidad queda declarada")
check(identical(d1$n_used, AN$sample$n_used), "R1.8 n_used correcto")
# La corrección se propaga a la exportación.
check(identical(uv_a$export_table$fingerprint[1], d1$fingerprint),
      "R1.9 la exportación lleva la huella aunque no haya bootstrap")

# R2. Tras ejecutar bootstrap sobre la MISMA muestra.
d2 <- uv$reproducibility$data
check(identical(d2$fingerprint, d1$fingerprint),
      "R2.1 la huella del pasaporte no cambia al añadir el bootstrap")
check(identical(d2$fingerprint_source, "bootstrap"),
      "R2.2 con bootstrap vigente la identidad se asocia a ese resultado")
check(identical(d2$fingerprint, BOO$data_fingerprint),
      "R2.3 y coincide con la huella registrada por B13")
check(identical(uv$validation$comparability$sample_identity_verified, TRUE),
      "R2.4 OD-18: con ambas vías sobre la misma muestra, identidad verificada")

# R3. Otro dataset con el MISMO n.
set.seed(97L)
df_B <- data.frame(coste = stats::rgamma(nrow(df), shape = 2, scale = 500))
AN_B <- dist_fit_analyze(df_B, "coste", method = "mle")
check(identical(AN_B$sample$n_used, AN$sample$n_used),
      "R3.1 el segundo dataset tiene el MISMO n modelizado")
FIT_B <- AN_B$motor$fits[[DIST]]
PE_B  <- list(params = FIT_B$params, estimator = "mle", distribution = DIST)
ANA_B <- .mle_uncertainty(FIT_B, AN_B$sample$x, confidence_level = 0.95)
uv_B  <- build_uncertainty_view(AN_B, PE_B, analytic = ANA_B, manifest = manifest)
d3 <- uv_B$reproducibility$data
check(grepl(FP_RE, d3$fingerprint), "R3.2 huella válida para el segundo dataset")
check(!identical(d3$fingerprint, d1$fingerprint),
      "R3.3 mismo n pero datos distintos -> huella DISTINTA: no se hereda identidad")

# R4. MoM / PM antes del bootstrap: no se inventa huella.
mom_pe <- .estimate(DIST, AN$sample$x, "mom")
if (!is.null(mom_pe)) {
  PE_mom <- list(params = mom_pe$params, estimator = "mom", distribution = DIST)
  uv_mom <- build_uncertainty_view(AN, PE_mom, analytic = NULL, bootstrap = NULL,
                                   manifest = manifest)
  check(is.na(uv_mom$reproducibility$data$fingerprint) &&
        is.na(uv_mom$reproducibility$data$fingerprint_source),
        "R4.1 MoM sin ninguna vía calculada -> NO se inventa huella")
  check(identical(uv_mom$reproducibility$data$n_used, AN$sample$n_used),
        "R4.2 n_used se informa, pero NO sustituye a la identidad")
  BOO_mom <- .bootstrap_estimator(AN$sample$x,
                                  .bootstrap_adapter_fit(DIST, "mom",
                                                         family = AN$candidates$family,
                                                         resolution = AN$sample$resolution),
                                  B = 40L, seed = SEED, theta_hat = mom_pe$params,
                                  estimator = "mom", distribution = DIST)
  uv_mom2 <- build_uncertainty_view(AN, PE_mom, analytic = NULL,
                                    bootstrap = BOO_mom, manifest = manifest)
  d4 <- uv_mom2$reproducibility$data
  check(grepl(FP_RE, d4$fingerprint) && identical(d4$fingerprint_status, "complete"),
        "R4.3 tras el bootstrap la huella es obligatoria y está completa")
  check(identical(d4$fingerprint, fp_muestra),
        "R4.4 y es la de la misma muestra de análisis")
}
# PM antes del bootstrap: mismo principio.
pm_pre <- .pm_fit(DIST, AN$sample$x)
if (isTRUE(pm_pre$converged)) {
  uv_pm_pre <- build_uncertainty_view(
    AN, list(params = pm_pre$params, estimator = "pm", distribution = DIST,
             pm_percentiles = pm_pre$percentiles),
    analytic = NULL, bootstrap = NULL, manifest = manifest)
  check(is.na(uv_pm_pre$reproducibility$data$fingerprint),
        "R4.5 PM sin bootstrap -> tampoco se inventa huella")
}

# ------------------------------------------------------------
# F. PM ALTERNATIVO (OD-15, opción C)
# ------------------------------------------------------------
cat("\n-- F. PM alternativo --\n")

pmf <- .pm_fit(DIST, AN$sample$x)
check(identical(pmf$status, "success"), "F.1 PM estima sobre la distribución seleccionada")
PEpm <- list(params = pmf$params, estimator = "pm", distribution = DIST,
             pm_percentiles = pmf$percentiles)
BOOpm <- .bootstrap_estimator(AN$sample$x, .bootstrap_adapter_pm(DIST, pmf$percentiles),
                              B = 60L, seed = SEED, theta_hat = pmf$params,
                              estimator = "pm", distribution = DIST,
                              pm_percentiles = pmf$percentiles)
uv_pm <- build_uncertainty_view(AN, PEpm, analytic = ANA, bootstrap = BOOpm,
                                manifest = manifest)
check(identical(uv_pm$analytic$status, "not_applicable"),
      "F.2 con PM la vía analítica queda descartada, no 'fallida'")
check(any(grepl("discarded", uv_pm$diagnostics)),
      "F.3 el descarte del bloque analítico se DECLARA, no es silencioso")
check(!identical(uv_pm$comparison$comparison_status, "available"),
      "F.4 B15 NO compara analítica de MLE con bootstrap de PM")
check(identical(uv_pm$comparison$comparison_status, "bootstrap_only"),
      "F.5 con PM solo hay vía bootstrap")
check(isTRUE(uv_pm$context$is_alternative_estimator),
      "F.6 el contexto marca PM como estimador ALTERNATIVO")
check(!identical(uv_pm$point_estimate, FIT$params),
      "F.7 la estimación PM es independiente de la oficial del análisis")
check(identical(uv_pm$point_estimate, pmf$params),
      "F.8 el point estimate mostrado con PM es el de PM")
pl_pm <- build_bootstrap_plot_data(BOOpm, pmf$params, names(pmf$params)[1])
check(identical(pl_pm$theta_hat, unname(unlist(pmf$params))[1]),
      "F.9 el gráfico usa theta_hat de PM, no el del MLE")
check(identical(uv_pm$reproducibility$analysis$pm_percentiles, pmf$percentiles),
      "F.10 los percentiles PM entran en la reproducibilidad")

# PM no toca el motor ni el ranking.
check(!("pm" %in% MOD_METHOD_CHOICES),
      "F.11 PM NO está en el selector de método del análisis")
check(inherits(try(.motor(AN$sample, AN$candidates, method = "pm"), silent = TRUE),
               "try-error"),
      "F.12 .motor sigue rechazando method = 'pm'")
AN2 <- dist_fit_analyze(df, "coste", method = "mle")
check(identical(AN2$assessment$ranking, AN$assessment$ranking),
      "F.13 el ranking no cambia por haber usado PM en la vista")
check(identical(AN2$assessment$recommendation$level1,
                AN$assessment$recommendation$level1),
      "F.14 la recomendación oficial no cambia")
check(all(vapply(AN2$motor$fits, function(f) !identical(f$method, "pm"), TRUE)),
      "F.15 ningún ajuste del motor usa PM")

# ------------------------------------------------------------
# G. EXPORTACIÓN
# ------------------------------------------------------------
cat("\n-- G. Exportación --\n")

ex <- uv$export_table
check(is.data.frame(ex) && nrow(ex) == length(FIT$params),
      "G.1 grano = una fila por parámetro")
for (col in c("distribucion", "estimador", "parametro", "estimacion",
              "analitico_se", "bootstrap_se", "b_solicitadas", "b_exitosas",
              "b_fallidas", "seed", "n_modelizada", "fingerprint",
              "herramienta", "version_herramienta", "version_schema")) {
  check(col %in% names(ex), sprintf("G.2 la exportación incluye `%s`", col))
}
check(identical(ex$version_schema[1], "1.1.0"), "G.3 schema en la exportación")
check(identical(ex$seed[1], BOO$seed) && identical(ex$b_solicitadas[1], BOO$B_requested),
      "G.4 metadatos de reproducibilidad verbatim")
check(identical(ex$fingerprint[1], BOO$data_fingerprint),
      "G.5 huella verbatim, no recalculada")
check(nrow(uv_pm$export_table) == length(pmf$params) &&
      identical(uv_pm$export_table$pm_percentiles[1],
                paste(pmf$percentiles, collapse = "/")),
      "G.6 con PM se exporta su configuración de percentiles")
# El export del ranking no cambia de grano.
vm <- prepare_view_model(AN, manifest = manifest)
check(nrow(vm$export_table) == length(AN$assessment$ranking),
      "G.7 el export del ranking conserva su grano (una fila por distribución)")
check(!("parametro" %in% names(vm$export_table)),
      "G.8 el export del ranking NO se ha contaminado con columnas de parámetro")

# ------------------------------------------------------------
# H. SCHEMA Y VERSIÓN
# ------------------------------------------------------------
cat("\n-- H. Schema y versión --\n")

check(identical(DFIT_SCHEMA_VERSION, "1.1.0"), "H.1 schema sigue en 1.1.0")
check(identical(as.character(manifest$version), "1.0.2"), "H.2 manifest sigue en 1.0.2")
check(identical(vm$meta$schema_version, "1.1.0"), "H.3 el View Model expone 1.1.0")
check(is.null(vm$uncertainty),
      "H.4 la incertidumbre NO se cuelga del View Model: estructura paralela")

# ------------------------------------------------------------
# AUTO. ESTIMADOR EFECTIVO, NO EL SOLICITADO
# ------------------------------------------------------------
# `meta$method` es el método SOLICITADO; con "auto", `.fit_auto()` puede caer a
# MoM o L-momentos POR DISTRIBUCIÓN. La fuente de verdad es `fits[[id]]$method`.
cat("\n-- AUTO. Estimador efectivo --\n")

AN_AUTO <- dist_fit_analyze(df, "coste", method = "auto")
check(identical(AN_AUTO$meta$method, "auto"),
      "AUTO.0 el análisis registra el método SOLICITADO")

# Fixture controlada: se fuerza el método EFECTIVO de una distribución a "mom"
# SIN tocar `.fit_auto()`. Es el único modo determinista de separar el método
# solicitado del efectivo, que es exactamente lo que el contrato exige.
#
# La distribución NO puede darse por supuesta: `DFIT_MOM` no incluye `burr` —el
# catálogo declara que Burr no dispone de MoM ni L-momentos en v1— y varios
# estimadores MoM declinan legítimamente según la muestra (`.mom_pareto` exige
# CV^2 > 1, `.mom_loglogistic` exige forma > 2). Se recorre el ranking y se toma
# la PRIMERA candidata cuyo MoM sea realmente calculable, de modo que la fixture
# es determinista sin depender de qué distribución gane el ranking.
FX <- AN_AUTO
D2 <- NULL; mom <- NULL
for (e in AN_AUTO$assessment$ranking) {
  cand <- .estimate(e$id, FX$sample$x, "mom")
  if (!is.null(cand) && !is.null(cand$params) &&
      length(cand$params) > 0L && all(is.finite(unlist(cand$params)))) {
    D2 <- e$id; mom <- cand; break
  }
}
check(!is.null(mom), "AUTO.1 la fixture usa un MoM realmente disponible")
cat(sprintf("     distribución de la fixture: %s (MoM real)\n", D2))
FX$motor$fits[[D2]]$method <- "mom"
FX$motor$fits[[D2]]$params <- mom$params
fit_fx <- FX$motor$fits[[D2]]
check(identical(FX$meta$method, "auto") && identical(fit_fx$method, "mom"),
      "AUTO.2 fixture: meta = 'auto' pero método efectivo = 'mom'")

PE_fx <- list(params = fit_fx$params, estimator = fit_fx$method, distribution = D2)
uv_fx <- build_uncertainty_view(FX, PE_fx, analytic = NULL, bootstrap = NULL,
                                manifest = manifest)
check(identical(uv_fx$context$estimator, "mom"),
      "AUTO.A el estimador base de la vista es fit$method")
check(!identical(uv_fx$context$estimator, "mle") &&
      !grepl("MLE", uv_fx$context$estimator_label),
      "AUTO.B NO se etiqueta como MLE")
check(identical(uv_fx$context$analysis_method_requested, "auto") &&
      identical(uv_fx$context$analysis_method_effective, "mom"),
      "AUTO.B2 el contexto distingue método solicitado y efectivo")
check(!isTRUE(uv_fx$context$is_alternative_estimator),
      "AUTO.B3 MoM efectivo no se marca como estimador alternativo")
check(identical(uv_fx$point_estimate, fit_fx$params),
      "AUTO.D los parámetros son los del fit seleccionado")

# E. Sin inferencia analítica cuando el método efectivo no es MLE.
uv_fx2 <- build_uncertainty_view(FX, PE_fx, analytic = ANA, bootstrap = NULL,
                                 manifest = manifest)
check(identical(uv_fx2$analytic$status, "not_applicable"),
      "AUTO.E con método efectivo MoM no hay inferencia analítica")
check(any(grepl("discarded", uv_fx2$diagnostics)),
      "AUTO.E2 el descarte del bloque analítico se declara")

# F. El bootstrap usa el adaptador del método efectivo.
BOO_fx <- .bootstrap_estimator(FX$sample$x,
                               .bootstrap_adapter_fit(D2, fit_fx$method,
                                                      family = FX$candidates$family,
                                                      resolution = FX$sample$resolution),
                               B = 40L, seed = SEED, theta_hat = fit_fx$params,
                               estimator = fit_fx$method, distribution = D2)
check(identical(BOO_fx$estimator, "mom"),
      "AUTO.F el bootstrap se ejecuta con el estimador efectivo")
uv_fx3 <- build_uncertainty_view(FX, PE_fx, analytic = NULL, bootstrap = BOO_fx,
                                 manifest = manifest)
check(identical(uv_fx3$comparison$comparison_status, "bootstrap_only"),
      "AUTO.F2 con MoM solo hay vía bootstrap")
check(identical(uv_fx3$reproducibility$analysis$estimator, "mom"),
      "AUTO.F3 la reproducibilidad registra el estimador efectivo")

# G. Otra distribución con método efectivo distinto actualiza la lectura.
# Se elige una candidata DISTINTA de la mutada: solo `D2` tiene "mom" en la
# fixture, de modo que la comparación discrimina de verdad.
otras <- Filter(function(e) !identical(e$id, D2), AN_AUTO$assessment$ranking)
if (length(otras) > 0L) {
  D3 <- otras[[1]]$id
  fit3 <- FX$motor$fits[[D3]]
  PE3 <- list(params = fit3$params, estimator = fit3$method, distribution = D3)
  uv3 <- build_uncertainty_view(FX, PE3, manifest = manifest)
  check(identical(uv3$context$estimator, fit3$method),
        "AUTO.G otra distribución -> su propio método efectivo")
  check(!identical(uv3$context$estimator, uv_fx$context$estimator),
        "AUTO.G2 el método efectivo se lee por distribución, no del análisis")
  check(identical(uv3$context$analysis_method_requested, "auto"),
        "AUTO.G3b el método solicitado sigue siendo el mismo para ambas")
}

# H. Ranking y recomendación intactos.
check(identical(AN_AUTO$assessment$ranking,
                dist_fit_analyze(df, "coste", method = "auto")$assessment$ranking),
      "AUTO.H el ranking no se ve afectado")

# Pin del contrato en el código reactivo: la derivación NO puede volver a
# traducir "auto" a "mle" ni leer `meta$method` como estimador base.
src_mod <- paste(readLines(file.path(.tool_root, "R", "mod_tool.R"),
                           warn = FALSE), collapse = "\n")
check(grepl("unc_base_estimator <- shiny::reactive", src_mod, fixed = TRUE),
      "AUTO.I existe un reactivo dedicado al estimador efectivo")
check(!grepl('identical(base, "auto")', src_mod, fixed = TRUE),
      "AUTO.I2 no queda la traducción artificial 'auto' -> 'mle'")
check(grepl('motor$fits[[id]]$method', src_mod, fixed = TRUE),
      "AUTO.I3 el estimador base se lee del ajuste seleccionado")

# ------------------------------------------------------------
# A-D. COMPORTAMIENTO REACTIVO
# ------------------------------------------------------------
cat("\n-- A-D. Reactivo (testServer) --\n")

shiny::testServer(mod_tool_server, args = list(manifest = manifest), {
  session$setInputs(variable = "coste", metodo = "mle", profundidad = "standard")
  session$setInputs(calcular = 1)
  check(!is.null(analysis()), "A.0 el análisis se calcula al pulsar Calcular")
  n_calls <- 0L
  base_sel <- selected_id()

  # AUTO en el camino reactivo: el estimador base sale del ajuste, no de meta.
  base0 <- unc_base_estimator()
  check(identical(base0, analysis()$motor$fits[[selected_id()]]$method),
        "AUTO.C unc_base_estimator() == fits[[selected_id()]]$method")
  session$setInputs(unc_estimador = base0)
  check(identical(unc_point()$estimator, base0) &&
        identical(unc_point()$params,
                  analysis()$motor$fits[[selected_id()]]$params),
        "AUTO.C2 unc_point() usa estimador y parámetros del ajuste seleccionado")
  ids0 <- ranked_ids()
  if (length(ids0) > 1L) {
    session$setInputs(tabla_ranking_rows_selected = 2L)
    check(identical(unc_base_estimator(),
                    analysis()$motor$fits[[selected_id()]]$method),
          "AUTO.G3 cambiar de fila reevalúa el estimador efectivo")
    session$setInputs(tabla_ranking_rows_selected = 1L)
  }

  # A. Navegación.
  session$setInputs(ir_incertidumbre = 1)
  a1 <- analysis()
  session$setInputs(volver_analisis = 1)
  check(identical(analysis(), a1), "A.1 navegar no recalcula analysis()")
  check(identical(selected_id(), base_sel), "A.2 selected_id se preserva al navegar")

  # B. El bootstrap NO se dispara solo.
  session$setInputs(unc_estimador = "mle", unc_B = "500", unc_nivel = 0.95,
                    unc_seed = 12345)
  check(is.null(unc_boot()), "B.1 entrar en la vista NO ejecuta bootstrap")
  session$setInputs(unc_B = "1000")
  session$setInputs(unc_nivel = 0.90)
  session$setInputs(unc_seed = 777)
  check(is.null(unc_boot()), "B.2 cambiar B/nivel/semilla NO ejecuta bootstrap")
  ids <- ranked_ids()
  if (length(ids) > 1L) {
    session$setInputs(tabla_ranking_rows_selected = 2L)
    check(is.null(unc_boot()), "B.3 cambiar de fila del ranking NO ejecuta bootstrap")
    session$setInputs(tabla_ranking_rows_selected = 1L)
  }
  session$setInputs(unc_seed = 4242, unc_B = "500", unc_nivel = 0.95)
  session$setInputs(unc_calcular = 1)
  check(!is.null(unc_boot()), "B.4 sí se ejecuta al pulsar la acción explícita")
  st1 <- unc_boot()
  check(!is.null(unc_boot_vigente()), "B.5 el resultado es vigente tras ejecutar")
  check(identical(st1$bootstrap$B_requested, 500L),
        "B.6 se usó el B seleccionado")

  # C. Identidad / invalidación.
  session$setInputs(unc_B = "1000")
  check(is.null(unc_boot_vigente()), "C.1 cambiar B invalida la vigencia")
  session$setInputs(unc_B = "500")
  check(!is.null(unc_boot_vigente()), "C.2 restaurar la configuración la revalida")
  session$setInputs(unc_nivel = 0.90)
  check(is.null(unc_boot_vigente()), "C.3 cambiar el nivel invalida")
  session$setInputs(unc_nivel = 0.95)
  session$setInputs(unc_seed = 999)
  check(is.null(unc_boot_vigente()), "C.4 cambiar la semilla invalida")
  session$setInputs(unc_seed = 4242)
  check(!is.null(unc_boot_vigente()), "C.5 vuelve a ser vigente con la semilla original")
  if (length(ids) > 1L) {
    session$setInputs(tabla_ranking_rows_selected = 2L)
    check(is.null(unc_boot_vigente()),
          "C.6 cambiar de distribución invalida: no se reutiliza en silencio")
    session$setInputs(tabla_ranking_rows_selected = 1L)
    check(!is.null(unc_boot_vigente()), "C.7 volver a la distribución original la revalida")
  }
  session$setInputs(unc_estimador = "pm")
  check(is.null(unc_boot_vigente()), "C.8 cambiar de estimador invalida")
  session$setInputs(unc_estimador = "mle")

  # D. Metadatos congelados.
  st_before <- unc_boot()
  session$setInputs(unc_seed = 5555, unc_B = "2000", unc_nivel = 0.80)
  check(identical(unc_boot(), st_before),
        "D.1 editar los inputs NO altera el resultado ya calculado")
  check(identical(unc_boot()$bootstrap$seed, 4242L),
        "D.2 la semilla congelada del resultado es la realmente usada")
  check(is.null(unc_boot_vigente()),
        "D.3 pero deja de presentarse como vigente")

  # PM dentro de la vista.
  session$setInputs(unc_seed = 4242, unc_B = "500", unc_nivel = 0.95,
                    unc_estimador = "pm")
  pe <- unc_point()
  check(identical(pe$estimator, "pm") && !is.null(pe$params),
        "F.16 PM se estima dentro de la vista")
  check(is.null(unc_analytic()),
        "F.17 con PM no se calcula inferencia analítica")
  check(identical(analysis()$meta$method, "mle"),
        "F.18 el análisis principal sigue en MLE")
})

cat("\nB16.1 — VISTA DE INCERTIDUMBRE VERIFICADA\n")
