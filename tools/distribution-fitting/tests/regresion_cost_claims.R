# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/regresion_cost_claims.R
# Regresión con datos REALES de siniestralidad de automóvil.
#
# Motivo de su existencia: este dataset destapó tres defectos (H1 verosimilitud
# no acotada de Lomax con átomo en cero, H2 comparación entre muestras distintas,
# H3 escalas incompatibles en el gráfico) que 24 ficheros sintéticos no
# encontraron. Se conserva reducido y versionado para que no vuelvan a colarse.
#
# Fichero: data/samples/real_cost_claims_reducido.csv
#   Muestreo sistemático determinista (1 de cada 19) del original de 95.554
#   filas; conserva la proporción de ceros (81,7 % frente al 81,5 % original).
#   Sin RNG: reproducible byte a byte.
#
# Referencias calculadas con una réplica INDEPENDIENTE del motor en Python /
# NumPy / SciPy, no con esta implementación.
# Autor: BMK — Última actualización: 2026-08-09
# ============================================================
#
#   Rscript tests/regresion_cost_claims.R   # desde la raíz de la herramienta
#   Rscript regresion_cost_claims.R         # desde la carpeta tests/

.locate_script <- function() {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    return(normalizePath(sub("^--file=", "", file_arg[1]), mustWork = FALSE))
  }
  for (i in rev(seq_len(sys.nframe()))) {
    of <- sys.frame(i)$ofile
    if (!is.null(of)) return(normalizePath(of, mustWork = FALSE))
  }
  NULL
}
.tool_root <- local({
  s <- .locate_script()
  if (!is.null(s)) dirname(dirname(s))
  else if (file.exists("R/calc.R")) normalizePath(".")
  else if (file.exists(file.path("..", "R", "calc.R"))) normalizePath("..")
  else stop("No se pudo localizar la raíz de la herramienta.", call. = FALSE)
})
source(file.path(.tool_root, "R", "calc.R"))

check <- function(cond, msg) {
  if (!isTRUE(cond)) stop(sprintf("FALLO: %s", msg), call. = FALSE)
  cat(sprintf("  OK  - %s\n", msg))
}
rel <- function(actual, ref, reltol, msg) {
  ok <- is.finite(actual) && abs(actual - ref) <= reltol * abs(ref)
  check(ok, sprintf("%s  (%.6g ~ %.6g, rel<=%g)", msg, actual, ref, reltol))
}

cat("== REGRESIÓN CON DATOS REALES (Cost_claims_year) — distribution-fitting ==\n")

ruta <- file.path(.tool_root, "data", "samples", "real_cost_claims_reducido.csv")
check(file.exists(ruta), "fichero de regresión presente")
d <- utils::read.csv(ruta, stringsAsFactors = FALSE)
res <- dist_fit_analyze(d, "Cost_claims_year")

# ------------------------------------------------------------
# 1. Muestra común (ADR-026)
# ------------------------------------------------------------
cat("\n-- 1. Muestra común --\n")
s <- res$sample
check(s$n_input == 5030L,            "n_input = 5030 observaciones válidas")
check(s$n_excluded_zeros == 4111L,   "4111 ceros excluidos (81,7 %)")
check(s$n_used == 919L,              "n_used = 919 severidades positivas")
check(isTRUE(s$requires_positive),   "soporte común (0, Inf)")
n_used <- vapply(res$motor$fits, function(f) as.integer(f$n_used), integer(1))
check(all(n_used == 919L),           "las 7 candidatas se ajustan sobre las mismas 919")
check(res$motor$control_fits$normal$n_used == 919L,
      "el control Normal comparte la muestra de las candidatas")

# ------------------------------------------------------------
# 2. Pareto/Lomax: sana, no degenerada (ADR-027 + H1)
# ------------------------------------------------------------
# Sobre el dataset COMPLETO, con los ceros dentro, este ajuste devolvía
# scale = 4,94e-324 (menor subnormal IEEE-754), logLik = +5,73e7 y
# AIC = -114.612.053,32. Con la muestra común el MLE existe y es ordinario.
cat("\n-- 2. Pareto/Lomax --\n")
pa <- res$motor$fits$pareto
check(isTRUE(pa$converged),                    "Pareto converge")
check(pa$params$scale > .Machine$double.xmin,  "scale fuera del rango subnormal")
rel(pa$params$shape,  1.785157, 5e-3, "Pareto shape (alfa)")
rel(pa$params$scale,  599.538,  5e-3, "Pareto scale (lambda)")
rel(pa$logLik,       -6779.30,  1e-3, "Pareto logLik (finita y negativa)")
rel(res$diagnostics$per_fit$pareto$information$aic, 13562.61, 1e-3, "Pareto AIC")

# ------------------------------------------------------------
# 3. Criterios de información comparables (H2)
# ------------------------------------------------------------
cat("\n-- 3. AIC/BIC comparables --\n")
aic <- vapply(res$diagnostics$per_fit,
              function(x) if (isTRUE(x$converged)) x$information$aic else NA_real_,
              numeric(1))
check(all(is.finite(aic)),        "los 7 AIC son finitos")
check(all(aic > 0),               "ningún AIC negativo")
check(diff(range(aic)) < 1000,    "los 7 AIC caben en un rango de 1000 (misma muestra)")
rel(aic[["lognormal"]],   13478.55, 1e-3, "AIC lognormal")
rel(aic[["burr"]],        13350.51, 1e-3, "AIC burr (mejor por verosimilitud)")
rel(aic[["exponential"]], 14134.03, 1e-3, "AIC exponencial")
rel(res$diagnostics$control$normal$information$aic, 17301.97, 1e-3, "AIC del control Normal")

# ------------------------------------------------------------
# 4. Ranking y pilar B con rango útil
# ------------------------------------------------------------
cat("\n-- 4. Assessment --\n")
rk  <- res$assessment$ranking
by  <- function(id) Filter(function(e) e$id == id, rk)[[1]]
check(rk[[1]]$id == "lognormal",   "recomendada = lognormal")
check(rk[[2]]$id == "loglogistic", "segunda = loglogística")
rel(rk[[1]]$composite,           95.0, 0.02, "score lognormal")
rel(by("loglogistic")$composite, 91.4, 0.02, "score loglogística")
rel(by("burr")$composite,        85.1, 0.02, "score burr")
rel(by("pareto")$composite,      84.6, 0.02, "score pareto")
pb <- vapply(rk, function(e) e$pillar_scores$B, numeric(1))
check(abs(max(pb) - 100) < 1e-6 && abs(min(pb)) < 1e-6,
      "pilar B recupera el rango completo 0-100 (antes comprimido a ~0,8)")
check(!isTRUE(res$assessment$control_check$normal_better_than_best),
      "el control Normal no gana a la mejor candidata")

# ------------------------------------------------------------
# 5. ΔAIC de magnitud interpretable (H4 sigue abierto, sin tocar)
# ------------------------------------------------------------
# Nota: el ΔAIC sigue siendo NEGATIVO porque el compuesto recomienda lognormal
# mientras el mejor AIC es burr. Eso es el defecto conceptual H4 del criterio de
# confianza (ADR-021), pendiente de decisión separada. Lo que esta regresión
# blinda es que la MAGNITUD deje de ser absurda: de -1,15e8 a -128.
cat("\n-- 5. ΔAIC --\n")
lvl1 <- res$assessment$recommendation$level1
rel(lvl1$delta_aic, -128.04, 0.02, "ΔAIC de magnitud interpretable")
check(abs(lvl1$delta_aic) < 1000, "ΔAIC ya no es de orden 1e8")
check(identical(lvl1$confidence, "baja"),
      "confianza baja (H4 abierto: el compuesto y el AIC discrepan)")

# ------------------------------------------------------------
# 6. Comunicación (ADR-026) y Visual Engine (ADR-028)
# ------------------------------------------------------------
cat("\n-- 6. Comunicación y gráficos --\n")
w <- res$text_builder$warnings
check(sum(grepl("cero", w, fixed = TRUE)) == 1L, "un único aviso de exclusión de ceros")
check(any(grepl("4111", w, fixed = TRUE)),       "el aviso cuantifica los 4111 ceros")
check(grepl("919", res$text_builder$summary, fixed = TRUE),
      "el summary declara las 919 observaciones modelizadas, no las 5030")
vd <- build_visual_data(res, d)
check(sum(vd$histogram_density$histogram$count) == 919L,
      "el histograma se construye sobre las 919 observaciones de la muestra común")
check(nrow(vd$qq_plot$points) == 919L, "el QQ-plot usa la muestra común")

cat("\nREGRESIÓN CON DATOS REALES SUPERADA\n")
