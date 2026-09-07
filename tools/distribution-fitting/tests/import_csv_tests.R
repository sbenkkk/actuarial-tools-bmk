# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/import_csv_tests.R
# Tests del FLUJO DE IMPORTACIÓN (ADR-017 / ADR-018): lectura robusta de CSV en
# shared/modules/mod_data_input.R y detección de columnas numéricas. No valida
# estadística. Genera los ficheros de prueba en un directorio temporal.
# Autor: BMK — Última actualización: 2026-07-28
# ============================================================
#
#   Rscript tests/import_csv_tests.R      # desde la raíz de la herramienta
#   Rscript import_csv_tests.R            # desde la carpeta tests/

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

library(shiny); library(bslib)
source("../../shared/load_shared.R")

check <- function(cond, msg) {
  if (!isTRUE(cond)) stop(sprintf("FALLO: %s", msg), call. = FALSE)
  cat(sprintf("  OK  - %s\n", msg))
}
num_cols <- function(df) names(df)[vapply(df, is.numeric, logical(1))]

tmp <- file.path(tempdir(), "bmk_import_tests")
dir.create(tmp, showWarnings = FALSE)
w <- function(nombre, texto) {
  p <- file.path(tmp, nombre)
  writeLines(texto, p)
  p
}

cat("== TESTS DE IMPORTACIÓN CSV (ADR-017 / ADR-018) ==\n")

# ------------------------------------------------------------
# 1. CSV con cabecera, coma, varias columnas (formato de referencia)
# ------------------------------------------------------------
cat("\n-- 1. Con cabecera, coma, varias columnas --\n")
p1 <- w("con_cabecera.csv", c("loss_amount,exposure", "123.5,0.4", "456.7,0.9"))
d1 <- .bmk_read_csv_robust(p1)
check(identical(names(d1), c("loss_amount", "exposure")),
      "conserva los nombres de la cabecera")
check(nrow(d1) == 2L, "lee todas las filas de datos")
check(setequal(num_cols(d1), c("loss_amount", "exposure")),
      "detecta ambas columnas como numéricas")

# ------------------------------------------------------------
# 2. CSV sin cabecera, UNA columna (caso real que provocó el bug)
# ------------------------------------------------------------
cat("\n-- 2. Sin cabecera, una columna --\n")
p2 <- w("sin_cabecera_1col.csv", c("398518.41", "635225.43", "543781.11"))
d2 <- .bmk_read_csv_robust(p2)
check(identical(names(d2), "Variable_1"), "asigna el nombre Variable_1")
check(nrow(d2) == 3L,
      "NO pierde la primera observación (3 filas, no 2)")
check(abs(d2$Variable_1[1] - 398518.41) < 1e-6,
      "la primera observación conserva su valor")
check(identical(num_cols(d2), "Variable_1"), "la columna es numérica")

# ------------------------------------------------------------
# 3. CSV sin cabecera, varias columnas, separador punto y coma
# ------------------------------------------------------------
cat("\n-- 3. Sin cabecera, varias columnas, ';' --\n")
p3 <- w("sin_cabecera_pyc.csv", c("123.5;0.4", "456.7;0.9"))
d3 <- .bmk_read_csv_robust(p3)
check(identical(names(d3), c("Variable_1", "Variable_2")),
      "asigna Variable_1 y Variable_2")
check(nrow(d3) == 2L && ncol(d3) == 2L, "separa correctamente por ';'")
check(length(num_cols(d3)) == 2L, "ambas columnas son numéricas")

# ------------------------------------------------------------
# 4. CSV con cabecera y separador punto y coma
# ------------------------------------------------------------
cat("\n-- 4. Con cabecera, ';' --\n")
p4 <- w("cabecera_pyc.csv", c("severidad;exposicion", "1000;0.5", "2000;0.7"))
d4 <- .bmk_read_csv_robust(p4)
check(identical(names(d4), c("severidad", "exposicion")),
      "detecta la cabecera pese al separador ';'")
check(nrow(d4) == 2L, "lee las filas de datos")

# ------------------------------------------------------------
# 5. Separador tabulador
# ------------------------------------------------------------
cat("\n-- 5. Tabulador --\n")
p5 <- w("tabulador.csv", c("x\ty", "1\t2", "3\t4"))
d5 <- .bmk_read_csv_robust(p5)
check(ncol(d5) == 2L && nrow(d5) == 2L, "detecta el tabulador como separador")

# ------------------------------------------------------------
# 6. Archivo sin columnas numéricas
# ------------------------------------------------------------
cat("\n-- 6. Sin columnas numéricas --\n")
p6 <- w("sin_numericas.csv", c("policy,zona", "P1,norte", "P2,sur"))
d6 <- .bmk_read_csv_robust(p6)
check(nrow(d6) == 2L, "el archivo se lee sin error")
check(length(num_cols(d6)) == 0L,
      "no se detecta ninguna columna numérica (la herramienta debe avisar)")

# ------------------------------------------------------------
# 7. El nombre de las columnas NO forma parte de la validación (ADR-018)
# ------------------------------------------------------------
cat("\n-- 7. Validación sin contrato de columnas --\n")
check(isTRUE(bmk_validate_data(d2, NULL)$valid),
      "un CSV sin 'loss_amount' es válido cuando no hay contrato")
check(isTRUE(bmk_validate_data(d6, NULL)$valid),
      "la validación estructural no depende de los nombres de columna")
check(isFALSE(bmk_validate_data(d2[0, , drop = FALSE], NULL)$valid),
      "se mantienen las comprobaciones estructurales (dataset vacío)")

# ------------------------------------------------------------
# 8. Compatibilidad hacia atrás: el ejemplo de la herramienta
# ------------------------------------------------------------
cat("\n-- 8. Compatibilidad hacia atrás --\n")
d8 <- .bmk_read_csv_robust("data/example_data.csv")
check(all(c("policy_id", "claim_id", "loss_amount", "exposure") %in% names(d8)),
      "el CSV de ejemplo conserva exactamente sus nombres de columna")
check(nrow(d8) == 60L, "el CSV de ejemplo conserva sus 60 filas")
check(all(c("loss_amount", "exposure") %in% num_cols(d8)),
      "las columnas numéricas del ejemplo se detectan como tales")

unlink(tmp, recursive = TRUE)
setwd(.old_wd)
cat("\nTESTS DE IMPORTACIÓN SUPERADOS\n")
