# ============================================================
# Actuarial Tools by BMK — Componentes
# Archivo: ui_plot_container.R — envoltorio de un output de gráfico
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Función pura de UI (catálogo 7.2). Envuelve un output de gráfico en una card
# titulada. No crea el output: recibe el elemento (p. ej. plotOutput(ns("p")) o
# plotlyOutput(ns("p"))) generado por el módulo de la herramienta.

#' Card titulada genérica (helper interno compartido por los contenedores)
#'
#' Base común de `bmk_plot_container()` y `bmk_table_container()`, para no
#' duplicar el andamiaje de la tarjeta. La resolución de nombres en R ocurre en
#' tiempo de ejecución, por lo que el orden de carga de los componentes es
#' indiferente.
#' @param title Título de la tarjeta.
#' @param ...   Contenido del cuerpo (el output que se envuelve).
#' @return Tag `div` de htmltools con clase `.card`.
.bmk_card <- function(title, ...) {
  htmltools::tags$div(
    class = "card",
    role = "region",
    `aria-label` = title,
    htmltools::tags$div(class = "card-header", title),
    htmltools::tags$div(class = "card-body", ...)
  )
}

#' Contenedor de gráfico
#'
#' @param title Título del gráfico.
#' @param ...   Output de gráfico a envolver (plotOutput / plotlyOutput).
#' @return Tag `div` de htmltools con clase `.card`.
bmk_plot_container <- function(title, ...) {
  .bmk_card(title, ...)
}
