# ============================================================
# Actuarial Tools by BMK — Componentes
# Archivo: ui_table_container.R — envoltorio de una tabla de resultados
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Función pura de UI (catálogo 7.2). Envuelve un output de tabla (DTOutput) en
# una card titulada. Reutiliza el helper .bmk_card() de ui_plot_container.R para
# no duplicar el andamiaje.

#' Contenedor de tabla
#'
#' @param title Título de la tabla.
#' @param ...   Output de tabla a envolver (DT::DTOutput).
#' @return Tag `div` de htmltools con clase `.card`.
bmk_table_container <- function(title, ...) {
  .bmk_card(title, ...)
}
