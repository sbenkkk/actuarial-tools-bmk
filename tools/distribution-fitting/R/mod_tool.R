# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: mod_tool.R — módulo Shiny (UI + reactividad). Solo presentación.
# Autor: BMK
# Última actualización: 2026-07-25
# ============================================================
#
# Capa de interfaz de Tool-02 (B8). Consume EXCLUSIVAMENTE:
#   - el View Model  -> prepare_view_model()  (B6)
#   - los datos de gráficos -> build_visual_data() (B7)
#
# REGLA DE ARQUITECTURA CONGELADA:
#   mod_tool.R NO contiene lógica estadística, ni de decisión, ni generación de
#   texto, ni evaluación de distribuciones. Toda esa lógica vive en calc.R
#   (B1-B7). La UI se limita a: (1) recoger inputs, (2) invocar el motor,
#   (3) renderizar el View Model y los datasets de gráficos. Sin CSS/HTML suelto
#   fuera de los componentes de shared/ (regla 16).

# --- Constantes de UI (guardas de interfaz, no cálculo estadístico) ----------
MOD_MIN_OBS <- 5L

# --- Ayudas de presentación de tipos (diagnóstico de importación, ADR-022) ----
# Traducen la clase de R a una etiqueta legible para el aviso "sin columnas
# numéricas". Son formateo de interfaz, no lógica estadística.
.dfit_type_label <- function(v) {
  if (is.numeric(v))                      "numérico"
  else if (inherits(v, c("Date", "POSIXt"))) "fecha"
  else if (is.logical(v))                 "lógico"
  else if (is.factor(v))                  "categórico"
  else                                    "texto"
}

.dfit_first_value <- function(v, max_chars = 28L) {
  ok <- which(!is.na(v))
  if (length(ok) == 0L) return("(vacía)")
  s <- as.character(v[[ok[1]]])
  if (nchar(s) > max_chars) paste0(substr(s, 1L, max_chars - 1L), "…") else s
}

# Opciones de los selectores (etiqueta visible -> valor del contrato de calc.R).
MOD_METHOD_CHOICES <- c(
  "MLE (máxima verosimilitud)" = "mle",
  "Automático"                 = "auto",
  "Momentos (MoM)"             = "mom",
  "L-momentos"                 = "lmom"
)
MOD_DEPTH_CHOICES <- c("Standard" = "standard", "Comprehensive" = "comprehensive")

# B16.1 — Vista de incertidumbre. Lista CERRADA de réplicas: en v1.1 no hay B
# personalizado. El defecto es 1000 (contrato B13 / ADR-035).
MOD_UNC_B_CHOICES <- c("500" = "500", "1000" = "1000",
                       "2000" = "2000", "5000" = "5000")
MOD_UNC_B_DEFAULT <- 1000L
MOD_UNC_LEVEL_DEFAULT <- 0.95
# Rango de la semilla propuesta. `.validate_bootstrap_seed()` exige escalar
# finito y entero; este rango solo acota la propuesta automática.
MOD_UNC_SEED_MAX <- 99999999L

# Límites del modo comparación (guardas de interfaz).
MOD_COMPARE_MIN <- 2L
MOD_COMPARE_MAX <- 4L


# ============================================================
# HELPERS DE PRESENTACIÓN (sin estadística)
# ============================================================

#' Familia tipográfica utilizable por el dispositivo gráfico
#'
#' La identidad visual define `Inter` (shared/theme/theme_bmk.R). Esa familia se
#' sirve al NAVEGADOR como webfont (`bslib::font_google`), pero los gráficos se
#' dibujan en el SERVIDOR con el dispositivo gráfico de R, que solo puede usar
#' fuentes instaladas en el sistema. Si `Inter` no está instalada, el dispositivo
#' ya dibuja con su fuente sustitutiva y, además, emite un warning por cada
#' elemento de texto.
#'
#' Este helper resuelve la familia una sola vez: devuelve `Inter` cuando está
#' realmente disponible (aspecto idéntico al diseño) y, si no, `""` (familia por
#' defecto del dispositivo, que es exactamente la que ya se estaba usando). No
#' altera el resultado ni el aspecto de los gráficos; solo evita la búsqueda
#' fallida. No añade dependencias: `systemfonts` se consulta únicamente si está
#' instalado (llega con el stack gráfico habitual).
#' @section Tipo: Auxiliar (presentación).
.plot_family <- local({
  cached <- NULL
  function() {
    if (!is.null(cached)) return(cached)
    fam <- bmk_font$family
    available <- tryCatch(
      requireNamespace("systemfonts", quietly = TRUE) &&
        fam %in% systemfonts::system_fonts()$family,
      error = function(e) FALSE
    )
    cached <<- if (isTRUE(available)) fam else ""
    cached
  }
})

#' Tema de marca para los gráficos, con familia tipográfica resuelta
#' @section Tipo: Auxiliar (presentación).
.theme_plot <- function() theme_bmk_ggplot(base_family = .plot_family())

#' Traduce un token semántico del View Model a un color de la paleta de marca
#'
#' El View Model emite tokens ("brand", "neutral", "muted"); la resolución a
#' color es responsabilidad de la interfaz (regla 16).
#' @section Tipo: Auxiliar (presentación).
.tone_color <- function(tone) {
  switch(tone,
    brand   = bmk_colors$primary,
    neutral = bmk_colors$text,
    muted   = bmk_colors$text_secondary,
    bmk_colors$text
  )
}

#' Identificador de origen de eventos del gráfico principal (plotly)
MOD_PLOT_SOURCE <- "dfit_fit_plot"

#' Gráfico de ajuste interactivo (plotly): observado + densidades ajustadas
#'
#' Presentación pura: dibuja los datos ya calculados por el Visual Engine (B7).
#' La distribución **seleccionada** se resalta (trazo grueso, color de marca) y el
#' resto queda atenuado en gris. El histograma y la KDE no se alteran nunca.
#'
#' La leyenda es control de VISIBILIDAD (ADR-029): conserva el comportamiento
#' nativo de Plotly (clic = ocultar/mostrar curva) y no interviene en la
#' selección analítica, que corresponde en exclusiva al ranking.
#' @section Tipo: Auxiliar (presentación).
#' @param compare_ids Ids a comparar. Si es `NULL` (modo exploración) se muestran
#'   todas las curvas con la seleccionada resaltada. Si trae ids (modo
#'   comparación) solo se dibujan esas, cada una con su color de la paleta
#'   categórica de marca. El histograma y la KDE se muestran siempre.
.plot_fit_plotly <- function(vd, selected_id, compare_ids = NULL) {
  block <- vd$histogram_density
  continua <- identical(block$family, "continuous")
  comparando <- length(compare_ids) > 0L
  p <- plotly::plot_ly(source = MOD_PLOT_SOURCE)

  # En comparación, cada distribución recibe un color propio de la paleta de
  # marca; en exploración, la seleccionada usa el color primario y el resto gris.
  color_of <- function(id) {
    if (!comparando) {
      return(if (identical(id, selected_id)) bmk_colors$primary else bmk_colors$text_secondary)
    }
    i <- match(id, compare_ids)
    bmk_colors$categorical[((i - 1L) %% length(bmk_colors$categorical)) + 1L]
  }
  width_of <- function(id) if (comparando || identical(id, selected_id)) 3 else 1
  alpha_of <- function(id) if (comparando || identical(id, selected_id)) 1 else 0.45
  visible_of <- function(id) !comparando || id %in% compare_ids

  line_of <- function(sel) list(
    color = if (sel) bmk_colors$primary else bmk_colors$text_secondary,
    width = if (sel) 3 else 1
  )

  if (continua) {
    p <- plotly::add_bars(
      p, x = block$histogram$mid, y = block$histogram$density,
      width = block$histogram$bin_end - block$histogram$bin_start,
      marker = list(color = bmk_colors$border), name = "Observado",
      showlegend = FALSE, hoverinfo = "skip")
    for (cv in block$curves) {
      p <- plotly::add_lines(
        p, x = cv$curve$x, y = cv$curve$density, name = cv$label,
        line = list(color = color_of(cv$id), width = width_of(cv$id)),
        opacity = alpha_of(cv$id),
        visible = if (visible_of(cv$id)) TRUE else "legendonly")
    }
    p <- plotly::add_lines(p, x = block$kde$curve$x, y = block$kde$curve$density,
                           name = "KDE (empírica)",
                           line = list(color = bmk_colors$accent, dash = "dash", width = 2))
    p <- plotly::layout(p, xaxis = list(title = ""), yaxis = list(title = "Densidad"))
  } else {
    p <- plotly::add_bars(
      p, x = block$observed$k, y = block$observed$freq,
      marker = list(color = bmk_colors$border), name = "Observado",
      showlegend = FALSE, hoverinfo = "skip")
    for (cv in block$curves) {
      p <- plotly::add_markers(
        p, x = cv$curve$k, y = cv$curve$pmf, name = cv$label,
        marker = list(color = color_of(cv$id),
                      size = if (width_of(cv$id) > 1) 11 else 7),
        opacity = alpha_of(cv$id),
        visible = if (visible_of(cv$id)) TRUE else "legendonly")
    }
    p <- plotly::layout(p, xaxis = list(title = "Recuento"),
                        yaxis = list(title = "Frecuencia"))
  }

  # ADR-029: no se registra `plotly_legendclick`. No se escucha ese evento, así
  # que registrarlo solo produciría el aviso de evento no consumido. La leyenda
  # se deja al comportamiento nativo de Plotly (mostrar/ocultar).
  bmk_plotly_layout(p)
}

#' Gráfico de ajuste estático (ggplot) — conservado para tests y uso sin interacción
#'
#' Presentación pura: dibuja los datos ya calculados por el Visual Engine (B7).
#' @section Tipo: Auxiliar (presentación).
.plot_fit_overlay <- function(vd, recommended_id) {
  block <- vd$histogram_density
  if (identical(block$family, "continuous")) {
    p <- ggplot2::ggplot() +
      ggplot2::geom_rect(
        data = block$histogram,
        ggplot2::aes(xmin = bin_start, xmax = bin_end, ymin = 0, ymax = density),
        fill = bmk_colors$border, colour = bmk_colors$surface) +
      ggplot2::labs(x = NULL, y = "Densidad")
    for (cv in block$curves) {
      if (identical(cv$id, recommended_id)) next
      p <- p + ggplot2::geom_line(data = cv$curve,
                                  ggplot2::aes(x = x, y = density),
                                  colour = bmk_colors$text_secondary,
                                  linewidth = 0.3, alpha = 0.5)
    }
    rec <- Filter(function(cv) identical(cv$id, recommended_id), block$curves)
    if (length(rec) > 0) {
      p <- p + ggplot2::geom_line(data = rec[[1]]$curve,
                                  ggplot2::aes(x = x, y = density),
                                  colour = bmk_colors$primary, linewidth = 1)
    }
    p + ggplot2::geom_line(data = block$kde$curve,
                           ggplot2::aes(x = x, y = density),
                           colour = bmk_colors$accent, linetype = "dashed",
                           linewidth = 0.6) +
      .theme_plot()
  } else {
    rec <- Filter(function(cv) identical(cv$id, recommended_id), block$curves)
    p <- ggplot2::ggplot() +
      ggplot2::geom_col(data = block$observed, ggplot2::aes(x = k, y = freq),
                        fill = bmk_colors$border, width = 0.7) +
      ggplot2::labs(x = "Recuento", y = "Frecuencia")
    if (length(rec) > 0) {
      p <- p + ggplot2::geom_point(data = rec[[1]]$curve,
                                   ggplot2::aes(x = k, y = pmf),
                                   colour = bmk_colors$primary, size = 2.5)
    }
    p + .theme_plot()
  }
}

#' Gráfico QQ (datos del Visual Engine + recta de referencia)
#'
#' `vd` puede ser la salida completa de `build_visual_data()` o la ligera de
#' `build_qq_pp_data()`: ambas exponen `qq_plot`.
#' @section Tipo: Auxiliar (presentación).
.plot_qq <- function(vd) {
  ggplot2::ggplot(vd$qq_plot$points, ggplot2::aes(x = theoretical, y = sample)) +
    ggplot2::geom_abline(slope = 1, intercept = 0,
                         colour = bmk_colors$text_secondary, linetype = "dashed") +
    ggplot2::geom_point(colour = bmk_colors$primary, size = 2) +
    ggplot2::labs(x = "Cuantiles teóricos", y = "Cuantiles observados") +
    .theme_plot()
}

#' Gráfico PP (datos del Visual Engine + diagonal de referencia)
#' @section Tipo: Auxiliar (presentación).
.plot_pp <- function(vd) {
  ggplot2::ggplot(vd$pp_plot$points, ggplot2::aes(x = empirical, y = theoretical)) +
    ggplot2::geom_abline(slope = 1, intercept = 0,
                         colour = bmk_colors$text_secondary, linetype = "dashed") +
    ggplot2::geom_point(colour = bmk_colors$primary, size = 2) +
    ggplot2::labs(x = "Probabilidad empírica", y = "Probabilidad ajustada") +
    .theme_plot()
}


# ============================================================
# UI
# ============================================================

#' UI del módulo de Tool-02
#'
#' @param id Identificador del módulo (namespace).
#' @return Layout estándar: sidebar de entrada y panel principal de resultados.
#' Valor legible para la tabla de reproducibilidad (formateo, sin lógica).
.dfit_repro_txt <- function(v) {
  if (is.null(v) || length(v) == 0L) return("—")
  if (length(v) > 1L) return(paste(v, collapse = " / "))
  if (is.na(v)) return("—")
  if (is.numeric(v) && !is.integer(v) && v != round(v)) return(format(v))
  as.character(v)
}

#' Gráfico de la distribución bootstrap de un parámetro (B16.1)
#'
#' DESCRIPTIVO. Representa el dataset que produce `build_bootstrap_plot_data()`:
#' histograma de las réplicas válidas, estimación puntual del estimador ACTIVO e
#' intervalo percentil. Sin puntuaciones de acuerdo, sin semáforos y sin
#' clasificación automática: aquí no se interpreta calidad.
.plot_bootstrap <- function(d) {
  # Las verticales van como `shapes` con `yref = "paper"`: abarcan todo el alto
  # sin necesidad de conocer la altura de las barras.
  vline <- function(x, color, dash) list(
    type = "line", x0 = x, x1 = x, xref = "x", y0 = 0, y1 = 1, yref = "paper",
    line = list(color = color, width = 2, dash = dash))
  etiqueta <- function(x, txt, color) list(
    x = x, y = 1, xref = "x", yref = "paper", text = txt, showarrow = FALSE,
    yanchor = "bottom", font = list(color = color, size = 11))

  shapes <- list(); anns <- list()
  if (is.finite(d$theta_hat)) {
    shapes <- c(shapes, list(vline(d$theta_hat, .tone_color("brand"), "solid")))
    anns   <- c(anns, list(etiqueta(d$theta_hat, "θ̂", .tone_color("brand"))))
  }
  for (b in list(list(d$ci_lower, "IC inf."), list(d$ci_upper, "IC sup."))) {
    if (is.finite(b[[1]])) {
      shapes <- c(shapes, list(vline(b[[1]], .tone_color("muted"), "dash")))
      anns   <- c(anns, list(etiqueta(b[[1]], b[[2]], .tone_color("muted"))))
    }
  }
  sub <- if (is.finite(d$confidence_level)) {
    sprintf("%d réplicas válidas · intervalo percentil %.0f%%",
            d$n_replicates, 100 * d$confidence_level)
  } else sprintf("%d réplicas válidas", d$n_replicates)

  p <- plotly::plot_ly(x = d$replicates, type = "histogram",
                       name = "Réplicas bootstrap",
                       marker = list(color = .tone_color("brand"), opacity = 0.55),
                       hovertemplate = "%{x:.5g}<extra></extra>")
  plotly::layout(p,
                 title = list(text = sprintf("%s — %s", d$parameter, sub)),
                 xaxis = list(title = d$parameter),
                 yaxis = list(title = "Frecuencia"),
                 shapes = shapes, annotations = anns,
                 bargap = 0.02, showlegend = FALSE)
}


mod_tool_ui <- function(id) {
  ns <- shiny::NS(id)

  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 300,

      bmk_sidebar_section(
        "Datos",
        mod_data_input_ui(ns("datos")),
        shiny::selectInput(ns("variable"), "Variable a modelizar", choices = NULL),
        shiny::tags$p(
          class = "text-secondary",
          shiny::tags$small(
            "El CSV debe contener al menos una columna numérica. Tras cargarlo ",
            "podrás seleccionar la variable que deseas modelizar. Si el archivo ",
            "no tiene cabecera, la aplicación asignará nombres automáticamente ",
            "(", shiny::tags$code("Variable_1"), ", ", shiny::tags$code("Variable_2"),
            ", ...). Se admite coma, punto y coma o tabulador como separador; ",
            "los decimales deben usar punto. Máx. 10 MB / 100.000 filas."
          )
        ),
        mod_export_csv_ui(ns("plantilla"), "Descargar datos de ejemplo")
      ),

      bmk_sidebar_section(
        "Configuración",
        shiny::selectInput(ns("metodo"), "Método de estimación",
                           choices = MOD_METHOD_CHOICES, selected = "mle"),
        shiny::selectInput(ns("profundidad"), "Profundidad del análisis",
                           choices = MOD_DEPTH_CHOICES, selected = "standard")
      ),

      bmk_sidebar_section(
        "Cálculo",
        shiny::actionButton(ns("calcular"), "Calcular", class = "btn-primary")
      ),

      bmk_sidebar_section(
        "Exploración",
        shiny::checkboxInput(ns("modo_comparacion"), "Modo comparación", value = FALSE),
        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == true", ns("modo_comparacion")),
          shiny::checkboxGroupInput(ns("comparar"), "Distribuciones a comparar",
                                    choices = NULL),
          # ADR-029 (K-06): el texto de ayuda pasa a ser reactivo. Por debajo del
          # mínimo la comparación no puede mostrarse, y hasta ahora eso ocurría en
          # silencio: el gráfico volvía a exploración sin explicar por qué. El
          # modo NO se desactiva y la selección se conserva, para no romper el
          # intercambio de una distribución por otra.
          shiny::uiOutput(ns("aviso_comparacion"))
        ),
        shiny::actionButton(ns("restablecer"), "Restablecer análisis"),
        shiny::tags$p(
          class = "text-secondary",
          shiny::tags$small(
            "Vuelve a la recomendación oficial sin recalcular el análisis."
          )
        )
      )
    ),

    # B16: dos vistas dentro de la MISMA herramienta. `navset_hidden` conserva
    # ambos paneles en el DOM: navegar no destruye el análisis ni lo recalcula.
    bslib::navset_hidden(
      id = ns("vista"),

      bslib::nav_panel_hidden(
        "analisis",

    # Descripción breve (apartado 4.1 de la arquitectura).
    shiny::tags$p(
      class = "text-secondary",
      "Ajuste automático de distribuciones a una variable numérica (continua o",
      "discreta). La herramienta estima las candidatas de la familia detectada,",
      "las evalúa y recomienda cuál utilizar y por qué."
    ),

    # Métricas de cabecera.
    shiny::uiOutput(ns("metricas")),

    # Gráfico principal interactivo: sincronizado con el ranking.
    bmk_plot_container(
      "Ajuste sobre los datos observados",
      bmk_loading(plotly::plotlyOutput(ns("grafico_ajuste"), height = "340px")),
      shiny::tags$p(
        class = "text-secondary",
        shiny::tags$small(
          "Selecciona una distribución en el ranking para explorarla.",
          "Usa la leyenda para mostrar u ocultar curvas.",
          "La recomendación oficial no cambia."
        )
      )
    ),
    # 2) Comparar candidatas: ranking seleccionable.
    bmk_table_container(
      "Ranking de distribuciones",
      bmk_loading(DT::DTOutput(ns("tabla_ranking"))),
      shiny::tags$p(
        class = "text-secondary",
        shiny::tags$small("Haz clic en una fila para explorar esa distribución.")
      )
    ),

    # 3) Analizar la distribución mostrada: diagnóstico gráfico y ficha técnica.
    bslib::layout_columns(
      col_widths = c(6, 6),
      bmk_plot_container(
        "QQ-plot de la distribución mostrada",
        bmk_loading(shiny::plotOutput(ns("grafico_qq"), height = "280px"))
      ),
      bmk_plot_container(
        "PP-plot de la distribución mostrada",
        bmk_loading(shiny::plotOutput(ns("grafico_pp"), height = "280px"))
      )
    ),
    bmk_table_container(
      "Ficha técnica",
      shiny::uiOutput(ns("cabecera_seleccion")),
      shiny::uiOutput(ns("ficha_identificacion")),
      bslib::layout_columns(
        col_widths = c(5, 7),
        DT::DTOutput(ns("tabla_parametros")),
        DT::DTOutput(ns("tabla_metricas"))
      )
    ),

    # 4) Entender por qué: comparación con la recomendación oficial.
    shiny::uiOutput(ns("bloque_comparacion")),
    shiny::uiOutput(ns("interpretacion")),

    # 5) B16: acceso a la vista dedicada de incertidumbre. Es una tarjeta, no un
    # bloque de contenido: la pantalla principal no se llena de incertidumbre.
    shiny::uiOutput(ns("cta_incertidumbre")),
    mod_export_csv_ui(ns("exportar"))

      ),

      bslib::nav_panel_hidden("incertidumbre", .dfit_incertidumbre_ui(ns))
    )
  )
}

#' Panel de la vista dedicada de incertidumbre (B16.1)
#'
#' Se monta dentro de `navset_hidden`: la navegación no destruye el panel de
#' análisis, de modo que volver no reconstruye plotly ni DT desde cero.
.dfit_incertidumbre_ui <- function(ns) {
  htmltools::tagList(
    shiny::actionLink(ns("volver_analisis"), "← Volver al análisis"),
    shiny::tags$h3("Incertidumbre de parámetros", class = "mt-2"),
    shiny::uiOutput(ns("unc_cabecera")),

    bmk_table_container(
      "Incertidumbre analítica",
      shiny::uiOutput(ns("unc_analitica_estado")),
      DT::DTOutput(ns("unc_tabla_analitica"))
    ),

    bmk_table_container(
      "Incertidumbre bootstrap",
      bslib::layout_columns(
        col_widths = c(4, 4, 4),
        shiny::selectInput(ns("unc_B"), "Réplicas",
                           choices = MOD_UNC_B_CHOICES,
                           selected = as.character(MOD_UNC_B_DEFAULT)),
        shiny::numericInput(ns("unc_nivel"), "Nivel de confianza",
                            value = MOD_UNC_LEVEL_DEFAULT,
                            min = 0.5, max = 0.999, step = 0.01),
        shiny::selectInput(ns("unc_estimador"), "Estimador para la incertidumbre",
                           choices = NULL)
      ),
      shiny::actionButton(ns("unc_calcular"), "Calcular incertidumbre bootstrap",
                          class = "btn-primary"),
      shiny::tags$details(
        shiny::tags$summary("Opciones avanzadas"),
        bslib::layout_columns(
          col_widths = c(8, 4),
          shiny::numericInput(ns("unc_seed"), "Semilla", value = NA, step = 1),
          shiny::actionButton(ns("unc_nueva_seed"), "Generar otra")
        )
      ),
      shiny::uiOutput(ns("unc_bootstrap_estado")),
      bmk_loading(DT::DTOutput(ns("unc_tabla_bootstrap")))
    ),

    bmk_plot_container(
      "Distribución bootstrap del parámetro",
      shiny::uiOutput(ns("unc_selector_parametro")),
      bmk_loading(plotly::plotlyOutput(ns("unc_grafico"), height = "320px")),
      shiny::tags$p(class = "text-secondary", shiny::tags$small(
        "Distribución de las réplicas válidas, la estimación puntual y el",
        "intervalo percentil. Es una representación descriptiva."))
    ),

    shiny::uiOutput(ns("unc_comparacion")),
    shiny::uiOutput(ns("unc_reproducibilidad")),
    mod_export_csv_ui(ns("exportar_incertidumbre"),
                      "Exportar incertidumbre (CSV)")
  )
}


# ============================================================
# SERVER
# ============================================================

#' Server del módulo de Tool-02
#'
#' Recoge inputs, invoca el motor (`dist_fit_analyze`), construye el View Model
#' (`prepare_view_model`) y los datos de gráficos (`build_visual_data`), y
#' renderiza. No realiza ningún cálculo estadístico.
#'
#' @param id Identificador del módulo (namespace).
#' @param manifest Lista del `manifest.yml` (nombre y versión de la herramienta).
#' @return NULL (invisible).
mod_tool_server <- function(id, manifest) {
  shiny::moduleServer(id, function(input, output, session) {

    # --- Entrada de datos -----------------------------------------------------
    example_df <- as.data.frame(
      readr::read_csv("data/example_data.csv", show_col_types = FALSE)
    )
    # Sin contrato de columnas (ADR-018): la herramienta acepta cualquier CSV y
    # el usuario elige después la variable. La única exigencia funcional —que
    # exista al menos una columna numérica— se verifica al poblar el selector.
    datos <- mod_data_input_server(
      "datos",
      example_data     = example_df,
      expected_columns = NULL
    )
    mod_export_csv_server(
      "plantilla",
      data     = shiny::reactive(example_df),
      filename = "distribution-fitting-plantilla"
    )

    # --- Selector de variable: columnas numéricas del dataset activo ---------
    # Única exigencia funcional sobre el CSV: al menos una columna numérica.
    shiny::observeEvent(datos(), {
      shiny::req(datos()$is_valid)
      d <- datos()$data
      num_cols <- names(d)[vapply(d, is.numeric, logical(1))]
      if (length(num_cols) == 0L) {
        shiny::updateSelectInput(session, "variable", choices = character(0))
        # Aviso MODAL, no flotante (ADR-022): sin columnas numéricas no se puede
        # modelizar nada, así que el usuario debe enterarse sí o sí. Se le muestra
        # qué ha leído la herramienta en cada columna para que localice la causa.
        bmk_show_modal_alert(
          title   = "El archivo no contiene datos numéricos",
          type    = "error",
          message = paste(
            "Para ajustar una distribución hace falta al menos una columna de",
            "números, y en este archivo todas se han leído como texto o fecha.",
            "Corrige el archivo y vuelve a cargarlo."
          ),
          details = htmltools::tagList(
            htmltools::tags$p(
              htmltools::tags$strong("Columnas detectadas en el archivo:")
            ),
            htmltools::tags$table(
              htmltools::tags$thead(htmltools::tags$tr(
                htmltools::tags$th("Columna"),
                htmltools::tags$th("Tipo leído"),
                htmltools::tags$th("Primer valor")
              )),
              htmltools::tags$tbody(lapply(names(d), function(nm) {
                v <- d[[nm]]
                htmltools::tags$tr(
                  htmltools::tags$td(nm),
                  htmltools::tags$td(.dfit_type_label(v)),
                  htmltools::tags$td(.dfit_first_value(v))
                )
              }))
            ),
            htmltools::tags$p(
              htmltools::tags$strong("Causas más frecuentes:")
            ),
            htmltools::tags$ul(
              htmltools::tags$li(
                "El separador decimal es la coma (1.234,56) en lugar del punto."
              ),
              htmltools::tags$li(
                "Los números llevan separador de miles (12.500) o símbolo de moneda (12500 €)."
              ),
              htmltools::tags$li(
                "La columna contiene texto mezclado con los números (guiones, 'n/d', notas)."
              ),
              htmltools::tags$li(
                "El archivo solo tiene identificadores, fechas o categorías."
              )
            ),
            htmltools::tags$p(
              "Puedes descargar la plantilla de ejemplo desde el panel lateral",
              "para ver el formato esperado."
            )
          )
        )
        return()
      }
      sel <- if (!is.null(input$variable) && input$variable %in% num_cols) {
        input$variable
      } else {
        num_cols[1]
      }
      shiny::updateSelectInput(session, "variable", choices = num_cols, selected = sel)
      if (length(num_cols) < ncol(d)) {
        bmk_notify(
          sprintf("Se han detectado %d columna(s) numérica(s) de %d. Elige la variable a modelizar.",
                  length(num_cols), ncol(d)),
          type = "info"
        )
      }
    })

    # Columna seleccionada (extracción, sin estadística).
    variable_sel <- shiny::reactive({
      shiny::req(datos()$is_valid)
      d <- datos()$data
      col <- input$variable
      if (is.null(col) || !nzchar(col) || !(col %in% names(d)) || !is.numeric(d[[col]])) {
        num_cols <- names(d)[vapply(d, is.numeric, logical(1))]
        shiny::req(length(num_cols) > 0)
        col <- num_cols[1]
      }
      col
    })

    # --- Motor: una sola llamada; la UI no recalcula nada ---------------------
    analysis <- shiny::eventReactive(input$calcular, {
      shiny::req(datos()$is_valid)
      d <- datos()$data
      col <- variable_sel()
      v <- d[[col]]
      if (sum(is.finite(v)) < MOD_MIN_OBS) {
        bmk_notify(sprintf("Se necesitan al menos %d observaciones válidas.", MOD_MIN_OBS),
                   type = "error")
        return(NULL)
      }
      dist_fit_analyze(d, col, method = input$metodo,
                       analysis_depth = input$profundidad)
    })

    view_model <- shiny::reactive({
      an <- shiny::req(analysis())
      prepare_view_model(an, manifest = manifest)
    })
    visual_data <- shiny::reactive({
      an <- shiny::req(analysis())
      build_visual_data(an, datos()$data)
    })

    # Avisos del View Model (una notificación por aviso).
    shiny::observeEvent(analysis(), {
      for (w in view_model()$warnings) bmk_notify(w$text, type = w$notify_type)
    })

    # --- Metric cards ---------------------------------------------------------
    output$metricas <- shiny::renderUI({
      cards <- view_model()$metric_cards
      shiny::req(length(cards) > 0)
      widgets <- lapply(cards, function(c) {
        value <- if (is.na(c$value)) "—" else c$value
        bmk_metric_card(c$label, value, note = c$note)
      })
      do.call(bslib::layout_columns,
              c(list(col_widths = rep(12L %/% length(cards), length(cards))), widgets))
    })

    # --- Estado de exploración (solo visualización; NO altera la recomendación)
    # La recomendación oficial siempre es la del Assessment (B4). `selected_id`
    # es estado de interfaz: qué curva se resalta y qué parámetros se muestran.
    selected_id <- shiny::reactiveVal(NULL)

    # Ids de las candidatas evaluadas, en el mismo orden que las filas del ranking
    # y que las curvas del gráfico (contrato del View Model).
    ranked_ids <- shiny::reactive({
      vapply(view_model()$fits, function(f) f$id, character(1))
    })

    # Al recalcular: la selección vuelve por defecto a la recomendada.
    shiny::observeEvent(view_model(), {
      selected_id(view_model()$recommendation$level1$id)
    }, priority = 10)

    # (a) Ranking -> estado. Las filas descartadas no tienen curva: se ignoran.
    shiny::observeEvent(input$tabla_ranking_rows_selected, {
      ids <- ranked_ids()
      i <- input$tabla_ranking_rows_selected
      if (length(i) == 1L && i <= length(ids) && !identical(selected_id(), ids[i])) {
        selected_id(ids[i])
      }
    }, ignoreNULL = TRUE)

    # Etiquetas de las candidatas para el panel de comparación.
    shiny::observeEvent(view_model(), {
      vm <- view_model()
      opciones <- stats::setNames(vapply(vm$fits, function(f) f$id, character(1)),
                                  vapply(vm$fits, function(f) f$name, character(1)))
      # Preselección: la recomendada y la siguiente del ranking (mínimo del modo).
      sel <- utils::head(unname(opciones), MOD_COMPARE_MIN)
      shiny::updateCheckboxGroupInput(session, "comparar",
                                      choices = opciones, selected = sel)
    })

    # Guarda del modo comparación: entre MOD_COMPARE_MIN y MOD_COMPARE_MAX.
    shiny::observeEvent(input$comparar, {
      sel <- input$comparar
      if (length(sel) > MOD_COMPARE_MAX) {
        bmk_notify(sprintf("Puedes comparar como máximo %d distribuciones.",
                           MOD_COMPARE_MAX), type = "warning")
        shiny::updateCheckboxGroupInput(session, "comparar",
                                        selected = utils::head(sel, MOD_COMPARE_MAX))
      }
    }, ignoreNULL = FALSE)

    # Aviso inline del panel de comparación (ADR-029, K-06). Solo texto: no altera
    # `compare_ids()` ni ninguna otra lógica.
    output$aviso_comparacion <- shiny::renderUI({
      n <- length(input$comparar)
      if (n < MOD_COMPARE_MIN) {
        shiny::tags$p(
          class = "text-warning",
          shiny::tags$small(sprintf(
            paste("Marca al menos %d distribuciones para activar la comparación",
                  "(llevas %d). El modo sigue activo y tu selección se conserva."),
            MOD_COMPARE_MIN, n))
        )
      } else {
        shiny::tags$p(
          class = "text-secondary",
          shiny::tags$small(sprintf("Comparando %d distribuciones (entre %d y %d).",
                                    min(n, MOD_COMPARE_MAX), MOD_COMPARE_MIN,
                                    MOD_COMPARE_MAX))
        )
      }
    })

    # Ids en comparación (NULL si el modo está desactivado o hay menos del mínimo).
    compare_ids <- shiny::reactive({
      if (!isTRUE(input$modo_comparacion)) return(NULL)
      sel <- input$comparar
      if (length(sel) < MOD_COMPARE_MIN) return(NULL)
      utils::head(sel, MOD_COMPARE_MAX)
    })

    # (b) ADR-029: la leyenda NO participa en el estado analítico. Aquí existía un
    # observador de `plotly_legendclick` que en exploración escribía en
    # `selected_id` y en comparación reescribía `input$comparar`. Ninguna de las
    # dos ramas llegaba a ejecutarse —`event_data()` no aporta `curveNumber`— y
    # además emitía el aviso de evento no registrado en cada renderizado. Se
    # elimina junto con su `event_register()`: la leyenda queda como control de
    # VISIBILIDAD, con el comportamiento nativo de Plotly.

    # (c) Estado -> ranking: mantiene la fila resaltada y visible.
    shiny::observeEvent(selected_id(), {
      i <- match(selected_id(), ranked_ids())
      if (!is.na(i) && !identical(as.integer(input$tabla_ranking_rows_selected), as.integer(i))) {
        DT::selectRows(DT::dataTableProxy("tabla_ranking"), i)
      }
    }, ignoreNULL = TRUE)

    # --- Gráficos (datos del Visual Engine) ----------------------------------
    # El principal se redibuja al cambiar la selección: solo cambian el grosor y
    # la opacidad de las curvas; histograma y KDE permanecen intactos.
    output$grafico_ajuste <- plotly::renderPlotly({
      .plot_fit_plotly(visual_data(), selected_id(), compare_ids())
    })
    # QQ y PP siguen a la distribución MOSTRADA. Se recalculan con el bloque
    # ligero del Visual Engine (sin rehacer histograma, KDE ni curvas).
    qq_pp <- shiny::reactive({
      an <- shiny::req(analysis())
      build_qq_pp_data(an, datos()$data, distribution = selected_id())
    })
    output$grafico_qq <- shiny::renderPlot(.plot_qq(qq_pp()))
    output$grafico_pp <- shiny::renderPlot(.plot_pp(qq_pp()))

    # --- Tabla de ranking (seleccionable) ------------------------------------
    output$tabla_ranking <- DT::renderDT({
      rk <- view_model()$ranking
      DT::datatable(
        rk$data, rownames = FALSE,
        colnames = unname(rk$column_labels[names(rk$data)]),
        selection = list(mode = "single", target = "row", selected = 1L),
        options = list(dom = "t", pageLength = 15, ordering = FALSE)
      )
    })

    # --- Detalle de la distribución seleccionada ------------------------------
    selected_fit <- shiny::reactive({
      id <- shiny::req(selected_id())
      f <- Filter(function(x) identical(x$id, id), view_model()$fits)
      shiny::req(length(f) > 0)
      f[[1]]
    })

    # Cabecera: distingue explícitamente recomendación automática de exploración
    # manual. La recomendación del Assessment nunca cambia por explorar.
    # Cabecera: separa visualmente los dos conceptos mediante dos metric cards.
    # La recomendación oficial permanece siempre visible y no cambia al explorar.
    output$cabecera_seleccion <- shiny::renderUI({
      f    <- selected_fit()
      vm   <- view_model()
      rec  <- vm$recommendation$level1$id
      rec_f <- Filter(function(x) identical(x$id, rec), vm$fits)[[1]]
      es_recomendada <- identical(f$id, rec)

      # ADR-029 (K-08): la ficha sigue SIEMPRE a la selección del ranking, también
      # durante la comparación. No se cambia la fuente de selección: se hace
      # explícita, y se avisa de forma discreta cuando la distribución mostrada
      # no pertenece al conjunto comparado (en ese caso puede estar oculta del
      # gráfico y aun así ser la que describe toda la ficha).
      cmp  <- compare_ids()
      nota <- if (es_recomendada) {
        sprintf("seleccionada en el ranking · coincide con la recomendación · puesto %d de %d",
                f$rank, length(vm$fits))
      } else {
        sprintf("seleccionada en el ranking · exploración manual · puesto %d de %d",
                f$rank, length(vm$fits))
      }
      if (!is.null(cmp) && !(f$id %in% cmp)) {
        nota <- paste(nota, "· no está entre las comparadas: su curva no se dibuja")
      }

      bslib::layout_columns(
        col_widths = c(6, 6),
        bmk_metric_card("Recomendación oficial", rec_f$name,
                        note = "calculada por el Assessment · no cambia al explorar"),
        bmk_metric_card("Distribución mostrada", f$name, note = nota)
      )
    })

    # BLOQUE 1 de la ficha: identificación y origen del método de estimación.
    output$ficha_identificacion <- shiny::renderUI({
      f   <- selected_fit()
      vm  <- view_model()
      rec <- vm$recommendation$level1$id
      origen_metodo <- if (identical(vm$meta$method, "auto")) {
        "Método seleccionado automáticamente para esta distribución."
      } else {
        "Método seleccionado manualmente por el usuario."
      }
      shiny::tags$p(
        sprintf("%s · %s · método %s · %d parámetro(s)",
                f$name,
                if (identical(f$id, rec)) "recomendada" else "evaluada",
                toupper(f$method), f$n_params),
        shiny::tags$br(),
        shiny::tags$span(class = "text-secondary", shiny::tags$small(origen_metodo))
      )
    })

    # Comparación con la recomendación: solo cuando se explora otra distribución.
    # Todos los valores proceden del View Model; no se recalcula nada.
    output$bloque_comparacion <- shiny::renderUI({
      f   <- selected_fit()
      vm  <- view_model()
      rec <- vm$recommendation$level1$id
      if (identical(f$id, rec)) return(NULL)
      r <- Filter(function(x) identical(x$id, rec), vm$fits)[[1]]

      fila <- function(etiqueta, a, b) c(etiqueta, a, b)
      gof_rows <- if (!is.null(f$metrics$gof$ad)) {
        list(fila("Anderson-Darling (A²)", .fmt_num(r$metrics$gof$ad, 4), .fmt_num(f$metrics$gof$ad, 4)),
             fila("Kolmogorov-Smirnov (D)", .fmt_num(r$metrics$gof$ks, 4), .fmt_num(f$metrics$gof$ks, 4)),
             fila("Cramér-von Mises (W²)", .fmt_num(r$metrics$gof$cvm, 4), .fmt_num(f$metrics$gof$cvm, 4)))
      } else {
        list(fila("Chi-cuadrado", .fmt_num(r$metrics$gof$chisq, 4), .fmt_num(f$metrics$gof$chisq, 4)),
             fila("Sobredispersión", .fmt_num(r$metrics$gof$overdispersion, 4),
                  .fmt_num(f$metrics$gof$overdispersion, 4)))
      }
      filas <- c(
        list(fila("Puntuación global", .fmt_num(r$score, 1), .fmt_num(f$score, 1)),
             fila("AIC", .fmt_num(r$metrics$information$aic, 2), .fmt_num(f$metrics$information$aic, 2)),
             fila("BIC", .fmt_num(r$metrics$information$bic, 2), .fmt_num(f$metrics$information$bic, 2))),
        gof_rows,
        list(fila("Número de parámetros", as.character(r$n_params), as.character(f$n_params)))
      )
      df <- data.frame(
        concepto = vapply(filas, `[`, character(1), 1),
        recomendada = vapply(filas, `[`, character(1), 2),
        mostrada = vapply(filas, `[`, character(1), 3),
        stringsAsFactors = FALSE
      )

      # Observaciones ✔/✘ redactadas por los Text Builders (B5).
      obs <- lapply(f$vs_recommended, function(it) {
        shiny::tags$li(sprintf("%s %s", if (isTRUE(it$ok)) "✔" else "✘", it$text))
      })

      bmk_table_container(
        "Comparación con la recomendación",
        DT::renderDT(DT::datatable(
          df, rownames = FALSE,
          colnames = c("Concepto", sprintf("%s (recomendada)", r$name),
                       sprintf("%s (seleccionada en el ranking)", f$name)),
          selection = "none", options = list(dom = "t", ordering = FALSE)
        )),
        shiny::tags$div(
          shiny::tags$p(shiny::tags$strong("¿Por qué no es la recomendada?")),
          shiny::tags$ul(obs)
        )
      )
    })

    # --- Restablecer análisis: restaura el estado de interfaz, sin recalcular --
    shiny::observeEvent(input$restablecer, {
      vm <- view_model()
      selected_id(vm$recommendation$level1$id)
      shiny::updateCheckboxInput(session, "modo_comparacion", value = FALSE)
      shiny::updateCheckboxGroupInput(
        session, "comparar",
        selected = utils::head(vapply(vm$fits, function(f) f$id, character(1)),
                               MOD_COMPARE_MIN))
      bmk_notify("Análisis restablecido a la recomendación oficial.", type = "info")
    })

    output$tabla_parametros <- DT::renderDT({
      f <- selected_fit()
      df <- data.frame(
        parametro = names(f$params),
        valor = vapply(f$params, .fmt_num, character(1), digits = 4),
        stringsAsFactors = FALSE
      )
      DT::datatable(
        df, rownames = FALSE,
        colnames = c("Parámetro", "Valor estimado"),
        selection = "none",
        options = list(dom = "t", ordering = FALSE)
      )
    })

    # Métricas de la distribución mostrada. Todos los valores se COPIAN del View
    # Model (Diagnostics/Assessment); aquí no se calcula ninguna métrica.
    output$tabla_metricas <- DT::renderDT({
      f   <- selected_fit()
      rec <- view_model()$recommendation$level1$id
      inf <- f$metrics$information
      gof <- f$metrics$gof

      # Bloque 3: criterios de información. Bloque 4: bondad de ajuste (adaptado
      # a la familia). Bloque 5: evaluación del Assessment.
      filas <- list(
        c("Criterios de información", "Log-verosimilitud", .fmt_num(f$loglik, 3)),
        c("Criterios de información", "AIC", .fmt_num(inf$aic, 2)),
        c("Criterios de información", "BIC", .fmt_num(inf$bic, 2))
      )
      filas <- c(filas, if (!is.null(gof$ad)) {
        list(c("Bondad de ajuste", "Anderson-Darling (A²)", .fmt_num(gof$ad, 4)),
             c("Bondad de ajuste", "Kolmogorov-Smirnov (D)", .fmt_num(gof$ks, 4)),
             c("Bondad de ajuste", "Cramér-von Mises (W²)", .fmt_num(gof$cvm, 4)))
      } else {
        list(c("Bondad de ajuste", "Chi-cuadrado", .fmt_num(gof$chisq, 4)),
             c("Bondad de ajuste", "Grados de libertad", as.character(gof$df)),
             c("Bondad de ajuste", "Sobredispersión", .fmt_num(gof$overdispersion, 4)))
      })
      filas <- c(filas, list(
        c("Evaluación", "Puntuación global (0-100)", .fmt_num(f$score, 1)),
        c("Evaluación", "Nivel de ajuste (0-100)", .fmt_num(f$pillar_scores$A, 1)),
        c("Evaluación", "Nivel de parsimonia (0-100)", .fmt_num(f$pillar_scores$B, 1)),
        c("Evaluación", "Observaciones usadas", .fmt_num(f$n_used, 0))
      ))

      df <- data.frame(
        bloque  = vapply(filas, `[`, character(1), 1),
        metrica = vapply(filas, `[`, character(1), 2),
        valor   = vapply(filas, `[`, character(1), 3),
        stringsAsFactors = FALSE
      )
      DT::datatable(
        df, rownames = FALSE, colnames = c("Bloque", "Métrica", "Valor"),
        selection = "none", options = list(dom = "t", ordering = FALSE)
      )
    })

    # --- Interpretación (texto ya redactado por los Text Builders) -----------
    output$interpretacion <- shiny::renderUI({
      it <- view_model()$interpretation
      rec <- view_model()$recommendation$level1
      bmk_interpretation_box(
        htmltools::tagList(
          shiny::tags$p(it$summary),
          shiny::tags$p(rec$headline),
          shiny::tags$p(rec$confidence),
          shiny::tags$p(rec$main_reason),
          if (length(it$insights$why_won) > 0) {
            shiny::tags$ul(lapply(it$insights$why_won, shiny::tags$li))
          },
          if (length(it$insights$observations) > 0) {
            shiny::tags$ul(lapply(it$insights$observations, shiny::tags$li))
          }
        )
      )
    })

    # --- Exportación ----------------------------------------------------------
    base_nombre <- if (bmk_is_blank(manifest$slug)) {
      bmk_slugify(manifest$name)
    } else {
      manifest$slug
    }
    mod_export_csv_server(
      "exportar",
      data     = shiny::reactive(view_model()$export_table),
      filename = base_nombre
    )

    # ========================================================================
    # B16.1 — VISTA DE INCERTIDUMBRE DE PARÁMETROS
    # ========================================================================
    # Consume B12–B15 a través de `build_uncertainty_view()`. No reestima, no
    # toca ranking, recomendación, AUTO ni Decision Engine (ADR-029 intacto).

    # --- Navegación -----------------------------------------------------------
    output$cta_incertidumbre <- shiny::renderUI({
      shiny::req(analysis())
      bmk_interpretation_box(htmltools::tagList(
        shiny::tags$h5("Incertidumbre de parámetros"),
        shiny::tags$p(class = "text-secondary",
                      "Evalúa la precisión de los parámetros estimados."),
        shiny::actionButton(session$ns("ir_incertidumbre"),
                            "Explorar incertidumbre →", class = "btn-secondary")
      ))
    })
    shiny::observeEvent(input$ir_incertidumbre, {
      bslib::nav_select("vista", "incertidumbre", session = session)
    })
    shiny::observeEvent(input$volver_analisis, {
      bslib::nav_select("vista", "analisis", session = session)
    })

    # --- Estimador EFECTIVO de la distribución seleccionada -------------------
    # `analysis()$meta$method` es el método SOLICITADO: con "auto" no dice qué se
    # usó realmente. `.fit_auto()` es MLE-first pero cae a MoM o L-momentos POR
    # DISTRIBUCIÓN, de modo que la única fuente de verdad es el propio ajuste.
    # Traducir "auto" a "mle" etiquetaría como MLE un ajuste hecho por momentos.
    unc_base_estimator <- shiny::reactive({
      an <- shiny::req(analysis()); id <- shiny::req(selected_id())
      m <- an$motor$fits[[id]]$method
      shiny::req(!is.null(m), nzchar(m))
      m
    })

    # Opciones del selector: método EFECTIVO de la distribución seleccionada, más
    # PM como alternativo (OD-15, opción C). Depende también de `selected_id()`,
    # porque cambiar de fila del ranking NO recalcula `analysis()` y el método
    # efectivo puede ser distinto en otra distribución.
    shiny::observeEvent(list(analysis(), selected_id()), {
      base <- shiny::req(unc_base_estimator())
      opciones <- stats::setNames(
        c(base, "pm"),
        c(unname(DFIT_UNCERTAINTY_ESTIMATORS[[base]]),
          unname(DFIT_UNCERTAINTY_ESTIMATORS[["pm"]])))
      shiny::updateSelectInput(session, "unc_estimador",
                               choices = opciones, selected = base)
    }, ignoreNULL = TRUE)

    # --- Estimación puntual del estimador activo ------------------------------
    unc_point <- shiny::reactive({
      an <- shiny::req(analysis()); id <- shiny::req(selected_id())
      base <- shiny::req(unc_base_estimator())
      # Solo hay dos opciones: el método efectivo o PM. Cualquier otro valor
      # —incluido el residuo del selector mientras se actualiza tras cambiar de
      # distribución— se resuelve al método efectivo, nunca a uno inventado.
      est <- if (identical(input$unc_estimador, "pm")) "pm" else base
      if (identical(est, "pm")) {
        # Estimación PM sobre la MISMA distribución seleccionada. B11 productivo.
        r <- .pm_fit(id, an$sample$x)
        if (!isTRUE(r$converged)) {
          return(list(params = NULL, estimator = "pm", distribution = id,
                      pm_status = r$status, pm_reason = r$reason,
                      pm_percentiles = r$percentiles))
        }
        return(list(params = r$params, estimator = "pm", distribution = id,
                    pm_status = "success", pm_reason = NA_character_,
                    pm_percentiles = r$percentiles))
      }
      list(params = an$motor$fits[[id]]$params, estimator = est, distribution = id)
    })

    # --- Incertidumbre analítica, solo si el estimador EFECTIVO es MLE --------
    # Si el análisis se pidió en AUTO y para esta distribución hubo caída a MoM o
    # L-momentos, B12 NO aplica: `pe$estimator` ya es el método efectivo, de modo
    # que la comprobación es sobre él y no sobre `meta$method`.
    unc_analytic <- shiny::reactive({
      an <- shiny::req(analysis()); pe <- shiny::req(unc_point())
      if (!identical(pe$estimator, "mle") || is.null(pe$params)) return(NULL)
      fit <- an$motor$fits[[pe$distribution]]
      if (!isTRUE(fit$converged) || !identical(fit$method, "mle")) return(NULL)
      .mle_uncertainty(fit, an$sample$x, confidence_level = input$unc_nivel)
    })

    # --- Semilla: propuesta, editable, y CONGELADA al ejecutar ---------------
    shiny::observeEvent(analysis(), {
      shiny::updateNumericInput(session, "unc_seed",
                                value = sample.int(MOD_UNC_SEED_MAX, 1L))
    })
    shiny::observeEvent(input$unc_nueva_seed, {
      shiny::updateNumericInput(session, "unc_seed",
                                value = sample.int(MOD_UNC_SEED_MAX, 1L))
    })

    # --- Clave de identidad de la ejecución bootstrap -------------------------
    # Incluye el FINGERPRINT de la muestra, no `n` (lección de OD-18), y la
    # semilla: un resultado solo se presenta como vigente si toda la
    # configuración coincide.
    unc_key <- shiny::reactive({
      an <- shiny::req(analysis()); pe <- shiny::req(unc_point())
      list(distribution = pe$distribution, estimator = pe$estimator,
           fingerprint = .data_fingerprint(an$sample$x)$fingerprint,
           B = suppressWarnings(as.integer(input$unc_B)),
           confidence_level = input$unc_nivel,
           seed = suppressWarnings(as.integer(input$unc_seed)),
           pm_percentiles = if (identical(pe$estimator, "pm")) pe$pm_percentiles else NULL)
    })

    # Un único resultado en sesión: `list(key, bootstrap)`. Sin cache múltiple.
    unc_boot <- shiny::reactiveVal(NULL)

    shiny::observeEvent(input$unc_calcular, {
      an <- shiny::req(analysis()); pe <- shiny::req(unc_point())
      k <- unc_key()
      if (is.null(pe$params)) {
        bmk_notify("No hay estimación puntual para este estimador.", type = "error")
        return(invisible(NULL))
      }
      if (!is.na(.validate_bootstrap_seed(k$seed))) {
        bmk_notify("La semilla debe ser un número entero.", type = "error")
        return(invisible(NULL))
      }
      adapter <- if (identical(pe$estimator, "pm")) {
        .bootstrap_adapter_pm(pe$distribution, pe$pm_percentiles)
      } else {
        .bootstrap_adapter_fit(pe$distribution, pe$estimator,
                               family = an$candidates$family,
                               resolution = an$sample$resolution)
      }
      res <- .bootstrap_estimator(
        an$sample$x, adapter, B = k$B, seed = k$seed,
        confidence_level = k$confidence_level, theta_hat = pe$params,
        estimator = pe$estimator, distribution = pe$distribution,
        pm_percentiles = k$pm_percentiles)
      # La configuración queda CONGELADA junto al resultado: editar los campos
      # después no altera estos metadatos.
      unc_boot(list(key = k, bootstrap = res))
      if (!isTRUE(res$valid)) {
        bmk_notify(sprintf("Bootstrap sin resultado utilizable: %s", res$reason),
                   type = "warning")
      }
    })

    # Resultado vigente SOLO si la configuración coincide exactamente.
    unc_boot_vigente <- shiny::reactive({
      st <- unc_boot()
      if (is.null(st)) return(NULL)
      if (!identical(st$key, unc_key())) return(NULL)
      st$bootstrap
    })

    # --- Payload de la vista --------------------------------------------------
    unc_view <- shiny::reactive({
      an <- shiny::req(analysis()); pe <- shiny::req(unc_point())
      shiny::req(!is.null(pe$params))
      build_uncertainty_view(an, pe, analytic = unc_analytic(),
                             bootstrap = unc_boot_vigente(), manifest = manifest)
    })

    # --- Cabecera -------------------------------------------------------------
    output$unc_cabecera <- shiny::renderUI({
      pe <- shiny::req(unc_point()); an <- shiny::req(analysis())
      lab <- an$motor$fits[[pe$distribution]]$label
      htmltools::tagList(
        shiny::tags$p(shiny::tags$strong(sprintf("Analizando: %s · %s", lab,
          unname(DFIT_UNCERTAINTY_ESTIMATORS[[pe$estimator]])))),
        if (identical(pe$estimator, "pm")) shiny::tags$p(
          class = "text-secondary",
          shiny::tags$small(sprintf(paste(
            "Percentile Matching es un estimador ALTERNATIVO disponible solo en",
            "esta vista. No participa en el ranking ni en la recomendación",
            "oficial, que para esta distribución se basan en %s."),
            unname(DFIT_UNCERTAINTY_ESTIMATORS[[an$motor$fits[[pe$distribution]]$method]])))),
        # Con AUTO el método pedido y el usado pueden diferir por distribución.
        if (identical(an$meta$method, "auto")) shiny::tags$p(
          class = "text-secondary",
          shiny::tags$small(sprintf(paste(
            "El análisis se ejecutó en modo automático; para esta distribución",
            "el método efectivamente utilizado fue %s."),
            unname(DFIT_UNCERTAINTY_ESTIMATORS[[an$motor$fits[[pe$distribution]]$method]])))),
        shiny::tags$p(class = "text-secondary", shiny::tags$small(sprintf(
          "Muestra modelizada: n = %s · soporte %s%s",
          format(an$sample$n_used, big.mark = "."), an$sample$support_label,
          if (an$sample$n_excluded_zeros > 0)
            sprintf(" · %d ceros excluidos", an$sample$n_excluded_zeros) else ""))),
        shiny::tags$p(class = "text-secondary", shiny::tags$small(
          "La recomendación oficial del análisis no cambia por explorar aquí."))
      )
    })

    # --- Analítica ------------------------------------------------------------
    output$unc_analitica_estado <- shiny::renderUI({
      uv <- shiny::req(unc_view())
      if (identical(uv$analytic$status, "complete")) {
        return(shiny::tags$p(class = "text-secondary", shiny::tags$small(sprintf(
          "Información observada del MLE · nivel de confianza %.0f%%",
          100 * uv$analytic$confidence_level))))
      }
      msg <- switch(uv$analytic$status,
        not_applicable = "La incertidumbre analítica no está disponible para este estimador en v1.1. Puedes calcularla por bootstrap.",
        not_requested  = "No se ha calculado incertidumbre analítica.",
        "No ha podido obtenerse incertidumbre analítica para este ajuste. Puedes calcularla por bootstrap.")
      htmltools::tagList(
        shiny::tags$p(msg),
        if (!is.na(uv$analytic$reason)) shiny::tags$details(
          shiny::tags$summary("Detalles técnicos"),
          shiny::tags$p(class = "text-secondary",
                        shiny::tags$small(uv$analytic$reason)))
      )
    })
    output$unc_tabla_analitica <- DT::renderDT({
      uv <- shiny::req(unc_view())
      shiny::req(identical(uv$analytic$status, "complete"))
      DT::datatable(uv$analytic$table, rownames = FALSE,
                    colnames = c("Parámetro", "Estimación", "SE",
                                 "IC inferior", "IC superior"),
                    selection = "none",
                    options = list(dom = "t", ordering = FALSE)) |>
        DT::formatSignif(columns = 2:5, digits = 5)
    })

    # --- Bootstrap ------------------------------------------------------------
    output$unc_bootstrap_estado <- shiny::renderUI({
      uv <- shiny::req(unc_view())
      if (is.null(unc_boot_vigente())) {
        txt <- if (is.null(unc_boot())) {
          "No se ha calculado bootstrap para esta selección."
        } else {
          paste("La configuración actual es distinta de la utilizada en el último",
                "bootstrap. Calcula de nuevo la incertidumbre para actualizar los",
                "resultados.")
        }
        return(shiny::tags$p(class = "text-secondary", txt))
      }
      b <- uv$bootstrap
      htmltools::tagList(
        shiny::tags$p(sprintf(
          "Réplicas solicitadas: %s · exitosas: %s · fallidas: %s",
          b$B_requested, b$B_success, b$B_failed)),
        if (isTRUE(b$B_failed > 0)) shiny::tags$p(
          class = "text-secondary", shiny::tags$small(paste(
            "Algunas réplicas no produjeron un ajuste válido y no se incluyen en",
            "los resúmenes. Los motivos se detallan en Reproducibilidad."))),
        if (length(uv$limitations) > 0) shiny::tags$details(
          shiny::tags$summary("Limitaciones"),
          shiny::tags$ul(lapply(uv$limitations, function(l)
            shiny::tags$li(shiny::tags$small(l)))))
      )
    })
    output$unc_tabla_bootstrap <- DT::renderDT({
      uv <- shiny::req(unc_view()); shiny::req(!is.null(unc_boot_vigente()))
      DT::datatable(uv$bootstrap$table, rownames = FALSE,
                    colnames = c("Parámetro", "Estimación", "SE bootstrap",
                                 "IC inferior", "IC superior"),
                    selection = "none",
                    options = list(dom = "t", ordering = FALSE)) |>
        DT::formatSignif(columns = 2:5, digits = 5)
    })

    # --- Gráfico por parámetro ------------------------------------------------
    output$unc_selector_parametro <- shiny::renderUI({
      uv <- shiny::req(unc_view()); ps <- uv$bootstrap$parameters
      shiny::req(length(ps) > 1L, !is.null(unc_boot_vigente()))
      shiny::radioButtons(session$ns("unc_param"), NULL, choices = ps,
                          selected = ps[1], inline = TRUE)
    })
    output$unc_grafico <- plotly::renderPlotly({
      uv <- shiny::req(unc_view()); bt <- shiny::req(unc_boot_vigente())
      ps <- uv$bootstrap$parameters
      p <- if (!is.null(input$unc_param) && input$unc_param %in% ps)
             input$unc_param else ps[1]
      d <- build_bootstrap_plot_data(bt, uv$point_estimate, p)
      shiny::validate(shiny::need(d$available, "Sin réplicas suficientes."))
      .plot_bootstrap(d)
    })

    # --- Comparación descriptiva (B15) ---------------------------------------
    output$unc_comparacion <- shiny::renderUI({
      uv <- shiny::req(unc_view()); st <- uv$comparison$comparison_status
      if (identical(st, "available")) {
        return(bmk_table_container(
          "Comparación descriptiva",
          shiny::tags$p(class = "text-secondary", shiny::tags$small(
            "Ambas vías corresponden a la misma muestra. La comparación es",
            "descriptiva: no se aplica ningún criterio automático de acuerdo.")),
          DT::renderDT({
            DT::datatable(uv$comparison$parameters[, c(
              "parameter", "estimate", "analytic_se", "analytic_ci_lower",
              "analytic_ci_upper", "bootstrap_se", "bootstrap_ci_lower",
              "bootstrap_ci_upper")],
              rownames = FALSE, selection = "none",
              colnames = c("Parámetro", "Estimación", "SE analítico",
                           "IC analítico inf.", "IC analítico sup.",
                           "SE bootstrap", "IC bootstrap inf.",
                           "IC bootstrap sup."),
              options = list(dom = "t", ordering = FALSE)) |>
              DT::formatSignif(columns = 2:8, digits = 5)
          })))
      }
      if (identical(st, "not_comparable")) {
        return(bmk_interpretation_box(htmltools::tagList(
          shiny::tags$p(paste(
            "No se ha podido verificar que la incertidumbre analítica y la",
            "bootstrap correspondan exactamente a la misma muestra, de modo que",
            "no se presentan como una comparación. Cada una sigue siendo válida",
            "por separado.")),
          shiny::tags$p(class = "text-secondary", shiny::tags$small(
            uv$validation$comparability$sample_identity_reason)))))
      }
      NULL
    })

    # --- Reproducibilidad -----------------------------------------------------
    output$unc_reproducibilidad <- shiny::renderUI({
      uv <- shiny::req(unc_view()); r <- uv$reproducibility
      fila <- function(k, v) shiny::tags$tr(shiny::tags$td(k),
                                            shiny::tags$td(.dfit_repro_txt(v)))
      shiny::tags$details(
        shiny::tags$summary("Reproducibilidad y detalles técnicos"),
        shiny::tags$table(class = "table table-sm", shiny::tags$tbody(
          fila("Distribución", r$analysis$distribution),
          fila("Estimador", r$analysis$estimator),
          fila("Método de incertidumbre", r$analysis$uncertainty_method),
          fila("Réplicas solicitadas", r$analysis$B_requested),
          fila("Réplicas exitosas", r$analysis$B_success),
          fila("Réplicas fallidas", r$analysis$B_failed),
          fila("Nivel de confianza", r$analysis$confidence_level),
          fila("Semilla", r$analysis$seed),
          if (!is.null(r$analysis$pm_percentiles))
            fila("Percentiles PM", paste(r$analysis$pm_percentiles, collapse = " / ")),
          fila("n modelizada", r$data$n_used),
          fila("Huella de datos", r$data$fingerprint),
          fila("Algoritmo de huella", r$data$fingerprint_algo),
          fila("Herramienta", r$software$tool_name),
          fila("Versión", r$software$tool_version),
          fila("Versión de schema", r$software$schema_version)
        )),
        if (length(uv$diagnostics) > 0)
          shiny::tags$ul(lapply(uv$diagnostics, function(d)
            shiny::tags$li(shiny::tags$small(d))))
      )
    })

    # --- Exportación de incertidumbre (tercera instancia del módulo) ---------
    mod_export_csv_server(
      "exportar_incertidumbre",
      data     = shiny::reactive(unc_view()$export_table),
      filename = paste0(base_nombre, "-incertidumbre")
    )

    invisible(NULL)
  })
}
