# ============================================================
# Actuarial Tools by BMK — Utilidades
# Archivo: formatters.R — formateo de valores para presentación
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Funciones PURAS de formateo. No dependen de Shiny ni de ninguna herramienta,
# no modifican sus argumentos y devuelven SIEMPRE character. Locale español por
# defecto (miles ".", decimal ","). Existen aquí porque el formateo es
# presentación transversal (apartado 2.2): las metric cards, tablas y cajas de
# interpretación de las 40 herramientas lo necesitan de forma idéntica; no
# pertenece a ninguna herramienta concreta.

#' Formatea un número (miles + decimales) devolviendo texto
#'
#' @param x Vector numérico (o coercible). No se modifica.
#' @param decimals Número de decimales.
#' @param big_mark Separador de miles.
#' @param decimal_mark Separador decimal.
#' @param na_text Texto para los valores `NA`.
#' @return `character` de la misma longitud que `x`.
#' @examples
#' bmk_format_number(1234567.5, decimals = 2)   # "1.234.567,50"
#' bmk_format_number(c(10, NA), na_text = "s/d")
bmk_format_number <- function(x, decimals = 0, big_mark = ".",
                              decimal_mark = ",", na_text = "—") {
  fx <- .bmk_fmt(x, decimals, big_mark, decimal_mark)
  ifelse(is.na(fx), na_text, fx)
}

#' Formatea una proporción (0-1) como porcentaje
#'
#' @param x Vector numérico en escala 0-1 (una proporción). No se modifica.
#' @param decimals Número de decimales.
#' @param decimal_mark Separador decimal.
#' @param na_text Texto para los valores `NA`.
#' @return `character` de la misma longitud que `x`, con sufijo " %".
#' @examples
#' bmk_format_percent(0.2537)          # "25,4 %"
#' bmk_format_percent(c(0.5, NA))
bmk_format_percent <- function(x, decimals = 1, decimal_mark = ",",
                               na_text = "—") {
  fx <- .bmk_fmt(x * 100, decimals, "", decimal_mark)
  ifelse(is.na(fx), na_text, paste0(fx, " %"))
}

#' Formatea un importe monetario (símbolo sufijo, estilo España)
#'
#' @param x Vector numérico (o coercible). No se modifica.
#' @param symbol Símbolo de la moneda (sufijo).
#' @param decimals Número de decimales.
#' @param big_mark Separador de miles.
#' @param decimal_mark Separador decimal.
#' @param na_text Texto para los valores `NA`.
#' @return `character` de la misma longitud que `x`.
#' @examples
#' bmk_format_currency(1234.5)             # "1.234,50 €"
#' bmk_format_currency(99, symbol = "$")
bmk_format_currency <- function(x, symbol = "€", decimals = 2, big_mark = ".",
                                decimal_mark = ",", na_text = "—") {
  fx <- .bmk_fmt(x, decimals, big_mark, decimal_mark)
  ifelse(is.na(fx), na_text, paste0(fx, " ", symbol))
}

# --- Helper interno de formateo -----------------------------------------------

#' Núcleo de formateo numérico compartido por los formatters
#'
#' Coerce a numérico, formatea con separadores y devuelve `NA_character_` en las
#' posiciones ausentes (cada formatter aplica luego su propio `na_text`). Evita
#' duplicar la lógica de formateo entre las funciones públicas.
#' @param x Vector a formatear.
#' @param decimals Decimales.
#' @param big_mark Separador de miles.
#' @param decimal_mark Separador decimal.
#' @return `character`; `NA_character_` donde `x` es `NA`.
.bmk_fmt <- function(x, decimals, big_mark, decimal_mark) {
  x <- suppressWarnings(as.numeric(x))
  out <- formatC(x, format = "f", digits = decimals,
                 big.mark = big_mark, decimal.mark = decimal_mark)
  out[is.na(x)] <- NA_character_
  out
}
