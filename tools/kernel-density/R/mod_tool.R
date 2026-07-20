# ============================================================
# Tool: kernel-density
# Archivo: mod_tool.R — módulo Shiny (UI + reactividad). Solo presentación.
# Autor: BMK
# Última actualización: 2026-07-19
# ============================================================
#
# Núcleo de interfaz de la herramienta. Orquesta mod_data_input, invocará
# kde_analyze() (calc.R) y renderizará métricas, gráficos, tablas, resumen del
# modelo y Actuarial Insights, montando mod_export_csv.
#
# REGLA DE ARQUITECTURA CONGELADA:
#   mod_tool.R NO implementa cálculos estadísticos. Toda la matemática vive en
#   calc.R. La UI se limita a: (1) recoger inputs, (2) llamar a kde_analyze(),
#   (3) reorganizar su salida con prepare_view_model() [4B] y (4) renderizar los
#   componentes de shared/. Sin CSS/HTML suelto (regla 16).
#
# Construcción incremental por sub-bloques:
#   [4A] Estructura del módulo, sidebar, carga de datos y validaciones <- hecho
#   [4B] Reactividad + kde_analyze() + prepare_view_model()            <- hecho
#   [4C] Metric cards, tablas y resumen del modelo                     <- hecho
#   [4D] Gráficos Plotly                                               <- hecho
#   [4E] Actuarial Insights, indicador de bandwidth y exportaciones    <- ESTE

# --- Constantes de UI (no son cálculo estadístico) ---------------------------
# Mínimo de observaciones para que la herramienta opere (guarda de interfaz).
MOD_MIN_OBS <- 5L
# Semilla de procedencia del dataset de ejemplo (para trazabilidad/metadata).
MOD_EXAMPLE_SEED <- 20260719L


# ============================================================
# VIEW MODEL — capa de adaptación (pura, determinista)
# ============================================================
#
# prepare_view_model() adapta el CONTRATO DEL MOTOR (salida de kde_analyze) al
# CONTRATO DE LA INTERFAZ, organizado por componentes de la UI. Reglas congeladas:
#  - Función PURA y determinista: no accede a reactivos, ni a input, ni a session.
#  - NO recalcula estadística (solo formatea y, como mucho, restas de presentación
#    entre valores ya provistos por el motor).
#  - La UI consume EXCLUSIVAMENTE este objeto; nunca accede a estimation,
#    diagnostics ni assessment directamente.
# El View Model se organiza por componentes: cards, plots, tables, indicator,
# insights, downloads, metadata (no replica la estructura interna del motor).

#' Formatea un nivel de probabilidad como etiqueta corta ("95%", "99,5%")
#' @section Tipo: Auxiliar (presentación).
.fmt_level <- function(p) {
  v <- p * 100
  s <- ifelse(v == round(v), sprintf("%d", round(v)),
              gsub(".", ",", sprintf("%g", v), fixed = TRUE))
  paste0(s, "%")
}

#' Etiqueta legible del método de bandwidth (de KDE_BW_METHODS, o "Manual")
#' @section Tipo: Auxiliar (presentación).
.bw_label <- function(method) {
  if (identical(method, "manual")) return("Manual")
  m <- KDE_BW_METHODS[[method]]
  if (is.null(m)) method else m$label
}

#' Envuelve un bloque de Actuarial Insights (título + frases del View Model)
#'
#' Presentación pura: NO concatena ni interpreta; solo envuelve cada frase (ya
#' redactada por los Text Builders) en un elemento de lista. Bloque vacío -> NULL.
#' @section Tipo: Auxiliar (presentación).
.insight_block <- function(title, items) {
  if (length(items) == 0L) return(NULL)
  htmltools::tagList(
    htmltools::tags$div(class = "bmk-sidebar-title", title),
    htmltools::tags$ul(lapply(items, htmltools::tags$li))
  )
}

#' Adapta la salida de kde_analyze() al View Model de la interfaz
#'
#' @section Tipo: Pública (presentación pura).
#' @param analysis Salida de kde_analyze() (contrato del motor).
#' @param x Vector de severidad usado (para el histograma del gráfico). Dato, no
#'   se recalcula nada con él.
#' @param manifest Lista del manifest.yml (opcional).
#' @return list(cards, plots, tables, indicator, insights, downloads, metadata).
prepare_view_model <- function(analysis, x, manifest = NULL) {
  a      <- analysis
  est    <- a$estimation
  var_df <- est$var                 # level, var_kde, var_empirical, rel_gap
  bw     <- a$bandwidth
  st     <- a$diagnostics$stats
  ass    <- a$assessment
  txt    <- a$text
  top    <- nrow(var_df)            # nivel más alto (levels en orden ascendente)

  # --- cards (4 KPIs) — contrato: title, value, subtitle, icon, status ---
  dir_txt <- switch(ass$skewness_direction,
                    right = "cola derecha", left = "cola izquierda", "aprox. simétrica")
  cards <- list(
    list(title = "Observaciones", value = bmk_format_number(a$input$n_used),
         subtitle = "válidas", icon = "database", status = "info"),
    list(title = "Ancho de banda (h)", value = bmk_format_number(bw$h, decimals = 2),
         subtitle = txt$bandwidth_message, icon = "sliders",
         status = if (identical(bw$classification$status, "near")) "info" else "warning"),
    list(title = sprintf("VaR %s (KDE)", .fmt_level(var_df$level[top])),
         value = bmk_format_currency(var_df$var_kde[top]),
         subtitle = "kernel", icon = "graph-up-arrow", status = "info"),
    list(title = "Asimetría", value = bmk_format_number(st$skewness, decimals = 2),
         subtitle = dir_txt, icon = "bar-chart-line",
         status = if (identical(ass$skewness_level, "high")) "warning" else "info")
  )

  # --- plots: capas ya preparadas (gramática visual congelada de Tool-01) -----
  # Densidad: Histograma, KDE, VaR KDE, VaR empírico.
  # CDF:      CDF, VaR KDE, VaR empírico, Nivel de confianza.
  # El render solo dibuja estas capas en este orden; no construye lógica.
  lvl <- .fmt_level(var_df$level)
  plots <- list(
    density = list(
      hist          = x,                                                  # 1 Histograma
      kde           = data.frame(x = est$curve$x, y = est$curve$density), # 2 KDE
      ymax          = max(est$curve$density),                            # extensión vertical
      var_kde       = data.frame(level = lvl, x = var_df$var_kde),       # 3 VaR KDE
      var_empirical = data.frame(level = lvl, x = var_df$var_empirical)  # 4 VaR empírico
    ),
    cdf = list(
      cdf           = data.frame(x = est$curve$x, y = est$curve$cdf),                 # 1 CDF
      var_kde       = data.frame(level = lvl, x = var_df$var_kde,       y = var_df$level), # 2 VaR KDE
      var_empirical = data.frame(level = lvl, x = var_df$var_empirical, y = var_df$level), # 3 VaR empírico
      levels        = data.frame(level = lvl, y = var_df$level),                      # 4 Nivel de confianza
      xrange        = range(est$curve$x)
    )
  )

  # --- tables (display) ---
  risk <- data.frame(
    Nivel              = .fmt_level(var_df$level),
    `VaR KDE`          = bmk_format_currency(var_df$var_kde),
    `Cuantil empírico` = bmk_format_currency(var_df$var_empirical),
    Diferencia         = bmk_format_currency(var_df$var_kde - var_df$var_empirical),
    `Diferencia %`     = bmk_format_percent(var_df$rel_gap),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  model_summary <- data.frame(
    Campo = c("Kernel", "Método de bandwidth", "Valor de h", "Observaciones (n)",
              "Dominio", paste("VaR KDE", .fmt_level(var_df$level)),
              paste("VaR empírico", .fmt_level(var_df$level))),
    Valor = c(a$metadata$kernel, .bw_label(bw$method), bmk_format_number(bw$h, 2),
              bmk_format_number(a$input$n_used),
              sprintf("[%s ; %s]", bmk_format_number(a$input$domain[1], 2),
                      bmk_format_number(a$input$domain[2], 2)),
              bmk_format_currency(var_df$var_kde),
              bmk_format_currency(var_df$var_empirical)),
    stringsAsFactors = FALSE
  )
  diagnostic <- data.frame(
    Estadístico = c("Observaciones (n)", "Valores únicos", "Coef. variación",
                    "Asimetría", "Curtosis", "Valores extremos"),
    Valor = c(bmk_format_number(st$n), bmk_format_number(st$n_unique),
              bmk_format_number(st$cv, 2), bmk_format_number(st$skewness, 2),
              bmk_format_number(st$kurtosis, 2),
              bmk_format_number(a$diagnostics$outliers$count)),
    stringsAsFactors = FALSE
  )
  tables <- list(risk = risk, model_summary = model_summary, diagnostic = diagnostic)

  # --- indicator (elemento interpretativo simple; puntos ya posicionados) ---
  ind_pts <- data.frame(
    label = c(vapply(names(bw$automatic), .bw_label, character(1)), "h actual"),
    x     = c(unname(bw$automatic), bw$h),
    type  = c(rep("auto", length(bw$automatic)), "current"),
    stringsAsFactors = FALSE
  )
  indicator <- list(
    points       = ind_pts,
    status       = bw$classification$status,
    band_low     = bw$classification$band_low,
    band_high    = bw$classification$band_high,
    h            = bw$h,
    rel_position = bw$classification$rel_position
  )

  # --- insights (texto ya en character desde el motor) ---
  insights <- list(
    diagnostic_notes  = txt$diagnostic_notes,
    bandwidth_message = txt$bandwidth_message,
    quality           = txt$insights$quality,
    diagnosis         = txt$insights$diagnosis,
    recommendation    = txt$insights$recommendation
  )

  # --- downloads (numérico crudo para CSV limpio; nombres congelados) ---
  # diagnostics.csv / risk_summary.csv / model_summary.csv
  diagnostics_raw <- data.frame(
    statistic = c("n", "n_unique", "mean", "median", "sd", "cv",
                  "skewness", "kurtosis", "min", "max", "iqr", "outliers"),
    value = c(st$n, st$n_unique, st$mean, st$median, st$sd, st$cv,
              st$skewness, st$kurtosis, st$min, st$max, st$iqr,
              a$diagnostics$outliers$count),
    stringsAsFactors = FALSE
  )
  downloads <- list(
    diagnostics   = diagnostics_raw,   # -> diagnostics.csv
    risk          = var_df,            # -> risk_summary.csv
    model_summary = model_summary      # -> model_summary.csv
  )

  list(
    cards     = cards,
    plots     = plots,
    tables    = tables,
    indicator = indicator,
    insights  = insights,
    downloads = downloads,
    metadata  = a$metadata
  )
}


#' UI del módulo kernel-density
#'
#' Layout estándar del framework: sidebar de inputs a la izquierda, panel de
#' resultados a la derecha. Solo estructura y componentes de shared/; los outputs
#' se rellenan en los sub-bloques 4C-4E.
#'
#' @param id Identificador del módulo (namespace).
#' @return Un layout_sidebar de bslib.
mod_tool_ui <- function(id) {
  ns <- shiny::NS(id)

  # Opciones de kernel (etiqueta UI -> clave de KDE_KERNELS).
  kernel_choices <- c(
    "Gaussian (Standard)" = "gaussian",
    "Epanechnikov"        = "epanechnikov",
    "Uniform"             = "uniform",
    "Triangular"          = "triangular",
    "Biweight"            = "biweight"
  )
  # Opciones de bandwidth reutilizando las etiquetas del registro (calc.R) + Manual.
  bw_labels  <- vapply(KDE_BW_METHODS, function(m) m$label, character(1))
  bw_choices <- c(stats::setNames(names(KDE_BW_METHODS), bw_labels), "Manual" = "manual")

  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 300,

      bmk_sidebar_section(
        "Datos",
        mod_data_input_ui(ns("datos")),
        shiny::selectInput(ns("sev_col"), "Columna de severidad", choices = NULL),
        shiny::tags$p(
          class = "text-secondary",
          shiny::tags$small(
            "Formato del CSV: separador coma, decimales con punto, sin celdas vacías. ",
            "Debe incluir una columna numérica de importes llamada ",
            shiny::tags$code("loss_amount"), ". Máx. 10 MB / 100.000 filas."
          )
        ),
        mod_export_csv_ui(ns("plantilla"), "Descargar datos de ejemplo"),
        shiny::tags$p(
          class = "text-secondary",
          shiny::tags$small(
            "Puedes usarlo como plantilla: sustituye los valores de ",
            shiny::tags$code("loss_amount"), " por los tuyos (conserva la cabecera), ",
            "guárdalo como CSV y súbelo."
          )
        )
      ),

      bmk_sidebar_section(
        "Kernel",
        shiny::selectInput(ns("kernel"), "Kernel", choices = kernel_choices,
                           selected = "gaussian")
      ),

      bmk_sidebar_section(
        "Bandwidth",
        shiny::selectInput(ns("bw_method"), "Método", choices = bw_choices,
                           selected = "silverman"),
        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == 'manual'", ns("bw_method")),
          shiny::sliderInput(ns("h_manual"), "h (manual)",
                             min = 0.1, max = 500, value = 10, step = 0.5),
          shiny::numericInput(ns("h_manual_num"), "h exacto (con decimales)",
                              value = 10, min = 0.001, step = 0.01)
        ),
        # Mensaje dinámico del bandwidth (feature D); se rellena en 4B/4E.
        shiny::uiOutput(ns("bw_message"))
      ),

      bmk_sidebar_section(
        "Riesgo (VaR)",
        shiny::checkboxGroupInput(
          ns("var_levels"), "Niveles",
          choices  = c("95%" = "0.95", "99%" = "0.99", "99,5%" = "0.995"),
          selected = c("0.95", "0.995")
        )
      ),

      bmk_sidebar_section(
        "Acción",
        shiny::actionButton(ns("calcular"), "Calcular", class = "btn-primary")
      )
    ),

    # --- Panel principal (estructura; los renders llegan en 4C-4E) ---
    shiny::tags$p(
      class = "text-secondary",
      "Explora la densidad de una variable de severidad de forma no paramétrica y",
      "lee su VaR. Carga un CSV o usa los datos de ejemplo, ajusta kernel y",
      "bandwidth, y pulsa Calcular."
    ),

    # 1. Metric cards (4C).
    shiny::uiOutput(ns("metric_cards")),

    # 2. Indicador de bandwidth (4E).
    bmk_plot_container("Indicador de bandwidth",
                       shiny::plotOutput(ns("bw_indicator"), height = "90px")),

    # Gráficos (4D).
    bmk_plot_container("Densidad estimada por kernel",
                       bmk_loading(plotly::plotlyOutput(ns("plot_density"), height = "360px"))),
    bmk_plot_container("Función de distribución estimada (kernel)",
                       bmk_loading(plotly::plotlyOutput(ns("plot_cdf"), height = "320px"))),

    # 3. Tablas (4C): diagnóstico de la muestra + VaR.
    bmk_table_container("Diagnóstico de la muestra", DT::DTOutput(ns("diag_table"))),
    shiny::uiOutput(ns("diag_note")),
    bmk_table_container("VaR: kernel frente a empírico",
                        bmk_loading(DT::DTOutput(ns("risk_table")))),

    # 4. Resumen del modelo (4C).
    bmk_table_container("Resumen del modelo", DT::DTOutput(ns("model_summary"))),

    # Actuarial Insights (4E).
    shiny::uiOutput(ns("insights")),

    # Exportaciones (4E) — nombres de archivo congelados.
    shiny::tagList(
      mod_export_csv_ui(ns("exp_diagnostics"), "Descargar diagnóstico"),
      mod_export_csv_ui(ns("exp_risk"),        "Descargar riesgo"),
      mod_export_csv_ui(ns("exp_model"),       "Descargar resumen del modelo")
    )
  )
}


#' Server del módulo kernel-density
#'
#' Sub-bloque 4A: carga de datos (mod_data_input), selector de columna de
#' severidad y validaciones de entrada. La reactividad de cálculo (kde_analyze),
#' el View Model y los renders se añaden en 4B-4E.
#'
#' @param id Identificador del módulo (namespace).
#' @param manifest Lista del manifest.yml (nombre/slug/versión para exportación y
#'   metadata). Se usa a partir de 4B.
#' @return NULL (invisible). Registra la reactividad de la herramienta.
mod_tool_server <- function(id, manifest) {
  shiny::moduleServer(id, function(input, output, session) {

    # --- Carga de datos: ejemplo desde el CSV incluido (determinista) ---------
    example_df <- as.data.frame(
      readr::read_csv("data/example_data.csv", show_col_types = FALSE)
    )
    datos <- mod_data_input_server(
      "datos",
      example_data     = example_df,
      expected_columns = c(loss_amount = "numeric")
    )

    # Descarga del dataset de ejemplo como plantilla (formato correcto garantizado).
    mod_export_csv_server(
      "plantilla",
      data     = shiny::reactive(example_df),
      filename = "kernel-density-plantilla"
    )

    # --- Selector de columna de severidad: columnas numéricas del dataset -----
    shiny::observeEvent(datos()$is_valid, {
      shiny::req(datos()$is_valid)
      d <- datos()$data
      num_cols <- names(d)[vapply(d, is.numeric, logical(1))]
      shiny::req(length(num_cols) > 0)
      sel <- if ("loss_amount" %in% num_cols) "loss_amount" else num_cols[1]
      shiny::updateSelectInput(session, "sev_col", choices = num_cols, selected = sel)
    })

    # --- Vector de severidad seleccionado (extracción pura, sin estadística) ---
    # Devuelve el vector numérico finito de la columna elegida, o NULL si no
    # procede. NO calcula nada: solo selecciona y limpia no-finitos.
    severity <- shiny::reactive({
      shiny::req(datos()$is_valid)
      d <- datos()$data
      col <- input$sev_col
      # Robustez en el arranque: si el selector aún no está fijado, usa loss_amount
      # o la primera columna numérica (extracción, no estadística).
      if (is.null(col) || !nzchar(col) || !(col %in% names(d))) {
        num_cols <- names(d)[vapply(d, is.numeric, logical(1))]
        shiny::req(length(num_cols) > 0)
        col <- if ("loss_amount" %in% num_cols) "loss_amount" else num_cols[1]
      }
      v <- d[[col]]
      v[is.finite(v)]
    })

    # --- Validaciones de entrada de la herramienta (avisos, no bloqueo) -------
    # Se disparan al cambiar datos o columna. El bloqueo efectivo del cálculo se
    # aplicará en 4B (req sobre estas mismas condiciones antes de kde_analyze).
    shiny::observeEvent(list(datos()$is_valid, input$sev_col), {
      shiny::req(datos()$is_valid, input$sev_col %in% names(datos()$data))
      v <- severity()
      if (length(v) < MOD_MIN_OBS) {
        bmk_notify(
          sprintf("Se necesitan al menos %d observaciones para estimar la densidad.",
                  MOD_MIN_OBS),
          type = "error"
        )
        return(invisible(NULL))
      }
      n_nonpos <- sum(v <= 0)
      if (n_nonpos > 0) {
        bmk_notify(
          sprintf("Detectados %d valores <= 0. La severidad suele ser positiva; revisa los datos.",
                  n_nonpos),
          type = "warning"
        )
      }
    })

    # --- Sincronización del h manual: slider <-> cuadro numérico --------------
    # El cuadro numérico admite decimales y es la fuente de verdad del cálculo;
    # el slider es un ajuste rápido y aproximado. Umbral de 0.5 (paso del slider)
    # para evitar rebotes entre ambos.
    shiny::observeEvent(input$h_manual, {
      if (is.null(input$h_manual_num) ||
          abs(input$h_manual - input$h_manual_num) > 0.5) {
        shiny::updateNumericInput(session, "h_manual_num", value = input$h_manual)
      }
    })
    shiny::observeEvent(input$h_manual_num, {
      shiny::req(input$h_manual_num)
      if (abs(input$h_manual_num - input$h_manual) > 0.5) {
        shiny::updateSliderInput(session, "h_manual", value = input$h_manual_num)
      }
    })

    # --- Reactividad de cálculo (regla 3: SOLO eventReactive con Calcular) -----
    # Los cambios en los controles NO ejecutan el motor. El cálculo se dispara al
    # pulsar Calcular y, además, una vez al arrancar (ignoreNULL = FALSE) para
    # cumplir "cero pantalla vacía". La UI consume EXCLUSIVAMENTE view_model();
    # nunca accede a estimation/diagnostics/assessment (los adapta prepare_view_model).
    view_model <- shiny::eventReactive(input$calcular, {
      shiny::req(datos()$is_valid)
      sev <- severity()
      shiny::req(length(sev) >= MOD_MIN_OBS)

      levels <- sort(as.numeric(input$var_levels))
      if (length(levels) == 0L) {
        bmk_notify("Selecciona al menos un nivel de VaR.", type = "warning")
        shiny::req(FALSE)
      }

      method   <- input$bw_method
      h_manual <- if (identical(method, "manual")) input$h_manual_num else NULL
      if (identical(method, "manual") &&
          (is.null(h_manual) || !is.finite(h_manual) || h_manual <= 0)) {
        bmk_notify("El ancho de banda manual debe ser un número positivo.",
                   type = "warning")
        shiny::req(FALSE)
      }
      seed     <- if (identical(datos()$source, "example")) MOD_EXAMPLE_SEED else NULL

      analysis <- kde_analyze(
        sev,
        kernel       = input$kernel,
        method       = method,
        h_manual     = h_manual,
        levels       = levels,
        tool_version = manifest$version,
        seed         = seed
      )
      prepare_view_model(analysis, sev, manifest)
    }, ignoreNULL = FALSE)

    # ==========================================================================
    # RENDERS [4C] — declarativos: consumen EXCLUSIVAMENTE view_model().
    # Ningún render accede al resultado de kde_analyze(); toda transformación se
    # hizo en prepare_view_model(). Aquí solo se pintan objetos ya preparados.
    # ==========================================================================

    # Opciones DT comunes para tablas pequeñas: sin buscador ni paginación.
    .dt_opts <- list(dom = "t", ordering = FALSE, paging = FALSE)

    # --- 1. Metric cards ------------------------------------------------------
    output$metric_cards <- shiny::renderUI({
      vm <- shiny::req(view_model())
      cards_ui <- lapply(vm$cards, function(c) {
        bmk_metric_card(label = c$title, value = c$value, note = c$subtitle)
      })
      do.call(bslib::layout_columns,
              c(list(col_widths = c(3, 3, 3, 3)), cards_ui))
    })

    # --- 3. Tablas: diagnóstico + VaR -----------------------------------------
    output$diag_table <- DT::renderDT({
      vm <- shiny::req(view_model())
      DT::datatable(vm$tables$diagnostic, rownames = FALSE,
                    options = .dt_opts, selection = "none")
    })

    output$risk_table <- DT::renderDT({
      vm <- shiny::req(view_model())
      DT::datatable(vm$tables$risk, rownames = FALSE,
                    options = .dt_opts, selection = "none")
    })

    # --- 4. Resumen del modelo ------------------------------------------------
    output$model_summary <- DT::renderDT({
      vm <- shiny::req(view_model())
      DT::datatable(vm$tables$model_summary, rownames = FALSE,
                    options = .dt_opts, selection = "none")
    })

    # ==========================================================================
    # RENDERS [4D] — Plotly declarativo. Las capas ya vienen preparadas en
    # view_model()$plots; el render solo las dibuja en el orden congelado y aplica
    # bmk_plotly_layout(). No construye lógica de gráfico.
    # ==========================================================================

    # --- Gráfico de densidad: Histograma, KDE, VaR KDE, VaR empírico ----------
    output$plot_density <- plotly::renderPlotly({
      vm <- shiny::req(view_model())
      d  <- vm$plots$density

      p <- plotly::plot_ly()
      # 1) Histograma (normalizado a densidad)
      p <- plotly::add_histogram(
        p, x = d$hist, histnorm = "probability density",
        marker = list(color = bmk_colors$border),
        opacity = 0.6, name = "Histograma"
      )
      # 2) KDE
      p <- plotly::add_lines(
        p, data = d$kde, x = ~x, y = ~y,
        line = list(color = bmk_colors$primary, width = 2), name = "KDE"
      )
      # 3) VaR KDE (líneas verticales continuas)
      p <- plotly::add_segments(
        p, data = d$var_kde, x = ~x, xend = ~x, y = 0, yend = d$ymax,
        line = list(color = bmk_colors$accent, width = 1.5),
        name = "VaR KDE"
      )
      # 4) VaR empírico (líneas verticales discontinuas)
      p <- plotly::add_segments(
        p, data = d$var_empirical, x = ~x, xend = ~x, y = 0, yend = d$ymax,
        line = list(color = bmk_colors$text_secondary, width = 1.5, dash = "dash"),
        name = "VaR empírico"
      )
      # Etiqueta del nivel: UNA por nivel (95%, 99,5%...), sobre el par de líneas.
      # KDE (continua) y empírico (discontinua) de ese nivel quedan a ambos lados y
      # se distinguen por estilo/leyenda, evitando etiquetas duplicadas superpuestas.
      p <- plotly::add_text(
        p, data = d$var_kde, x = ~x, y = d$ymax, text = ~level,
        textposition = "top center", cliponaxis = FALSE,
        textfont = list(color = bmk_colors$text, size = 12),
        showlegend = FALSE, hoverinfo = "skip"
      )
      p <- plotly::layout(p, barmode = "overlay",
                          xaxis = list(title = "Severidad"),
                          yaxis = list(title = "Densidad"))
      bmk_plotly_layout(p)
    })

    # --- Gráfico CDF: CDF, VaR KDE, VaR empírico, Nivel de confianza ----------
    output$plot_cdf <- plotly::renderPlotly({
      vm <- shiny::req(view_model())
      c  <- vm$plots$cdf

      p <- plotly::plot_ly()
      # 1) CDF estimada
      p <- plotly::add_lines(
        p, data = c$cdf, x = ~x, y = ~y,
        line = list(color = bmk_colors$primary, width = 2), name = "CDF"
      )
      # 2) VaR KDE (marcas en la curva)
      p <- plotly::add_markers(
        p, data = c$var_kde, x = ~x, y = ~y,
        marker = list(color = bmk_colors$accent, size = 8), name = "VaR KDE"
      )
      # 3) VaR empírico (marcas)
      p <- plotly::add_markers(
        p, data = c$var_empirical, x = ~x, y = ~y,
        marker = list(color = bmk_colors$text_secondary, size = 8,
                      symbol = "diamond"), name = "VaR empírico"
      )
      # 4) Nivel de confianza (líneas horizontales en y = p)
      p <- plotly::add_segments(
        p, data = c$levels, x = c$xrange[1], xend = c$xrange[2], y = ~y, yend = ~y,
        line = list(color = bmk_colors$text_secondary, width = 1, dash = "dot"),
        name = "Nivel de confianza"
      )
      # Etiqueta del nivel: UNA por nivel, junto a la marca de VaR (abajo-derecha,
      # en la zona despejada bajo la meseta de la CDF).
      p <- plotly::add_text(
        p, data = c$var_kde, x = ~x, y = ~y, text = ~level,
        textposition = "bottom right", cliponaxis = FALSE,
        textfont = list(color = bmk_colors$text, size = 12),
        showlegend = FALSE, hoverinfo = "skip"
      )
      p <- plotly::layout(p, xaxis = list(title = "Severidad"),
                          yaxis = list(title = "F(x)", range = c(0, 1)))
      bmk_plotly_layout(p)
    })

    # ==========================================================================
    # RENDERS [4E] — Indicador de bandwidth, notas de diagnóstico, Actuarial
    # Insights y exportaciones. Declarativos: consumen solo view_model().
    # ==========================================================================

    # --- Indicador de bandwidth (simple, interpretativo, no analítico) --------
    output$bw_indicator <- shiny::renderPlot({
      vm  <- shiny::req(view_model())
      pts <- vm$indicator$points
      ggplot2::ggplot(pts, ggplot2::aes(x = x, y = 0)) +
        ggplot2::geom_hline(yintercept = 0, color = bmk_colors$border, linewidth = 0.6) +
        ggplot2::geom_point(ggplot2::aes(color = type, size = type)) +
        ggplot2::geom_text(ggplot2::aes(label = label), vjust = -1.2, size = 3,
                           color = bmk_colors$text_secondary) +
        ggplot2::scale_color_manual(
          values = c(auto = bmk_colors$text_secondary, current = bmk_colors$accent),
          guide = "none") +
        ggplot2::scale_size_manual(values = c(auto = 2.5, current = 4.5), guide = "none") +
        ggplot2::scale_y_continuous(limits = c(-1, 1.5)) +
        ggplot2::labs(x = "Ancho de banda (h)", y = NULL) +
        theme_bmk_ggplot() +
        ggplot2::theme(
          axis.text.y  = ggplot2::element_blank(),
          axis.ticks.y = ggplot2::element_blank(),
          panel.grid   = ggplot2::element_blank()
        )
    })

    # --- Notas del diagnóstico (feature E) ------------------------------------
    output$diag_note <- shiny::renderUI({
      vm    <- shiny::req(view_model())
      notes <- vm$insights$diagnostic_notes
      if (length(notes) == 0L) return(NULL)
      bmk_interpretation_box(
        htmltools::tags$ul(lapply(notes, htmltools::tags$li)),
        title = "Notas del diagnóstico"
      )
    })

    # --- Actuarial Insights (feature G): bloques Quality/Diagnosis/Recommendation
    output$insights <- shiny::renderUI({
      vm  <- shiny::req(view_model())
      ins <- vm$insights
      content <- htmltools::tagList(
        .insight_block("Calidad",        ins$quality),
        .insight_block("Diagnóstico",    ins$diagnosis),
        .insight_block("Recomendaciones", ins$recommendation)
      )
      bmk_interpretation_box(content, title = "Actuarial Insights")
    })

    # --- Exportaciones: consumen EXCLUSIVAMENTE view_model()$downloads ---------
    # Nombres base congelados (el módulo añade _<fecha>.csv por convención shared).
    mod_export_csv_server(
      "exp_diagnostics",
      data     = shiny::reactive(shiny::req(view_model())$downloads$diagnostics),
      filename = "diagnostics"
    )
    mod_export_csv_server(
      "exp_risk",
      data     = shiny::reactive(shiny::req(view_model())$downloads$risk),
      filename = "risk_summary"
    )
    mod_export_csv_server(
      "exp_model",
      data     = shiny::reactive(shiny::req(view_model())$downloads$model_summary),
      filename = "model_summary"
    )

    invisible(NULL)
  })
}
