# ============================================================
# Tool-02 (distribution-fitting) — B11.1-R3
# Archivo: experiments/pm_warnings_capture.R
#
# Captura y clasificacion de los avisos de R que aparecieron durante T2/T3 y T5 de
# `pm_r_verification.R` ("Hubo 50 o mas avisos").
#
# Captura TODOS los avisos y evita su duplicacion en consola DESPUES de registrarlos:
# withCallingHandlers() registra CADA aviso junto con la distribucion, el escenario,
# el modo de normalizacion, la repeticion y el theta que se estaba evaluando en ese
# instante, y a continuacion invoca muffleWarning() para que el aviso ya guardado no
# se reimprima.  Ningun aviso se pierde: el CSV y el resumen contienen la totalidad.
#
# ENTORNO EXPERIMENTAL: no toca calc.R, mod_tool.R, manifest, schema ni tests.
#
# Uso:    Rscript tools/distribution-fitting/experiments/pm_warnings_capture.R
# Salida: experiments/results/pm_warnings_capture.csv + resumen por consola
# Autor: BMK — 2026-09-03
# ============================================================

options(warn = 1)          # emitir cada aviso en el momento, no agrupar al final
MASTER_SEED <- 20260901L
R_MC        <- 100L        # las mismas repeticiones que T2/T3 y T5
OUTDIR      <- file.path("tools", "distribution-fitting", "experiments", "results")
if (!dir.exists(OUTDIR)) OUTDIR <- file.path("experiments", "results")
dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)

cat("R:", R.version.string, "|", R.version$platform, "\n\n")

# ---- catalogo (copia verbatim de pm_r_verification.R) ----
q_fun <- list(
  exponential = function(p, t) stats::qexp(p, t[1]),
  gamma       = function(p, t) stats::qgamma(p, shape = t[1], scale = t[2]),
  lognormal   = function(p, t) stats::qlnorm(p, t[1], t[2]),
  burr        = function(p, t) t[3] * ((1 - p)^(-1 / t[2]) - 1)^(1 / t[1]),
  normal      = function(p, t) stats::qnorm(p, t[1], t[2])
)
r_fun <- list(
  exponential = function(n, t) stats::rexp(n, t[1]),
  gamma       = function(n, t) stats::rgamma(n, shape = t[1], scale = t[2]),
  lognormal   = function(n, t) stats::rlnorm(n, t[1], t[2]),
  burr        = function(n, t) q_fun$burr(stats::runif(n), t),
  normal      = function(n, t) stats::rnorm(n, t[1], t[2])
)
META <- list(
  exponential = list(names = "rate",                       pos = TRUE),
  gamma       = list(names = c("shape","scale"),           pos = c(TRUE, TRUE)),
  lognormal   = list(names = c("meanlog","sdlog"),         pos = c(FALSE, TRUE)),
  burr        = list(names = c("shape1","shape2","scale"), pos = c(TRUE, TRUE, TRUE)),
  normal      = list(names = c("mean","sd"),               pos = c(FALSE, TRUE))
)
start_values <- function(dist, x) {
  m <- mean(x); v <- stats::var(x)
  switch(dist,
    exponential = 1 / m,
    gamma       = c(m^2 / v, v / m),
    lognormal   = { lx <- log(x); c(mean(lx), sqrt(mean((lx - mean(lx))^2))) },
    burr        = c(1, 1, stats::median(x)),
    normal      = c(m, sqrt(v)))
}
seed_for <- function(tag, rep) {
  s <- MASTER_SEED
  for (ch in utf8ToInt(paste0(tag, "_", rep))) s <- (s * 31 + ch) %% 2147483647
  as.integer(s)
}

# ---- registro global de avisos ----
LOG <- new.env(parent = emptyenv())
LOG$rows <- list()
CTX <- new.env(parent = emptyenv())     # contexto vivo: que se esta evaluando
CTX$dist <- CTX$scenario <- CTX$mode <- NA_character_
CTX$rep <- NA_integer_
CTX$theta <- NA_character_
CTX$where <- NA_character_

record <- function(w) {
  LOG$rows[[length(LOG$rows) + 1L]] <- data.frame(
    dist = CTX$dist, scenario = CTX$scenario, mode = CTX$mode, rep = CTX$rep,
    where = CTX$where, theta = CTX$theta,
    message = conditionMessage(w),
    call = paste(deparse(conditionCall(w)), collapse = " "),
    stringsAsFactors = FALSE)
}

# ---- ajuste PM, instrumentado ----
fit_pm <- function(dist, x, p, scale_mode) {
  qhat <- stats::quantile(x, p, names = FALSE, type = 7)
  s2 <- if (scale_mode == "none") 1 else stats::IQR(x)^2
  if (!is.finite(s2) || s2 <= 0) return(list(theta = NULL, status = "scale_degenerate"))
  Q <- q_fun[[dist]]; pos <- META[[dist]]$pos
  th0 <- start_values(dist, x)
  J <- function(theta) {
    CTX$theta <- paste(signif(theta, 6), collapse = ",")   # theta en curso
    CTX$where <- "objetivo Q(p;theta)"
    v <- tryCatch({
      qt <- Q(p, theta)
      if (!all(is.finite(qt))) return(1e10)
      sum((qt - qhat)^2) / s2
    }, error = function(e) 1e10)
    if (is.finite(v)) v else 1e10
  }
  to_u  <- function(th) ifelse(pos, log(th), th)
  to_th <- function(u)  ifelse(pos, exp(u),  u)
  Ju <- function(u) {
    CTX$where <- "transformacion exp(u)"
    th <- to_th(u)
    if (!all(is.finite(th))) return(1e10)
    J(th)
  }
  fit <- tryCatch(stats::optim(to_u(th0), Ju, method = "L-BFGS-B",
                               control = list(maxit = 500L)),
                  error = function(e) NULL)
  if (is.null(fit) || !is.finite(fit$value) || fit$value >= 1e10)
    return(list(theta = NULL, status = "optimizer_failure"))
  list(theta = to_th(fit$par), status = "success")
}

# ---- escenarios que produjeron avisos: T2/T3 (escala) y T5 (Normal) ----
ESC_ESCALA <- list(
  list("exponential", c(0.01),          "exp"),
  list("normal",      c(100, 15),       "norm"),
  list("gamma",       c(2.0, 500),      "gam"),
  list("lognormal",   c(7.0, 1.3),      "lnorm"),
  list("burr",        c(2.0, 1.5, 500), "burr")
)
run <- function() {
  # --- T2/T3: X y 1000*X, modos "none" y "iqr" ---
  for (e in ESC_ESCALA) {
    dist <- e[[1]]; true <- e[[2]]; tag <- e[[3]]
    for (mode in c("none", "iqr")) {
      for (rep in seq_len(R_MC)) {
        CTX$dist <- dist; CTX$scenario <- paste0("T2T3_", tag); CTX$mode <- mode
        CTX$rep <- rep
        set.seed(seed_for(paste0(tag, "_sc"), rep))
        x <- r_fun[[dist]](1000L, true)
        invisible(fit_pm(dist, x,      c(.25,.50,.75), mode))
        CTX$scenario <- paste0("T2T3_", tag, "_x1000")
        invisible(fit_pm(dist, x * 1000, c(.25,.50,.75), mode))
      }
    }
  }
  # --- T5: Normal con media positiva, cero y negativa ---
  for (mu in c(100, 0, -100)) {
    for (rep in seq_len(R_MC)) {
      CTX$dist <- "normal"; CTX$scenario <- paste0("T5_mu", mu)
      CTX$mode <- "iqr"; CTX$rep <- rep
      set.seed(seed_for(paste0("norm_", mu), rep))
      x <- stats::rnorm(1000L, mu, 15)
      invisible(fit_pm("normal", x, c(.25,.50,.75), "iqr"))
    }
  }
}

cat("Ejecutando escenarios T2/T3 y T5 con captura de avisos...\n")
withCallingHandlers(run(),
  warning = function(w) { record(w); invokeRestart("muffleWarning") })

# ---- informe ----
if (length(LOG$rows) == 0L) {
  cat("\nNO se registro ningun aviso.\n")
} else {
  W <- do.call(rbind, LOG$rows)
  utils::write.csv(W, file.path(OUTDIR, "pm_warnings_capture.csv"), row.names = FALSE)
  cat(sprintf("\nAvisos registrados: %d\n\n", nrow(W)))

  cat("== Por mensaje ==\n")
  tb <- sort(table(W$message), decreasing = TRUE)
  for (i in seq_along(tb)) cat(sprintf("  %6d  %s\n", tb[[i]], names(tb)[i]))

  cat("\n== Por distribucion x mensaje ==\n")
  print(table(W$dist, W$message))

  cat("\n== Por escenario ==\n")
  print(sort(table(W$scenario), decreasing = TRUE))

  cat("\n== Por punto del codigo ==\n")
  print(table(W$where))

  cat("\n== Primeros 5 ejemplos con theta ==\n")
  print(utils::head(W[, c("dist", "scenario", "mode", "rep", "where", "theta", "message")], 5))

  cat("\n== Clasificacion automatica propuesta (revisar manualmente) ==\n")
  clasif <- ifelse(grepl("NaN|produced|Inf|overflow|convergencia|convergence", W$message,
                         ignore.case = TRUE),
                   "EXPECTED NUMERICAL EXPLORATION", "REVISAR MANUALMENTE")
  print(table(clasif, W$dist))
  cat("\n  NOTA: 'EXPECTED NUMERICAL EXPLORATION' solo es valido si el aviso ocurre\n")
  cat("  evaluando Q(p;theta) o exp(u) y la funcion devuelve la penalizacion 1e10.\n")
  cat("  Cualquier aviso en otro punto debe clasificarse a mano.\n")
  cat(sprintf("\nCSV: %s\n", file.path(OUTDIR, "pm_warnings_capture.csv")))
}
