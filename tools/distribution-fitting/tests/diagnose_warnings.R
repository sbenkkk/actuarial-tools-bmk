# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/diagnose_warnings.R
# DIAGNÓSTICO (no es un test): captura y AGRUPA los warnings por etapa y por
# llamada responsable, para localizar el origen exacto sin modificar código.
# No corrige nada. No forma parte del gate de ningún bloque.
# Autor: BMK — Última actualización: 2026-07-25
# ============================================================
#
#   Rscript tests/diagnose_warnings.R      # desde la raíz de la herramienta
#   Rscript diagnose_warnings.R            # desde la carpeta tests/

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
.old_wd <- setwd(.tool_root)

# Registro global de warnings capturados.
.WLOG <- new.env(parent = emptyenv())
.WLOG$rows <- list()

#' Ejecuta `expr` capturando TODOS los warnings sin detener la ejecución.
#' Registra: etapa, mensaje, llamada responsable y paquete/entorno de origen.
capture_stage <- function(stage, expr) {
  res <- withCallingHandlers(
    tryCatch(force(expr), error = function(e) {
      cat(sprintf("  [ERROR] %s -> %s\n", stage, conditionMessage(e))); NULL
    }),
    warning = function(w) {
      cl <- conditionCall(w)
      fn <- if (is.null(cl)) "<sin llamada>" else paste(deparse(cl)[1], collapse = " ")
      # Origen: paquete que define la función llamada (si se puede resolver).
      origen <- tryCatch({
        nm <- if (is.null(cl)) NA_character_ else as.character(cl[[1]])[1]
        e <- if (is.na(nm)) NULL else environment(get0(nm, mode = "function"))
        if (is.null(e)) "desconocido" else environmentName(topenv(e))
      }, error = function(e) "desconocido")
      .WLOG$rows[[length(.WLOG$rows) + 1L]] <- data.frame(
        etapa = stage, mensaje = conditionMessage(w),
        llamada = substr(fn, 1, 70), origen = origen, stringsAsFactors = FALSE)
      invokeRestart("muffleWarning")
    }
  )
  res
}

library(shiny); library(bslib)
source("../../shared/load_shared.R")
source("R/calc.R")
source("R/mod_tool.R")

manifest <- yaml::read_yaml("manifest.yml")
df <- as.data.frame(readr::read_csv("data/example_data.csv", show_col_types = FALSE))

cat("== DIAGNÓSTICO DE WARNINGS — distribution-fitting ==\n")
cat("Filas:", nrow(df), "| columnas numéricas:",
    paste(names(df)[vapply(df, is.numeric, logical(1))], collapse = ", "), "\n\n")

# ---- Etapa por etapa, para aislar el origen --------------------------------
an_loss <- capture_stage("B2 motor · loss_amount · mle",
                         dist_fit_analyze(df, "loss_amount", method = "mle"))
an_exp  <- capture_stage("B2 motor · exposure · mle",
                         dist_fit_analyze(df, "exposure", method = "mle"))
an_auto <- capture_stage("B2 motor · loss_amount · auto",
                         dist_fit_analyze(df, "loss_amount", method = "auto"))
an_mom  <- capture_stage("B2 motor · exposure · mom",
                         dist_fit_analyze(df, "exposure", method = "mom"))

for (nm in c("loss_amount", "exposure")) {
  an <- if (nm == "loss_amount") an_loss else an_exp
  if (is.null(an)) next
  capture_stage(sprintf("B6 view model · %s", nm), prepare_view_model(an, manifest))
  vd <- capture_stage(sprintf("B7 visual data · %s", nm), build_visual_data(an, df))
  if (!is.null(vd)) {
    vm <- prepare_view_model(an, manifest)
    capture_stage(sprintf("B8 plot ajuste · %s", nm),
                  .plot_fit_overlay(vd, vm$recommendation$level1$id))
    capture_stage(sprintf("B8 plot QQ · %s", nm), .plot_qq(vd))
    capture_stage(sprintf("B8 plot PP · %s", nm), .plot_pp(vd))
  }
}

capture_stage("B8 servidor · flujo completo", {
  testServer(mod_tool_server, args = list(manifest = manifest), {
    session$setInputs(variable = "loss_amount", metodo = "mle",
                      profundidad = "standard", calcular = 1)
    invisible(view_model()); invisible(visual_data())
    session$setInputs(metodo = "auto", calcular = 2)
    invisible(view_model())
    session$setInputs(variable = "exposure", metodo = "mle", calcular = 3)
    invisible(view_model()); invisible(visual_data())
  })
})

# ---- Resumen agrupado -------------------------------------------------------
cat("\n\n================ RESUMEN AGRUPADO ================\n")
if (length(.WLOG$rows) == 0L) {
  cat("Sin warnings capturados.\n")
} else {
  all <- do.call(rbind, .WLOG$rows)
  cat("Total de warnings capturados:", nrow(all), "\n\n")

  cat("--- Por mensaje (tipo) ---\n")
  by_msg <- aggregate(list(n = seq_len(nrow(all))), by = list(mensaje = all$mensaje),
                      FUN = length)
  by_msg <- by_msg[order(-by_msg$n), ]
  for (i in seq_len(nrow(by_msg))) {
    cat(sprintf("  [%3d] %s\n", by_msg$n[i], by_msg$mensaje[i]))
  }

  cat("\n--- Por mensaje + llamada + origen ---\n")
  key <- paste(all$mensaje, "||", all$llamada, "||", all$origen)
  by_key <- aggregate(list(n = seq_along(key)), by = list(k = key), FUN = length)
  by_key <- by_key[order(-by_key$n), ]
  for (i in seq_len(nrow(by_key))) {
    parts <- strsplit(by_key$k[i], " \\|\\| ")[[1]]
    cat(sprintf("  [%3d] %s\n        llamada: %s\n        origen : %s\n",
                by_key$n[i], parts[1], parts[2], parts[3]))
  }

  cat("\n--- Por etapa ---\n")
  by_stage <- aggregate(list(n = seq_len(nrow(all))), by = list(etapa = all$etapa),
                        FUN = length)
  by_stage <- by_stage[order(-by_stage$n), ]
  for (i in seq_len(nrow(by_stage))) {
    cat(sprintf("  [%3d] %s\n", by_stage$n[i], by_stage$etapa[i]))
  }
}

setwd(.old_wd)
cat("\n== FIN DEL DIAGNÓSTICO ==\n")
