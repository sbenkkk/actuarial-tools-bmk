# ============================================================
# Tool: tool-00-template
# Archivo: calc.R — operación mínima de demostración (sin Shiny, sin actuarial)
# Autor: BMK
# Última actualización: 2026-07-18
# ============================================================
#
# Lógica local de la plantilla (regla 7): ejecutable con source() sin Shiny. Su
# único objetivo es demostrar el flujo, no realizar cálculo actuarial. Las
# funciones son locales de la herramienta: sin prefijo bmk_ (regla 3).

#' Resumen básico del dataset, una fila por columna
#'
#' @param data data.frame de entrada.
#' @return data.frame con columna, tipo, nº de valores válidos y media (numéricas).
resumen_datos <- function(data) {
  data.frame(
    columna   = names(data),
    tipo      = vapply(data, function(col) class(col)[1], character(1)),
    validos   = vapply(data, function(col) sum(!is.na(col)), integer(1)),
    media     = vapply(
      data,
      function(col) if (is.numeric(col)) mean(col, na.rm = TRUE) else NA_real_,
      numeric(1)
    ),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}

#' Métricas de dimensión del dataset
#'
#' @param data data.frame de entrada.
#' @return list con nº de filas, columnas, columnas numéricas y media de
#'   loss_amount (o NA si la columna no existe).
metricas_basicas <- function(data) {
  numericas <- vapply(data, is.numeric, logical(1))
  media_loss <- if ("loss_amount" %in% names(data)) {
    mean(data[["loss_amount"]], na.rm = TRUE)
  } else {
    NA_real_
  }
  list(
    filas      = nrow(data),
    columnas   = ncol(data),
    numericas  = sum(numericas),
    media_loss = media_loss
  )
}
