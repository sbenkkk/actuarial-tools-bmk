# ============================================================
# Actuarial Tools by BMK — Componentes
# Archivo: ui_sidebar_section.R — bloque titulado de inputs en el sidebar
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Función pura de UI (catálogo 7.2). Agrupa inputs bajo un título de sección,
# para que el sidebar sea legible incluso con varios parámetros (apartado 3.5).

#' Sección titulada del sidebar
#'
#' @param title Título de la sección (texto corto).
#' @param ...   Inputs u otros tags que componen la sección.
#' @return Tag `div` de htmltools con clase `.bmk-sidebar-section`.
bmk_sidebar_section <- function(title, ...) {
  htmltools::tags$div(
    class = "bmk-sidebar-section",
    role = "group",
    `aria-label` = title,
    htmltools::tags$div(class = "bmk-sidebar-title", title),
    ...
  )
}
