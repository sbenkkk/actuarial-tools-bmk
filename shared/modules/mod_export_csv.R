# ============================================================
# Actuarial Tools by BMK — Módulos compartidos
# Archivo: mod_export_csv.R — exportación de resultados en CSV
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Módulo Shiny (catálogo 7.2). Conecta un botón de descarga que escribe un
# data.frame reactivo a CSV EXACTAMENTE como lo recibe, con un nombre de archivo
# coherente. No genera, transforma ni formatea resultados.

#' UI del módulo de exportación CSV
#'
#' Botón de descarga, pensado para colocarse al final del panel principal
#' (layout apartado 4.2), siempre en la misma posición en todas las herramientas.
#' @param id    Identificador del módulo (namespace).
#' @param label Texto del botón.
#' @return Un `downloadButton`.
mod_export_csv_ui <- function(id, label = "Exportar CSV") {
  ns <- shiny::NS(id)
  shiny::downloadButton(ns("download"), label = label, class = "btn-secondary")
}

#' Server del módulo de exportación CSV
#'
#' Registra el `downloadHandler` que exporta el `data.frame` recibido, sin
#' modificarlo. El nombre de archivo se compone como `<base>_<AAAA-MM-DD>.csv`.
#'
#' @param id       Identificador del módulo (namespace).
#' @param data     `reactive` cuyo valor debe ser un `data.frame` (los resultados
#'   a exportar). Es responsabilidad de la herramienta garantizar que `data()`
#'   produce un `data.frame`; el módulo lo escribe tal cual, sin convertir tipos.
#' @param filename Nombre base del archivo (character o función sin argumentos).
#' @return `invisible(NULL)`. El módulo solo registra la descarga.
#' @examples
#' \dontrun{
#' server <- function(input, output, session) {
#'   resultados <- reactive(head(iris))
#'   mod_export_csv_server("exportar", data = resultados, filename = "kernel-density")
#' }
#' }
mod_export_csv_server <- function(id, data, filename = "bmk-export") {
  shiny::moduleServer(id, function(input, output, session) {

    resolve_base <- function() if (is.function(filename)) filename() else filename

    output$download <- shiny::downloadHandler(
      filename = function() sprintf("%s_%s.csv", resolve_base(), Sys.Date()),
      content  = function(file) {
        df <- data()
        shiny::req(df)
        readr::write_csv(df, file)   # exporta verbatim: sin formato ni row names
      }
    )

    invisible(NULL)
  })
}
