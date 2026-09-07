# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b2_muestra_comun.R
# Tests N1-N9 de ADR-026 (muestra común comparable), ADR-027 (guardas del
# optimizador) y ADR-028 (coherencia de muestra en el Visual Engine).
# Dataset sintético con masa de probabilidad en cero (80 %), el patrón que
# destapó los hallazgos H1/H2/H3 con datos reales de siniestralidad.
# Autor: BMK — Última actualización: 2026-08-09
# ============================================================
#
#   Rscript tests/b2_muestra_comun.R   # desde la raíz de la herramienta
#   Rscript b2_muestra_comun.R         # desde la carpeta tests/

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

cat("== MUESTRA COMÚN (ADR-026/027/028) — distribution-fitting ==\n")

# ------------------------------------------------------------
# Datasets
# ------------------------------------------------------------
# Continuo con átomo en cero: 800 ceros + 200 severidades lognormales. Es el
# patrón de `Cost_claims_year` (81,5 % de pólizas sin siniestro). Los positivos
# se redondean a céntimos, igual que un importe real: eso fija la resolución del
# dato que consume la guarda (B) de ADR-027.
set.seed(20260809)
xz <- c(rep(0, 800), round(stats::rlnorm(200, meanlog = 5.7, sdlog = 1.3), 2))
# Discreta: recuentos con ceros legítimos (aquí el 0 SÍ debe conservarse).
xd <- c(0, 1, 0, 2, 1, 3, 0, 1, 2, 4, 1, 0, 2, 1, 5)

dz <- data.frame(coste = xz)
res <- dist_fit_analyze(dz, "coste")
fits <- res$motor$fits

# ------------------------------------------------------------
# N1. Mismo n_used en las 7 candidatas
# ------------------------------------------------------------
cat("\n-- N1. Muestra idéntica en todas las candidatas --\n")
n_used <- vapply(fits, function(f) as.integer(f$n_used), integer(1))
check(length(unique(n_used)) == 1L, "N1: las 7 candidatas comparten un único n_used")
check(unname(n_used[1]) == 200L,    "N1: n_used = 200 (solo las observaciones positivas)")
check(length(fits) == 7L,           "N1: se ofrecen las 7 candidatas continuas")

# ------------------------------------------------------------
# N2. Exclusión global cuantificada
# ------------------------------------------------------------
cat("\n-- N2. Bloque analysis$sample --\n")
s <- res$sample
check(s$n_input == 1000L,              "N2: n_input = 1000 observaciones válidas")
check(s$n_used == 200L,                "N2: n_used = 200 tras el soporte común")
check(s$n_excluded_zeros == 800L,      "N2: 800 ceros excluidos y cuantificados")
check(s$n_excluded_negatives == 0L,    "N2: sin negativos que excluir")
check(isTRUE(s$requires_positive),     "N2: la intersección de soportes exige x > 0")
check(identical(s$support_label, "(0, Inf)"), "N2: soporte común declarado")
check(is.finite(s$resolution),         "N2: resolución empírica calculada (guarda B)")

# ------------------------------------------------------------
# N3. Comunicación al usuario: un único aviso
# ------------------------------------------------------------
cat("\n-- N3. Aviso único y summary honesto --\n")
w <- res$text_builder$warnings
n_avisos_cero <- sum(grepl("cero", w, fixed = TRUE))
check(n_avisos_cero == 1L,
      "N3: la exclusión de ceros se comunica UNA sola vez (antes: uno por distribución)")
check(any(grepl("800", w, fixed = TRUE)),
      "N3: el aviso cuantifica las observaciones excluidas")
check(any(grepl("CONDICIONADA", w, fixed = TRUE)),
      "N3: el aviso declara que se modeliza severidad condicionada")
check(grepl("200", res$text_builder$summary, fixed = TRUE),
      "N3: el summary declara la muestra realmente modelizada (200)")

# ------------------------------------------------------------
# N4. AIC/BIC comparables
# ------------------------------------------------------------
cat("\n-- N4. Criterios de información comparables --\n")
pf   <- res$diagnostics$per_fit
conv <- Filter(function(d) isTRUE(d$converged), pf)
aics <- vapply(conv, function(d) d$information$aic, numeric(1))
check(all(is.finite(aics)),                "N4: todos los AIC son finitos")
check(all(aics > 0),                       "N4: ningún AIC absurdamente negativo")
check(diff(range(aics)) < 1e5,             "N4: el rango de AIC es del orden esperado")
check(length(unique(vapply(conv, function(d) as.integer(d$n_used), integer(1)))) == 1L,
      "N4: todos los criterios se han calculado sobre el mismo n")

# ------------------------------------------------------------
# N5. Pareto/Lomax finita y no degenerada (H1)
# ------------------------------------------------------------
cat("\n-- N5. Pareto/Lomax sana --\n")
pa <- fits$pareto
check(isTRUE(pa$converged),                       "N5: Pareto converge")
check(pa$params$scale > .Machine$double.xmin,     "N5: scale fuera del rango subnormal")
check(pa$params$scale > 1e-6,                     "N5: scale con magnitud interpretable")
check(is.finite(pa$logLik) && pa$logLik < 0,      "N5: logLik finita y negativa")
check(abs(pf$pareto$information$aic / pf$lognormal$information$aic) < 2,
      "N5: el AIC de Pareto es del mismo orden que el de Lognormal")

# ------------------------------------------------------------
# N6. La familia discreta conserva los ceros
# ------------------------------------------------------------
cat("\n-- N6. Discreta intacta --\n")
rd <- dist_fit_analyze(data.frame(recuento = xd), "recuento")
check(rd$sample$n_used == length(xd),     "N6: la muestra discreta conserva las 15 observaciones")
check(rd$sample$n_excluded_zeros == 0L,   "N6: los ceros NO se excluyen en recuentos")
check(!isTRUE(rd$sample$requires_positive),
      "N6: la intersección de soportes discretos admite el 0")
check(!any(grepl("cero", rd$text_builder$warnings, fixed = TRUE)),
      "N6: no se emite aviso de exclusión de ceros en la familia discreta")

# ------------------------------------------------------------
# N7. Visual Engine sobre la misma muestra (ADR-028)
# ------------------------------------------------------------
cat("\n-- N7. Visual Engine coherente --\n")
vd <- build_visual_data(res, dz)
hd <- vd$histogram_density$histogram
check(sum(hd$count) == res$sample$n_used,
      "N7: el histograma cuenta exactamente las observaciones de la muestra común")
area <- sum(hd$density * (hd$bin_end - hd$bin_start))
check(abs(area - 1) < 1e-8,               "N7: el histograma integra a 1 sobre la muestra común")
gx <- vd$histogram_density$kde$curve$x
check(abs(min(gx) - min(res$sample$x)) < 1e-9 && abs(max(gx) - max(res$sample$x)) < 1e-9,
      "N7: la rejilla de KDE y curvas cubre exactamente el rango de la muestra común")
check(abs(min(hd$bin_start) - min(res$sample$x)) < 1e-9,
      "N7: el histograma NO arranca en 0 (los ceros no forman parte del análisis)")
check(nrow(vd$qq_plot$points) == res$sample$n_used,
      "N7: el QQ-plot usa la muestra común")
check(nrow(vd$pp_plot$points) == res$sample$n_used,
      "N7: el PP-plot usa la muestra común")
# Escala comparable: el máximo de la curva ajustada recomendada y el de la KDE
# deben estar en el mismo orden de magnitud. Antes de ADR-028 diferían en un
# factor 1/P(X>0) porque el histograma/KDE eran incondicionales y las curvas no.
rec_id  <- res$assessment$recommendation$level1$id
cur_rec <- Filter(function(c) identical(c$id, rec_id), vd$histogram_density$curves)[[1]]
ratio   <- max(cur_rec$curve$density, na.rm = TRUE) /
  max(vd$histogram_density$kde$curve$density, na.rm = TRUE)
check(is.finite(ratio) && ratio > 0.2 && ratio < 5,
      sprintf("N7: curva ajustada y KDE en la misma escala (ratio = %.2f)", ratio))

# ------------------------------------------------------------
# N8. Invariante del Assessment
# ------------------------------------------------------------
cat("\n-- N8. Invariante de comparabilidad --\n")
check(length(res$assessment$ranking) >= 2L, "N8: hay ranking sobre el que comprobar")
pb <- vapply(res$assessment$ranking, function(e) e$pillar_scores$B, numeric(1))
check(diff(range(pb)) > 50,
      "N8: el pilar B recupera rango útil (antes quedaba comprimido por la Pareto degenerada)")
check(is.finite(res$assessment$recommendation$level1$delta_aic),
      "N8: ΔAIC finito y de magnitud interpretable")
check(abs(res$assessment$recommendation$level1$delta_aic) < 1e5,
      "N8: ΔAIC ya no es de orden 1e8")

# ------------------------------------------------------------
# N9. Una sola invocación del filtro de soporte
# ------------------------------------------------------------
cat("\n-- N9. Sin copias de la lógica de filtrado --\n")
src <- readLines(file.path(.tool_root, "R", "calc.R"), warn = FALSE)
codigo <- src[!grepl("^\\s*#", src)]                       # descarta comentarios
llamadas <- grep(".prepare_support(", codigo, fixed = TRUE, value = TRUE)
llamadas <- llamadas[!grepl("<- function", llamadas, fixed = TRUE)]  # descarta la definición
check(length(llamadas) == 1L,
      sprintf("N9: `.prepare_support()` se invoca exactamente una vez (encontradas: %d)",
              length(llamadas)))

# ------------------------------------------------------------
# N10. Las guardas de ADR-027 no disparan sobre datos legítimos
# ------------------------------------------------------------
cat("\n-- N10. Ausencia de falsos positivos en las guardas --\n")
for (f in c("continua_lognormal.csv", "continua_gamma.csv", "continua_weibull.csv",
            "continua_pareto_cola_pesada.csv", "continua_exponencial.csv",
            "limite_casi_constante.csv", "limite_enteros_grandes.csv")) {
  ruta <- file.path(.tool_root, "data", "samples", f)
  if (!file.exists(ruta)) next
  d  <- utils::read.csv(ruta, stringsAsFactors = FALSE)
  nm <- names(d)[vapply(d, is.numeric, logical(1))][1]
  r  <- dist_fit_analyze(d[, nm, drop = FALSE], nm)
  degenerados <- Filter(function(e) grepl("no acotada|frontera numérica", e$reason),
                        r$assessment$excluded)
  check(length(degenerados) == 0L,
        sprintf("N10: %s no dispara ninguna guarda de ADR-027", f))
}

cat("\nTESTS DE MUESTRA COMÚN SUPERADOS\n")
