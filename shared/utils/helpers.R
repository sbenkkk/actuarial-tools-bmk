# ============================================================
# Actuarial Tools by BMK — Utilidades
# Archivo: helpers.R — pequeños helpers generales del framework
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Helpers puros, sin efectos secundarios, sin Shiny, sin lógica de negocio. Solo
# se incluye lo transversal y demostrablemente general (regla 4: no generalizar
# por anticipación). El operador `%||%` NO vive aquí: ya está definido en
# theme_bmk.R (Fase 2 congelada) y no se duplica.

#' Comprueba si un valor está "en blanco"
#'
#' Considera en blanco: `NULL`, longitud cero, `NA` o cadena de solo espacios.
#' Existe en shared porque es una comprobación de UI/flujo transversal (defaults,
#' inputs vacíos) que usarán muchas herramientas; no es lógica de ninguna tool.
#' @param x Valor a comprobar (`NULL` o vector atómico).
#' @return `TRUE`/`FALSE` único si `x` es `NULL` o de longitud cero; en otro caso,
#'   un `logical` por elemento.
#' @examples
#' bmk_is_blank(NULL)          # TRUE
#' bmk_is_blank("   ")         # TRUE
#' bmk_is_blank(c("a", NA, "")) # FALSE TRUE TRUE
bmk_is_blank <- function(x) {
  if (is.null(x) || length(x) == 0L) return(TRUE)
  blank <- is.na(x)
  if (is.character(x)) blank <- blank | trimws(x) == ""
  blank
}

#' Convierte un texto a slug en formato kebab-case
#'
#' Normaliza a minúsculas ASCII y une con guiones. Existe en shared porque
#' codifica la convención de nombres del proyecto (apartado 9.1: slugs de
#' herramienta en kebab-case) y es útil para nombres de archivo coherentes; no
#' pertenece a ninguna herramienta.
#' @param x Vector de texto a convertir.
#' @return `character` con el slug; `NA` se propaga.
#' @examples
#' bmk_slugify("Estimación de Densidades")  # "estimacion-de-densidades"
#' bmk_slugify("Bootstrap  MSE!")           # "bootstrap-mse"
bmk_slugify <- function(x) {
  x <- as.character(x)
  x <- iconv(x, to = "ASCII//TRANSLIT")
  x <- tolower(x)
  x <- gsub("[^a-z0-9]+", "-", x)
  gsub("^-+|-+$", "", x)
}
