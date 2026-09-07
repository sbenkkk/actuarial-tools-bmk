# ============================================================
# Tool: tool-00-template
# Archivo: mod_tool.R — módulo Shiny de la plantilla (UI + reactividad)
# Autor: BMK
# Última actualización: 2026-07-18
# ============================================================
#
# Núcleo funcional de la plantilla. Orquesta mod_data_input, invoca calc.R,
# renderiza métricas, gráfico, tabla e interpretación, y monta mod_export_csv.
# No contiene lógica de cálculo (vive en calc.R) ni CSS/HTML suelto (regla 16).

#' UI del módulo de la plantilla
#'
#' @param id Identificador del módulo (namespace).
#' @return Layout con sidebar (entrada + acción) y panel principal (resultados).
mod_tool_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 300,
      bmk_sidebar_section("Datos", mod_data_input_ui(ns("datos"))),
      bmk_sidebar_section(
        "Cálculo",
        shiny::actionButton(ns("calcular"), "Calcular", class = "btn-primary")
      )
    ),

    # Descripción breve (apartado 4.1).
    shiny::tags$p(
      class = "text-secondary",
      "Plantilla de demostración del framework. Carga datos de ejemplo o un CSV,",
      "pulsa Calcular y exporta el resumen. Sin lógica actuarial."
    ),

    # Métricas.
    shiny::uiOutput(ns("metricas")),

    # Gráfico y tabla (envueltos con spinner de marca).
    bmk_plot_container(
      "Registros válidos por columna",
      bmk_loading(shiny::plotOutput(ns("grafico"), height = "300px"))
    ),
    bmk_table_container(
      "Resumen por columna",
      bmk_loading(DT::DTOutput(ns("tabla")))
    ),

    # Interpretación y exportación.
    shiny::uiOutput(ns("interpretacion")),
    mod_export_csv_ui(ns("exportar"))
  )
}

#' Server del módulo de la plantilla
#'
#' @param id Identificador del módulo (namespace).
#' @param manifest Lista del manifest.yml (para el nombre/slug de exportación).
#' @return NULL (invisible). Registra la reactividad de la herramienta.
mod_tool_server <- function(id, manifest) {
  shiny::moduleServer(id, function(input, output, session) {

    # Datos de ejemplo de la herramienta (columnas del data_contract).
    example_df <- readr::read_csv("data/example_data.csv", show_col_types = FALSE)

    # Entrada de datos: contrato con tipo, delegado a bmk_validate_data().
    datos <- mod_data_input_server(
      "datos",
      example_data     = as.data.frame(example_df),
      expected_columns = c(loss_amount = "numeric")
    )

    # Cálculo bajo demanda (solo con datos válidos).
    resultado <- shiny::eventReactive(input$calcular, {
      shiny::req(datos()$is_valid)
      d <- datos()$data
      list(resumen = resumen_datos(d), metricas = metricas_basicas(d))
    })

    # Notificación de sistema al completar el cálculo.
    shiny::observeEvent(input$calcular, {
      shiny::req(datos()$is_valid)
      bmk_notify("Resumen calculado sobre los datos activos.", type = "info")
    })

    # --- Métricas (formatters: número, porcentaje, moneda) -------------------
    output$metricas <- shiny::renderUI({
      m <- shiny::req(resultado())$metricas
      bslib::layout_columns(
        col_widths = c(3, 3, 3, 3),
        bmk_metric_card("Filas", bmk_format_number(m$filas)),
        bmk_metric_card("Columnas", bmk_format_number(m$columnas)),
        bmk_metric_card("Columnas numéricas",
                        bmk_format_percent(m$numericas / m$columnas)),
        bmk_metric_card("Siniestro medio",
                        bmk_format_currency(m$media_loss),
                        note = "columna loss_amount")
      )
    })

    # --- Gráfico (theme_bmk_ggplot) ------------------------------------------
    output$grafico <- shiny::renderPlot({
      r <- shiny::req(resultado())$resumen
      ggplot2::ggplot(
        r, ggplot2::aes(x = stats::reorder(columna, validos), y = validos)
      ) +
        ggplot2::geom_col(fill = bmk_colors$primary, width = 0.65) +
        ggplot2::coord_flip() +
        ggplot2::labs(x = NULL, y = "Registros válidos") +
        theme_bmk_ggplot()
    })

    # --- Tabla (DT + formatter en la media) ----------------------------------
    output$tabla <- DT::renderDT({
      df <- shiny::req(resultado())$resumen
      df$media <- bmk_format_number(df$media, decimals = 2)
      DT::datatable(
        df, rownames = FALSE,
        colnames = c("Columna", "Tipo", "Válidos", "Media"),
        options = list(dom = "tp", pageLength = 10)
      )
    })

    # --- Interpretación (glue + bmk_interpretation_box) ----------------------
    output$interpretacion <- shiny::renderUI({
      m <- shiny::req(resultado())$metricas
      texto <- glue::glue(
        "El conjunto activo tiene {bmk_format_number(m$filas)} filas y ",
        "{m$columnas} columnas, de las cuales {m$numericas} son numéricas. ",
        "El importe medio de siniestro es {bmk_format_currency(m$media_loss)}."
      )
      bmk_interpretation_box(texto)
    })

    # --- Exportación (helpers: slug con fallback si el slug está en blanco) ---
    base_nombre <- if (bmk_is_blank(manifest$slug)) {
      bmk_slugify(manifest$name)
    } else {
      manifest$slug
    }
    mod_export_csv_server(
      "exportar",
      data     = shiny::reactive(shiny::req(resultado())$resumen),
      filename = base_nombre
    )

    invisible(NULL)
  })
}
