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
  c("automatic","h","band_low","band_high","status","rel_position")),
  "indicator: campos del bandwidth")
stopifnot_msg(setequal(names(vm$insights),
  c("diagnostic_notes","bandwidth_message","quality","diagnosis","recommendation")),
  "insights: 5 bloques de texto")
stopifnot_msg(setequal(names(vm$downloads), c("summary","risk","curve")),
              "downloads: summary + risk + curve")

# --- 3) Reproducibilidad en metadata ------------------------------------------
md <- vm$metadata
stopifnot_msg(all(c("engine_version","tool_version","bandwidth_method","kernel",
                    "seed","created_at") %in% names(md)),
              "metadata: campos de reproducibilidad presentes")
stopifnot_msg(identical(md$seed, 20260719L), "metadata: seed correcto")

# --- 4) Coherencia: valores del View Model consistentes con el motor ----------
stopifnot_msg(nrow(vm$downloads$risk) == 3L, "downloads$risk: una fila por nivel")
stopifnot_msg(nrow(vm$downloads$curve) == KDE_DEFAULTS$grid_n,
              "downloads$curve: grid_n puntos")
stopifnot_msg(all(vapply(vm$cards, function(c) is.character(c$value) || is.numeric(c$value),
                         logical(1))), "cards: valores formateados presentes")

cat("\nTODAS LAS COMPROBACIONES DE INTEGRACIÓN OK\n")
