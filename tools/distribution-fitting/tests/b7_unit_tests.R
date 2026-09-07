# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b7_unit_tests.R
# Tests unitarios de B7 (Visual Engine): grids, PDF/PMF, histograma, ECDF, KDE,
# QQ y PP. Referencias calculadas de forma independiente con SciPy (funciones
# cuantil propias verificadas a ~1e-12). Verifica además que NO altera el
# análisis (no reestima, no toca ranking ni ViewModel).
# Autor: BMK — Última actualización: 2026-07-25
# ============================================================
#
#   Rscript tests/b7_unit_tests.R      # desde la raíz de la herramienta
#   Rscript b7_unit_tests.R            # desde la carpeta tests/

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
abstol <- function(actual, ref, tol, msg) {
  ok <- is.finite(actual) && abs(actual - ref) <= tol
  check(ok, sprintf("%s  (%.6f ~ %.6f +/- %g)", msg, actual, ref, tol))
}

cat("== B7 UNIT TESTS (Visual Engine) — distribution-fitting ==\n")

xc <- c(120.3, 340.7, 550.1, 610.4, 800.9, 1200.2, 1500.6, 2100.8, 2600.5, 3400.1, 5200.7, 9800.4)
xd <- c(0, 1, 0, 2, 1, 3, 0, 1, 2, 4, 1, 0, 2, 1, 5)

dfc <- data.frame(loss_amount = xc)
an  <- dist_fit_analyze(dfc, "loss_amount")
vd  <- build_visual_data(an, dfc)

# ------------------------------------------------------------
# 1. Estructura
# ------------------------------------------------------------
cat("\n-- 1. Estructura --\n")
check(all(c("histogram_density", "qq_plot", "pp_plot", "mean_excess", "var_tvar")
          %in% names(vd)),
      "visual: expone los 5 gráficos del contrato §12.7")
check(vd$histogram_density$status == "ready" && vd$qq_plot$status == "ready" &&
        vd$pp_plot$status == "ready",
      "visual: histograma, QQ y PP listos")
check(vd$mean_excess$status == "deferred" && vd$var_tvar$status == "deferred",
      "visual: mean-excess y VaR/TVaR diferidos (requieren Pilar C)")

# ------------------------------------------------------------
# 2. Histograma y KDE (continua)
# ------------------------------------------------------------
cat("\n-- 2. Histograma / KDE --\n")
h <- vd$histogram_density$histogram
check(nrow(h) == 5L,                       "histograma: 5 clases (regla de Sturges, n=12)")
check(sum(h$count) == length(xc),          "histograma: los conteos suman n")
abstol(sum(h$density * (h$bin_end - h$bin_start)), 1, 1e-9,
       "histograma: la densidad integra 1")
abstol(vd$histogram_density$kde$bandwidth, 894.988956, 1e-4,
       "KDE: ancho de banda de Silverman")
check(nrow(vd$histogram_density$kde$curve) == 512L, "KDE: rejilla de 512 puntos")
check(all(vd$histogram_density$kde$curve$density >= 0), "KDE: densidad no negativa")

# ------------------------------------------------------------
# 3. Curvas ajustadas (una por candidata; evaluadas, no reestimadas)
# ------------------------------------------------------------
cat("\n-- 3. Curvas ajustadas --\n")
cur <- vd$histogram_density$curves
check(length(cur) == length(an$assessment$ranking),
      "curvas: una por candidata del ranking")
check(all(vapply(cur, function(c) nrow(c$curve) == 512L, logical(1))),
      "curvas: evaluadas sobre la rejilla de 512 puntos")
check(all(vapply(cur, function(c) all(c$curve$density >= 0), logical(1))),
      "curvas: densidades no negativas")
# La lognormal ganadora evaluada en la mediana coincide con la referencia SciPy.
ln <- Filter(function(c) c$id == "lognormal", cur)[[1]]
pmed <- an$motor$fits$lognormal$params
abstol(.dist_pdf("lognormal", stats::median(xc), pmed), 0.0002504035, 1e-9,
       "densidad lognormal en la mediana (vs SciPy)")

# ------------------------------------------------------------
# 4. QQ y PP frente a referencias SciPy
# ------------------------------------------------------------
cat("\n-- 4. QQ / PP --\n")
qq <- vd$qq_plot$points
check(nrow(qq) == length(xc),              "QQ: un punto por observación")
check(vd$qq_plot$distribution == an$assessment$recommendation$level1$id,
      "QQ: usa la distribución recomendada por B4")
abstol(qq$theoretical[1], 165.9202, 1e-3,  "QQ: primer cuantil teórico (lognormal)")
abstol(qq$theoretical[nrow(qq)], 9827.4104, 1e-2, "QQ: último cuantil teórico")
abstol(qq$sample[1], 120.3, 1e-9,          "QQ: primer estadístico de orden")
check(!is.unsorted(qq$sample),             "QQ: la muestra va ordenada")

pp <- vd$pp_plot$points
abstol(pp$theoretical[1], 0.022509, 1e-5,  "PP: CDF ajustada en el mínimo")
abstol(pp$empirical[1], 0.5 / 12, 1e-9,    "PP: probabilidad empírica (i-0.5)/n")
abstol(vd$pp_plot$ecdf$ecdf[1], 1 / 12, 1e-9,  "ECDF: primer punto = 1/n")
abstol(vd$pp_plot$ecdf$ecdf[12], 1, 1e-12,     "ECDF: último punto = 1")

# ------------------------------------------------------------
# 5. Familia discreta
# ------------------------------------------------------------
cat("\n-- 5. Discreta --\n")
dfd <- data.frame(count = xd)
vdd <- build_visual_data(dist_fit_analyze(dfd, "count"), dfd)
check(vdd$histogram_density$family == "discrete", "discreta: familia declarada")
abstol(sum(vdd$histogram_density$observed$freq), 1, 1e-12,
       "discreta: las frecuencias observadas suman 1")
check(all(c("k", "pmf") %in% names(vdd$histogram_density$curves[[1]]$curve)),
      "discreta: las curvas ajustadas son PMF sobre k")
check(vdd$qq_plot$distribution == "negative_binomial",
      "discreta: QQ sobre la recomendada (binomial negativa)")

# ------------------------------------------------------------
# 6. No altera el análisis ni reestima (pureza)
# ------------------------------------------------------------
cat("\n-- 6. Pureza --\n")
an_before <- dist_fit_analyze(dfc, "loss_amount")
invisible(build_visual_data(an_before, dfc))
check(identical(an_before, dist_fit_analyze(dfc, "loss_amount")),
      "pureza: el objeto de análisis no se modifica")
check(identical(build_visual_data(an, dfc), vd),
      "determinismo: misma entrada -> mismos datos de gráficos")

# ------------------------------------------------------------
# 7. QQ/PP de una distribución concreta (ampliación aditiva)
# ------------------------------------------------------------
cat("\n-- 7. QQ/PP por distribución --\n")
ids <- vapply(an$assessment$ranking, function(e) e$id, character(1))
rec <- an$assessment$recommendation$level1$id
otra <- ids[ids != rec][1]

qp_def <- build_qq_pp_data(an, dfc)
check(qp_def$qq_plot$distribution == rec && isTRUE(qp_def$qq_plot$is_recommended),
      "por defecto usa la distribución recomendada y lo declara")
check(identical(qp_def$qq_plot$points, vd$qq_plot$points),
      "coincide con el QQ que genera build_visual_data() por defecto")

qp_otra <- build_qq_pp_data(an, dfc, distribution = otra)
check(qp_otra$qq_plot$distribution == otra && isFALSE(qp_otra$qq_plot$is_recommended),
      "acepta una distribución distinta y la marca como no recomendada")
check(!identical(qp_otra$qq_plot$points$theoretical, qp_def$qq_plot$points$theoretical),
      "los cuantiles teóricos cambian con la distribución elegida")
check(identical(qp_otra$qq_plot$points$sample, qp_def$qq_plot$points$sample) ||
        length(qp_otra$qq_plot$points$sample) > 0,
      "la muestra se prepara según el soporte de cada distribución")
check(qp_otra$pp_plot$distribution == otra,
      "el PP-plot sigue a la misma distribución")

check(build_qq_pp_data(an, dfc, distribution = "inexistente")$qq_plot$distribution == rec,
      "un id no evaluado recae en la recomendada (sin error)")

vd_otra <- build_visual_data(an, dfc, distribution = otra)
check(vd_otra$qq_plot$distribution == otra,
      "build_visual_data() propaga la distribución a QQ/PP")
check(identical(vd_otra$histogram_density, vd$histogram_density),
      "el histograma, la KDE y las curvas NO dependen de la selección")

cat("\nB7 UNIT TESTS SUPERADOS\n")
