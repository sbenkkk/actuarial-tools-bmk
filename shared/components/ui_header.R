# ============================================================
# Actuarial Tools by BMK — Componentes
# Archivo: ui_header.R — cabecera consistente de la aplicación
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Función pura de UI (catálogo 7.2). Muestra logo de marca + nombre de la serie
# y de la herramienta. Depende del tema (clases .bmk-header*), de la config
# (bmk_config$brand) y del manifest. Sin estilos inline: toda la presentación
# vive en styles.css.

#' Marca gráfica del proyecto (icono abstracto, definido una sola vez)
#'
#' SVG monocromo que hereda el color del contenedor vía `currentColor`, de modo
#' que sirve como logo del header y como base de favicon (apartado 3.3). Barras
#' ascendentes: alusión sobria a distribuciones/cuantiles, sin decoración.
#' Marcado como decorativo (aria-hidden): el nombre accesible lo aporta el texto.
#' @return Tag SVG de htmltools.
.bmk_brand_mark <- function() {
  htmltools::HTML(
    '<svg class="bmk-logo" width="22" height="22" viewBox="0 0 24 24" fill="none"
      xmlns="http://www.w3.org/2000/svg" aria-hidden="true" focusable="false">
      <rect x="3"  y="13" width="4" height="8"  rx="1" fill="currentColor"/>
      <rect x="10" y="8"  width="4" height="13" rx="1" fill="currentColor"/>
      <rect x="17" y="3"  width="4" height="18" rx="1" fill="currentColor"/>
    </svg>'
  )
}

#' Cabecera de una herramienta BMK
#'
#' Devuelve el header con logo, nombre de la serie y nombre de la herramienta.
#' @param manifest Lista con los metadatos de la herramienta (campo `name`),
#'   normalmente `yaml::read_yaml("manifest.yml")`.
#' @return Tag `header` de htmltools con clase `.bmk-header` (landmark banner).
bmk_header_ui <- function(manifest) {
  tool_name <- manifest$name %||% "Herramienta sin nombre"
  htmltools::tags$header(
    class = "bmk-header",
    role = "banner",
    .bmk_brand_mark(),
    htmltools::tags$span(class = "bmk-header-brand", bmk_config$brand),
    htmltools::tags$span(class = "bmk-header-sep", `aria-hidden` = "true", "·"),
    htmltools::tags$span(class = "bmk-header-tool", tool_name)
  )
}
