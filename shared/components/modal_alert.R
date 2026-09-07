# ============================================================
# Actuarial Tools by BMK — Componentes
# Archivo: modal_alert.R — aviso modal bloqueante
# Autor: BMK — Última actualización: 2026-08-04
# ============================================================
#
# Función de UI (catálogo 7.2), añadida por ADR-022. Wrapper de
# `shiny::modalDialog` con los mismos tres estados que `notify.R` (info, warning,
# error). Se usa cuando el usuario DEBE enterarse de una condición que impide
# continuar —p. ej. un CSV sin ninguna columna numérica—: `bmk_notify()` emite un
# aviso flotante que puede pasar desapercibido y deja la interfaz en un estado
# ambiguo; el modal bloquea e informa. Para avisos no bloqueantes (informativos o
# de advertencia sobre datos que sí se pueden usar) se sigue usando `bmk_notify()`.
#
# No mantiene estado reactivo: es una función, no un módulo (regla 5). Sin
# estilos inline: el color por estado y el layout viven en styles.css
# (.bmk-modal*), coherente con la decisión 13.

# Configuración por estado: icono bsicons (outline) y rol ARIA. El error usa
# role="alertdialog" (interrumpe al lector de pantalla); info y warning usan
# role="dialog". El color por estado lo aplica el CSS según la clase
# .bmk-modal-<type>.
.BMK_MODAL_CFG <- list(
  info    = list(icon = "info-circle",          role = "dialog"),
  warning = list(icon = "exclamation-triangle", role = "dialog"),
  error   = list(icon = "x-circle",             role = "alertdialog")
)

#' Construir un aviso modal con estilo de marca
#'
#' Devuelve el `modalDialog`; no lo muestra. Úsese con `shiny::showModal()`, o
#' directamente con `bmk_show_modal_alert()`.
#'
#' @param title    Título del aviso (frase corta, sin punto final).
#' @param message  Mensaje principal, orientado a la acción. Texto o etiqueta.
#' @param type     Estado: "info", "warning" o "error".
#' @param details  Contenido adicional opcional (etiquetas HTML: listas, tablas).
#'   Se muestra bajo el mensaje, en tipografía auxiliar.
#' @param footer   Contenido del pie. Por defecto, un único botón de cierre.
#' @param easy_close Si TRUE, se cierra pulsando fuera o con Esc. Por defecto
#'   FALSE en "error" (obliga a un cierre explícito) y TRUE en el resto.
#' @param size     Tamaño del modal: "s", "m" (defecto) o "l".
#' @return Un objeto `shiny::modalDialog`.
bmk_modal_alert <- function(title, message, type = c("info", "warning", "error"),
                            details = NULL, footer = NULL, easy_close = NULL,
                            size = c("m", "s", "l")) {
  type <- match.arg(type)
  size <- match.arg(size)
  cfg  <- .BMK_MODAL_CFG[[type]]
  if (is.null(easy_close)) easy_close <- !identical(type, "error")
  if (is.null(footer)) {
    footer <- shiny::modalButton("Entendido")
  }

  shiny::modalDialog(
    title = htmltools::tags$div(
      class = paste0("bmk-modal-title bmk-modal-", type),
      htmltools::tags$span(
        class = "bmk-modal-icon",
        bsicons::bs_icon(cfg$icon, a11y = "deco")
      ),
      htmltools::tags$span(title)
    ),
    htmltools::tags$div(
      class = "bmk-modal-body",
      role  = cfg$role,
      htmltools::tags$p(class = "bmk-modal-message", message),
      if (!is.null(details)) htmltools::tags$div(class = "bmk-modal-details", details)
    ),
    footer     = footer,
    easyClose  = easy_close,
    size       = size,
    fade       = TRUE
  )
}

#' Mostrar directamente un aviso modal de marca
#'
#' Atajo de `shiny::showModal(bmk_modal_alert(...))`. Acepta los mismos
#' argumentos que `bmk_modal_alert()`.
#'
#' @inheritParams bmk_modal_alert
#' @return (Invisible) NULL.
bmk_show_modal_alert <- function(...) {
  shiny::showModal(bmk_modal_alert(...))
  invisible(NULL)
}
