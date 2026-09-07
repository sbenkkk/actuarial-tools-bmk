# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b6_unit_tests.R
# Tests unitarios de B6 (ViewModel): secciones del §12, presentación (iconos,
# tokens de color, orden), copia fiel de las capas previas (sin recalcular),
# ausencia de texto nuevo y especificación de gráficos SIN datos (B7).
# Autor: BMK — Última actualización: 2026-07-25
# ============================================================
#
#   Rscript tests/b6_unit_tests.R      # desde la raíz de la herramienta
#   Rscript b6_unit_tests.R            # desde la carpeta tests/

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

cat("== B6 UNIT TESTS (ViewModel) — distribution-fitting ==\n")

xc <- c(120.3, 340.7, 550.1, 610.4, 800.9, 1200.2, 1500.6, 2100.8, 2600.5, 3400.1, 5200.7, 9800.4)
xd <- c(0, 1, 0, 2, 1, 3, 0, 1, 2, 4, 1, 0, 2, 1, 5)

an <- dist_fit_analyze(data.frame(loss_amount = xc), "loss_amount")
mf <- list(name = "Ajuste de Distribuciones", version = "1.0.0")
vm <- prepare_view_model(an, manifest = mf, generated_at = "2026-07-25")

# ------------------------------------------------------------
# 1. Secciones del contrato §12
# ------------------------------------------------------------
cat("\n-- 1. Secciones §12 --\n")
check(all(c("meta", "input_summary", "sample", "dataset_diagnosis", "metric_cards",
            "ranking", "recommendation", "fits", "plots", "interpretation", "warnings",
            "export_table", "presentation") %in% names(vm)),
      "view model: expone todas las secciones del §12 + sample (ADR-026) + presentation")
# ADR-026: cambio ADITIVO del contrato (nuevo bloque `sample`). Sube la versión de
# la FORMA del View Model; el criterio (decision_engine_version) no cambia.
check(vm$meta$schema_version == "1.1.0",              "meta: schema_version del contrato (1.1.0, ADR-026)")
check(vm$meta$decision_engine_version == "0.2",       "meta: decision_engine_version copiado (sin cambio)")
check(vm$meta$tool_version == "1.0.0" && vm$meta$variable == "loss_amount",
      "meta: versión del manifest sintético (mf) y variable modelizada")
check(!is.null(vm$sample) && vm$sample$n_used == length(xc) &&
        vm$sample$n_excluded_zeros == 0L,
      "sample: bloque presente; sin ceros que excluir en este dataset")
check(vm$meta$analysis_depth == "standard",           "meta: perfil de profundidad")

# ------------------------------------------------------------
# 2. Metric cards (§12.3)
# ------------------------------------------------------------
cat("\n-- 2. Metric cards --\n")
check(length(vm$metric_cards) == 4L,                  "cards: 4 KPIs de cabecera")
check(vm$metric_cards[[1]]$value == an$motor$fits[[an$assessment$recommendation$level1$id]]$label,
      "card 1: distribución recomendada (copiada del assessment)")
check(vm$metric_cards[[4]]$status == "deferred",
      "card 4: calidad de cola marcada como diferida (Pilar C)")
check(all(vapply(vm$metric_cards, function(c) is.character(c$icon), logical(1))),
      "cards: icono declarado como nombre (bsicons)")

# ------------------------------------------------------------
# 3. Tabla de ranking (§12.4): copia fiel, sin recalcular
# ------------------------------------------------------------
cat("\n-- 3. Ranking --\n")
check(is.data.frame(vm$ranking$data),                 "ranking: data.frame listo para DT")
check(nrow(vm$ranking$data) == length(an$assessment$ranking) + length(an$assessment$excluded),
      "ranking: una fila por candidata evaluada + descartada")
check(abs(vm$ranking$data$puntuacion[1] - round(an$assessment$ranking[[1]]$composite, 1)) < 1e-9,
      "ranking: la puntuación se copia del assessment (no se recalcula)")
check(vm$ranking$data$estado[1] == "Recomendada",     "ranking: marca la fila recomendada")
check(all(names(vm$ranking$column_labels) %in% names(vm$ranking$data)),
      "ranking: etiquetas de columna coherentes con los datos")

# ------------------------------------------------------------
# 4. Recomendación (§12.5): reutiliza el texto de B5, sin generar texto nuevo
# ------------------------------------------------------------
cat("\n-- 4. Recomendación --\n")
check(identical(vm$recommendation$level1$headline, an$text_builder$recommendation$headline),
      "recomendación: headline idéntico al de B5 (no se genera texto nuevo)")
check(identical(vm$recommendation$level1$params,
                an$motor$fits[[an$assessment$recommendation$level1$id]]$params),
      "recomendación: parámetros copiados del motor")
check(vm$recommendation$level2_use_case$status == "deferred" &&
        vm$recommendation$evt_recommendation$status == "deferred",
      "recomendación: Nivel 2 y EVT marcados como diferidos")

# ------------------------------------------------------------
# 5. Plots (§12.7): ESPECIFICACIÓN sin datos (los genera B7)
# ------------------------------------------------------------
cat("\n-- 5. Plots (spec) --\n")
check(length(vm$plots) == 5L,                         "plots (continua): 5 gráficos especificados")
check(all(vapply(vm$plots, function(p) is.null(p$data), logical(1))),
      "plots: sin datos numéricos (evaluación diferida al Visual Engine, B7)")
check(sum(vapply(vm$plots, function(p) p$status == "pending_visual_engine", logical(1))) == 3L,
      "plots: 3 pendientes de B7 (histograma, QQ, PP)")
check(sum(vapply(vm$plots, function(p) p$status == "deferred", logical(1))) == 2L,
      "plots: 2 diferidos por requerir Pilar C (mean-excess, VaR/TVaR)")

# ------------------------------------------------------------
# 6. Interpretación, avisos y exportación
# ------------------------------------------------------------
cat("\n-- 6. Interpretación / avisos / exportación --\n")
check(identical(vm$interpretation$summary, an$text_builder$summary),
      "interpretación: summary copiado de B5")
check(length(vm$interpretation$cards) == length(an$text_builder$distribution_cards),
      "interpretación: una card por distribución (de B5)")
check(is.data.frame(vm$export_table) &&
        nrow(vm$export_table) == length(an$assessment$ranking),
      "export_table: data.frame con una fila por distribución evaluada")
check(all(c("distribucion", "puntuacion", "aic", "bic") %in% names(vm$export_table)),
      "export_table: columnas de exportación presentes")

# ------------------------------------------------------------
# 7. Presentación: tokens semánticos, sin colores literales
# ------------------------------------------------------------
cat("\n-- 7. Presentación --\n")
check(!any(grepl("#", unlist(vm$presentation), fixed = TRUE)),
      "presentación: sin literales de color (solo tokens semánticos)")
check(!any(grepl("#", vapply(vm$metric_cards, function(c) c$tone, character(1)), fixed = TRUE)),
      "cards: tone es un token semántico, no un hex")
check(vm$presentation$section_order[1] == "metric_cards",
      "presentación: orden de secciones definido")

# ------------------------------------------------------------
# 8. Determinismo y familia discreta
# ------------------------------------------------------------
cat("\n-- 8. Determinismo / discreta --\n")
check(identical(prepare_view_model(an, manifest = mf, generated_at = "2026-07-25"), vm),
      "determinismo: misma entrada y fecha -> mismo View Model")
vd <- prepare_view_model(dist_fit_analyze(data.frame(count = xd), "count"),
                         manifest = mf, generated_at = "2026-07-25")
check(vd$meta$family == "discrete",                   "discreta: familia en meta")
check(length(vd$plots) == 3L,
      "discreta: solo los gráficos aplicables a su familia (3)")
check(vd$dataset_diagnosis$flags$looks_like_count,    "discreta: flag looks_like_count activo")

# ------------------------------------------------------------
# 9. Datos de la ficha técnica (copiados, no recalculados)
# ------------------------------------------------------------
cat("\n-- 9. Ficha técnica --\n")
f1 <- vm$fits[[1]]
check(all(c("loglik", "verdict", "method", "n_used", "params", "pillar_scores", "metrics")
          %in% names(f1)),
      "fits: expone loglik, verdict, método y métricas para la ficha técnica")
check(identical(f1$loglik, an$motor$fits[[f1$id]]$logLik),
      "fits: la log-verosimilitud se copia del motor (no se recalcula)")
check(is.character(f1$verdict) && nzchar(f1$verdict),
      "fits: el veredicto viene redactado por los Text Builders")
check(identical(f1$verdict,
                Filter(function(c) identical(c$id, f1$id),
                       an$text_builder$distribution_cards)[[1]]$verdict),
      "fits: el veredicto es exactamente el de B5 (sin texto nuevo)")
check(all(vapply(vm$fits, function(f) !is.null(f$loglik), logical(1))),
      "fits: todas las candidatas evaluadas exponen su log-verosimilitud")
check(all(vapply(vm$fits, function(f) !is.null(f$n_params), logical(1))),
      "fits: expone el nº de parámetros para la ficha y la comparación")
check(length(vm$fits[[1]]$vs_recommended) == 0L &&
        length(vm$fits[[2]]$vs_recommended) == 3L,
      "fits: la comparación con la recomendada llega desde B5")

cat("\nB6 UNIT TESTS SUPERADOS\n")
