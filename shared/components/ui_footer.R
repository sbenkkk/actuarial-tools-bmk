# ============================================================
# Actuarial Tools by BMK — Componentes
# Archivo: ui_footer.R — pie consistente de la aplicación
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Función pura de UI (catálogo 7.2). Muestra versión, aviso de privacidad,
# disclaimer de uso y copyright. La versión procede del manifest (fuente única
# de verdad, apartado 9.2). Los textos fijos proceden de la config global
# (bmk_config). Depende del tema (clase .bmk-footer) y del manifest.

#' Pie de página de una herramienta BMK
#'
#' @param manifest Lista con los metadatos de la herramienta (campo `version`),
#'   normalmente `yaml::read_yaml("manifest.yml")`.
#' @return Tag `footer` de htmltools con clase `.bmk-footer` (landmark contentinfo).
bmk_footer_ui <- function(manifest) {
  version <- manifest$version %||% "0.0.0"
  year    <- format(Sys.Date(), "%Y")

  htmltools::tags$footer(
    class = "bmk-footer",
    role = "contentinfo",
    htmltools::tags$div(
      sprintf("© %s %s · v%s", year, bmk_config$brand, version)
    ),
    htmltools::tags$div(class = "text-secondary", bmk_config$privacy_notice),
    htmltools::tags$div(class = "text-secondary", bmk_config$use_disclaimer)
  )
}
