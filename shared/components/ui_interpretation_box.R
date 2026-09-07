# ============================================================
# Actuarial Tools by BMK — Componentes
# Archivo: ui_interpretation_box.R — caja de interpretación en lenguaje natural
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Función pura de UI (catálogo 7.2). Elemento diferencial del proyecto (apartado
# 4.2): traduce el resultado técnico a lenguaje comprensible. El texto lo compone
# cada herramienta (típicamente con glue()); este componente solo le da estilo.

#' Caja de interpretación
#'
#' @param content Texto o tags a mostrar. Si es character, se muestra como texto
#'   (escapado). Para contenido con formato, pase tags de htmltools.
#' @param title   Título de la caja. NULL para ocultarlo.
#' @return Tag `div` de htmltools con clase `.bmk-interpretation`.
bmk_interpretation_box <- function(content, title = "Interpretación") {
  htmltools::tags$div(
    class = "bmk-interpretation",
    role = "note",
    `aria-label` = title %||% "Interpretación",
    if (!is.null(title)) {
      htmltools::tags$div(
        class = "bmk-interpretation-title",
        bsicons::bs_icon("info-circle", a11y = "deco"), " ", title
      )
    },
    htmltools::tags$div(content)
  )
}
