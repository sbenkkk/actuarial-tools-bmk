# ============================================================
# Tool-02 (distribution-fitting) — B11.1-R
# Archivo: experiments/pm_r_verification.R
#
# Verificacion DIRIGIDA en R de los hallazgos de B11.1 (obtenidos en Python).
# ENTORNO EXPERIMENTAL: no toca calc.R, mod_tool.R, manifest ni tests.
#
# Responde a seis preguntas concretas:
#   T1  A y normalized-A (J/s^2) producen el MISMO argmin cuando esta bien determinado
#   T2  La normalizacion mejora el comportamiento numerico frente a las unidades
#   T3  Exponencial: rate' = rate / c  (el punto que causo un bug en el script Python)
#   T4  Burr: P3c vs P3w vs P5 — identificacion de shape2
#   T5  Normal con media positiva, cero y negativa
#   T6  Configuraciones invalidas e IQR = 0
#
# Uso:   Rscript experiments/pm_r_verification.R
# Salida: experiments/results/pm_r_verification_*.csv  + resumen por consola
# Autor: BMK — 2026-09-01
# ============================================================

MASTER_SEED <- 20260901L
R_MC        <- 100L          # verificacion dirigida; subir a 300 si algo sale ambiguo
OUTDIR      <- file.path("experiments", "results")
dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)

cat("R:", R.version.string, "\n")
cat("plataforma:", R.version$platform, "\n\n")

# ---------------------------------------------------------------- catalogo
# Parametrizaciones IDENTICAS a R/calc.R.
q_fun <- list(
  exponential = function(p, t) stats::qexp(p, t[1]),
  gamma       = function(p, t) stats::qgamma(p, shape = t[1], scale = t[2]),
  weibull     = function(p, t) stats::qweibull(p, shape = t[1], scale = t[2]),
  lognormal   = function(p, t) stats::qlnorm(p, t[1], t[2]),
  loglogistic = function(p, t) t[2] * (p / (1 - p))^(1 / t[1]),
  pareto      = function(p, t) t[2] * ((1 - p)^(-1 / t[1]) - 1),
  burr        = function(p, t) t[3] * ((1 - p)^(-1 / t[2]) - 1)^(1 / t[1]),
  normal      = function(p, t) stats::qnorm(p, t[1], t[2])
)
r_fun <- list(
  exponential = function(n, t) stats::rexp(n, t[1]),
  gamma       = function(n, t) stats::rgamma(n, shape = t[1], scale = t[2]),
  weibull     = function(n, t) stats::rweibull(n, shape = t[1], scale = t[2]),
  lognormal   = function(n, t) stats::rlnorm(n, t[1], t[2]),
  loglogistic = function(n, t) q_fun$loglogistic(stats::runif(n), t),
  pareto      = function(n, t) q_fun$pareto(stats::runif(n), t),
  burr        = function(n, t) q_fun$burr(stats::runif(n), t),
  normal      = function(n, t) stats::rnorm(n, t[1], t[2])
)
META <- list(
  exponential = list(names = "rate",                       pos = TRUE),
  gamma       = list(names = c("shape","scale"),           pos = c(TRUE, TRUE)),
  weibull     = list(names = c("shape","scale"),           pos = c(TRUE, TRUE)),
  lognormal   = list(names = c("meanlog","sdlog"),         pos = c(FALSE, TRUE)),
  loglogistic = list(names = c("shape","scale"),           pos = c(TRUE, TRUE)),
  pareto      = list(names = c("shape","scale"),           pos = c(TRUE, TRUE)),
  burr        = list(names = c("shape1","shape2","scale"), pos = c(TRUE, TRUE, TRUE)),
  normal      = list(names = c("mean","sd"),               pos = c(FALSE, TRUE))
)

# Arranques: los MISMOS que usa calc.R para MLE (comparacion justa entre variantes).
start_values <- function(dist, x) {
  m <- mean(x); v <- stats::var(x)
  switch(dist,
    exponential = 1 / m,
    gamma       = c(m^2 / v, v / m),
    weibull     = { cv <- sqrt(v) / m; s0 <- max(cv^(-1.086), 0.5)
                    c(s0, m / gamma(1 + 1 / s0)) },
    lognormal   = { lx <- log(x); c(mean(lx), sqrt(mean((lx - mean(lx))^2))) },
    loglogistic = c(1, stats::median(x)),
    pareto      = c(2, m),
    burr        = c(1, 1, stats::median(x)),
    normal      = c(m, sqrt(v)))
}

# ------------------------------------------------------- ajuste PM
# OPTIMIZADOR: replica el patron productivo de `.mle_optim()` en calc.R —
#   optim(), method = "L-BFGS-B", control = list(maxit = 500),
#   reparametrizacion log de los parametros estrictamente positivos (ADR-014),
#   penalizacion finita 1e10 cuando el objetivo no es finito,
#   guarda de frontera de ADR-027 (parametro < .Machine$double.xmin).
# `scale_mode`: "none" -> J_A ;  "iqr" -> J_A / IQR(x)^2 ;  "spread" -> J_A / spread(q)^2
fit_pm <- function(dist, x, p, scale_mode = "none", start = NULL, maxit = 500L) {
  qhat <- stats::quantile(x, p, names = FALSE, type = 7)
  s2 <- switch(scale_mode,
    none   = 1,
    iqr    = stats::IQR(x)^2,
    spread = (max(qhat) - min(qhat))^2,
    stop("scale_mode desconocido"))
  if (!is.finite(s2) || s2 <= 0)
    return(list(theta = NULL, status = "scale_degenerate", conv = NA_integer_,
                fevals = NA_integer_, J = NA_real_))
  Q   <- q_fun[[dist]]
  pos <- META[[dist]]$pos
  th0 <- if (is.null(start)) start_values(dist, x) else start
  J <- function(theta) {
    v <- tryCatch({
      qt <- Q(p, theta)
      if (!all(is.finite(qt))) return(1e10)
      sum((qt - qhat)^2) / s2
    }, error = function(e) 1e10)
    if (is.finite(v)) v else 1e10
  }
  to_u  <- function(th) ifelse(pos, log(th), th)
  to_th <- function(u)  ifelse(pos, exp(u),  u)
  Ju <- function(u) { th <- to_th(u); if (!all(is.finite(th))) return(1e10); J(th) }
  fit <- tryCatch(stats::optim(to_u(th0), Ju, method = "L-BFGS-B",
                               control = list(maxit = maxit)),
                  error = function(e) NULL)
  if (is.null(fit) || !is.finite(fit$value) || fit$value >= 1e10)
    return(list(theta = NULL, status = "optimizer_failure", conv = NA_integer_,
                fevals = NA_integer_, J = NA_real_))
  th <- to_th(fit$par)
  if (!all(is.finite(th)))
    return(list(theta = NULL, status = "nonfinite", conv = fit$convergence,
                fevals = fit$counts[[1]], J = fit$value))
  if (any(abs(th)[pos] < .Machine$double.xmin))
    return(list(theta = NULL, status = "boundary_guard", conv = fit$convergence,
                fevals = fit$counts[[1]], J = fit$value))
  list(theta = th,
       status = if (fit$convergence == 0L) "success" else "optimizer_failure",
       conv = fit$convergence, fevals = fit$counts[[1]],
       J = fit$value * s2)          # J en escala ABSOLUTA, comparable entre modos
}

# Semilla determinista por (etiqueta, repeticion).
# NOTA (B11.1-R): la version anterior usaba FNV-1a con bitwXor()/bitwAnd(). En R eso
# NO funciona: esas funciones coercionan a integer y la constante inicial FNV
# (2166136261) supera .Machine$integer.max (2147483647), produciendo NA y abortando
# en set.seed(). Se sustituye por un hash multiplicativo sobre doubles con modulo,
# que se mantiene siempre por debajo de 2^53 y es exactamente representable.
# Sigue cumpliendo el requisito: anadir un escenario NO desplaza los demas.
seed_for <- function(tag, rep) {
  s <- MASTER_SEED
  for (ch in utf8ToInt(paste0(tag, "_", rep)))
    s <- (s * 31 + ch) %% 2147483647
  as.integer(s)
}

# ============================================================
# T1 — MISMO ARGMIN: J_A vs J_A/IQR^2
# ============================================================
cat("== T1. Mismo argmin: A vs normalized-A ==\n")
ESC <- list(
  list("exponential", c(0.01),            c(.25,.50,.75), "exp"),
  list("normal",      c(100, 15),         c(.25,.50,.75), "norm"),
  list("gamma",       c(2.0, 500),        c(.25,.50,.75), "gam"),
  list("lognormal",   c(7.0, 1.3),        c(.25,.50,.75), "lnorm"),
  list("weibull",     c(1.5, 600),        c(.25,.50,.75), "wei"),
  list("pareto",      c(3.5, 700),        c(.25,.50,.75), "par"),
  list("burr",        c(2.0, 1.5, 500),   c(.25,.50,.75), "burr_m3"),
  list("burr",        c(2.0, 1.5, 500),   c(.10,.25,.50,.75,.90), "burr_m5")
)
t1 <- NULL
for (e in ESC) {
  dist <- e[[1]]; true <- e[[2]]; p <- e[[3]]; tag <- e[[4]]
  da <- dr <- dJ <- numeric(0); ca <- cb <- 0L; np_ <- 0L
  for (rep in seq_len(R_MC)) {
    set.seed(seed_for(tag, rep)); x <- r_fun[[dist]](1000L, true)
    fa <- fit_pm(dist, x, p, "none"); fb <- fit_pm(dist, x, p, "iqr")
    ca <- ca + (fa$status == "success"); cb <- cb + (fb$status == "success")
    if (fa$status == "success" && fb$status == "success") {
      np_ <- np_ + 1L
      da <- c(da, max(abs(fa$theta - fb$theta)))
      dr <- c(dr, max(abs(fa$theta - fb$theta) / pmax(abs(fa$theta), 1e-30)))
      dJ <- c(dJ, abs(fa$J - fb$J) / max(abs(fa$J), 1e-30))
    }
  }
  t1 <- rbind(t1, data.frame(escenario = tag, dist = dist, m = length(p), pares = np_,
    max_dif_abs = if (np_) max(da) else NA, max_dif_rel = if (np_) max(dr) else NA,
    max_dif_rel_J = if (np_) max(dJ) else NA,
    conv_A = ca / R_MC, conv_norm = cb / R_MC, stringsAsFactors = FALSE))
  cat(sprintf("  %-9s m=%d  dif_rel_theta=%.3e  dif_rel_J=%.3e  conv A=%.3f norm=%.3f\n",
              tag, length(p), if (np_) max(dr) else NA, if (np_) max(dJ) else NA,
              ca / R_MC, cb / R_MC))
}
utils::write.csv(t1, file.path(OUTDIR, "pm_r_verification_T1_argmin.csv"), row.names = FALSE)
cat("  LECTURA: dif_rel_theta grande CON dif_rel_J ~ 0 = valle plano (no identificado),\n")
cat("           no un argmin distinto. Ver T4 para Burr.\n\n")

# ============================================================
# T2 y T3 — ESCALA
# ============================================================
cat("== T2/T3. Invariancia de escala (c = 1000) ==\n")
ESC2 <- list(
  list("exponential", c(0.01),          "exp",  function(t, c) t / c),      # rate: INVERSA
  list("normal",      c(100, 15),       "norm", function(t, c) t * c),
  list("gamma",       c(2.0, 500),      "gam",  function(t, c) c(t[1], t[2] * c)),
  list("lognormal",   c(7.0, 1.3),      "lnorm",function(t, c) c(t[1] + log(c), t[2])),
  list("burr",        c(2.0, 1.5, 500), "burr", function(t, c) c(t[1], t[2], t[3] * c))
)
CC <- 1000
t2 <- NULL
for (e in ESC2) {
  dist <- e[[1]]; true <- e[[2]]; tag <- e[[3]]; eqv <- e[[4]]
  for (mode in c("none", "iqr")) {
    dev <- numeric(0); c1 <- c2 <- 0L; fe1 <- fe2 <- numeric(0)
    for (rep in seq_len(R_MC)) {
      set.seed(seed_for(paste0(tag, "_sc"), rep)); x <- r_fun[[dist]](1000L, true)
      f1 <- fit_pm(dist, x,      c(.25,.50,.75), mode)
      f2 <- fit_pm(dist, x * CC, c(.25,.50,.75), mode)
      c1 <- c1 + (f1$status == "success"); c2 <- c2 + (f2$status == "success")
      if (f1$status == "success" && f2$status == "success") {
        esperado <- eqv(f1$theta, CC)
        dev <- c(dev, max(abs(f2$theta - esperado) / pmax(abs(esperado), 1e-30)))
        fe1 <- c(fe1, f1$fevals); fe2 <- c(fe2, f2$fevals)
      }
    }
    t2 <- rbind(t2, data.frame(dist = dist, escenario = tag, modo = mode, c = CC,
      conv_X = c1 / R_MC, conv_cX = c2 / R_MC,
      max_dev_equivarianza = if (length(dev)) max(dev) else NA,
      fevals_X = if (length(fe1)) mean(fe1) else NA,
      fevals_cX = if (length(fe2)) mean(fe2) else NA, stringsAsFactors = FALSE))
    cat(sprintf("  %-6s %-5s conv X=%.3f  conv 1000X=%.3f  dev=%.3e  fev %.0f/%.0f\n",
                tag, mode, c1 / R_MC, c2 / R_MC,
                if (length(dev)) max(dev) else NA,
                if (length(fe1)) mean(fe1) else NA, if (length(fe2)) mean(fe2) else NA))
  }
}
utils::write.csv(t2, file.path(OUTDIR, "pm_r_verification_T2_escala.csv"), row.names = FALSE)
cat("\n")

# ============================================================
# T4 — BURR: P3c vs P3w vs P5
# ============================================================
cat("== T4. Burr: identificacion de shape2 segun percentiles ==\n")
CFG <- list(P3c = c(.25,.50,.75), P3w = c(.10,.50,.90), P5 = c(.10,.25,.50,.75,.90))
DGP <- list(list(c(2.0, 1.5, 500), "moderada"), list(c(1.2, 0.8, 400), "pesada"))
t4 <- NULL
for (g in DGP) {
  true <- g[[1]]; lab <- g[[2]]
  for (cn in names(CFG)) {
    est <- NULL; ok <- 0L
    for (rep in seq_len(R_MC)) {
      set.seed(seed_for(paste0("burr_", lab, "_", cn), rep))
      x <- r_fun$burr(1000L, true)
      f <- fit_pm("burr", x, CFG[[cn]], "iqr")
      if (f$status == "success") { est <- rbind(est, f$theta); ok <- ok + 1L }
    }
    for (j in 1:3) {
      nm <- META$burr$names[j]; tv <- true[j]
      b <- if (ok) mean(est[, j]) - tv else NA
      rm_ <- if (ok) sqrt(mean((est[, j] - tv)^2)) else NA
      t4 <- rbind(t4, data.frame(dgp = lab, cfg = cn, m = length(CFG[[cn]]), k = 3,
        parametro = nm, theta_true = tv, R = R_MC, n_success = ok,
        conv_rate = ok / R_MC, bias = b, rel_bias = b / tv,
        rmse = rm_, rel_rmse = rm_ / abs(tv), stringsAsFactors = FALSE))
    }
    cat(sprintf("  %-9s %-4s conv=%.3f  rel_RMSE shape1=%.3f shape2=%.3f scale=%.3f\n",
                lab, cn, ok / R_MC,
                t4$rel_rmse[nrow(t4) - 2], t4$rel_rmse[nrow(t4) - 1], t4$rel_rmse[nrow(t4)]))
  }
}
utils::write.csv(t4, file.path(OUTDIR, "pm_r_verification_T4_burr.csv"), row.names = FALSE)
cat("  CLAVE: convergencia alta con rel_RMSE de shape2 enorme = converge pero NO identifica.\n\n")

# ============================================================
# T5 — NORMAL: media positiva, cero y negativa
# ============================================================
cat("== T5. Normal: el objetivo no depende del signo de los cuantiles ==\n")
t5 <- NULL
for (mu in c(100, 0, -100)) {
  est <- NULL; ok <- 0L
  for (rep in seq_len(R_MC)) {
    set.seed(seed_for(paste0("norm_", mu), rep)); x <- stats::rnorm(1000L, mu, 15)
    f <- fit_pm("normal", x, c(.25,.50,.75), "iqr")
    if (f$status == "success") { est <- rbind(est, f$theta); ok <- ok + 1L }
  }
  for (j in 1:2) {
    tv <- c(mu, 15)[j]
    t5 <- rbind(t5, data.frame(mu_true = mu, parametro = META$normal$names[j],
      theta_true = tv, R = R_MC, n_success = ok, conv_rate = ok / R_MC,
      bias = if (ok) mean(est[, j]) - tv else NA,
      rmse = if (ok) sqrt(mean((est[, j] - tv)^2)) else NA, stringsAsFactors = FALSE))
  }
  cat(sprintf("  mu=%5.0f  conv=%.3f  RMSE mean=%.4f  RMSE sd=%.4f\n", mu, ok / R_MC,
              t5$rmse[nrow(t5) - 1], t5$rmse[nrow(t5)]))
}
utils::write.csv(t5, file.path(OUTDIR, "pm_r_verification_T5_normal.csv"), row.names = FALSE)
cat("\n")

# ============================================================
# T6 — CONFIGURACIONES INVALIDAS E IQR = 0
# ============================================================
cat("== T6. Validacion de configuracion e IQR = 0 ==\n")
validate_percentiles <- function(p, k) {
  if (is.null(p) || length(p) == 0L)     return(c("REJECT", "conjunto vacio"))
  if (any(!is.finite(p)))                return(c("REJECT", "percentil no finito (NA/NaN/Inf)"))
  if (any(p <= 0) || any(p >= 1))        return(c("REJECT", "percentil fuera de (0,1)"))
  if (anyDuplicated(p) > 0L)             return(c("REJECT", "percentiles duplicados"))
  if (length(unique(p)) < k)             return(c("REJECT", sprintf("m=%d < k=%d", length(unique(p)), k)))
  c("ACCEPT", "configuracion valida")
}
CASOS <- list(list("p = 0", c(0, .5, .75), 2), list("p = 1", c(.25, .5, 1), 2),
  list("p < 0", c(-.1, .5, .75), 2), list("p > 1", c(.25, .5, 1.7), 2),
  list("NA", c(.25, NA, .75), 2), list("NaN", c(.25, NaN, .75), 2),
  list("Inf", c(.25, Inf, .75), 2), list("duplicados", c(.5, .5, .75), 2),
  list("vacio", numeric(0), 2), list("m<k (m=1,k=2)", c(.5), 2),
  list("m<k (m=2,k=3)", c(.25, .75), 3), list("m=k (k=2)", c(.25, .75), 2),
  list("preset 25/50/75 k=3", c(.25, .5, .75), 3),
  list("P5 k=3", c(.10,.25,.50,.75,.90), 3))
t6a <- NULL
for (cs in CASOS) {
  v <- validate_percentiles(cs[[2]], cs[[3]])
  t6a <- rbind(t6a, data.frame(caso = cs[[1]], k = cs[[3]], estado = v[1],
                               motivo = v[2], stringsAsFactors = FALSE))
  cat(sprintf("  %-22s k=%d  %-7s %s\n", cs[[1]], cs[[3]], v[1], v[2]))
}
utils::write.csv(t6a, file.path(OUTDIR, "pm_r_verification_T6a_config.csv"), row.names = FALSE)

cat("\n  -- IQR = 0: taxonomia --\n")
set.seed(MASTER_SEED)
X_deg  <- rep(1000, 400)                                        # A: degenerada
X_iqr0 <- c(stats::rlnorm(80, 6.0, .3), rep(1000, 240), stats::rlnorm(80, 8.5, .3))
X_round<- round(stats::rlnorm(400, 7, 1.3) / 1000) * 1000
X_ok   <- stats::rlnorm(400, 7, 1.3)
t6b <- NULL
for (cs in list(list("A. degenerada", X_deg), list("B. 60% masa central", X_iqr0),
                list("C. redondeo x1000", X_round), list("D. continua", X_ok))) {
  lab <- cs[[1]]; x <- cs[[2]]
  for (cn in c("P3c", "P5")) {
    p <- if (cn == "P3c") c(.25,.50,.75) else c(.10,.25,.50,.75,.90)
    qh <- stats::quantile(x, p, names = FALSE, type = 7)
    f_iqr <- fit_pm("lognormal", x[x > 0], p, "iqr")
    f_spr <- fit_pm("lognormal", x[x > 0], p, "spread")
    t6b <- rbind(t6b, data.frame(caso = lab, cfg = cn,
      IQR = stats::IQR(x), sd = stats::sd(x), MAD = stats::mad(x, constant = 1),
      q_distintos = length(unique(qh)), m = length(p),
      spread_q = max(qh) - min(qh),
      estado_iqr = f_iqr$status, estado_spread = f_spr$status,
      sdlog_iqr = if (!is.null(f_iqr$theta)) f_iqr$theta[2] else NA,
      stringsAsFactors = FALSE))
    cat(sprintf("  %-20s %-4s IQR=%9.2f  q_dist=%d/%d  spread_q=%9.2f  %s / %s  sdlog=%.4g\n",
                lab, cn, stats::IQR(x), length(unique(qh)), length(p), max(qh) - min(qh),
                f_iqr$status, f_spr$status,
                if (!is.null(f_iqr$theta)) f_iqr$theta[2] else NA))
  }
}
utils::write.csv(t6b, file.path(OUTDIR, "pm_r_verification_T6b_iqr0.csv"), row.names = FALSE)

cat("\n== Rendimiento (ms por fit, n=1000) ==\n")
for (d in c("exponential", "gamma", "lognormal", "burr", "normal")) {
  tr <- list(exponential = c(0.01), gamma = c(2, 500), lognormal = c(7, 1.3),
             burr = c(2, 1.5, 500), normal = c(100, 15))[[d]]
  set.seed(MASTER_SEED); x <- r_fun[[d]](1000L, tr)
  for (cn in c("P3c", "P5")) {
    p <- if (cn == "P3c") c(.25,.50,.75) else c(.10,.25,.50,.75,.90)
    tt <- system.time(for (i in 1:30) fit_pm(d, x, p, "iqr"))[["elapsed"]] / 30 * 1000
    cat(sprintf("  %-12s %-4s %6.2f ms\n", d, cn, tt))
  }
}

cat("\nCSV escritos en", OUTDIR, "\n")
cat("sessionInfo:\n"); print(utils::sessionInfo()$R.version$version.string)
