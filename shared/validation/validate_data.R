# ============================================================
# Actuarial Tools by BMK — Validación compartida
# Archivo: validate_data.R — define bmk_validate_data()
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Función PURA de validación de datos de entrada (apartado 7.4). No depende de
# Shiny (regla 7): puede ejecutarse con source() sin Shiny cargado. Nunca emite
# notificaciones ni interactúa con la interfaz; solo devuelve el veredicto. La
# comunicación del error corresponde a mod_data_input mediante bmk_notify().
#
# La validación del tamaño de archivo NO es competencia de esta función (queda en
# mod_data_input, apartado 7.5). Aquí sí se aplica el límite de FILAS.
#
# Depende de: bmk_config (shared/config), para el límite de filas y el umbral de NA.

#' Validar el dataset de entrada de una herramienta
#'
#' Comprueba, sin modificar los datos, que un `data.frame` cumple el contrato de
#' la herramienta. Acumula todos los errores detectados en una sola pasada.
#'
#' Casos cubiertos (apartado 7.4): dataset vacío, columnas obligatorias ausentes,
#' nombres de columna incorrectos (se listan las disponibles), tipos de datos
#' erróneos, exceso de valores ausentes y superación del límite de filas.
#'
#' @param data `data.frame` ya cargado en memoria.
#' @param contract Contrato de columnas esperado. Admite tres formas:
#'   \itemize{
#'     \item `NULL`: solo comprobaciones estructurales (vacío y límite de filas).
#'     \item Vector de nombres, p. ej. `c("loss_amount")`: columnas obligatorias,
#'       sin comprobación de tipo.
#'     \item Vector/lista con tipos, p. ej. `c(loss_amount = "numeric")`: columnas
#'       obligatorias con tipo esperado. Tipos admitidos: "numeric", "double",
#'       "integer", "character", "logical", "factor", "Date".
#'   }
#' @return `list(valid, data, errors)`:
#'   \itemize{
#'     \item `valid` (logical): TRUE si el dataset cumple el contrato.
#'     \item `data` (data.frame): el mismo `data.frame` recibido, sin modificar.
#'     \item `errors` (character): mensajes en español orientados al usuario
#'       final, ya redactados para mostrarse tal cual. Están diseñados para ser
#'       consumidos por `bmk_notify()` desde `mod_data_input` (esta función no
#'       notifica). Vector vacío si `valid` es TRUE.
#'   }
#' @examples
#' bmk_validate_data(data.frame(loss_amount = c(1, 2, 3)),
#'                   contract = c(loss_amount = "numeric"))
bmk_validate_data <- function(data, contract = NULL) {
  # Guarda defensiva: la entrada debe ser un data.frame.
  if (!is.data.frame(data)) {
    return(list(valid = FALSE, data = data,
                errors = "La entrada no es un data.frame."))
  }

  errors <- character(0)
  n_rows <- nrow(data)

  # --- Comprobaciones estructurales ------------------------------------------
  if (n_rows == 0L) {
    errors <- c(errors, "El conjunto de datos está vacío (0 filas).")
  }
  max_rows <- bmk_config$max_rows
  if (n_rows > max_rows) {
    errors <- c(errors, sprintf(
      "El conjunto de datos supera el límite de %s filas (tiene %s).",
      format(max_rows, big.mark = "."), format(n_rows, big.mark = ".")
    ))
  }

  # --- Comprobaciones de contrato de columnas --------------------------------
  spec <- .bmk_normalize_contract(contract)
  if (!is.null(spec)) {
    required <- names(spec)
    missing  <- setdiff(required, names(data))
    if (length(missing) > 0L) {
      errors <- c(errors, sprintf(
        "Faltan columnas obligatorias: %s. Columnas disponibles: %s.",
        paste(missing, collapse = ", "),
        paste(names(data), collapse = ", ")
      ))
    }

    # Tipo y NA solo sobre columnas obligatorias presentes y con al menos una
    # fila (sobre 0 filas estas comprobaciones no tienen sentido y el error de
    # "dataset vacío" ya se ha registrado más arriba).
    if (n_rows > 0L) {
      for (col in intersect(required, names(data))) {
        expected_type <- spec[[col]]
        if (!.bmk_type_ok(data[[col]], expected_type)) {
          errors <- c(errors, sprintf(
            "La columna '%s' debería ser de tipo %s.", col, expected_type
          ))
        }
        na_prop <- mean(is.na(data[[col]]))
        if (na_prop > bmk_config$max_na_prop) {
          errors <- c(errors, sprintf(
            "La columna '%s' tiene demasiados valores ausentes (%.0f%% NA).",
            col, 100 * na_prop
          ))
        }
      }
    }
  }

  list(valid = length(errors) == 0L, data = data, errors = errors)
}

# --- Helpers internos ---------------------------------------------------------

#' Normaliza el contrato a un vector nombrado columna -> tipo esperado
#'
#' Unifica las tres formas admitidas en un único vector de caracteres con nombres
#' (las columnas) y valores (el tipo, o `NA` para "cualquier tipo").
#' @param contract Contrato en cualquiera de las formas admitidas, o `NULL`.
#' @return Vector de caracteres nombrado, o `NULL` si no hay contrato.
.bmk_normalize_contract <- function(contract) {
  if (is.null(contract) || length(contract) == 0L) return(NULL)

  if (is.list(contract)) {
    vals <- vapply(contract, function(v) as.character(v)[1], character(1))
    return(stats::setNames(vals, names(contract)))
  }
  if (is.character(contract)) {
    # Sin nombres: los elementos son las columnas obligatorias, sin tipo.
    if (is.null(names(contract))) {
      return(stats::setNames(rep(NA_character_, length(contract)), contract))
    }
    # Con nombres: ya es columna -> tipo.
    return(contract)
  }
  NULL
}

#' Comprueba si un vector cumple el tipo esperado del contrato
#'
#' @param x Vector (columna del data.frame).
#' @param type Tipo esperado (character) o `NA` para no comprobar.
#' @return TRUE si el tipo es correcto o no debe comprobarse.
.bmk_type_ok <- function(x, type) {
  if (is.na(type)) return(TRUE)
  ok <- switch(
    type,
    numeric   = is.numeric(x),
    double    = is.double(x),
    integer   = is.integer(x),
    character = is.character(x),
    logical   = is.logical(x),
    factor    = is.factor(x),
    Date      = inherits(x, "Date"),
    TRUE  # tipo no reconocido: no se comprueba (contrato demasiado laxo)
  )
  isTRUE(ok)
}
