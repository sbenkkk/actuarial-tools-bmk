# ============================================================
# Actuarial Tools by BMK — Design System
# Archivo: colors.R — tokens de color (fuente única de verdad de la paleta)
# Autor: BMK
# Última actualización: 2026-07-18
# ============================================================
#
# Este archivo NO contiene funciones: es el diccionario de color del proyecto.
# Cualquier color usado en la interfaz, los gráficos o el CSS procede de aquí.
# Los valores reproducen literalmente la paleta del apartado 3.1 de la
# arquitectura v1.1. No se añaden colores nuevos ni se improvisan tonos por
# herramienta.
#
# Debe cargarse antes que theme_bmk.R (es la base del sistema, catálogo 7.2).

# --- Paleta base (apartado 3.1) -----------------------------------------------
# Cada entrada es un rol semántico, no un color "suelto". El código de las
# herramientas referencia el rol (bmk_colors$primary), nunca el hex directo.
bmk_colors <- list(
  background     = "#F5F6F8",  # Fondo de la aplicación
  surface        = "#FFFFFF",  # Tarjetas, tablas, contenedores
  text           = "#1C1E21",  # Texto y títulos
  text_secondary = "#6B7280",  # Descripciones, labels
  border         = "#E5E7EB",  # Líneas y bordes de card
  primary        = "#0B3D91",  # Marca: header, botones primarios, enlaces
  accent         = "#3B82C4",  # Acento secundario: highlights, hover
  success        = "#2E7D57",  # Solo bmk_notify()
  warning        = "#B8860B",  # Solo bmk_notify()
  error          = "#B3261E"   # Solo bmk_notify()
)

# --- Tokens de superficie complementarios -------------------------------------
# Fondo de sidebar fijado por la arquitectura (apartado 3.5: gris muy claro).
bmk_colors$sidebar <- "#FAFAFA"
# Texto de contraste sobre superficies de marca (header, botón primario).
bmk_colors$on_primary <- "#FFFFFF"

# --- Tokens de hover (apartado 3.5: oscurecimiento del 8%) --------------------
# Valores precalculados (RGB x 0.92) en lugar de aplicar filtros CSS en tiempo de
# render: un estado hover explícito es predecible, testeable y coherente entre
# navegadores. Si se ajusta un color de marca, se recalcula aquí su hover.
bmk_colors$primary_hover <- "#0A3885"  # #0B3D91 oscurecido 8%
bmk_colors$error_hover   <- "#A5231C"  # #B3261E oscurecido 8%

# --- Tokens derivados para gráficos -------------------------------------------
# Regla de color (apartado 3.1): máximo 2 acentos activos; si un gráfico necesita
# más categorías se usa una escala secuencial de azules/grises, nunca multicolor.

# Grid de gráficos: un gris más claro que el borde de UI, para no competir con
# los datos. Deriva del rol de borde para mantener coherencia.
bmk_colors$grid <- "#EDEFF2"

# Escala SECUENCIAL de azules (para variables continuas / mapas de intensidad).
# Se genera por interpolación entre el azul de marca y un azul muy claro, de modo
# que un solo cambio en `primary`/`accent` reajusta toda la rampa.
bmk_colors$sequential <- grDevices::colorRampPalette(
  c(bmk_colors$primary, bmk_colors$accent, "#DCE7F5")
)(6)

# Escala CATEGÓRICA restringida (para series discretas). Prioriza los dos acentos
# de marca y completa con grises y azules apagados, evitando cualquier color
# ajeno a la identidad. Ordenada por prominencia visual descendente.
bmk_colors$categorical <- c(
  bmk_colors$primary,  # serie principal
  bmk_colors$accent,   # segunda serie
  "#6B7280",           # gris medio
  "#7FA6CE",           # azul apagado
  "#9AA3AE",           # gris azulado
  "#C3D2E6"            # azul muy claro
)
