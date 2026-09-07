# ============================================================
# Tool: tool-00-template
# Archivo: app.R — orquestación (regla 6/15): library -> shared -> ui -> server
# Autor: BMK
# Última actualización: 2026-07-18
# ============================================================
#
# Capa mínima de orquestación. Sin lógica de cálculo (regla 6). Cada herramienta
# futura nace copiando esta plantilla (apartado 12.1).

# 1) Librerías (namespacing explícito en el resto; aquí solo lo esencial).
library(shiny)
library(bslib)

# 2) Carga del framework compartido y de la lógica local de la herramienta.
source("../../shared/load_shared.R")   # todo shared/ + configuración global
source("R/calc.R")                     # lógica local (sin Shiny)
source("R/mod_tool.R")                 # módulo de la herramienta

# 3) Metadatos: fuente única del nombre y la versión (apartado 9.2).
manifest <- yaml::read_yaml("manifest.yml")

# 4) UI: tema de marca (+ styles.css) y ensamblaje header / módulo / footer.
ui <- bslib::page_fluid(
  theme = theme_bmk(),
  bmk_header_ui(manifest),
  mod_tool_ui("tool"),
  bmk_footer_ui(manifest)
)

# 5) Server: monta el único módulo de la herramienta.
server <- function(input, output, session) {
  mod_tool_server("tool", manifest)
}

# 6) Arranque.
shinyApp(ui, server)
