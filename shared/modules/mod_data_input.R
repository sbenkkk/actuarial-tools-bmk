# ============================================================
# Actuarial Tools by BMK — Módulos compartidos
# Archivo: mod_data_input.R — entrada de datos de cada herramienta
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Módulo Shiny (catálogo 7.2). Punto único de entrada de datos de una herramienta:
# gestiona el toggle "Datos de ejemplo / Subir CSV", lee el CSV, VERIFICA el
# tamaño del archivo (apartado 7.5) y DELEGA la validación en bmk_validate_data()
# (no la implementa). Expone el dataset activo como un reactive con el contrato
# fijo del apartado 7.3.
#
# El límite se lee de bmk_config$max_file_bytes (shared/config.R); la
# configuración global de shiny.maxRequestSize la fija load_shared.R.
#
# Depende de: bmk_config (shared/config), bmk_validate_data() (shared/validation),
# bmk_notify() (shared/components). No transforma, limpia ni calcula.

#' UI del módulo de entrada de datos
#'
#' Renderiza el selector "Datos de ejemplo / Subir CSV" y, solo cuando se elige
#' subir, el control de archivo. Pensado para colocarse dentro de
#' `bmk_sidebar_section()` en la herramienta.
#' @param id Identificador del módulo (namespace).
#' @return Un `tagList` con los inputs de entrada de datos.
mod_data_input_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::radioButtons(
      ns("source"), label = NULL,
      choices  = c("Datos de ejemplo" = "example", "Subir CSV" = "upload"),
      selected = "example"
    ),
    shiny::conditionalPanel(
      condition = sprintf("input['%s'] == 'upload'", ns("source")),
      shiny::fileInput(
        ns("file"), label = NULL, accept = c(".csv", "text/csv"),
        buttonLabel = "Examinar", placeholder = "Ningún archivo seleccionado"
      )
    )
  )
}

#' Server del módulo de entrada de datos
#'
#' Devuelve el dataset activo como un `reactive` con el contrato del apartado 7.3.
#' La validación se delega en `bmk_validate_data()`; los errores se comunican al
#' usuario con `bmk_notify()`. Este módulo no valida columnas por sí mismo.
#'
#' @param id Identificador del módulo (namespace).
#' @param example_data `data.frame` de ejemplo de la herramienta, o función sin
#'   argumentos que lo devuelve (para datos de ejemplo generados).
#' @param expected_columns Contrato de columnas esperado por la herramienta. Se
#'   pasa sin modificar a `bmk_validate_data()`. Puede ser `NULL`.
#' @return Un `reactive` que produce siempre
#'   `list(data, is_valid, errors, source)` (contrato 7.3).
#' @examples
#' \dontrun{
#' server <- function(input, output, session) {
#'   datos <- mod_data_input_server(
#'     "entrada",
#'     example_data     = readr::read_csv("data/example_data.csv"),
#'     expected_columns = c("loss_amount")
#'   )
#'   observe({ req(datos()$is_valid); str(datos()$data) })
#' }
#' }
mod_data_input_server <- function(id, example_data, expected_columns = NULL) {
  shiny::moduleServer(id, function(input, output, session) {

    # Resuelve el dataset de ejemplo, admitiendo data.frame o función generadora.
    get_example <- function() {
      out <- if (is.function(example_data)) example_data() else example_data
      as.data.frame(out)
    }

    shiny::reactive({
      if (identical(input$source, "upload")) {
        file <- input$file
        shiny::req(file)

        # Guarda de tamaño antes de leer (complementa shiny.maxRequestSize).
        if (isTRUE(file$size > bmk_config$max_file_bytes)) {
          bmk_notify(
            sprintf("El archivo supera el límite de %d MB.", bmk_config$max_file_mb),
            type = "error"
          )
          return(list(data = NULL, is_valid = FALSE,
                      errors = "Archivo demasiado grande.", source = "upload"))
        }

        raw <- tryCatch(
          as.data.frame(readr::read_csv(file$datapath, show_col_types = FALSE)),
          error = function(e) e
        )
        if (inherits(raw, "error")) {
          bmk_notify("No se pudo leer el archivo CSV. Compruebe el formato.",
                     type = "error")
          return(list(data = NULL, is_valid = FALSE,
                      errors = conditionMessage(raw), source = "upload"))
        }
        src <- "upload"

      } else {
        raw <- get_example()
        src <- "example"
      }

      # Delegación de la validación (Fase 5). Este módulo no la implementa.
      result <- bmk_validate_data(raw, expected_columns)
      if (!isTRUE(result$valid)) {
        bmk_notify(paste(result$errors, collapse = " "), type = "error")
      }

      list(
        data     = result$data,
        is_valid = result$valid,
        errors   = result$errors,
        source   = src
      )
    })
  })
}
