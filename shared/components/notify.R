# ============================================================
# Actuarial Tools by BMK — Componentes
# Archivo: notify.R — notificaciones de sistema
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Función de UI (catálogo 7.2). Wrapper de shiny::showNotification con tres
# estados: info, warning, error. Es el ÚNICO lugar del proyecto donde se usan los
# colores éxito/alerta/error de la paleta (decisión 13). No mantiene estado
# reactivo: es una función, no un módulo (regla 5). Sin estilos inline: el color
# por estado y el layout viven en styles.css (.bmk-notification*).

# Configuración por estado: icono bsicons (outline), duración por defecto en
# segundos y rol ARIA. El error es persistente (NULL) para dar tiempo a leerlo y
# usa role="alert" (interrumpe al lector de pantalla); info/warning usan
# role="status" (no interrumpen). El color por estado lo aplica el CSS según la
# clase .bmk-notification-<type>.
.BMK_NOTIFY_CFG <- list(
  info    = list(icon = "info-circle",          duration = 5,    role = "status"),
  warning = list(icon = "exclamation-triangle", duration = 7,    role = "status"),
  error   = list(icon = "x-circle",             duration = NULL, role = "alert")
)

#' Emitir una notificación de sistema con estilo de marca
#'
#' @param message  Mensaje a mostrar (texto claro, orientado a la acción).
#' @param type     Estado: "info", "warning" o "error".
#' @param duration Duración en segundos. Si se omite, usa la del estado (el error
#'   es persistente). Pase NULL para forzar persistencia.
#' @param id       Identificador opcional para reemplazar/cerrar la notificación.
#' @return (Invisible) el id de la notificación, como shiny::showNotification.
bmk_notify <- function(message, type = c("info", "warning", "error"),
                       duration, id = NULL) {
  type <- match.arg(type)
  cfg  <- .BMK_NOTIFY_CFG[[type]]
  if (missing(duration)) duration <- cfg$duration

  ui <- htmltools::tags$div(
    class = paste0("bmk-notification bmk-notification-", type),
    role = cfg$role,
    htmltools::tags$span(
      class = "bmk-notification-icon",
      bsicons::bs_icon(cfg$icon, a11y = "deco")
    ),
    htmltools::tags$span(message)
  )

  shiny::showNotification(
    ui = ui, duration = duration, id = id, type = "default", closeButton = TRUE
  )
}
