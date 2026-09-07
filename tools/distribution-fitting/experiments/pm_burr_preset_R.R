# ============================================================
# Tool-02 (distribution-fitting) — B11.1-R3
# Archivo: experiments/pm_burr_preset_R.R
#
# Benchmark de PRESET para Burr en R.  P3c vs P3w vs P5, R_MC = 300, 6 DGP.
# Produce la EVIDENCIA PRIMARIA sobre el preset.  (El equivalente en Python,
# `pm_burr_preset.py`, es evidencia secundaria y ademas usa un diseno NO pareado.)
#
# ENTORNO EXPERIMENTAL: no toca calc.R, mod_tool.R, manifest, schema ni tests.
#
# DISENO MONTE CARLO PAREADO
# --------------------------
# La semilla depende de (DGP, repeticion) y NO del preset.  Para cada (DGP, rep) se
# genera el vector x UNA sola vez y los tres presets se ajustan sobre EXACTAMENTE la
# misma muestra.  Asi la comparacion entre presets no arrastra el ruido de muestras
# distintas y admite analisis pareado replica a replica.
#
# NORMALIZACION PRINCIPAL: scale_mode = "spread",  s(x,p) = max(qhat) - min(qhat).
# Es la candidata de OD-13.  Cualquier s > 0 independiente de theta define el MISMO
# estimador, pero la escala si afecta al criterio de parada de optim(), de modo que
# el benchmark que decide el preset de produccion debe usar la escala de produccion.
#
# Los bloques de catalogo, arranques y optimizacion son COPIA VERBATIM de
# `pm_r_verification.R`, ya ejecutado con exito en R 4.4.1.
#
# Uso:    Rscript tools/distribution-fitting/experiments/pm_burr_preset_R.R
# Salida: experiments/results/pm_burr_preset_R.csv         (metricas por parametro)
#         experiments/results/pm_burr_preset_R_paired.csv  (comparacion pareada)
# Autor: BMK — 2026-09-03
# ============================================================

MASTER_SEED <- 20260902L
R_MC        <- 300L
N_OBS       <- 1000L
SCALE_MODE  <- "spread"          # OD-13: s_Q = max(qhat) - min(qhat)
OUTDIR      <- file.path("tools", "distribution-fitting", "experiments", "results")
if (!dir.exists(OUTDIR)) OUTDIR <- file.path("experiments", "results")
dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)

cat("R:", R.version.string, "|", R.version$platform, "\n")
cat("R_MC =", R_MC, " n =", N_OBS, " normalizacion =", SCALE_MODE,
    " diseno = PAREADO (misma x para los 3 presets)\n\n")

# ---------------------------------------------------------------- catalogo
# Parametrizacion Burr XII IDENTICA a R/calc.R:
#   F(x) = 1 - (1 + (x/scale)^shape1)^(-shape2)
#   Q(p) = scale * ((1-p)^(-1/shape2) - 1)^(1/shape1)
q_burr <- function(p, t) t[3] * ((1 - p)^(-1 / t[2]) - 1)^(1 / t[1])
r_burr <- function(n, t) q_burr(stats::runif(n), t)
NAMES  <- c("shape1", "shape2", "scale")
POS    <- c(TRUE, TRUE, TRUE)

# Arranque: el MISMO que usa calc.R para el MLE de Burr.
start_burr <- function(x) c(1, 1, stats::median(x))

# Semilla determinista por (DGP, repeticion).  NO depende del preset: es lo que
# garantiza el pareado.  Hash multiplicativo sobre doubles (se mantiene bajo 2^53 y
# evita el problema de bitwXor() con enteros mayores que .Machine$integer.max).
seed_for <- function(tag, rep) {
  s <- MASTER_SEED
  for (ch in utf8ToInt(paste0(tag, "_", rep))) s <- (s * 31 + ch) %% 2147483647
  as.integer(s)
}

# --------------------------------------------------------- ajuste PM
# Normalized Quantile SSE:  J(theta) = (1/s^2) * SUM_j [Q_theta(p_j) - q_emp(p_j)]^2
#   "spread" -> s = max(qhat) - min(qhat)   (OD-13, principal)
#   "iqr"    -> s = IQR(x)                  (comparacion secundaria)
# Reparametrizacion log de los parametros positivos (ADR-014); penalizacion 1e10;
# guarda de frontera de ADR-027.  optim(method = "L-BFGS-B", maxit = 500).
# NO se modifican tolerancias.
fit_pm_burr <- function(x, p, scale_mode = SCALE_MODE, start = NULL, maxit = 500L) {
  qhat <- stats::quantile(x, p, names = FALSE, type = 7)
  s2 <- switch(scale_mode,
               spread = (max(qhat) - min(qhat))^2,
               iqr    = stats::IQR(x)^2,
               stop("scale_mode desconocido"))
  # OD-13: si s_Q = 0 los cuantiles elegidos no aportan dispersion -> se rechaza.
  # NO se introduce epsilon ni recurso alternativo en este bloque.
  if (!is.finite(s2) || s2 <= 0)
    return(list(theta = NULL, status = "scale_degenerate", conv = NA_integer_,
                m_eff = length(unique(qhat))))
  th0 <- if (is.null(start)) start_burr(x) else start
  J <- function(theta) {
    v <- tryCatch({
      qt <- q_burr(p, theta)
      if (!all(is.finite(qt))) return(1e10)
      sum((qt - qhat)^2) / s2
    }, error = function(e) 1e10)
    if (is.finite(v)) v else 1e10
  }
  to_u  <- function(th) ifelse(POS, log(th), th)
  to_th <- function(u)  ifelse(POS, exp(u),  u)
  Ju <- function(u) { th <- to_th(u); if (!all(is.finite(th))) return(1e10); J(th) }
  fit <- tryCatch(stats::optim(to_u(th0), Ju, method = "L-BFGS-B",
                               control = list(maxit = maxit)),
                  error = function(e) NULL)
  m_eff <- length(unique(qhat))
  if (is.null(fit) || !is.finite(fit$value) || fit$value >= 1e10)
    return(list(theta = NULL, status = "optimizer_failure", conv = NA_integer_,
                m_eff = m_eff))
  th <- to_th(fit$par)
  if (!all(is.finite(th)))
    return(list(theta = NULL, status = "nonfinite", conv = fit$convergence, m_eff = m_eff))
  if (any(abs(th)[POS] < .Machine$double.xmin))
    return(list(theta = NULL, status = "boundary_guard", conv = fit$convergence,
                m_eff = m_eff))
  list(theta = th,
       status = if (fit$convergence == 0L) "success" else "optimizer_failure",
       conv = fit$convergence, m_eff = m_eff)
}

# ------------------------------------------------------------------- DGPs
# Los SEIS DGP del diagnostico previo, explicitos aqui para que el script sea
# autocontenido y auditable.
#
# NOTA sobre `escala_x1000`: es una REPLICA DISTRIBUCIONAL reescalada, es decir, se
# simula de Burr(2.0, 1.5, 500000).  NO es la muestra de `moderada` multiplicada por
# 1000.  Por tanto NO debe leerse como prueba de identidad exacta bajo cambio de
# unidad: esa invariancia sample-by-sample ya quedo verificada en T2/T3 de
# `pm_r_verification.R`.  Aqui solo comprueba que el comportamiento AGREGADO del
# preset no cambia al trabajar en otra magnitud.
DGPS <- list(
  list("moderada",      c(2.0, 1.5, 500)),      # referencia
  list("pesada",        c(1.2, 0.8, 400)),      # cola pesada
  list("shapes_suaves", c(3.0, 2.5, 600)),      # formas menos extremas
  list("shape2_alto",   c(2.0, 4.0, 500)),      # shape2 alto
  list("shape2_bajo",   c(2.0, 0.5, 500)),      # shape2 bajo
  list("escala_x1000",  c(2.0, 1.5, 500000))    # replica reescalada (ver nota)
)
CFG <- list(P3c = c(.25, .50, .75),
            P3w = c(.10, .50, .90),
            P5  = c(.10, .25, .50, .75, .90))
CFGN <- names(CFG)

# DEFINICION DE FALLO CATASTROFICO (identica a la del diagnostico previo):
#   |theta_hat_j - theta_j| / |theta_j|  >  1     (error relativo > 100 %)
CATASTROPHIC_THRESHOLD <- 1.0

# ------------------------------------------------------------------ main
res <- list(); paired <- list(); t0 <- Sys.time()

for (g in DGPS) {
  lab <- g[[1]]; true <- g[[2]]

  # Matrices de error relativo por replica: filas = repeticion, columnas = parametro.
  # NA cuando ese preset no convergio en esa replica.
  relerr <- lapply(CFGN, function(z) matrix(NA_real_, nrow = R_MC, ncol = 3L))
  names(relerr) <- CFGN
  est    <- lapply(CFGN, function(z) matrix(NA_real_, nrow = R_MC, ncol = 3L))
  names(est) <- CFGN
  meff   <- lapply(CFGN, function(z) rep(NA_integer_, R_MC)); names(meff) <- CFGN

  for (rep in seq_len(R_MC)) {
    # --- PAREADO: una sola muestra por (DGP, rep), compartida por los 3 presets ---
    set.seed(seed_for(lab, rep))
    x <- r_burr(N_OBS, true)
    for (cn in CFGN) {
      f <- fit_pm_burr(x, CFG[[cn]], SCALE_MODE)
      meff[[cn]][rep] <- f$m_eff
      if (f$status == "success") {
        est[[cn]][rep, ] <- f$theta
        relerr[[cn]][rep, ] <- abs(f$theta - true) / abs(true)
      }
    }
  }

  # ---- metricas por preset y parametro ----
  for (cn in CFGN) {
    ok <- sum(!is.na(est[[cn]][, 1]))
    for (j in seq_len(3)) {
      tv <- true[j]; e <- est[[cn]][, j]; e <- e[!is.na(e)]
      rl <- relerr[[cn]][, j]; rl <- rl[!is.na(rl)]
      if (length(e) > 0L) {
        b <- mean(e) - tv; rm_ <- sqrt(mean((e - tv)^2))
        med <- stats::median(rl)
        p90 <- unname(stats::quantile(rl, 0.90, type = 7))
        p95 <- unname(stats::quantile(rl, 0.95, type = 7))
        cat_ <- sum(rl > CATASTROPHIC_THRESHOLD)
      } else { b <- rm_ <- med <- p90 <- p95 <- NA_real_; cat_ <- 0L }
      res[[length(res) + 1L]] <- data.frame(
        dgp = lab, cfg = cn, m = length(CFG[[cn]]), k = 3L, parameter = NAMES[j],
        theta_true = tv, R = R_MC, n = N_OBS, scale_mode = SCALE_MODE,
        paired_design = TRUE, n_success = ok, conv_rate = ok / R_MC,
        bias = b, rel_bias = b / tv, rmse = rm_, rel_rmse = rm_ / abs(tv),
        median_abs_rel_err = med, p90_rel_err = p90, p95_rel_err = p95,
        catastrophic = cat_, catastrophic_rate = cat_ / max(ok, 1L),
        m_eff_median = stats::median(meff[[cn]], na.rm = TRUE),
        stringsAsFactors = FALSE)
    }
    n3 <- length(res)
    cat(sprintf("  %-14s %-4s conv=%.3f  relRMSE sh1=%.4f sh2=%.4f sc=%.4f  catastr sh2=%d sc=%d\n",
                lab, cn, ok / R_MC,
                res[[n3 - 2]]$rel_rmse, res[[n3 - 1]]$rel_rmse, res[[n3]]$rel_rmse,
                res[[n3 - 1]]$catastrophic, res[[n3]]$catastrophic))
  }

  # ---- comparacion PAREADA P3w vs P5 (solo posible por el diseno pareado) ----
  for (j in c(2L, 3L)) {           # shape2 y scale
    a <- relerr$P3w[, j]; b <- relerr$P5[, j]
    both <- !is.na(a) & !is.na(b)
    d <- a[both] - b[both]         # < 0  =>  P3w tiene MENOR error que P5
    paired[[length(paired) + 1L]] <- data.frame(
      dgp = lab, parameter = NAMES[j], R = R_MC,
      n_pairs = sum(both),
      prop_P3w_mejor = if (sum(both)) mean(d < 0) else NA_real_,
      mediana_dif_relerr = if (sum(both)) stats::median(d) else NA_real_,
      media_dif_relerr = if (sum(both)) mean(d) else NA_real_,
      stringsAsFactors = FALSE)
    cat(sprintf("    [pareado] %-6s  P3w mejor en %.1f%% de %d replicas;  mediana(P3w-P5) = %+.5f\n",
                NAMES[j], 100 * mean(d < 0), sum(both), stats::median(d)))
  }
}

out <- do.call(rbind, res)
utils::write.csv(out, file.path(OUTDIR, "pm_burr_preset_R.csv"), row.names = FALSE)
pr <- do.call(rbind, paired)
utils::write.csv(pr, file.path(OUTDIR, "pm_burr_preset_R_paired.csv"), row.names = FALSE)

# ------------------------------------------------------------ resumen
cat("\n== TOTAL de fallos catastroficos (|err rel| > 1), shape2 + scale ==\n")
cat("   (sobre", R_MC * length(DGPS), "replicas por preset)\n")
for (cn in CFGN) {
  sel <- out$cfg == cn & out$parameter %in% c("shape2", "scale")
  cat(sprintf("  %-4s : %d\n", cn, sum(out$catastrophic[sel])))
}

cat("\n== Resumen pareado P3w vs P5 ==\n")
for (par in c("shape2", "scale")) {
  sel <- pr$parameter == par
  cat(sprintf("  %-7s  P3w mejor en %.1f%% de las replicas (media sobre los 6 DGP)\n",
              par, 100 * mean(pr$prop_P3w_mejor[sel], na.rm = TRUE)))
}

cat(sprintf("\nCSV: %s\n     %s\ntiempo: %s\n",
            file.path(OUTDIR, "pm_burr_preset_R.csv"),
            file.path(OUTDIR, "pm_burr_preset_R_paired.csv"),
            format(Sys.time() - t0)))
