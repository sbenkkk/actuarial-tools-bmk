# ============================================================
# Actuarial Tools by BMK — Componentes
# Archivo: ui_metric_card.R — tarjeta de KPI
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Función pura de UI (catálogo 7.2). Patrón fijo (apartado 3.5): label pequeño
# arriba, número grande en el centro, nota auxiliar opcional debajo. El formateo
# del valor (separadores, decimales, símbolo) es responsabilidad de la herramienta.

#' Tarjeta de métrica (KPI)
#'
#' @param label Etiqueta descriptiva del indicador.
#' @param value Valor ya formateado (character o numeric).
#' @param note  Nota auxiliar opcional bajo el valor (unidad, contexto).
#' @return Tag `div` de htmltools con clase `.bmk-metric-card`.
bmk_metric_card <- function(label, value, note = NULL) {
  htmltools::tags$div(
    class = "bmk-metric-card",
    role = "group",
    `aria-label` = label,
    htmltools::tags$div(class = "bmk-metric-label", label),
    htmltools::tags$div(class = "bmk-metric-value", value),
    if (!is.null(note)) htmltools::tags$div(class = "bmk-metric-note", note)
  )
}
