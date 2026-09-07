# ============================================================
# Tool: kernel-density
# Archivo: tests/integration_view_model.R
# Comprobación de INTEGRACIÓN (manual, no testthat) del Sub-bloque 4B.
# Autor: BMK — Última actualización: 2026-07-19
# ============================================================
#
# Verifica en ejecución que el pipeline motor -> View Model funciona y respeta el
# contrato, SIN Shiny (prepare_view_model y calc.R son puros; solo se necesitan
# los formatters de shared/). Preparado para ejecutarse en el primer ensamblado:
#
#   Rscript tests/integration_view_model.R      # desde tools/kernel-density/
#
# No forma parte de la app; es una salvaguarda de integración de Fase 1.

# --- Carga mínima (sin Shiny) -------------------------------------------------
source("../../shared/theme/colors.R")        # bmk_colors (por si algún formatter lo usa)
source("../../shared/config.R")              # bmk_config
source("../../shared/utils/formatters.R")    # bmk_format_number/currency/percent
source("R/calc.R")                           # motor
# mod_tool.R define prepare_view_model() y helpers en el top-level (sin evaluar
# Shiny al hacer source): las funciones de UI/servidor solo se definen, no se llaman.
source("R/mod_tool.R")

stopifnot_msg <- function(cond, msg) {
  if (!isTRUE(cond)) stop(sprintf("FALLO: %s", msg), call. = FALSE)
  cat(sprintf("  OK  - %s\n", msg))
}

cat("== Integración motor -> View Model ==\n")

# --- 1) Motor: kde_analyze sobre datos de ejemplo reproducibles ---------------
x  <- make_example_data(n = 300L, seed = 20260719L)$loss_amount
an <- kde_analyze(x, kernel = "gaussian", method = "silverman",
                  levels = c(0.95, 0.99, 0.995),
                  tool_version = "1.0.0", seed = 20260719L)

stopifnot_msg(setequal(names(an),
  c("input","bandwidth","estimation","diagnostics","assessment","text","metadata")),
  "kde_analyze devuelve los 7 bloques del contrato del motor")

# --- 2) Adapter: prepare_view_model -------------------------------------------
vm <- prepare_view_model(an, x, manifest = list(version = "1.0.0"))

stopifnot_msg(setequal(names(vm),
  c("cards","plots","tables","indicator","insights","downloads","metadata")),
  "View Model tiene los 7 bloques por componente UI")
stopifnot_msg(length(vm$cards) == 4L, "cards: 4 metric cards")
stopifnot_msg(setequal(names(vm$plots), c("density","cdf")), "plots: density + cdf")
stopifnot_msg(setequal(names(vm$tables), c("risk","model_summary","diagnostic")),
              "tables: risk + model_summary + diagnostic")
stopifnot_msg(setequal(names(vm$indicator),
  c("automatic","h","h_label","band_low","band_high","status","ref_caption")),
  "indicator: campos del bandwidth")
stopifnot_msg(setequal(names(vm$insights),
  c("diagnostic_notes","bandwidth_message","quality","diagnosis","recommendation")),
  "insights: 5 bloques de texto")
# ADR-023: contrato real y documentado de `downloads` (README, implementación y
# los tres downloadHandler de la UI): diagnostics / risk / model_summary.
stopifnot_msg(setequal(names(vm$downloads), c("diagnostics","risk","model_summary")),
              "downloads: diagnostics + risk + model_summary")

# --- 3) Reproducibilidad en metadata ------------------------------------------
md <- vm$metadata
stopifnot_msg(all(c("engine_version","tool_version","bandwidth_method","kernel",
                    "seed","created_at") %in% names(md)),
              "metadata: campos de reproducibilidad presentes")
stopifnot_msg(identical(md$seed, 20260719L), "metadata: seed correcto")

# --- 4) Coherencia: valores del View Model consistentes con el motor ----------
stopifnot_msg(nrow(vm$downloads$risk) == 3L, "downloads$risk: una fila por nivel")
# ADR-023: sustituye la comprobación de `downloads$curve` (bloque inexistente).
# La rejilla grid_n se sigue verificando sobre el motor y sobre plots/cdf.
stopifnot_msg(all(c("statistic", "value") %in% names(vm$downloads$diagnostics)) &&
                nrow(vm$downloads$diagnostics) > 0L,
              "downloads$diagnostics: statistic + value, no vacío")
stopifnot_msg(nrow(vm$downloads$model_summary) == 5L + 2L * nrow(vm$downloads$risk),
              "downloads$model_summary: 5 campos fijos + 2 filas por nivel")
stopifnot_msg(all(vapply(vm$cards, function(c) is.character(c$value) || is.numeric(c$value),
                         logical(1))), "cards: valores formateados presentes")

cat("\nTODAS LAS COMPROBACIONES DE INTEGRACIÓN OK\n")
