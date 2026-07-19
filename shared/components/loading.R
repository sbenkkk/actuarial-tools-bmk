# ============================================================
# Actuarial Tools by BMK — Componentes
# Archivo: loading.R — feedback visual de carga
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Función de UI (catálogo 7.2). Wrapper de shinycssloaders::withSpinner con la
# estética de marca (spinner discreto en color primario). Confirma que el cálculo
# está en curso (apartado 5, Fiabilidad).

#' Envolver un output con un spinner de marca
#'
#' @param ui    Output de Shiny a envolver (p. ej. plotOutput, DTOutput).
#' @param type  Tipo de spinner de shinycssloaders (1-8). Por defecto, discreto.
#' @param size  Tamaño relativo del spinner.
#' @param color Color del spinner. Por defecto, el primario de marca.
#' @param ...   Argumentos adicionales para shinycssloaders::withSpinner.
#' @return El output envuelto con el spinner.
bmk_loading <- function(ui, type = 4, size = 0.7, color = NULL, ...) {
  if (is.null(color)) color <- bmk_colors$primary
  shinycssloaders::withSpinner(
    ui, type = type, color = color, size = size,
    color.background = bmk_colors$surface, ...
  )
}
