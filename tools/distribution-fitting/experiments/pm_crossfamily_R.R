# ============================================================
# Tool-02 (distribution-fitting) — B11.1-R4  ·  ULTIMA PRUEBA DE B11.1
# Archivo: experiments/pm_crossfamily_R.R
#
# OBJETIVO UNICO: decidir entre  P3w = 10/50/90  y  P5 = 10/25/50/75/90
# fuera de Burr, con diseno PAREADO y normalizacion s_Q (OD-13, congelada).
#
# NO incluye P3c.  NO pesos.  NO nuevos objetivos.  NO nuevas normalizaciones.
# ENTORNO EXPERIMENTAL: no toca calc.R, mod_tool.R, app.R, manifest, schema ni
# tests productivos.  PM sigue sin implementacion en produccion.
#
# ------------------------------------------------------------
# DISENO
# ------------------------------------------------------------
# * PAREADO.  La semilla depende de (familia, DGP, repeticion) y NUNCA del preset.
#   Para cada terna se genera x UNA sola vez y P3w y P5 se ajustan sobre
#   EXACTAMENTE el mismo vector.  Permite analisis replica a replica.
# * Normalizacion  s_Q = max_j qhat_j - min_j qhat_j  (OD-13 CONGELADA):
#       J_PM(theta) = SUM_j [Q_theta(p_j) - qhat_j]^2 / s_Q^2
#   si s_Q es finita y > 0.  Si s_Q = 0 -> REJECT con diagnostico explicito.
#   Sin epsilon.  Sin recurso a IQR.
# * n = 1000,  R_MC = 300,  22 DGP.
# * Parametrizaciones y arranques COPIADOS de R/calc.R (ver cada familia).
#
# ------------------------------------------------------------
# ERROR DE REFERENCIA (importante: no todo parametro admite error relativo)
# ------------------------------------------------------------
# Para cada parametro se define una ESCALA DE REFERENCIA ref_j y se mide
#       e_j = |theta_hat_j - theta_j| / ref_j
#
#   - parametros de forma y de escala positivos  ->  ref_j = |theta_j|
#     (e_j es el error relativo habitual; `rel_ok = TRUE`)
#   - `mean` de la Normal        ->  ref_j = sd_true          (`rel_ok = FALSE`)
#   - `meanlog` de la Lognormal  ->  ref_j = sdlog_true       (`rel_ok = FALSE`)
#
# El motivo del segundo caso NO es solo que `mean` pueda ser 0 o negativo.
# `meanlog` es un parametro de LOCALIZACION en escala logaritmica: si se cambia
# la unidad de los datos, meanlog se desplaza en una constante aditiva, de modo
# que su "error relativo" depende de la unidad elegida y no es una medida
# invariante.  Referenciarlo a la dispersion del propio modelo si lo es.
#
# `bias` y `RMSE` se reportan siempre en unidades del parametro.
# `rel_bias` y `rel_RMSE` se reportan SOLO si `rel_ok = TRUE` (NA en otro caso).
# FALLO CATASTROFICO: e_j > 1.  Definicion unica para todos los parametros.
#
# ------------------------------------------------------------
# AVISOS
# ------------------------------------------------------------
# Se aplica ya el patron exigido para B11.2, para no inundar la consola:
#   (1) GUARDA PREVIA: `to_u`/`to_th` transforman SOLO las componentes positivas
#       mediante indexacion, en lugar de `ifelse(pos, log(th), th)`.  Ese ifelse
#       evaluaba log() sobre valores negativos aunque despues descartase el
#       resultado, y era el origen de los 149 avisos de la Normal en T5.
#   (2) CAPTURA LOCAL Y ACOTADA: solo dentro de la evaluacion de Q(p;theta), y
#       solo para el aviso conocido "NaNs"; cualquier otro aviso se propaga.
#       Los silenciados se CUENTAN y se reportan de forma agregada.
#   NO se usa suppressWarnings() global en ningun punto.
#
# Uso:    Rscript tools/distribution-fitting/experiments/pm_crossfamily_R.R
# Salida: experiments/results/pm_crossfamily_R.csv         (metricas)
#         experiments/results/pm_crossfamily_R_paired.csv  (comparacion pareada)
# Autor: BMK — 2026-09-03
# ============================================================

MASTER_SEED <- 20260903L
R_MC        <- 300L
N_OBS       <- 1000L
CFG         <- list(P3w = c(.10, .50, .90),
                    P5  = c(.10, .25, .50, .75, .90))
CFGN        <- names(CFG)
CATASTROPHIC_THRESHOLD <- 1.0

OUTDIR <- file.path("tools", "distribution-fitting", "experiments", "results")
if (!dir.exists(OUTDIR)) OUTDIR <- file.path("experiments", "results")
dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)

cat("R:", R.version.string, "|", R.version$platform, "\n")
cat("B11.1-R4 cross-family | R_MC =", R_MC, "| n =", N_OBS,
    "| normalizacion = s_Q | diseno = PAREADO | presets: P3w vs P5\n\n")

MUFFLED <- new.env(parent = emptyenv()); MUFFLED$n <- 0L

# ---------------------------------------------------------------- catalogo
# Funciones cuantil IDENTICAS a `.dist_quantile()` de R/calc.R.
# Arranques IDENTICOS a los `.mle_*()` de R/calc.R (politica de inicializacion
# de ADR-031: PM arranca donde arranca el MLE).
FAM <- list(

  exponential = list(
    par = "rate", pos = TRUE, rel_ok = TRUE,
    Q = function(p, t) stats::qexp(p, t[1]),
    G = function(n, t) stats::rexp(n, t[1]),
    S = function(x) 1 / mean(x),
    dgps = list(
      list("rate_baja", c(0.01)),   # media 100
      list("rate_alta", c(2.00))    # media 0,5: otra magnitud
    )),

  gamma = list(
    par = c("shape", "scale"), pos = c(TRUE, TRUE), rel_ok = c(TRUE, TRUE),
    Q = function(p, t) stats::qgamma(p, shape = t[1], scale = t[2]),
    G = function(n, t) stats::rgamma(n, shape = t[1], scale = t[2]),
    S = function(x) { m <- mean(x); v <- stats::var(x); c(m^2 / v, v / m) },
    dgps = list(
      list("moderada",   c(2.0, 500)),    # asimetria moderada
      list("shape_bajo", c(0.5, 1000)),   # shape < 1: densidad no acotada en 0
      list("casi_sim",   c(9.0, 100))     # shape alto: casi simetrica
    )),

  weibull = list(
    par = c("shape", "scale"), pos = c(TRUE, TRUE), rel_ok = c(TRUE, TRUE),
    Q = function(p, t) stats::qweibull(p, shape = t[1], scale = t[2]),
    G = function(n, t) stats::rweibull(n, shape = t[1], scale = t[2]),
    S = function(x) { cv <- stats::sd(x) / mean(x)
                      sh <- max(cv^(-1.086), 0.5)          # aproximacion de Justus
                      c(sh, mean(x) / gamma(1 + 1 / sh)) },
    dgps = list(
      list("moderada",   c(1.5, 800)),
      list("shape_bajo", c(0.7, 500)),    # shape < 1: cola pesada, tasa decreciente
      list("casi_sim",   c(3.0, 1000))
    )),

  lognormal = list(
    par = c("meanlog", "sdlog"), pos = c(FALSE, TRUE), rel_ok = c(FALSE, TRUE),
    ref = function(t) c(t[2], abs(t[2])),   # meanlog referenciado a sdlog
    Q = function(p, t) stats::qlnorm(p, t[1], t[2]),
    G = function(n, t) stats::rlnorm(n, t[1], t[2]),
    S = function(x) { lx <- log(x); c(mean(lx), sqrt(mean((lx - mean(lx))^2))) },
    dgps = list(
      list("tipica",      c(7.0, 1.3)),
      list("poca_disp",   c(7.0, 0.4)),
      list("muy_dispersa",c(2.0, 2.0))
    )),

  loglogistic = list(
    par = c("shape", "scale"), pos = c(TRUE, TRUE), rel_ok = c(TRUE, TRUE),
    Q = function(p, t) t[2] * (p / (1 - p))^(1 / t[1]),
    G = function(n, t) { u <- stats::runif(n); t[2] * (u / (1 - u))^(1 / t[1]) },
    S = function(x) c(1, stats::median(x)),
    dgps = list(
      list("moderada",   c(2.5, 600)),
      list("cola_pesada",c(1.2, 400)),    # shape < 2: varianza infinita
      list("cola_ligera",c(4.0, 1000))
    )),

  pareto = list(   # Lomax / Pareto tipo II
    par = c("shape", "scale"), pos = c(TRUE, TRUE), rel_ok = c(TRUE, TRUE),
    Q = function(p, t) t[2] * ((1 - p)^(-1 / t[1]) - 1),
    G = function(n, t) t[2] * ((1 - stats::runif(n))^(-1 / t[1]) - 1),
    S = function(x) c(2, mean(x)),
    dgps = list(
      list("moderada",   c(2.5, 1000)),
      list("cola_pesada",c(1.2, 500)),    # shape < 2: varianza infinita
      list("cola_ligera",c(4.0, 2000))
    )),

  burr = list(     # CONTROL: ya validado en B11.1-R3; solo 2 DGP
    par = c("shape1", "shape2", "scale"), pos = c(TRUE, TRUE, TRUE),
    rel_ok = c(TRUE, TRUE, TRUE),
    Q = function(p, t) t[3] * ((1 - p)^(-1 / t[2]) - 1)^(1 / t[1]),
    G = function(n, t) { u <- stats::runif(n)
                         t[3] * ((1 - u)^(-1 / t[2]) - 1)^(1 / t[1]) },
    S = function(x) c(1, 1, stats::median(x)),
    dgps = list(
      list("moderada", c(2.0, 1.5, 500)),
      list("pesada",   c(1.2, 0.8, 400))
    )),

  normal = list(   # CONTROL de simetria; `mean` puede ser 0 o negativo
    par = c("mean", "sd"), pos = c(FALSE, TRUE), rel_ok = c(FALSE, TRUE),
    ref = function(t) c(t[2], abs(t[2])),   # mean referenciado a sd
    Q = function(p, t) stats::qnorm(p, t[1], t[2]),
    G = function(n, t) stats::rnorm(n, t[1], t[2]),
    S = function(x) c(mean(x), sqrt(mean((x - mean(x))^2))),
    dgps = list(
      list("mu_pos", c(100, 15)),
      list("mu_cero",c(  0,  1)),   # error relativo de `mean` indefinido
      list("mu_neg", c(-50, 20))    # error relativo de `mean` sin sentido
    ))
)

# escala de referencia por defecto: |theta_j|
ref_of <- function(f, true) if (is.null(f$ref)) abs(true) else f$ref(true)

# Semilla determinista por (familia, DGP, repeticion). NO depende del preset.
seed_for <- function(tag, rep) {
  s <- MASTER_SEED
  for (ch in utf8ToInt(paste0(tag, "_", rep))) s <- (s * 31 + ch) %% 2147483647
  as.integer(s)
}

# ------------------------------------------------- evaluacion protegida de Q
# Captura ACOTADA: solo aqui, y solo el aviso conocido de NaN. Cualquier otro
# aviso se deja propagar para que no pase inadvertido.
q_safe <- function(Q, p, theta) {
  withCallingHandlers(
    tryCatch(Q(p, theta), error = function(e) rep(NA_real_, length(p))),
    warning = function(w) {
      if (grepl("NaN", conditionMessage(w), fixed = TRUE)) {
        MUFFLED$n <- MUFFLED$n + 1L
        invokeRestart("muffleWarning")
      }
    })
}

# ------------------------------------------------------------- ajuste PM
fit_pm <- function(f, x, p, maxit = 500L) {
  qhat <- stats::quantile(x, p, names = FALSE, type = 7)
  sQ   <- max(qhat) - min(qhat)                     # OD-13, congelada
  m_eff <- length(unique(qhat))                     # solo DIAGNOSTICO
  if (!is.finite(sQ) || sQ <= 0)
    return(list(theta = NULL, m_eff = m_eff,
                status = "reject_quantiles_collapse"))  # sin epsilon, sin fallback
  s2  <- sQ^2
  pos <- f$pos
  th0 <- f$S(x)

  J <- function(theta) {
    if (!all(is.finite(theta))) return(1e10)
    if (any(theta[pos] <= 0))   return(1e10)        # guarda previa
    qt <- q_safe(f$Q, p, theta)
    if (!all(is.finite(qt))) return(1e10)
    v <- sum((qt - qhat)^2) / s2
    if (is.finite(v)) v else 1e10
  }
  # GUARDA PREVIA: log()/exp() SOLO sobre las componentes positivas (indexacion),
  # no mediante ifelse(), que evaluaria log() tambien sobre valores negativos.
  to_u  <- function(th) { u <- th; u[pos] <- log(th[pos]); u }
  to_th <- function(u)  { th <- u; th[pos] <- exp(u[pos]); th }

  if (any(th0[pos] <= 0) || !all(is.finite(th0)))
    return(list(theta = NULL, m_eff = m_eff, status = "bad_start"))

  fit <- tryCatch(stats::optim(to_u(th0), function(u) {
                    th <- to_th(u)
                    if (!all(is.finite(th))) return(1e10)
                    J(th)
                  }, method = "L-BFGS-B", control = list(maxit = maxit)),
                  error = function(e) NULL)

  if (is.null(fit) || !is.finite(fit$value) || fit$value >= 1e10)
    return(list(theta = NULL, m_eff = m_eff, status = "optimizer_failure"))
  th <- to_th(fit$par)
  if (!all(is.finite(th)))
    return(list(theta = NULL, m_eff = m_eff, status = "nonfinite"))
  if (any(abs(th[pos]) < .Machine$double.xmin))
    return(list(theta = NULL, m_eff = m_eff, status = "boundary_guard"))
  list(theta = th, m_eff = m_eff,
       status = if (fit$convergence == 0L) "success" else "optimizer_failure")
}

# -------------------------------------------------------------- catalogo DGP
cat("== DGP del benchmark (parametrizacion de R/calc.R) ==\n")
for (fn in names(FAM)) for (g in FAM[[fn]]$dgps)
  cat(sprintf("  %-12s %-13s %s = %s\n", fn, g[[1]],
              paste(FAM[[fn]]$par, collapse = "/"),
              paste(format(g[[2]], trim = TRUE), collapse = "/")))
cat(sprintf("\nTotal: %d DGP x %d replicas x %d presets = %d ajustes\n\n",
            sum(vapply(FAM, function(f) length(f$dgps), 1L)), R_MC, 2L,
            sum(vapply(FAM, function(f) length(f$dgps), 1L)) * R_MC * 2L))

# ------------------------------------------------------------------- main
res <- list(); pai <- list(); t0 <- Sys.time()

for (fn in names(FAM)) {
  f <- FAM[[fn]]; k <- length(f$par)
  for (g in f$dgps) {
    lab <- g[[1]]; true <- g[[2]]; ref <- ref_of(f, true)
    tag <- paste0(fn, "_", lab)

    est <- lapply(CFGN, function(z) matrix(NA_real_, R_MC, k)); names(est) <- CFGN
    err <- lapply(CFGN, function(z) matrix(NA_real_, R_MC, k)); names(err) <- CFGN
    sts <- lapply(CFGN, function(z) rep(NA_character_, R_MC));  names(sts) <- CFGN
    mef <- lapply(CFGN, function(z) rep(NA_integer_, R_MC));    names(mef) <- CFGN

    for (rep in seq_len(R_MC)) {
      # --- PAREADO: una sola muestra por (familia, DGP, rep) ---
      set.seed(seed_for(tag, rep))
      x <- f$G(N_OBS, true)
      for (cn in CFGN) {
        r <- fit_pm(f, x, CFG[[cn]])
        sts[[cn]][rep] <- r$status; mef[[cn]][rep] <- r$m_eff
        if (r$status == "success") {
          est[[cn]][rep, ] <- r$theta
          err[[cn]][rep, ] <- abs(r$theta - true) / ref     # error de referencia
        }
      }
    }

    for (cn in CFGN) {
      ok <- sum(!is.na(est[[cn]][, 1]))
      for (j in seq_len(k)) {
        tv <- true[j]; e <- est[[cn]][, j]; e <- e[!is.na(e)]
        ej <- err[[cn]][, j]; ej <- ej[!is.na(ej)]
        rk <- f$rel_ok[j]
        if (length(e) > 0L) {
          b   <- mean(e) - tv
          rms <- sqrt(mean((e - tv)^2))
          med <- stats::median(ej)
          p90 <- unname(stats::quantile(ej, 0.90, type = 7))
          ct  <- sum(ej > CATASTROPHIC_THRESHOLD)
        } else { b <- rms <- med <- p90 <- NA_real_; ct <- 0L }
        res[[length(res) + 1L]] <- data.frame(
          family = fn, dgp = lab, cfg = cn, m = length(CFG[[cn]]), k = k,
          parameter = f$par[j], theta_true = tv, ref_scale = ref[j],
          rel_interpretable = rk,
          R = R_MC, n = N_OBS, paired = TRUE, scale_mode = "s_Q",
          n_success = ok, conv_rate = ok / R_MC,
          bias = b,
          rel_bias  = if (rk) b   / tv       else NA_real_,
          rmse = rms,
          rel_rmse  = if (rk) rms / abs(tv)  else NA_real_,
          median_scaled_abs_err = med, p90_scaled_abs_err = p90,
          catastrophic = ct, catastrophic_rate = ct / max(ok, 1L),
          m_eff_median = stats::median(mef[[cn]], na.rm = TRUE),
          stringsAsFactors = FALSE)
      }
      cat(sprintf("  %-12s %-13s %-4s conv=%.3f  catastr=%d\n", fn, lab, cn,
                  ok / R_MC,
                  sum(vapply(res[(length(res) - k + 1L):length(res)],
                             function(z) z$catastrophic, 1L))))
    }

    # ---- comparacion PAREADA P3w vs P5, parametro a parametro ----
    for (j in seq_len(k)) {
      a <- err$P3w[, j]; b <- err$P5[, j]
      both <- !is.na(a) & !is.na(b)
      d <- a[both] - b[both]        # d < 0  =>  P3w con MENOR error en esa replica
      pai[[length(pai) + 1L]] <- data.frame(
        family = fn, dgp = lab, parameter = f$par[j], k = k, R = R_MC,
        n_pairs = sum(both),
        prop_P3w_mejor = if (sum(both)) mean(d < 0) else NA_real_,
        mediana_dif = if (sum(both)) stats::median(d) else NA_real_,
        media_dif   = if (sum(both)) mean(d) else NA_real_,
        cat_P3w = sum(a[both] > CATASTROPHIC_THRESHOLD),
        cat_P5  = sum(b[both] > CATASTROPHIC_THRESHOLD),
        stringsAsFactors = FALSE)
    }
  }
}

out <- do.call(rbind, res); pr <- do.call(rbind, pai)
utils::write.csv(out, file.path(OUTDIR, "pm_crossfamily_R.csv"), row.names = FALSE)
utils::write.csv(pr, file.path(OUTDIR, "pm_crossfamily_R_paired.csv"), row.names = FALSE)

# =========================== LECTURA PARA LA DECISION ===========================
cat("\n\n=================== RESUMEN POR FAMILIA ===================\n")
cat(sprintf("%-12s | %-22s | %-24s | %s\n", "familia",
            "catastroficos P3w/P5", "% replicas P3w mejor", "conv P3w/P5"))
for (fn in names(FAM)) {
  s <- out$family == fn; q <- pr$family == fn
  c3 <- sum(out$catastrophic[s & out$cfg == "P3w"])
  c5 <- sum(out$catastrophic[s & out$cfg == "P5"])
  cat(sprintf("%-12s | %10d / %-9d | %21.1f%% | %.3f / %.3f\n", fn, c3, c5,
              100 * mean(pr$prop_P3w_mejor[q], na.rm = TRUE),
              mean(out$conv_rate[s & out$cfg == "P3w"]),
              mean(out$conv_rate[s & out$cfg == "P5"])))
}

cat("\n--- A. Robustez fuera de Burr: fallos catastroficos, EXCLUYENDO Burr ---\n")
nb <- out$family != "burr"
cat(sprintf("  P3w = %d     P5 = %d\n",
            sum(out$catastrophic[nb & out$cfg == "P3w"]),
            sum(out$catastrophic[nb & out$cfg == "P5"])))

# CORRECCION B11.1-R4 (IMPLEMENTATION DEFECT - experimental reporting only):
# la version anterior imprimia esta tabla SIN filtrar Burr bajo un encabezado que
# decia "EXCLUYENDO Burr", de modo que aparecian filas de Burr. El total de arriba
# si filtraba. Ahora la tabla respeta el filtro y Burr se reporta aparte, como
# control. Los CSV y las metricas estadisticas NO cambian.
cat("\n--- C. DGP donde un preset falla catastroficamente y el otro NO ---\n")
cat("    (C.1 — familias de decision, EXCLUYENDO Burr)\n")
z <- pr[pr$family != "burr" &
        ((pr$cat_P3w == 0 & pr$cat_P5 > 0) | (pr$cat_P5 == 0 & pr$cat_P3w > 0)), ]
if (nrow(z) == 0L) cat("      (ninguno)\n") else
  for (i in seq_len(nrow(z)))
    cat(sprintf("      %-12s %-13s %-8s  P3w=%3d  P5=%3d\n",
                z$family[i], z$dgp[i], z$parameter[i], z$cat_P3w[i], z$cat_P5[i]))
cat("    (C.2 — Burr, CONTROL: no participa en el criterio A/C de decision)\n")
zb <- pr[pr$family == "burr" & (pr$cat_P3w > 0 | pr$cat_P5 > 0), ]
if (nrow(zb) == 0L) cat("      (ninguno)\n") else
  for (i in seq_len(nrow(zb)))
    cat(sprintf("      %-12s %-13s %-8s  P3w=%3d  P5=%3d\n",
                zb$family[i], zb$dgp[i], zb$parameter[i], zb$cat_P3w[i], zb$cat_P5[i]))

cat("\n--- B. Precision tipica: mediana del error escalado, P3w vs P5 ---\n")
cat("  (positivo => P3w peor en el caso tipico; negativo => P3w mejor)\n")
for (fn in names(FAM)) {
  s3 <- out$family == fn & out$cfg == "P3w"; s5 <- out$family == fn & out$cfg == "P5"
  cat(sprintf("  %-12s  mediana P3w = %.4f   P5 = %.4f   dif = %+.4f\n", fn,
              mean(out$median_scaled_abs_err[s3], na.rm = TRUE),
              mean(out$median_scaled_abs_err[s5], na.rm = TRUE),
              mean(out$median_scaled_abs_err[s3], na.rm = TRUE) -
              mean(out$median_scaled_abs_err[s5], na.rm = TRUE)))
}

cat("\n--- D. Magnitud de la diferencia por numero de parametros ---\n")
for (kk in sort(unique(pr$k))) {
  q <- pr$k == kk
  cat(sprintf("  k = %d :  %% replicas P3w mejor = %.1f%%   |mediana dif| media = %.5f\n",
              kk, 100 * mean(pr$prop_P3w_mejor[q], na.rm = TRUE),
              mean(abs(pr$mediana_dif[q]), na.rm = TRUE)))
}

cat("\n--- Estados de ajuste distintos de 'success' ---\n")
cat(sprintf("  (conv global P3w = %.4f | P5 = %.4f)\n",
            mean(out$conv_rate[out$cfg == "P3w"]), mean(out$conv_rate[out$cfg == "P5"])))

cat(sprintf("\nAvisos 'NaN' silenciados LOCALMENTE dentro de Q(p;theta): %d\n", MUFFLED$n))
cat("  (guarda previa activa; ningun aviso ajeno a Q(p;theta) fue silenciado)\n")

cat(sprintf("\nCSV: %s\n     %s\ntiempo: %s\n",
            file.path(OUTDIR, "pm_crossfamily_R.csv"),
            file.path(OUTDIR, "pm_crossfamily_R_paired.csv"),
            format(Sys.time() - t0)))
