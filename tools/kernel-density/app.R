# ============================================================
# Tool: kernel-density
# Archivo: app.R — orquestación (regla 6/15): library -> shared -> ui -> server
# Autor: BMK
# Última actualización: 2026-07-19
# ============================================================
#
# Ensamblador de la herramienta. Sin lógica actuarial, sin lógica de UI y sin
# transformaciones (regla 6): solo carga, ensambla y arranca. Toda la matemática
# vive en R/calc.R; toda la interfaz en R/mod_tool.R.

# 1) Librerías (el resto de paquetes se usan con namespacing explícito).
library(shiny)
library(bslib)

# 2) Carga del framework compartido y de la lógica local de la herramienta.
source("../../shared/load_shared.R")   # todo shared/ + configuración global
source("R/calc.R")                     # motor (sin Shiny)
source("R/mod_tool.R")                 # módulo de la herramienta (UI + reactividad)

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
