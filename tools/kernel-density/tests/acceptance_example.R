# ============================================================
# Tool: kernel-density
# Archivo: tests/acceptance_example.R
# Escenario de ACEPTACIÓN (manual, no testthat) — fija el comportamiento
# esperado de la interfaz con el dataset de ejemplo. Test de regresión.
# Autor: BMK — Última actualización: 2026-07-19
# ============================================================
#
# Configuración POR DEFECTO (gaussian + silverman, niveles 0.95/0.99/0.995) sobre
# data/example_data.csv. Sin Shiny (prepare_view_model y calc.R son puros).
#
#   Rscript tests/acceptance_example.R        # desde tools/kernel-density/
#
# Estructura del test (por indicación de diseño):
#   A) INVARIANTES FUERTES  -> estructura y propiedades matemáticas (exacto/bool).
#   B) VALORES DE REFERENCIA -> numéricos con TOLERANCIAS explícitas (no igualdad
#      exacta, para no romper ante pequeños cambios de implementación).

source("../../shared/theme/colors.R")
source("../../shared/config.R")
source("../../shared/utils/formatters.R")
source("R/calc.R")
source("R/mod_tool.R")

check <- function(cond, msg) {
  if (!isTRUE(cond)) stop(sprintf("FALLO: %s", msg), call. = FALSE)
  cat(sprintf("  OK  - %s\n", msg))
}
within_tol <- function(actual, ref, tol, msg) {
  ok <- is.finite(actual) && abs(actual - ref) <= tol
  check(ok, sprintf("%s  (%.4f ~ %.4f +/- %.4f)", msg, actual, ref, tol))
}

df <- utils::read.csv("data/example_data.csv", stringsAsFactors = FALSE)
x  <- df$loss_amount
an <- kde_analyze(x, kernel = "gaussian", method = "silverman",
                  levels = c(0.95, 0.99, 0.995),
                  tool_version = "1.0.0", seed = 20260719L)
vm <- prepare_view_model(an, x, manifest = list(version = "1.0.0"))

# ============================================================
# A) INVARIANTES FUERTES (estructura + propiedades matemáticas)
# ============================================================
cat("== A) INVARIANTES FUERTES ==\n")

# --- Estructura del View Model ---
check(setequal(names(vm),
  c("cards","plots","tables","indicator","insights","downloads","metadata")),
  "View Model: 7 bloques")
check(length(vm$cards) == 4L, "cards: 4 tarjetas")
check(all(vapply(vm$cards, function(c)
  all(c("title","value","subtitle","icon","status") %in% names(c)), logical(1))),
  "cards: cada una expone title/value/subtitle/icon/status")

# --- Conteos exactos (deterministas por el dataset) ---
check(an$input$n_used == 500L, "n = 500")
check(an$diagnostics$stats$n_unique == 500L, "n_unique = 500")
check(an$diagnostics$outliers$count == 41L, "outliers (Tukey) = 41")
check(nrow(vm$tables$risk) == 3L, "tabla de riesgo: 3 niveles")
check(identical(vm$tables$risk$Nivel, c("95%","99%","99,5%")),
      "niveles: 95% / 99% / 99,5%")

# --- Propiedades matemáticas de las capas de los gráficos ---
d <- vm$plots$density; cc <- vm$plots$cdf
check(length(d$hist) == 500L, "densidad: histograma con 500 datos")
check(nrow(d$kde) == KDE_DEFAULTS$grid_n, "densidad: curva KDE con grid_n puntos")
check(all(d$kde$y >= -1e-12), "densidad: KDE no negativa")
check(nrow(d$var_kde) == 3L && nrow(d$var_empirical) == 3L,
      "densidad: 3 líneas VaR KDE y 3 VaR empírico")
check(all(diff(d$var_kde$x) > 0), "densidad: VaR KDE creciente en el nivel")

check(nrow(cc$cdf) == KDE_DEFAULTS$grid_n, "CDF: grid_n puntos")
check(all(diff(cc$cdf$y) >= -1e-9), "CDF: monótona no decreciente")
check(min(cc$cdf$y) >= -1e-9 && max(cc$cdf$y) <= 1 + 1e-9, "CDF: acotada en [0,1]")
check(identical(cc$var_kde$y, c(0.95, 0.99, 0.995)),
      "CDF: marcas VaR KDE en y = nivel de confianza (F(VaR)=p por construcción)")
check(all(cc$var_kde$x >= an$input$domain[1] & cc$var_kde$x <= an$input$domain[2] * 1.5),
      "CDF: VaR KDE dentro de un rango razonable del dominio")

# --- Descargas ---
check(nrow(vm$downloads$curve) == KDE_DEFAULTS$grid_n, "descarga curva: grid_n filas")
check(nrow(vm$downloads$risk) == 3L, "descarga riesgo: 3 filas")

# --- Metadata reproducible ---
check(vm$metadata$kernel == "gaussian" &&
      vm$metadata$bandwidth_method == "silverman" &&
      identical(vm$metadata$seed, 20260719L),
      "metadata: kernel / método / seed esperados")

# ============================================================
# B) VALORES DE REFERENCIA (con tolerancias explícitas)
# ============================================================
cat("== B) VALORES DE REFERENCIA (tolerancias) ==\n")

within_tol(an$bandwidth$h,               100.42,  0.50, "h (silverman)")
within_tol(an$diagnostics$stats$skewness,  3.60,  0.05, "asimetría")
within_tol(an$diagnostics$stats$kurtosis, 21.18,  0.20, "curtosis")
within_tol(an$diagnostics$stats$cv,        1.22,  0.02, "coef. variación")

vk <- an$estimation$var$var_kde; ve <- an$estimation$var$var_empirical
within_tol(vk[1], 2019.0, 1.0, "VaR KDE 95%")
within_tol(vk[2], 4200.4, 1.5, "VaR KDE 99%")
within_tol(vk[3], 4853.7, 1.5, "VaR KDE 99,5%")
within_tol(ve[1], 1964.7, 0.5, "VaR empírico 95%")
within_tol(ve[3], 4778.2, 0.5, "VaR empírico 99,5%")
within_tol(vm$plots$density$ymax, 0.001558, 1e-4, "densidad: ymax")

cat("\nESCENARIO DE ACEPTACIÓN SUPERADO\n")
