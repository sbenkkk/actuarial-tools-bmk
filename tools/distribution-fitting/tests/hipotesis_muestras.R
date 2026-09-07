# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/hipotesis_muestras.R
# NO es un test unitario: ejecuta el motor sobre cada fichero de data/samples/ y
# muestra el resultado REAL (familia, top, confianza, ΔAIC, tiempo) para
# contrastarlo con lo documentado en data/samples/README.md.
#
# Sale con código 0 salvo que algún fichero provoque un error del motor.
# Autor: BMK — Última actualización: 2026-08-04
# ============================================================
#
#   Rscript tests/hipotesis_muestras.R      # desde la raíz de la herramienta

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

# Se carga el framework completo para usar EL MISMO lector que la aplicación
# (.bmk_read_csv_robust, ADR-017). Usar readr::read_csv aquí daría un resultado
# distinto del de la app en los ficheros sin cabecera o con ';'.
suppressPackageStartupMessages({ library(shiny); library(bslib) })
source("../../shared/load_shared.R")
source("R/calc.R")

# Patrón sin barras invertidas: inmune a problemas de escapado entre shell y R.
muestras <- sort(list.files("data/samples", pattern = "[.]csv$", full.names = TRUE))
if (length(muestras) == 0L) {
  cat("No hay ficheros en data/samples/\n"); setwd(.old_wd); quit(status = 0)
}

errores <- 0L
cat(sprintf("%-38s %-20s %-10s %-20s %-7s %9s %7s\n",
            "fichero", "variable", "familia", "top", "conf", "deltaAIC", "seg"))
cat(strrep("-", 116), "\n", sep = "")

for (f in muestras) {
  nm <- basename(f)
  d <- tryCatch(.bmk_read_csv_robust(f), error = function(e) e)
  if (inherits(d, "error")) {
    cat(sprintf("%-38s LECTURA FALLIDA: %s\n", nm, conditionMessage(d)))
    errores <- errores + 1L
    next
  }
  num <- names(d)[vapply(d, is.numeric, logical(1))]
  if (length(num) == 0L) {
    cat(sprintf("%-38s %-20s SIN COLUMNAS NUMERICAS -> modal de error (esperado)\n",
                nm, "-"))
    next
  }
  v  <- num[1]
  t0 <- Sys.time()
  r  <- tryCatch(dist_fit_analyze(d, v), error = function(e) e)
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (inherits(r, "error")) {
    cat(sprintf("%-38s %-20s ERROR DEL MOTOR: %s\n", nm, substr(v, 1, 20),
                conditionMessage(r)))
    errores <- errores + 1L
    next
  }
  a  <- r$assessment
  l1 <- a$recommendation$level1
  da <- if (is.null(l1$delta_aic) || !is.finite(l1$delta_aic)) NA_real_ else l1$delta_aic
  cat(sprintf("%-38s %-20s %-10s %-20s %-7s %9.2f %7.1f\n",
              nm, substr(v, 1, 20), a$family, l1$id, l1$confidence, da, el))
}

cat("\n")
if (errores > 0L) {
  cat(sprintf("HIPOTESIS: %d fichero(s) han provocado un error\n", errores))
  setwd(.old_wd)
  quit(status = 1)
}
cat("HIPOTESIS: ningun fichero ha provocado errores del motor\n")
setwd(.old_wd)
