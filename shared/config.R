# ============================================================
# Actuarial Tools by BMK — Configuración global
# Archivo: config.R — constantes compartidas por todo el proyecto
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Punto único para las constantes de proyecto (marca, textos legales y futuras
# constantes compartidas). No contiene lógica ni funciones: es configuración.
# Se carga antes que los componentes, que la consumen (bmk_config$...).
# Centralizar aquí evita que estos valores queden dispersos dentro de la UI y
# garantiza que sean idénticos y editables en un único lugar para las 40
# herramientas.

bmk_config <- list(

  # Nombre de la serie (header y footer).
  brand = "Actuarial Tools by BMK",

  # Aviso de privacidad (apartado 4.3). Debe ser cierto en la implementación.
  privacy_notice = paste(
    "Los datos que carga se procesan en su navegador durante la sesión;",
    "no se almacenan ni se envían a servidores externos."
  ),

  # Disclaimer de uso (apartado 4.3).
  use_disclaimer = paste(
    "Herramienta de apoyo al análisis. Los resultados no constituyen",
    "asesoramiento actuarial certificado."
  ),

  # Límites de datos de entrada (apartado 7.5), en un único lugar.
  # Tamaño de archivo en MB (los bytes se derivan debajo); número de filas.
  max_file_mb = 10L,
  max_rows    = 100000L,

  # Parámetro de validación (apartado 7.4): proporción máxima de NA admitida por
  # columna obligatoria antes de marcar "exceso de valores ausentes". La
  # arquitectura no fija valor; default conservador (más de la mitad = error).
  max_na_prop = 0.5
)

# Constante derivada: tamaño máximo en bytes (usado por load_shared.R para
# configurar shiny.maxRequestSize y por mod_data_input para verificar el archivo).
bmk_config$max_file_bytes <- bmk_config$max_file_mb * 1024L^2
