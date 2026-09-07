# ============================================================
# Tool: kernel-density
# Archivo: tests/smoke_test.R
# SMOKE TEST de ejecución real (headless, shiny::testServer). Cubre los flujos
# principales sin navegador. Preparado para el primer ensamblado.
# Autor: BMK — Última actualización: 2026-07-19
# ============================================================
#
#   Rscript tests/smoke_test.R        # desde tools/kernel-density/
#
# Requiere: shiny, bslib, DT, plotly, ggplot2, glue, readr, yaml, bsicons,
# shinycssloaders (las dependencias del framework).

library(shiny)
library(bslib)
source("../../shared/load_shared.R")
source("R/calc.R")
source("R/mod_tool.R")

manifest <- yaml::read_yaml("manifest.yml")
ok <- function(cond, msg) {
  if (!isTRUE(cond)) stop(sprintf("SMOKE FALLO: %s", msg), call. = FALSE)
  cat(sprintf("  OK  - %s\n", msg))
}

cat("== SMOKE TEST — kernel-density ==\n")

# --- 6) Dataset inválido (validación) — fuera de testServer -------------------
bad <- bmk_validate_data(data.frame(foo = 1:3), c(loss_amount = "numeric"))
ok(isFALSE(bad$valid) && length(bad$errors) > 0,
   "6. Dataset inválido: bmk_validate_data marca is_valid=FALSE con error")
good <- bmk_validate_data(data.frame(loss_amount = c(1, 2, 3)), c(loss_amount = "numeric"))
ok(isTRUE(good$valid), "   contrato válido con loss_amount numérico")

# --- Escenarios 1-5 en el servidor real (testServer) --------------------------
testServer(mod_tool_server, args = list(manifest = manifest), {

  base_inputs <- function(...) session$setInputs(
    sev_col = "loss_amount", kernel = "gaussian", bw_method = "silverman",
    var_levels = c("0.95", "0.995"), ...
  )

  # 1) Apertura con dataset de ejemplo
  base_inputs(calcular = 1)
  vm <- view_model()
  ok(setequal(names(vm),
     c("cards","plots","tables","indicator","insights","downloads","metadata")),
     "1. Apertura con ejemplo: View Model con 7 bloques")
  ok(vm$metadata$kernel == "gaussian" && vm$metadata$bandwidth_method == "silverman",
     "   metadata por defecto (gaussian + silverman)")
  ok(length(vm$cards) == 4L && nrow(vm$tables$risk) == 2L,
     "   4 cards y 2 niveles de VaR (95% + 99,5%)")

  # 2) Cambio de kernel
  session$setInputs(kernel = "epanechnikov", calcular = 2)
  ok(view_model()$metadata$kernel == "epanechnikov",
     "2. Cambio de kernel: recalcula con epanechnikov")

  # 3) Cambio de bandwidth
  session$setInputs(kernel = "gaussian", bw_method = "scott", calcular = 3)
  ok(view_model()$metadata$bandwidth_method == "scott",
     "3. Cambio de bandwidth: recalcula con scott")

  # 4) Bandwidth manual
  # ADR-024: se fijan AMBOS inputs del bandwidth manual. El servidor lee
  # `input$h_manual_num` (el numérico); el slider `h_manual` se sincroniza con él
  # mediante `updateNumericInput()`, que solo surte efecto en el navegador.
  # `testServer()` no ejecuta esa sincronización, de modo que fijar solo el slider
  # dejaba `h_manual_num` en NULL, disparaba la guarda del servidor y su
  # `req(FALSE)` abortaba el test con un error silencioso de mensaje vacío
  # (clase `shiny.silent.error`). No es un fallo funcional: en la aplicación real
  # la sincronización sí ocurre.
  session$setInputs(bw_method = "manual", h_manual = 60, h_manual_num = 60,
                    calcular = 4)
  # El bloque vigente del View Model es `indicator` (automatic, h, h_label,
  # band_low, band_high, status, ref_caption). No existe un bloque `bandwidth`.
  ok(abs(view_model()$indicator$h - 60) < 1e-9,
     "4. Bandwidth manual: h = 60 aplicado")

  # 5) Exportaciones (los data.frame de downloads existen y son válidos)
  session$setInputs(bw_method = "silverman", calcular = 5)
  dl <- view_model()$downloads
  ok(setequal(names(dl), c("diagnostics","risk","model_summary")),
     "5. Exportaciones: downloads con diagnostics/risk/model_summary")
  ok(all(vapply(dl, is.data.frame, logical(1))),
     "   los tres downloads son data.frame exportables")
})

cat("\nSMOKE TEST SUPERADO\n")
