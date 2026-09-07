# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b11_2_pm_tests.R
# Tests productivos de B11.2: motor de Percentile Matching (estimación PUNTUAL).
#
# Verifica el contrato CONGELADO en ADR-031 (B11.1, verificado en R 4.4.1):
#   s_Q = max(qhat) - min(qhat);  J_PM = SUM (Q_theta(p_j) - qhat_j)^2 / s_Q^2
#   rechazos: <2 percentiles, duplicados, fuera de (0,1), no finitos,
#             m_requested < k, s_Q = 0.  Sin epsilon, sin fallback IQR.
#   presets: p3w (default) 10/50/90; p5 10/25/50/75/90; p3c 25/50/75.
#
# NO valida SE, Hessiana, IC ni bootstrap: eso es B12-B14.
#
# Autor: BMK — Última actualización: 2026-09-03
# ============================================================
#
#   Rscript tests/b11_2_pm_tests.R     # desde la raíz de la herramienta
#   Rscript b11_2_pm_tests.R           # desde la carpeta tests/

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

cat("== B11.2 — PERCENTILE MATCHING (estimación puntual) ==\n")

P3W <- c(0.10, 0.50, 0.90)

# ------------------------------------------------------------
# A. VALIDACIÓN DE LA CONFIGURACIÓN
# ------------------------------------------------------------
cat("\n-- A. Validación de la configuración de percentiles --\n")

set.seed(20260903)
xg <- stats::rgamma(500L, shape = 2, scale = 500)   # k = 2

rej <- function(p, x = xg, id = "gamma") .pm_fit(id, x, p)

r <- rej(0.50)
check(identical(r$status, "reject_config") && !r$converged,
      "A.1 un solo percentil -> reject_config (mínimo 2)")
check(grepl("al menos 2", r$reason), "A.2 el motivo cita el mínimo de 2 percentiles")

r <- rej(c(0.25, 0.25, 0.75))
check(identical(r$status, "reject_config") && grepl("repetidos", r$reason),
      "A.3 percentiles duplicados -> reject_config con motivo explícito")

check(identical(rej(c(0.00, 0.50, 0.90))$status, "reject_config"),
      "A.4 p = 0 -> reject_config")
check(identical(rej(c(0.10, 0.50, 1.00))$status, "reject_config"),
      "A.5 p = 1 -> reject_config")
check(identical(rej(c(-0.10, 0.50, 0.90))$status, "reject_config"),
      "A.6 p negativo -> reject_config")
check(identical(rej(c(0.10, 0.50, 1.30))$status, "reject_config"),
      "A.7 p > 1 -> reject_config")

for (bad in list(c(0.10, NA_real_, 0.90), c(0.10, NaN, 0.90), c(0.10, Inf, 0.90))) {
  check(identical(rej(bad)$status, "reject_config"),
        sprintf("A.8 percentil no finito (%s) -> reject_config",
                paste(format(bad[2]), collapse = "")))
}
check(identical(rej(character(0))$status, "reject_config"),
      "A.9 vector no numérico / vacío -> reject_config")

# m_requested < k : Burr tiene k = 3, dos percentiles no bastan
xb <- 500 * ((1 - stats::runif(500L))^(-1 / 1.5) - 1)^(1 / 2)
r <- .pm_fit("burr", xb, c(0.25, 0.75))
check(identical(r$status, "reject_config") && grepl("estructuralmente insuficiente", r$reason),
      "A.10 m_requested = 2 < k = 3 (Burr) -> reject_config estructuralmente insuficiente")
check(identical(.pm_fit("gamma", xg, c(0.25, 0.75))$status, "success"),
      "A.11 m_requested = 2 = k (Gamma) NO se rechaza: la regla es m < k")

# s_Q = 0 : todos los cuantiles objetivo colapsan
x_col <- c(rep(1000, 480L), 1, 2, 3, 5000, 6000, 7000,
           8000, 9000, 10000, 11000, 12000, 13000,
           14000, 15000, 16000, 17000, 18000, 19000, 20000, 21000)
r <- .pm_fit("gamma", x_col, c(0.25, 0.50, 0.75))
check(identical(r$status, "reject_scale_collapse"),
      "A.12 cuantiles objetivo colapsados -> reject_scale_collapse")
check(r$s_Q == 0 && grepl("colapsan", r$reason),
      "A.13 s_Q = 0 exactamente y el motivo lo explica")
check(is.null(r$params) && !r$converged,
      "A.14 el rechazo NO devuelve parámetros ni declara convergencia")
check(is.na(r$objective), "A.15 sin objetivo cuando se rechaza")

# La misma muestra con percentiles más anchos SÍ es estimable: el diagnóstico
# correcto es el colapso de los cuantiles objetivo, no una propiedad del dato.
r2 <- .pm_fit("gamma", x_col, c(0.02, 0.50, 0.98))
check(r2$s_Q > 0 && !identical(r2$status, "reject_scale_collapse"),
      "A.16 la MISMA muestra con otros percentiles NO se rechaza: s_Q > 0")

# Configuración válida
r <- .pm_fit("gamma", xg, P3W)
check(identical(r$status, "success") && isTRUE(r$converged),
      "A.17 configuración válida -> success")

# Distribución no compatible (discreta): PM no disponible (OD-3)
check(identical(.pm_fit("poisson", xg, P3W)$status, "reject_config"),
      "A.18 distribución discreta -> PM no disponible")
check(is.null(.estimate("poisson", xg, "pm")),
      "A.19 .estimate(discreta, 'pm') devuelve NULL")

# ------------------------------------------------------------
# B. CONTRATO DE SALIDA
# ------------------------------------------------------------
cat("\n-- B. Contrato de salida de .pm_fit() --\n")

r <- .pm_fit("gamma", xg, P3W)
campos <- c("method", "id", "params", "percentiles", "q_empirical", "q_fitted",
            "s_Q", "objective", "m_requested", "m_effective", "n_params",
            "converged", "status", "reason", "optimizer")
check(all(campos %in% names(r)), "B.1 están todos los campos del contrato")
check(identical(r$method, "pm") && identical(r$id, "gamma"), "B.2 method e id")
check(identical(r$percentiles, P3W), "B.3 percentiles solicitados, tal cual")
check(length(r$q_empirical) == 3L && all(is.finite(r$q_empirical)),
      "B.4 cuantiles empíricos finitos, uno por percentil")
check(length(r$q_fitted) == 3L && all(is.finite(r$q_fitted)),
      "B.5 cuantiles ajustados finitos, uno por percentil")
check(identical(r$m_requested, 3L) && identical(r$n_params, 2L),
      "B.6 m_requested y n_params correctos")
check(is.integer(r$m_effective) || is.numeric(r$m_effective),
      "B.7 m_effective se publica como diagnóstico")
check(identical(names(r$params), c("shape", "scale")),
      "B.8 params con los nombres del catálogo, en orden")
check(is.na(r$reason), "B.9 sin reason cuando el ajuste tiene éxito")
check(is.finite(r$optimizer$convergence),
      "B.10 información del optimizador disponible para auditoría")

# El objetivo publicado coincide con la fórmula congelada, recalculada aparte.
J_manual <- sum((r$q_fitted - r$q_empirical)^2) / r$s_Q^2
check(abs(J_manual - r$objective) < 1e-10,
      "B.11 objective == SUM (q_fitted - q_emp)^2 / s_Q^2  (fórmula congelada)")
check(abs(r$s_Q - (max(r$q_empirical) - min(r$q_empirical))) < 1e-12,
      "B.12 s_Q == max(qhat) - min(qhat)")

# s_Q generaliza el IQR: con 25/50/75 coincide EXACTAMENTE con IQR(x) type 7.
rc <- .pm_fit("gamma", xg, c(0.25, 0.50, 0.75))
check(abs(rc$s_Q - stats::IQR(xg, type = 7)) < 1e-9,
      "B.13 con 25/50/75, s_Q == IQR(x) exactamente")

# ------------------------------------------------------------
# C. PRESETS
# ------------------------------------------------------------
cat("\n-- C. Presets congelados --\n")

check(identical(DFIT_PM$presets$p3w$percentiles, c(0.10, 0.50, 0.90)),
      "C.1 P3w = 0.10 / 0.50 / 0.90 exactamente")
check(identical(DFIT_PM$presets$p5$percentiles, c(0.10, 0.25, 0.50, 0.75, 0.90)),
      "C.2 P5 = 0.10 / 0.25 / 0.50 / 0.75 / 0.90 exactamente")
check(identical(DFIT_PM$presets$p3c$percentiles, c(0.25, 0.50, 0.75)),
      "C.3 P3c = 0.25 / 0.50 / 0.75 exactamente")
check(identical(DFIT_PM$default_preset, "p3w"),
      "C.4 el preset por defecto es P3w")
check(isTRUE(DFIT_PM$presets$p3w$recommended) &&
      !isTRUE(DFIT_PM$presets$p5$recommended) &&
      !isTRUE(DFIT_PM$presets$p3c$recommended),
      "C.5 solo P3w está marcado como recomendado")
check(identical(DFIT_PM$min_percentiles, 2L), "C.6 mínimo de 2 percentiles registrado")
check(all(vapply(DFIT_PM$presets, function(p) length(p$percentiles), 1L) >= 2L),
      "C.7 los tres presets cumplen el mínimo")
check(!is.null(DFIT_PM$presets$p3c) && identical(DFIT_PM$default_preset, "p3w"),
      "C.8 P3c sigue disponible pero NO es el default")

# El default se aplica de verdad cuando no se indican percentiles.
check(identical(.pm_fit("gamma", xg)$percentiles, DFIT_PM$presets$p3w$percentiles),
      "C.9 sin argumento, .pm_fit usa el preset por defecto")
check(identical(.estimate("gamma", xg, "pm")$pm$percentiles,
                DFIT_PM$presets$p3w$percentiles),
      "C.10 .estimate(..., 'pm') sin `pm` usa el preset por defecto")

# ------------------------------------------------------------
# D. RECUPERACIÓN SINTÉTICA POR FAMILIA
# ------------------------------------------------------------
cat("\n-- D. Recuperación sintética (parámetros finitos y plausibles) --\n")

set.seed(20260903)
n <- 2000L
u <- stats::runif(n)
casos <- list(
  list("exponential", stats::rexp(n, 0.01),                          c(rate = 0.01)),
  list("gamma",       stats::rgamma(n, shape = 2, scale = 500),      c(shape = 2, scale = 500)),
  list("weibull",     stats::rweibull(n, shape = 1.5, scale = 800),  c(shape = 1.5, scale = 800)),
  list("lognormal",   stats::rlnorm(n, 7, 1.3),                      c(meanlog = 7, sdlog = 1.3)),
  list("loglogistic", 600 * (u / (1 - u))^(1 / 2.5),                 c(shape = 2.5, scale = 600)),
  list("pareto",      1000 * ((1 - stats::runif(n))^(-1 / 2.5) - 1), c(shape = 2.5, scale = 1000)),
  list("burr",        500 * ((1 - stats::runif(n))^(-1 / 1.5) - 1)^(1 / 2),
                                                                     c(shape1 = 2, shape2 = 1.5, scale = 500)),
  list("normal",      stats::rnorm(n, 100, 15),                      c(mean = 100, sd = 15))
)

for (cs in casos) {
  id <- cs[[1]]; xx <- cs[[2]]; th <- cs[[3]]
  fx <- .pm_fit(id, xx, P3W)
  check(identical(fx$status, "success") && isTRUE(fx$converged),
        sprintf("D.%s converge", id))
  th_hat <- unlist(fx$params)
  check(all(is.finite(th_hat)), sprintf("D.%s parámetros finitos", id))
  check(identical(names(th_hat), names(th)),
        sprintf("D.%s nombres de parámetros del catálogo", id))
  pos <- DFIT_PM_POSITIVE[[id]]
  check(all(th_hat[pos] > 0), sprintf("D.%s parámetros positivos donde procede", id))
  # Plausibilidad, NO igualdad: error relativo por debajo del 50 % con n = 2000.
  # `mean` y `meanlog` son de localización: se referencian a la dispersión.
  ref <- abs(th)
  if (id == "normal")    ref["mean"]    <- th[["sd"]]
  if (id == "lognormal") ref["meanlog"] <- th[["sdlog"]]
  check(all(abs(th_hat - th) / ref < 0.5),
        sprintf("D.%s estimación plausible (error escalado < 0,5)", id))
  # Los cuantiles ajustados reproducen los empíricos de forma razonable.
  check(fx$objective < 0.5,
        sprintf("D.%s objetivo normalizado pequeño (%.2e)", id, fx$objective))
}

# ------------------------------------------------------------
# E. ESCALA
# ------------------------------------------------------------
cat("\n-- E. Equivarianza de escala --\n")

# El objetivo normalizado es invariante de escala: s_Q escala con el dato, luego
# J es adimensional. Los parámetros de escala deben escalar y los de forma no.
cte <- 1000
set.seed(20260903)
xw <- stats::rweibull(1500L, shape = 1.5, scale = 800)
a <- .pm_fit("weibull", xw, P3W)
b <- .pm_fit("weibull", xw * cte, P3W)
check(identical(a$status, "success") && identical(b$status, "success"),
      "E.1 Weibull converge en ambas escalas")
# Tolerancia 1e-3 y no precisión de máquina: la equivarianza es EXACTA en el
# objetivo, pero `optim()` aproxima el gradiente por diferencias finitas con paso
# absoluto (`ndeps`), y en la coordenada log el desplazamiento de +log(1000)
# cambia ligeramente esa aproximación. Es ruido del optimizador, no del método.
TOL <- 1e-3
check(abs(a$params$shape - b$params$shape) / a$params$shape < TOL,
      "E.2 shape es invariante de escala")
check(abs(b$params$scale - cte * a$params$scale) / (cte * a$params$scale) < TOL,
      "E.3 scale es equivariante de escala")
check(abs(b$s_Q - cte * a$s_Q) / (cte * a$s_Q) < 1e-9,
      "E.4 s_Q es equivariante de escala (exacto: no pasa por el optimizador)")
check(abs(a$objective - b$objective) <= 1e-9 + TOL * max(a$objective, b$objective),
      "E.5 el objetivo normalizado es invariante de escala (adimensional)")

# Exponencial: rate es INVERSO de la escala (rate' = rate / c).
xe <- stats::rexp(1500L, 0.01)
ea <- .pm_fit("exponential", xe, P3W)
eb <- .pm_fit("exponential", xe * cte, P3W)
check(abs(eb$params$rate - ea$params$rate / cte) / (ea$params$rate / cte) < TOL,
      "E.6 exponencial: rate' = rate / c")

# Lognormal: meanlog se DESPLAZA en log(c); sdlog no cambia.
xl <- stats::rlnorm(1500L, 7, 1.3)
la <- .pm_fit("lognormal", xl, P3W)
lb <- .pm_fit("lognormal", xl * cte, P3W)
check(abs((lb$params$meanlog - la$params$meanlog) - log(cte)) < 1e-2,
      "E.7 lognormal: meanlog' = meanlog + log(c)")
check(abs(lb$params$sdlog - la$params$sdlog) / la$params$sdlog < TOL,
      "E.8 lognormal: sdlog invariante")

# ------------------------------------------------------------
# F. WARNINGS: la ejecución normal no debe inundar la consola
# ------------------------------------------------------------
cat("\n-- F. Ruido de consola --\n")

capturados <- list()
withCallingHandlers({
  for (cs in casos) invisible(.pm_fit(cs[[1]], cs[[2]], P3W))
  # Casos que en el experimento SÍ generaban avisos espurios: Normal con media
  # cero y negativa (log() sobre el parámetro de localización) y Gamma reescalada.
  invisible(.pm_fit("normal", stats::rnorm(1000L,   0, 1),  P3W))
  invisible(.pm_fit("normal", stats::rnorm(1000L, -50, 20), P3W))
  invisible(.pm_fit("gamma",  stats::rgamma(1000L, shape = 2, scale = 500) * 1000, P3W))
}, warning = function(w) {
  capturados[[length(capturados) + 1L]] <<- conditionMessage(w)
  invokeRestart("muffleWarning")
})
if (length(capturados) > 0L) {
  cat("     avisos observados:\n")
  for (m in unique(unlist(capturados))) cat(sprintf("       - %s\n", m))
}
check(length(capturados) == 0L,
      "F.1 ningún aviso en ejecuciones válidas, incluidas Normal con mu <= 0")

# Y la guarda NO es un `suppressWarnings` encubierto: un aviso ajeno al caso
# conocido sí debe propagarse. `warner()` se pasa como argumento y R lo evalúa de
# forma perezosa DENTRO de `.pm_quantile_guarded`, es decir, dentro de la región
# protegida: si la guarda silenciara indiscriminadamente, este aviso no llegaría.
warner <- function() { warning("aviso ajeno al caso conocido"); list(shape = 2, scale = 500) }
visto <- FALSE
withCallingHandlers(
  invisible(.pm_quantile_guarded("gamma", 0.5, warner())),
  warning = function(w) { visto <<- TRUE; invokeRestart("muffleWarning") })
check(isTRUE(visto), "F.2 un aviso ajeno al caso conocido NO se silencia")
check(!any(grepl("suppressWarnings", deparse(.pm_quantile_guarded))),
      "F.3 la guarda no usa suppressWarnings()")

# ------------------------------------------------------------
# G. AISLAMIENTO: PM no toca AUTO, ranking ni recomendación
# ------------------------------------------------------------
cat("\n-- G. Aislamiento respecto de AUTO y ranking --\n")

set.seed(20260903)
df <- data.frame(coste = stats::rgamma(600L, shape = 2, scale = 500))
res <- dist_fit_analyze(df, "coste")
check(identical(res$motor$method, "mle"),
      "G.1 el análisis por defecto sigue usando MLE")
check(all(vapply(res$motor$fits, function(f) !identical(f$method, "pm"), TRUE)),
      "G.2 ningún ajuste del motor es PM")
check(inherits(try(.motor(res$sample, res$candidates, method = "pm"), silent = TRUE),
               "try-error"),
      "G.3 .motor rechaza explícitamente method = 'pm' (no entra en el ranking)")

# .fit_auto no conoce PM y no ha cambiado de comportamiento.
au <- .fit_auto("gamma", df$coste, list(id = "gamma"))
check(identical(au$method, "mle") && isTRUE(au$converged),
      "G.4 .fit_auto sigue eligiendo MLE, sin rastro de PM")

# .estimate mantiene su firma anterior: 3 argumentos posicionales siguen valiendo.
check(!is.null(.estimate("gamma", df$coste, "mle")$params),
      "G.5 .estimate(id, x, 'mle') sigue funcionando con 3 argumentos")
check(!is.null(.estimate("gamma", df$coste, "mom")$params),
      "G.6 .estimate(id, x, 'mom') intacto")

# Integración PM por la vía prevista.
e <- .estimate("gamma", df$coste, "pm", pm = DFIT_PM$presets$p5$percentiles)
check(isTRUE(e$converged) && identical(e$pm$percentiles, DFIT_PM$presets$p5$percentiles),
      "G.7 .estimate(..., 'pm', pm = P5) usa la configuración indicada")
check(is.finite(e$logLik),
      "G.8 se publica logLik por coherencia con MoM/L-momentos (no se usa en ranking)")

cat("\nB11.2 — MOTOR DE PERCENTILE MATCHING VERIFICADO\n")
