# ============================================================
# Actuarial Tools by BMK — Infraestructura compartida
# Archivo: load_shared.R — punto único de carga de shared/ (apartado 6.1)
# Autor: BMK — Última actualización: 2026-07-18
# ============================================================
#
# Único punto de entrada del código compartido: cada `app.R` hace
# `source(".../shared/load_shared.R")` y obtiene todo el framework cargado en el
# entorno global, en orden de dependencia. También fija la configuración global
# del framework (p. ej. el tamaño máximo de subida).
#
# No es un paquete de R (regla 1 del contrato técnico): carga por `source()`.

# --- Localización de este archivo (para resolver rutas relativas) -------------
# Se resuelve en tiempo de `source()`, cuando `ofile` está disponible.
.bmk_shared_dir <- local({
  dir <- NULL
  for (i in seq_len(sys.nframe())) {
    of <- sys.frame(i)$ofile
    if (!is.null(of)) dir <- dirname(of)
  }
  if (is.null(dir)) "." else normalizePath(dir)
})

# --- Carga en orden de dependencia --------------------------------------------
# 1) config: constantes globales (las consumen componentes y módulos).
# 2) theme: colors.R antes que theme_bmk.R (tokens y operador %||%).
# 3) resto de subcarpetas: el orden interno es indiferente porque R resuelve los
#    nombres en tiempo de ejecución, pero se cargan tras config y theme.
source(file.path(.bmk_shared_dir, "config.R"))

.bmk_source_dir <- function(subdir) {
  path <- file.path(.bmk_shared_dir, subdir)
  files <- list.files(path, pattern = "\\.R$", full.names = TRUE)
  for (f in sort(files)) source(f)
}

for (.bmk_sub in c("theme", "components", "modules", "validation", "utils", "actuarial")) {
  .bmk_source_dir(.bmk_sub)
}
rm(.bmk_sub)

# --- Configuración global del framework ---------------------------------------
# Tamaño máximo de subida (apartado 7.5). Se fija aquí, no en mod_data_input, para
# que sea una única inicialización global (config leída arriba).
options(shiny.maxRequestSize = bmk_config$max_file_bytes)
