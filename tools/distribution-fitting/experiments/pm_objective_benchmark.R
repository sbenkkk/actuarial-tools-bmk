# ============================================================
# Tool-02 (distribution-fitting) — B11.1
# Archivo: experiments/pm_objective_benchmark.R
#
# Benchmark Monte Carlo de formulaciones de Percentile Matching (OD-1).
# ENTORNO EXPERIMENTAL: NO forma parte del flujo productivo. No se carga desde
# app.R, no toca calc.R ni mod_tool.R, no se ejecuta en los tests.
#
# ADVERTENCIA IMPORTANTE
# ----------------------
# Esta transcripcion a R NO HA SIDO EJECUTADA por quien la escribio: la evidencia
# del informe `docs/tool02_pm_benchmark.md` se obtuvo con la replica en Python
# (`pm_core.py` + `pm_objective_benchmark.py`), que reproduce las mismas
# parametrizaciones. Este script se entrega para auditoria y reproducibilidad en
# el lenguaje del proyecto y DEBE CONSIDERARSE NO VERIFICADO hasta ejecutarlo.
#
# Uso:  Rscript experiments/pm_objective_benchmark.R
# Autor: BMK — 2026-08-31
# ============================================================

MASTER_SEED <- 20260830L
R_REPS      <- 300L
NS          <- c(100L, 1000L, 10000L)
OBJS        <- c("A", "B", "Bg", "C", "D")
OUT         <- file.path("experiments", "results", "pm_objective_benchmark_R.csv")

# ------------------------------------------------------------------ catalogo
# Parametrizaciones IDENTICAS a R/calc.R. Loglogistica, Lomax y Burr estan
# implementadas manualmente alli; aqui se replican sus Q y F exactamente.
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
p_fun <- list(
  exponential = function(x, t) stats::pexp(x, t[1]),
  gamma       = function(x, t) stats::pgamma(x, shape = t[1], scale = t[2]),
  weibull     = function(x, t) stats::pweibull(x, shape = t[1], scale = t[2]),
  lognormal   = function(x, t) stats::plnorm(x, t[1], t[2]),
  loglogistic = function(x, t) { z <- (x / t[2])^t[1]; z / (1 + z) },
  pareto      = function(x, t) 1 - (t[2] / (x + t[2]))^t[1],
  burr        = function(x, t) 1 - (1 + (x / t[3])^t[1])^(-t[2]),
  normal      = function(x, t) stats::pnorm(x, t[1], t[2])
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
# nombres, k y que parametros son estrictamente positivos (para la reparametrizacion)
META <- list(
  exponential = list(names = "rate",                          pos = TRUE),
  gamma       = list(names = c("shape","scale"),              pos = c(TRUE, TRUE)),
  weibull     = list(names = c("shape","scale"),              pos = c(TRUE, TRUE)),
  lognormal   = list(names = c("meanlog","sdlog"),            pos = c(FALSE, TRUE)),
  loglogistic = list(names = c("shape","scale"),              pos = c(TRUE, TRUE)),
  pareto      = list(names = c("shape","scale"),              pos = c(TRUE, TRUE)),
  burr        = list(names = c("shape1","shape2","scale"),    pos = c(TRUE, TRUE, TRUE)),
  normal      = list(names = c("mean","sd"),                  pos = c(FALSE, TRUE))
)

# ------------------------------------------------------------------- DGPs
DGPS <- list(
  list("exponential","exp_m100",      c(0.01)),
  list("exponential","exp_m1000",     c(0.001)),
  list("gamma",      "gam_moderada",  c(2.0, 500)),
  list("gamma",      "gam_asimetrica",c(0.6, 1500)),
  list("gamma",      "gam_casi_sim",  c(5.0, 200)),
  list("weibull",    "wei_moderada",  c(1.5, 600)),
  list("weibull",    "wei_hazard_dec",c(0.7, 500)),
  list("weibull",    "wei_ligera",    c(2.5, 800)),
  list("lognormal",  "lnorm_moderada",c(7.0, 0.6)),
  list("lognormal",  "lnorm_asim",    c(7.0, 1.3)),
  list("lognormal",  "lnorm_pesada",  c(5.0, 2.0)),
  list("loglogistic","llog_moderada", c(3.0, 300)),
  list("loglogistic","llog_pesada",   c(1.5, 300)),
  list("pareto",     "par_var_finita",c(3.5, 700)),
  list("pareto",     "par_pesada",    c(1.8, 600)),
  list("burr",       "burr_moderada", c(2.0, 1.5, 500)),
  list("burr",       "burr_pesada",   c(1.2, 0.8, 400)),
  list("normal",     "norm_positiva", c(100, 15)),
  list("normal",     "norm_estandar", c(0, 1))
)

configs_for <- function(dist) {
  k  <- length(META[[dist]]$names)
  mk <- switch(as.character(k), "1" = 0.50, "2" = c(0.25, 0.75), "3" = c(0.25, 0.50, 0.75))
  out <- list(P3c = c(.25,.50,.75), P3w = c(.10,.50,.90), P5 = c(.10,.25,.50,.75,.90))
  if (!any(vapply(out, function(v) isTRUE(all.equal(v, mk)), logical(1)))) out$Pmk <- mk
  out
}

# Semilla determinista por (dgp, n, repeticion): FNV-1a. Anadir un escenario NO
# desplaza los demas.
# NOTA (B11.1-R): version anterior con bitwXor()/bitwAnd() -> NA en R porque la
# constante FNV supera .Machine$integer.max. Sustituida por hash multiplicativo
# sobre doubles con modulo. Determinista por escenario; anadir uno no desplaza el resto.
seed_for <- function(dgp, n, rep) {
  s <- MASTER_SEED
  for (tok in c(dgp, as.character(n), as.character(rep)))
    for (ch in utf8ToInt(tok)) s <- (s * 31 + ch) %% 2147483647
  as.integer(s)
}

# Arranques: los MISMOS que usa calc.R para MLE. Identicos para los 5 objetivos,
# de modo que ninguno gane por recibir mejores valores iniciales.
start_values <- function(dist, x) {
  m <- mean(x); v <- stats::var(x)
  switch(dist,
    exponential = 1 / m,
    gamma       = c(m^2 / v, v / m),
    weibull     = { cv <- sqrt(v)/m; s0 <- max(cv^(-1.086), 0.5); c(s0, m/gamma(1+1/s0)) },
    lognormal   = { lx <- log(x); c(mean(lx), sqrt(mean((lx - mean(lx))^2))) },
    loglogistic = c(1, stats::median(x)),
    pareto      = c(2, m),
    burr        = c(1, 1, stats::median(x)),
    normal      = c(m, sqrt(v)))
}

# ------------------------------------------------------------- objetivos
# w_j = 1 en todo el experimento (pesos uniformes por diseno).
make_J <- function(kind, dist, p, qhat, x) {
  Q <- q_fun[[dist]]; FF <- p_fun[[dist]]
  iqr <- stats::IQR(x)
  function(theta) {
    v <- tryCatch({
      if (kind == "D") {
        d <- FF(qhat, theta) - p
      } else {
        qt <- Q(p, theta)
        if (!all(is.finite(qt))) return(1e10)
        d <- switch(kind,
          A  = qt - qhat,
          B  = (qt - qhat) / qhat,                     # denominador LOCAL
          Bg = (qt - qhat) / iqr,                      # denominador GLOBAL robusto
          C  = { if (any(qt <= 0) || any(qhat <= 0)) return(1e10)
                 log(qt) - log(qhat) })
      }
      sum(d^2)
    }, error = function(e) 1e10)
    if (is.finite(v)) v else 1e10
  }
}

applicable <- function(kind, qhat) {
  switch(kind, B = all(abs(qhat) > 1e-12), C = all(qhat > 0), TRUE)
}

# --------------------------------------------------------- ajuste PM
# Reparametrizacion logaritmica de los parametros positivos (esquema de ADR-014).
# ES UNA TRANSFORMACION DE OPTIMIZACION: no debe confundirse con la futura
# transformacion para IC analiticos de B12.
fit_pm <- function(dist, x, p, kind, start = NULL, maxit = 500L) {
  qhat <- stats::quantile(x, p, names = FALSE, type = 7)
  if (!applicable(kind, qhat)) return(list(theta = NULL, status = "not_applicable"))
  pos <- META[[dist]]$pos
  th0 <- if (is.null(start)) start_values(dist, x) else start
  J   <- make_J(kind, dist, p, qhat, x)
  to_u  <- function(th) ifelse(pos, log(th), th)
  to_th <- function(u)  ifelse(pos, exp(u),  u)
  Ju <- function(u) { th <- to_th(u); if (!all(is.finite(th))) return(1e10); J(th) }
  fit <- tryCatch(stats::optim(to_u(th0), Ju, method = "L-BFGS-B",
                               control = list(maxit = maxit)),
                  error = function(e) NULL)
  if (is.null(fit) || !is.finite(fit$value) || fit$value >= 1e10)
    return(list(theta = NULL, status = "optimizer_failure"))
  th <- to_th(fit$par)
  if (!all(is.finite(th)))                       return(list(theta = NULL, status = "nonfinite"))
  if (any(abs(th)[pos] < .Machine$double.xmin))  return(list(theta = NULL, status = "boundary_guard"))
  if (fit$convergence != 0L)                     return(list(theta = th, status = "optimizer_failure"))
  list(theta = th, status = "success")
}

# ------------------------------------------------------------------ main
main <- function() {
  res <- list(); t0 <- Sys.time()
  for (d in DGPS) {
    dist <- d[[1]]; lab <- d[[2]]; true <- d[[3]]
    nms <- META[[dist]]$names; k <- length(nms)
    for (n in NS) {
      cfgs <- configs_for(dist)
      acc <- list(); fails <- list()
      for (cn in names(cfgs)) for (ob in OBJS) {
        acc[[paste(cn, ob)]] <- NULL; fails[[paste(cn, ob)]] <- character(0)
      }
      for (rep in seq_len(R_REPS)) {
        set.seed(seed_for(lab, n, rep))
        x <- r_fun[[dist]](n, true)
        for (cn in names(cfgs)) for (ob in OBJS) {
          f <- fit_pm(dist, x, cfgs[[cn]], ob)
          key <- paste(cn, ob)
          if (f$status == "success") acc[[key]] <- rbind(acc[[key]], f$theta)
          else fails[[key]] <- c(fails[[key]], f$status)
        }
      }
      for (cn in names(cfgs)) for (ob in OBJS) {
        key <- paste(cn, ob); est <- acc[[key]]; fl <- fails[[key]]
        ns <- if (is.null(est)) 0L else nrow(est)
        for (j in seq_len(k)) {
          tv <- true[j]
          b <- rmse <- sdj <- NA_real_
          if (ns > 0L) {
            b    <- mean(est[, j]) - tv
            rmse <- sqrt(mean((est[, j] - tv)^2))
            sdj  <- if (ns > 1L) stats::sd(est[, j]) else NA_real_
          }
          res[[length(res) + 1L]] <- data.frame(
            dist = dist, dgp = lab, n = n, cfg = cn, m = length(cfgs[[cn]]), k = k,
            objective = ob, parameter = nms[j], theta_true = tv,
            R = R_REPS, n_success = ns, conv_rate = ns / R_REPS,
            bias = b, rel_bias = if (abs(tv) > 1e-12) b / tv else NA_real_,
            rmse = rmse, rel_rmse = if (abs(tv) > 1e-12) rmse / abs(tv) else NA_real_,
            sd = sdj,
            fail_not_applicable = sum(fl == "not_applicable"),
            fail_optimizer      = sum(fl == "optimizer_failure"),
            fail_boundary       = sum(fl == "boundary_guard"),
            fail_nonfinite      = sum(fl == "nonfinite"),
            stringsAsFactors = FALSE)
        }
      }
      cat(sprintf("  %-16s n=%-6d %s\n", lab, n, format(Sys.time() - t0)))
    }
  }
  out <- do.call(rbind, res)
  dir.create(dirname(OUT), showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(out, OUT, row.names = FALSE)
  cat(sprintf("\nfilas=%d  R=%d  ->  %s\n", nrow(out), R_REPS, OUT))
  cat("\nInformacion del entorno:\n"); print(utils::sessionInfo()$R.version$version.string)
}

if (sys.nframe() == 0L) main()
