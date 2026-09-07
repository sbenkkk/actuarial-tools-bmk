# ============================================================
# Actuarial Tools by BMK — Design System
# Archivo: theme_bmk.R — motor de theming (Bootstrap, ggplot2, plotly)
# Autor: BMK
# Última actualización: 2026-07-18
# ============================================================
#
# Depende de colors.R (debe cargarse después de él). Expone tres funciones
# públicas del catálogo 7.2:
#   - theme_bmk()          -> objeto bslib::bs_theme para la UI
#   - theme_bmk_ggplot()   -> tema ggplot2 de marca para gráficos estáticos
#   - bmk_plotly_layout()  -> aplica la estética BMK a un objeto plotly
# Los tokens tipográficos y de espaciado viven aquí por ser parámetros de
# theming (no de paleta). Ningún valor visual es "mágico": todo es constante
# nombrada (regla 8, aplicada por coherencia también fuera de calc.R).

# --- Captura de la ruta del archivo (para localizar styles.css) ---------------
# Se resuelve en tiempo de `source()`, momento en el que `ofile` está disponible.
.bmk_theme_file <- local({
  found <- NULL
  for (i in seq_len(sys.nframe())) {
    of <- sys.frame(i)$ofile
    if (!is.null(of)) found <- of
  }
  found
})

# --- Tokens tipográficos (apartado 3.2) ---------------------------------------
# Familia principal Inter, alternativa IBM Plex Sans; los gráficos usan la misma
# familia que la interfaz para lograr homogeneidad total.
bmk_font <- list(
  family   = "Inter",
  fallback = "IBM Plex Sans",
  # Pila de respaldo del sistema (si la fuente web no carga).
  stack    = "Inter, 'IBM Plex Sans', system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"
)

# Tamaños de la interfaz en píxeles (reflejan la tabla del apartado 3.2).
bmk_font_px <- list(
  app_title = 22,  # título de la aplicación (header)
  section   = 16,  # título de sección
  body      = 14,  # texto cuerpo (base de Bootstrap)
  aux       = 12,  # texto auxiliar y labels
  metric    = 30   # números destacados de metric cards (rango 28-32)
)

# Tamaños para gráficos en puntos (ggplot2 razona en pt, no en px).
bmk_font_pt <- list(
  base       = 12,
  title      = 15,
  subtitle   = 12,
  axis_title = 12,
  axis_text  = 11,
  legend     = 11,
  caption    = 9,
  strip      = 12
)

# --- Escala de espaciado ------------------------------------------------------
# Escala de base 4 (4/8/12/16/20/24). Toda separación de la interfaz usa un peldaño
# de esta escala en lugar de valores aislados: garantiza ritmo vertical y
# horizontal consistente entre componentes y herramientas, y evita la deriva de
# "números mágicos" de padding/margin.
bmk_space <- list(
  xs  = "4px",
  sm  = "8px",
  md  = "12px",
  lg  = "16px",
  xl  = "20px",
  xxl = "24px"
)

# --- Tokens de superficie (apartado 3.4) --------------------------------------
bmk_shape <- list(
  radius = "6px",                        # nunca superior a 8px
  shadow = "0 1px 3px rgba(0,0,0,0.06)", # sombra sutil, sin profundidad
  card_padding = bmk_space$xl,           # 20px, dentro del rango 16-24
  sidebar_width = "300px"
)

# ------------------------------------------------------------------------------
# theme_bmk()
# ------------------------------------------------------------------------------
#' Tema Bootstrap 5 de marca para toda la interfaz BMK
#'
#' Construye el objeto `bslib::bs_theme` que reescribe las variables de Bootstrap
#' con la identidad visual del proyecto, inyecta las custom properties de marca
#' `--bmk-*` (derivadas de `colors.R`) y adjunta `styles.css`. De este modo, una
#' única llamada deja lista toda la capa visual de una herramienta.
#'
#' @param include_css Logical. Si TRUE (por defecto) adjunta `styles.css` al tema.
#' @param css_path    Ruta opcional a `styles.css`. Si es NULL se localiza como
#'   archivo hermano de este script.
#' @return Objeto `bs_theme` listo para `bslib::page_*()` o `fluidPage(theme=)`.
theme_bmk <- function(include_css = TRUE, css_path = NULL) {
  theme <- bslib::bs_theme(
    version = 5,

    # Colores principales: Bootstrap deriva de aquí decenas de variables --bs-*.
    bg        = bmk_colors$surface,      # superficie base blanca
    fg        = bmk_colors$text,
    primary   = bmk_colors$primary,
    secondary = bmk_colors$text_secondary,
    success   = bmk_colors$success,
    warning   = bmk_colors$warning,
    danger    = bmk_colors$error,
    info      = bmk_colors$accent,

    # Tipografía: colección con fuente web + respaldo del sistema.
    base_font = bslib::font_collection(
      bslib::font_google(bmk_font$family, local = TRUE),
      bmk_font$fallback, "system-ui", "-apple-system", "Segoe UI",
      "Roboto", "sans-serif"
    ),

    # Sobrescritura de variables Sass de Bootstrap (nombres sin prefijo `$`).
    "body-bg"            = bmk_colors$background,  # fondo gris de la app
    "body-color"         = bmk_colors$text,
    "font-size-base"     = "0.875rem",             # 14px sobre 16px base
    "border-color"       = bmk_colors$border,
    "border-radius"      = bmk_shape$radius,
    "border-radius-sm"   = bmk_shape$radius,
    "border-radius-lg"   = bmk_shape$radius,
    "headings-font-weight" = "600",
    "headings-color"     = bmk_colors$text,
    "link-color"         = bmk_colors$primary,
    "link-hover-color"   = bmk_colors$primary,

    # Tarjetas.
    "card-bg"            = bmk_colors$surface,
    "card-cap-bg"        = bmk_colors$surface,
    "card-border-color"  = bmk_colors$border,
    "card-border-radius" = bmk_shape$radius,
    "card-box-shadow"    = bmk_shape$shadow,
    "card-spacer-y"      = bmk_shape$card_padding,
    "card-spacer-x"      = bmk_shape$card_padding,

    # Botones e inputs.
    "btn-font-weight"        = "500",
    "input-border-color"     = bmk_colors$border,
    "input-focus-border-color" = bmk_colors$primary,
    "component-active-bg"    = bmk_colors$primary
  )

  # Custom properties de marca + styles.css, todo como reglas Sass del tema.
  rules <- .bmk_brand_css_vars()
  if (include_css) {
    css_file <- css_path %||% .bmk_locate_css()
    if (!is.null(css_file) && !is.na(css_file) && file.exists(css_file)) {
      rules <- paste(rules, paste(readLines(css_file, warn = FALSE), collapse = "\n"),
                     sep = "\n")
    }
  }
  bslib::bs_add_rules(theme, rules)
}

# ------------------------------------------------------------------------------
# theme_bmk_ggplot()
# ------------------------------------------------------------------------------
#' Tema ggplot2 de marca para todos los gráficos estáticos del proyecto
#'
#' Estética homogénea: fondo blanco, grid mayor tenue, grid menor eliminado, ejes
#' en gris, tipografía de marca y jerarquía clara entre título, subtítulo, ejes,
#' leyenda y caption. Las escalas de color de los datos se aplican por gráfico con
#' `bmk_colors$sequential` / `bmk_colors$categorical`.
#'
#' @param base_size   Tamaño base de fuente en puntos.
#' @param base_family Familia tipográfica (por defecto, la de la interfaz).
#' @return Objeto `theme` de ggplot2 combinable con `+`.
theme_bmk_ggplot <- function(base_size = bmk_font_pt$base,
                             base_family = bmk_font$family) {
  half <- base_size / 2

  ggplot2::theme_minimal(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      # Superficie.
      plot.background  = ggplot2::element_rect(fill = bmk_colors$surface, colour = NA),
      panel.background = ggplot2::element_rect(fill = bmk_colors$surface, colour = NA),

      # Grid: solo mayor, muy tenue; menor eliminado para reducir ruido.
      panel.grid.major = ggplot2::element_line(colour = bmk_colors$grid, linewidth = 0.3),
      panel.grid.minor = ggplot2::element_blank(),

      # Ejes en gris; título del gráfico anclado al lienzo (alineación limpia).
      axis.line   = ggplot2::element_blank(),
      axis.ticks  = ggplot2::element_line(colour = bmk_colors$grid, linewidth = 0.3),
      axis.text   = ggplot2::element_text(colour = bmk_colors$text_secondary,
                                          size = bmk_font_pt$axis_text),
      axis.title  = ggplot2::element_text(colour = bmk_colors$text_secondary,
                                          size = bmk_font_pt$axis_title),
      axis.title.x = ggplot2::element_text(margin = ggplot2::margin(t = half)),
      axis.title.y = ggplot2::element_text(margin = ggplot2::margin(r = half)),

      # Jerarquía textual.
      plot.title.position = "plot",
      plot.title    = ggplot2::element_text(colour = bmk_colors$text,
                                            size = bmk_font_pt$title, face = "bold",
                                            margin = ggplot2::margin(b = half * 0.6)),
      plot.subtitle = ggplot2::element_text(colour = bmk_colors$text_secondary,
                                            size = bmk_font_pt$subtitle,
                                            margin = ggplot2::margin(b = half)),
      plot.caption.position = "plot",
      plot.caption  = ggplot2::element_text(colour = bmk_colors$text_secondary,
                                            size = bmk_font_pt$caption, hjust = 0,
                                            margin = ggplot2::margin(t = half)),

      # Leyenda: al pie, sin caja, integrada en el flujo de lectura.
      legend.position   = "bottom",
      legend.title      = ggplot2::element_text(colour = bmk_colors$text_secondary,
                                                size = bmk_font_pt$legend),
      legend.text       = ggplot2::element_text(colour = bmk_colors$text,
                                                size = bmk_font_pt$legend),
      legend.key        = ggplot2::element_blank(),
      legend.background = ggplot2::element_blank(),

      # Facetas.
      strip.background = ggplot2::element_rect(fill = bmk_colors$background, colour = NA),
      strip.text       = ggplot2::element_text(colour = bmk_colors$text,
                                               size = bmk_font_pt$strip, face = "bold"),

      # Márgenes generosos y consistentes.
      plot.margin = ggplot2::margin(base_size, base_size, base_size, base_size)
    )
}

# ------------------------------------------------------------------------------
# bmk_plotly_layout()
# ------------------------------------------------------------------------------
#' Aplica la estética BMK a un objeto plotly ya construido
#'
#' Garantiza que los gráficos interactivos compartan tipografía, colores de fondo,
#' grid, leyenda y hover con los estáticos. Preserva la interactividad nativa
#' (zoom, hover, descarga de imagen de la modebar).
#'
#' @param p Objeto `plotly`.
#' @return El mismo objeto con el layout de marca aplicado.
bmk_plotly_layout <- function(p) {
  base_font <- list(family = bmk_font$stack,
                    size = bmk_font_pt$axis_text + 1,
                    color = bmk_colors$text)
  axis <- list(
    gridcolor = bmk_colors$grid,
    zerolinecolor = bmk_colors$border,
    linecolor = bmk_colors$border,
    tickfont = list(color = bmk_colors$text_secondary),
    titlefont = list(color = bmk_colors$text_secondary),
    automargin = TRUE
  )

  plotly::layout(
    p,
    font = base_font,
    colorway = bmk_colors$categorical,
    paper_bgcolor = bmk_colors$surface,
    plot_bgcolor  = bmk_colors$surface,
    title = list(font = list(size = bmk_font_pt$title + 2, color = bmk_colors$text),
                 x = 0, xanchor = "left"),
    xaxis = axis,
    yaxis = axis,
    legend = list(orientation = "h", x = 0, y = -0.2,
                  font = list(color = bmk_colors$text)),
    hoverlabel = list(bgcolor = bmk_colors$surface,
                      bordercolor = bmk_colors$border,
                      font = list(family = bmk_font$stack, color = bmk_colors$text)),
    margin = list(l = 60, r = 30, t = 50, b = 60)
  )
}

# --- Helpers internos ---------------------------------------------------------

#' Genera el bloque :root con las custom properties de marca `--bmk-*`
#'
#' Deriva las variables CSS de `colors.R` y de los tokens de este archivo, de modo
#' que `styles.css` no contenga ningún valor literal (fuente única de verdad).
#' @return Cadena CSS con un bloque `:root { ... }`.
.bmk_brand_css_vars <- function() {
  vars <- c(
    sprintf("--bmk-bg: %s;",             bmk_colors$background),
    sprintf("--bmk-surface: %s;",        bmk_colors$surface),
    sprintf("--bmk-text: %s;",           bmk_colors$text),
    sprintf("--bmk-text-secondary: %s;", bmk_colors$text_secondary),
    sprintf("--bmk-border: %s;",         bmk_colors$border),
    sprintf("--bmk-primary: %s;",        bmk_colors$primary),
    sprintf("--bmk-accent: %s;",         bmk_colors$accent),
    sprintf("--bmk-success: %s;",        bmk_colors$success),
    sprintf("--bmk-warning: %s;",        bmk_colors$warning),
    sprintf("--bmk-error: %s;",          bmk_colors$error),
    sprintf("--bmk-grid: %s;",           bmk_colors$grid),
    sprintf("--bmk-sidebar: %s;",        bmk_colors$sidebar),
    sprintf("--bmk-on-primary: %s;",     bmk_colors$on_primary),
    sprintf("--bmk-primary-hover: %s;",  bmk_colors$primary_hover),
    sprintf("--bmk-error-hover: %s;",    bmk_colors$error_hover),
    sprintf("--bmk-radius: %s;",         bmk_shape$radius),
    sprintf("--bmk-shadow: %s;",         bmk_shape$shadow),
    sprintf("--bmk-sidebar-width: %s;",  bmk_shape$sidebar_width),
    sprintf("--bmk-space-xs: %s;",       bmk_space$xs),
    sprintf("--bmk-space-sm: %s;",       bmk_space$sm),
    sprintf("--bmk-space-md: %s;",       bmk_space$md),
    sprintf("--bmk-space-lg: %s;",       bmk_space$lg),
    sprintf("--bmk-space-xl: %s;",       bmk_space$xl),
    sprintf("--bmk-space-xxl: %s;",      bmk_space$xxl),
    sprintf("--bmk-fs-app-title: %dpx;", bmk_font_px$app_title),
    sprintf("--bmk-fs-section: %dpx;",   bmk_font_px$section),
    sprintf("--bmk-fs-body: %dpx;",      bmk_font_px$body),
    sprintf("--bmk-fs-aux: %dpx;",       bmk_font_px$aux),
    sprintf("--bmk-fs-metric: %dpx;",    bmk_font_px$metric),
    sprintf("--bmk-font-stack: %s;",     bmk_font$stack)
  )
  paste0(":root {\n  ", paste(vars, collapse = "\n  "), "\n}\n")
}

#' Localiza styles.css como archivo hermano de este script
#' @return Ruta al archivo, o NA si no se encuentra.
.bmk_locate_css <- function() {
  candidates <- character(0)
  if (!is.null(.bmk_theme_file)) {
    candidates <- c(candidates, file.path(dirname(.bmk_theme_file), "styles.css"))
  }
  candidates <- c(candidates,
                  "shared/theme/styles.css", "../theme/styles.css", "styles.css")
  hit <- candidates[file.exists(candidates)]
  if (length(hit)) normalizePath(hit[1]) else NA_character_
}

# Operador de respaldo (NULL-coalescing). Local al design system; no colisiona
# con implementaciones de otros paquetes gracias al scope de source().
`%||%` <- function(a, b) if (is.null(a)) b else a
