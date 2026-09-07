# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b8_smoke_test.R
# SMOKE TEST de la interfaz (B8) con shiny::testServer, sin navegador. Verifica
# que la UI renderiza consumiendo ÚNICAMENTE el View Model (B6) y los datos del
# Visual Engine (B7), y que la interacción del usuario funciona de extremo a
# extremo. No valida estadística (bloques B1-B7, congelados).
# Autor: BMK — Última actualización: 2026-07-25
# ============================================================
#
#   Rscript tests/b8_smoke_test.R      # desde la raíz de la herramienta
#   Rscript b8_smoke_test.R            # desde la carpeta tests/
#
# Requiere las dependencias del framework: shiny, bslib, DT, ggplot2, readr,
# yaml, bsicons, shinycssloaders.

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
# El módulo lee data/example_data.csv por ruta relativa: nos situamos en la raíz.
.old_wd <- setwd(.tool_root)

library(shiny)
library(bslib)
source("../../shared/load_shared.R")
source("R/calc.R")
source("R/mod_tool.R")

manifest <- yaml::read_yaml("manifest.yml")

check <- function(cond, msg) {
  if (!isTRUE(cond)) stop(sprintf("SMOKE FALLO: %s", msg), call. = FALSE)
  cat(sprintf("  OK  - %s\n", msg))
}

# Registro de warnings emitidos durante el test: el criterio de aprobación exige
# que la aplicación no genere warnings propios (p. ej. de resolución de fuentes).
.warns <- character(0)

cat("== B8 SMOKE TEST (Shiny UI) — distribution-fitting ==\n")

# ------------------------------------------------------------
# 1. UI: se construye sin errores
# ------------------------------------------------------------
cat("\n-- 1. Construcción de la UI --\n")
ui <- mod_tool_ui("tool")
check(!is.null(ui), "mod_tool_ui: se construye sin errores")

# ------------------------------------------------------------
# 2. Validación de datos (fuera de testServer)
# ------------------------------------------------------------
cat("\n-- 2. Validación de datos --\n")
bad <- bmk_validate_data(data.frame(foo = 1:3), c(loss_amount = "numeric"))
check(isFALSE(bad$valid) && length(bad$errors) > 0,
      "dataset inválido: bmk_validate_data marca is_valid = FALSE")
good <- bmk_validate_data(data.frame(loss_amount = c(1.5, 2.5, 3.5)),
                          c(loss_amount = "numeric"))
check(isTRUE(good$valid), "contrato válido con loss_amount numérico")

# ------------------------------------------------------------
# 3. Flujo de extremo a extremo en el servidor real
# ------------------------------------------------------------
withCallingHandlers(
testServer(mod_tool_server, args = list(manifest = manifest), {

  cat("\n-- 3. Cálculo con datos de ejemplo --\n")
  session$setInputs(variable = "loss_amount", metodo = "mle",
                    profundidad = "standard", calcular = 1)

  an <- analysis()
  check(!is.null(an), "el motor devuelve un análisis con el dataset de ejemplo")

  vm <- view_model()
  check(all(c("meta", "metric_cards", "ranking", "recommendation", "interpretation",
              "warnings", "export_table") %in% names(vm)),
        "la UI recibe el View Model completo (B6)")
  check(vm$meta$tool_version == manifest$version,
        "meta: la versión mostrada procede del manifest")

  vd <- visual_data()
  check(vd$qq_plot$status == "ready" && vd$pp_plot$status == "ready",
        "la UI recibe los datos de gráficos (B7) listos")

  cat("\n-- 4. Renderizado --\n")
  check(!is.null(output$metricas), "metric cards renderizadas")
  check(!is.null(output$interpretacion), "caja de interpretación renderizada")
  # Los gráficos se validan por su constructor (no se fuerza el dispositivo).
  check(inherits(.plot_fit_overlay(vd, vm$recommendation$level1$id), "ggplot"),
        "gráfico de ajuste: objeto ggplot construido desde los datos de B7")
  check(inherits(.plot_qq(vd), "ggplot") && inherits(.plot_pp(vd), "ggplot"),
        "QQ y PP: objetos ggplot construidos desde los datos de B7")
  check(nrow(vm$ranking$data) ==
          length(an$assessment$ranking) + length(an$assessment$excluded),
        "la tabla muestra todas las candidatas (evaluadas + descartadas)")
  check(is.data.frame(vm$export_table) && nrow(vm$export_table) > 0,
        "exportación: data.frame no vacío")

  cat("\n-- 5. Interacción: cambio de método --\n")
  session$setInputs(metodo = "auto", calcular = 2)
  check(analysis()$motor$method == "auto",
        "cambiar el método recalcula con la opción elegida")

  cat("\n-- 6. Interacción: cambio de variable --\n")
  session$setInputs(variable = "exposure", metodo = "mle", calcular = 3)
  check(analysis()$meta$variable == "exposure",
        "cambiar la variable recalcula sobre la columna elegida")
  check(!is.null(view_model()$metric_cards),
        "el View Model se reconstruye tras el cambio de variable")

  cat("\n-- 7. Profundidad del análisis --\n")
  session$setInputs(variable = "loss_amount", profundidad = "comprehensive",
                    calcular = 4)
  check(view_model()$meta$analysis_depth == "comprehensive",
        "el perfil de profundidad viaja al View Model")

  cat("\n-- 8. Explorador: sincronización ranking <-> gráfico --\n")
  session$setInputs(variable = "loss_amount", metodo = "mle",
                    profundidad = "standard", calcular = 5)
  recomendada <- view_model()$recommendation$level1$id
  check(identical(selected_id(), recomendada),
        "selección inicial = distribución recomendada")

  ids <- vapply(view_model()$fits, function(f) f$id, character(1))
  otra <- which(ids != recomendada)[1]
  session$setInputs(tabla_ranking_rows_selected = otra)
  check(identical(selected_id(), ids[otra]),
        "clic en el ranking cambia la distribución explorada")
  check(identical(view_model()$recommendation$level1$id, recomendada),
        "la recomendación oficial NO cambia al explorar otra distribución")
  check(identical(selected_fit()$id, ids[otra]),
        "los parámetros mostrados son los de la distribución seleccionada")

  # El gráfico interactivo se construye con la selección activa.
  check(inherits(.plot_fit_plotly(visual_data(), selected_id()), "plotly"),
        "gráfico principal: objeto plotly construido con la selección")
  check(inherits(.plot_fit_plotly(visual_data(), recomendada), "plotly"),
        "gráfico principal: se reconstruye con la recomendada")

  # QQ y PP siguen a la distribución mostrada, no a la recomendada.
  check(qq_pp()$qq_plot$distribution == ids[otra],
        "QQ-plot sigue a la distribución mostrada")
  check(qq_pp()$pp_plot$distribution == ids[otra],
        "PP-plot sigue a la distribución mostrada")
  check(isFALSE(qq_pp()$qq_plot$is_recommended),
        "QQ declara que no es la recomendada (exploración manual)")
  check(inherits(.plot_qq(qq_pp()), "ggplot") && inherits(.plot_pp(qq_pp()), "ggplot"),
        "QQ y PP se construyen con los datos de la distribución mostrada")

  # Volver a la recomendada restaura el estado coherente.
  session$setInputs(tabla_ranking_rows_selected = which(ids == recomendada)[1])
  check(qq_pp()$qq_plot$distribution == recomendada &&
          isTRUE(qq_pp()$qq_plot$is_recommended),
        "al volver a la recomendada, QQ/PP y la marca se restauran")

  cat("\n-- 9. Ficha técnica --\n")
  ft <- selected_fit()
  check(!is.null(ft$loglik) && is.finite(ft$loglik),
        "ficha: log-verosimilitud disponible")
  check(is.character(ft$verdict) && nzchar(ft$verdict),
        "ficha: interpretación automática disponible (de B5)")
  check(identical(ft$method, view_model()$fits[[which(ids == recomendada)[1]]]$method),
        "ficha: método de estimación procede del View Model")

  cat("\n-- 10. Modo comparación --\n")
  session$setInputs(modo_comparacion = FALSE)
  check(is.null(compare_ids()), "modo comparación desactivado -> sin conjunto comparado")

  session$setInputs(modo_comparacion = TRUE, comparar = ids[1:3])
  check(length(compare_ids()) == 3L, "modo comparación: 3 distribuciones activas")
  check(inherits(.plot_fit_plotly(visual_data(), selected_id(), compare_ids()), "plotly"),
        "gráfico: se construye en modo comparación")

  # Guarda del máximo: 5 seleccionadas se recortan a MOD_COMPARE_MAX.
  session$setInputs(comparar = ids[1:5])
  check(length(compare_ids()) <= MOD_COMPARE_MAX,
        sprintf("modo comparación: nunca supera %d distribuciones", MOD_COMPARE_MAX))

  # Por debajo del mínimo no se activa la comparación.
  session$setInputs(comparar = ids[1])
  check(is.null(compare_ids()),
        sprintf("modo comparación: requiere al menos %d distribuciones", MOD_COMPARE_MIN))

  cat("\n-- 11. Restablecer análisis --\n")
  # Estado alterado: otra distribución + modo comparación activo.
  session$setInputs(tabla_ranking_rows_selected = otra,
                    modo_comparacion = TRUE, comparar = ids[1:3])
  check(!identical(selected_id(), recomendada) && !is.null(compare_ids()),
        "estado de exploración alterado antes de restablecer")

  vm_antes <- view_model()
  session$setInputs(restablecer = 1)
  check(identical(selected_id(), recomendada),
        "restablecer: vuelve a la recomendación oficial")
  check(identical(view_model(), vm_antes),
        "restablecer: NO recalcula (el View Model es el mismo objeto)")

  cat("\n-- 12. Comparación con la recomendación --\n")
  session$setInputs(tabla_ranking_rows_selected = otra)
  fo <- selected_fit()
  check(length(fo$vs_recommended) == 3L,
        "la distribución explorada trae sus observaciones ✔/✘ desde B5")
  check(!is.null(fo$n_params) && !is.null(fo$metrics$information$aic),
        "la comparación dispone de nº de parámetros y criterios de información")
  frec <- Filter(function(x) identical(x$id, recomendada), view_model()$fits)[[1]]
  check(length(frec$vs_recommended) == 0L,
        "la recomendada no muestra bloque de comparación consigo misma")

  # La recomendación oficial sigue intacta tras toda la exploración.
  check(identical(view_model()$recommendation$level1$id, recomendada),
        "la recomendación oficial NO cambia tras comparar ni explorar")
}),
warning = function(w) {
  .warns <<- c(.warns, conditionMessage(w))
  invokeRestart("muffleWarning")
})

# ------------------------------------------------------------
# 13. Sin warnings propios de la aplicación (criterio de aprobación)
# ------------------------------------------------------------
cat("\n-- 13. Ausencia de warnings --\n")
font_warns <- grep("font|text width|text height", .warns, ignore.case = TRUE, value = TRUE)
if (length(font_warns) > 0) {
  cat(sprintf("  Warnings de fuentes detectados (%d). Primeros:\n", length(font_warns)))
  for (w in utils::head(unique(font_warns), 3)) cat("   -", w, "\n")
}
check(length(font_warns) == 0L,
      "renderizado de gráficos sin warnings de resolución de fuentes")
if (length(.warns) > 0) {
  cat(sprintf("  Aviso: %d warning(s) no relacionados con fuentes:\n", length(.warns)))
  for (w in utils::head(unique(.warns), 5)) cat("   -", w, "\n")
}

setwd(.old_wd)
cat("\nB8 SMOKE TEST SUPERADO\n")
