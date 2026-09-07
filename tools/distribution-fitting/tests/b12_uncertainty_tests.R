# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b12_uncertainty_tests.R
# Tests productivos de B12.2: incertidumbre analitica del MLE.
#
# Verifica el contrato congelado en ADR-033/ADR-034 y la politica numerica
# seleccionada en B12.1 (esquema A: h_j = eps^(1/4) * max(|u_j|,1), diferencias
# centrales, sin Richardson, sin numDeriv, sin optim(hessian=TRUE)).
#
# NO valida bootstrap, sesgo, MSE ni comparacion analitico-vs-bootstrap: B13-B15.
#
# TOLERANCIAS. La Hessiana numerica es una APROXIMACION: no se usa igualdad
# exacta en ningun punto. B12.1 midio, sobre las cinco familias con referencia
# analitica, un error relativo de Frobenius con mediana 9,8e-08 y p90 1,4e-06.
# Se adopta TOL_FRO = 1e-4, unas 70 veces el p90 medido: lo bastante holgado para
# no ser fragil frente al error normal de diferencias finitas, y lo bastante
# estricto para detectar una regresion real (un esquema equivocado, una
# transformacion mal declarada o un metodo delta ausente producen errores de
# orden 1e-2 o peores, entre dos y cuatro ordenes de magnitud por encima).
# Geometrica y Lognormal llevan una tolerancia algo mayor y justificada: su paso
# optimo empirico fue c* = 3,16e-4, no eps^(1/4) = 1,22e-4, de modo que el
# esquema congelado opera algo desplazado del minimo en esas dos familias.
#
# Autor: BMK — Ultima actualizacion: 2026-09-03
# ============================================================
#
#   Rscript tests/b12_uncertainty_tests.R    # desde la raiz de la herramienta
#   Rscript b12_uncertainty_tests.R          # desde la carpeta tests/

.locate_script <- function() {
  fa <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(fa) > 0) return(normalizePath(sub("^--file=", "", fa[1]), mustWork = FALSE))
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
  else stop("No se pudo localizar la raiz de la herramienta.", call. = FALSE)
})
source(file.path(.tool_root, "R", "calc.R"))

check <- function(cond, msg) {
  if (!isTRUE(cond)) stop(sprintf("FALLO: %s", msg), call. = FALSE)
  cat(sprintf("  OK  - %s\n", msg))
}
fro_rel <- function(A, B) sqrt(sum((A - B)^2)) / sqrt(sum(B^2))

TOL_FRO      <- 1e-4     # error relativo de Frobenius de J_u (~70x el p90 de B12.1)
TOL_FRO_WIDE <- 1e-3     # Geometrica y Lognormal: c* empirico != eps^(1/4)
TOL_SE       <- 1e-4     # error relativo de los SE en escala natural
N_TEST       <- 2000L

cat("== B12.2 — INCERTIDUMBRE ANALITICA DEL MLE ==\n")
cat(sprintf("   politica: h_j = %.3e * max(|u_j|,1) (eps^(1/4)); diferencias centrales\n",
            dfit_default_config()$hessian_step_c))

# ------------------------------------------------------------
# A. TRANSFORMACIONES DECLARATIVAS (OD-5)
# ------------------------------------------------------------
cat("\n-- A. Transformaciones --\n")

check(identical(names(DFIT_TRANSFORMS), c("identity", "log", "logit")),
      "A.1 el catalogo tiene exactamente identity, log y logit")

# Round-trip theta -> u -> theta en las tres transformaciones.
for (tn in names(DFIT_TRANSFORMS)) {
  tr <- DFIT_TRANSFORMS[[tn]]
  vals <- switch(tn,
                 identity = c(-1e4, -1, 0, 1, 1e4),
                 log      = c(1e-6, 0.5, 1, 1e3, 1e6),
                 logit    = c(1e-4, 0.1, 0.5, 0.9, 0.9999))
  back <- vapply(vals, function(v) tr$to_theta(tr$to_u(v)), 0)
  check(max(abs(back - vals) / pmax(abs(vals), 1e-12)) < 1e-10,
        sprintf("A.2 %-8s round-trip theta -> u -> theta", tn))
}

# Derivadas de la inversa, contrastadas contra diferencia central independiente.
num_d <- function(tr, t0) {
  u0 <- tr$to_u(t0); h <- 1e-6 * max(abs(u0), 1)
  (tr$to_theta(u0 + h) - tr$to_theta(u0 - h)) / (2 * h)
}
for (tn in names(DFIT_TRANSFORMS)) {
  tr <- DFIT_TRANSFORMS[[tn]]
  t0 <- switch(tn, identity = 3.5, log = 250, logit = 0.3)
  check(abs(tr$dtheta_du(t0) - num_d(tr, t0)) / abs(tr$dtheta_du(t0)) < 1e-6,
        sprintf("A.3 %-8s d theta/du coincide con la derivada numerica", tn))
}
check(abs(DFIT_TRANSFORMS$log$dtheta_du(250) - 250) < 1e-12,
      "A.4 log:   d theta/du = theta")
check(abs(DFIT_TRANSFORMS$logit$dtheta_du(0.3) - 0.3 * 0.7) < 1e-12,
      "A.5 logit: d theta/du = p(1-p)")
check(DFIT_TRANSFORMS$identity$dtheta_du(99) == 1,
      "A.6 identity: d theta/du = 1")

# La tabla cubre las 11 distribuciones del catalogo, con nombres y orden exactos.
check(setequal(names(DFIT_PARAM_TRANSFORM), names(DFIT_MLE)),
      "A.7 DFIT_PARAM_TRANSFORM cubre exactamente las distribuciones de DFIT_MLE")
check(all(unlist(DFIT_PARAM_TRANSFORM) %in% names(DFIT_TRANSFORMS)),
      "A.8 toda transformacion declarada existe en el catalogo")
check(identical(unname(DFIT_PARAM_TRANSFORM$normal), c("identity", "log")) &&
      identical(names(DFIT_PARAM_TRANSFORM$normal), c("mean", "sd")),
      "A.9 normal: mean identity, sd log")
check(identical(unname(DFIT_PARAM_TRANSFORM$lognormal), c("identity", "log")),
      "A.10 lognormal: meanlog identity, sdlog log")
check(identical(unname(DFIT_PARAM_TRANSFORM$geometric), "logit"),
      "A.11 geometric: prob logit (NO log: log no acota p por arriba)")
check(all(unlist(DFIT_PARAM_TRANSFORM[c("gamma","weibull","loglogistic","pareto","burr",
                                        "exponential","poisson","negative_binomial")]) == "log"),
      "A.12 el resto de parametros son positivos y van en log")

# Coherencia con el registro de PM: mismos nombres y mismo orden en las 8 comunes.
for (idc in names(DFIT_PM_PARAMS)) {
  check(identical(.dfit_param_names(idc), DFIT_PM_PARAMS[[idc]]),
        sprintf("A.13 %-12s nombres/orden coinciden con DFIT_PM_PARAMS", idc))
}

# Vectorizacion por distribucion.
th <- c(shape = 2, scale = 500)
u  <- .dfit_to_u("gamma", th)
check(identical(names(u), c("shape", "scale")) &&
      max(abs(.dfit_to_theta("gamma", u) - th)) < 1e-9,
      "A.14 round-trip vectorizado por distribucion, con nombres")
check(max(abs(.dfit_dtheta_du("gamma", th) - th)) < 1e-12,
      "A.15 G para gamma = (shape, scale)")

# ------------------------------------------------------------
# B. HESSIANA FRENTE A REFERENCIAS ANALITICAS
# ------------------------------------------------------------
cat("\n-- B. Informacion observada frente a referencia analitica --\n")
cat("     (comparacion CON TOLERANCIA: la Hessiana numerica es una aproximacion)\n")

set.seed(20260903)
n <- N_TEST

# --- Exponential: u = log(rate), J_u = n  (independiente de los datos) ---
xe <- stats::rexp(n, 0.01)
fe <- .estimate("exponential", xe, "mle")
oe <- .observed_information("exponential", xe, fe$params)
check(isTRUE(oe$valid), "B.1 exponential: informacion observada valida")
check(fro_rel(oe$J_u, matrix(n, 1, 1)) < TOL_FRO,
      sprintf("B.2 exponential: J_u ~ n = %d (err Fro %.2e)", n,
              fro_rel(oe$J_u, matrix(n, 1, 1))))

# --- Poisson: u = log(lambda), J_u = n * lambda_hat ---
xp <- stats::rpois(n, 4)
fp <- .estimate("poisson", xp, "mle")
op <- .observed_information("poisson", xp, fp$params)
Jp_ref <- matrix(n * fp$params$lambda, 1, 1)
check(isTRUE(op$valid) && fro_rel(op$J_u, Jp_ref) < TOL_FRO,
      sprintf("B.3 poisson: J_u ~ n*lambda_hat (err Fro %.2e)", fro_rel(op$J_u, Jp_ref)))

# --- Geometric: soporte {0,1,2,...}, p_hat = 1/(1+mean), u = logit(p),
#     J_u = n * (1 - p_hat) ---
xg <- stats::rgeom(n, 0.3)
fg <- .estimate("geometric", xg, "mle")
og <- .observed_information("geometric", xg, fg$params)
Jg_ref <- matrix(n * (1 - fg$params$prob), 1, 1)
check(abs(fg$params$prob - 1 / (1 + mean(xg))) < 1e-12,
      "B.4 geometric: p_hat = 1/(1+mean(x)), como en .mle_geometric()")
check(isTRUE(og$valid) && fro_rel(og$J_u, Jg_ref) < TOL_FRO_WIDE,
      sprintf("B.5 geometric: J_u ~ n(1-p_hat) en escala logit (err Fro %.2e)",
              fro_rel(og$J_u, Jg_ref)))

# --- Normal: u = (mean, log(sd)), J_u = diag(n/sd^2, 2n) ---
xn <- stats::rnorm(n, 100, 15)
fn <- .estimate("normal", xn, "mle")
on <- .observed_information("normal", xn, fn$params)
sdh <- fn$params$sd
Jn_ref <- diag(c(n / sdh^2, 2 * n))
check(isTRUE(on$valid) && fro_rel(on$J_u, Jn_ref) < TOL_FRO,
      sprintf("B.6 normal: J_u ~ diag(n/sd^2, 2n) (err Fro %.2e)",
              fro_rel(on$J_u, Jn_ref)))
# La off-diagonal es EXACTAMENTE 0 en el MLE: referencia cero -> error ABSOLUTO,
# escalado a la magnitud de la propia matriz. Un error relativo no tendria sentido.
check(abs(on$J_u[1, 2]) <= 1e-6 * max(abs(on$J_u)),
      sprintf("B.7 normal: off-diagonal ~ 0 en el MLE (|J[1,2]| = %.3e)", abs(on$J_u[1, 2])))

# --- Lognormal: identico sobre log(x) ---
xl <- stats::rlnorm(n, 7, 1.3)
fl <- .estimate("lognormal", xl, "mle")
ol <- .observed_information("lognormal", xl, fl$params)
sl <- fl$params$sdlog
Jl_ref <- diag(c(n / sl^2, 2 * n))
check(isTRUE(ol$valid) && fro_rel(ol$J_u, Jl_ref) < TOL_FRO_WIDE,
      sprintf("B.8 lognormal: J_u ~ diag(n/sdlog^2, 2n) (err Fro %.2e)",
              fro_rel(ol$J_u, Jl_ref)))
check(abs(ol$J_u[1, 2]) <= 1e-6 * max(abs(ol$J_u)),
      "B.9 lognormal: off-diagonal ~ 0 en el MLE")

# Simetria por construccion y diagnosticos presentes.
for (o in list(oe, op, og, on, ol)) {
  check(o$asym == 0, "B.10 asimetria EXACTAMENTE 0 (formula cruzada simetrica por construccion)")
}
check(on$n_eval == 2 * 2 + 1 + 4, "B.11 normal (k=2): 9 evaluaciones de logLik")
check(oe$n_eval == 3L,            "B.12 exponential (k=1): 3 evaluaciones")
check(is.finite(on$rcond) && is.finite(on$eig_min) && is.finite(on$eig_max),
      "B.13 rcond y autovalores extremos publicados como diagnostico")
h_esperado <- dfit_default_config()$hessian_step_c * max(abs(on$u_hat[1]), 1)
check(abs(on$step[[1]] - h_esperado) / h_esperado < 1e-12,
      "B.14 el paso sigue h_j = c * max(|u_j|,1) en escala u")

# ------------------------------------------------------------
# C. COVARIANZA, SE Y METODO DELTA (OD-5)
# ------------------------------------------------------------
cat("\n-- C. Covarianza y errores estandar --\n")

mk_fit <- function(id, est) c(list(id = id, method = "mle", converged = TRUE,
                                   message = NA_character_), est)

ue <- .mle_uncertainty(mk_fit("exponential", fe), xe)
check(isTRUE(ue$valid), "C.1 exponential: inferencia valida")
check(abs(ue$se_theta[["rate"]] - fe$params$rate / sqrt(n)) /
      (fe$params$rate / sqrt(n)) < TOL_SE,
      "C.2 exponential: Var(rate_hat) ~ rate^2/n tras el delta")

up <- .mle_uncertainty(mk_fit("poisson", fp), xp)
check(abs(up$se_theta[["lambda"]] - sqrt(fp$params$lambda / n)) /
      sqrt(fp$params$lambda / n) < TOL_SE,
      "C.3 poisson: Var(lambda_hat) ~ lambda/n")

ug <- .mle_uncertainty(mk_fit("geometric", fg), xg)
ph <- fg$params$prob
check(abs(ug$se_theta[["prob"]] - sqrt(ph^2 * (1 - ph) / n)) /
      sqrt(ph^2 * (1 - ph) / n) < TOL_FRO_WIDE,
      "C.4 geometric: Var(p_hat) ~ p^2(1-p)/n tras el delta desde logit")

un <- .mle_uncertainty(mk_fit("normal", fn), xn)
check(abs(un$se_theta[["mean"]] - sdh / sqrt(n)) / (sdh / sqrt(n)) < TOL_SE,
      "C.5 normal: Var(mean_hat) ~ sd^2/n")
check(abs(un$se_theta[["sd"]] - sdh / sqrt(2 * n)) / (sdh / sqrt(2 * n)) < TOL_SE,
      "C.6 normal: Var(sd_hat) ~ sd^2/(2n)  <- VALIDACION DEL METODO DELTA")
check(abs(un$se_u[["sd"]] - 1 / sqrt(2 * n)) / (1 / sqrt(2 * n)) < TOL_SE,
      "C.7 normal: Var(log sd_hat) ~ 1/(2n) en escala u  <- VALIDACION DE OD-5")
check(abs(un$se_u[["mean"]] - un$se_theta[["mean"]]) < 1e-12,
      "C.8 normal: para `mean` (identity) se_u == se_theta")

ul <- .mle_uncertainty(mk_fit("lognormal", fl), xl)
check(abs(ul$se_theta[["sdlog"]] - sl / sqrt(2 * n)) / (sl / sqrt(2 * n)) < TOL_FRO_WIDE,
      "C.9 lognormal: Var(sdlog_hat) ~ sdlog^2/(2n)")
check(abs(ul$se_u[["sdlog"]] - 1 / sqrt(2 * n)) / (1 / sqrt(2 * n)) < TOL_FRO_WIDE,
      "C.10 lognormal: Var(log sdlog_hat) ~ 1/(2n)")

# Coherencia interna: Sigma_theta = G Sigma_u G' recalculado aparte.
G <- diag(as.numeric(.dfit_dtheta_du("normal", unlist(fn$params))), nrow = 2)
check(max(abs(un$covariance_theta - G %*% un$covariance_u %*% t(G))) < 1e-12,
      "C.11 Sigma_theta == G Sigma_u G' (recalculado independientemente)")
check(all(is.finite(un$covariance_u)) && all(diag(un$covariance_theta) > 0),
      "C.12 covarianzas finitas y diagonal natural positiva")
check(all(un$se_theta > 0) && all(un$se_u > 0), "C.13 todos los SE positivos")

# ------------------------------------------------------------
# D. INTERVALOS DE CONFIANZA (OD-16)
# ------------------------------------------------------------
cat("\n-- D. Intervalos de confianza en escala transformada --\n")

check(abs(un$confidence_level - 0.95) < 1e-12, "D.1 nivel por defecto = 95 %")
check(abs(un$z - stats::qnorm(0.975)) < 1e-12, "D.2 z = qnorm(1 - alpha/2)")

# identity -> Wald habitual, simetrico.
pm_ <- un$parameters$mean
check(abs((pm_$ci_lower + pm_$ci_upper) / 2 - pm_$estimate) < 1e-9,
      "D.3 identity (mean): intervalo simetrico y centrado en la estimacion")
check(abs(pm_$ci_upper - (pm_$estimate + un$z * pm_$se)) < 1e-9,
      "D.4 identity (mean): coincide con theta_hat +/- z*SE")

# log -> estrictamente positivo y ASIMETRICO en escala natural.
ps_ <- un$parameters$sd
check(ps_$ci_lower > 0, "D.5 log (sd): extremo inferior estrictamente positivo")
check(ps_$ci_lower < ps_$estimate && ps_$estimate < ps_$ci_upper,
      "D.6 log (sd): la estimacion cae dentro del intervalo")
check(abs((ps_$ci_lower + ps_$ci_upper) / 2 - ps_$estimate) > 1e-12,
      "D.7 log (sd): intervalo ASIMETRICO en escala natural, como debe ser")
check(abs(ps_$ci_lower - exp(ps_$ci_lower_u)) < 1e-12 &&
      abs(ps_$ci_upper - exp(ps_$ci_upper_u)) < 1e-12,
      "D.8 log (sd): CI_theta = exp(CI_u), retrotransformacion monotona")

# logit -> estrictamente dentro de (0,1), SIN truncar.
pg_ <- ug$parameters$prob
check(pg_$ci_lower > 0 && pg_$ci_upper < 1,
      "D.9 logit (prob): intervalo estrictamente dentro de (0,1)")
check(abs(pg_$ci_lower - 1 / (1 + exp(-pg_$ci_lower_u))) < 1e-12,
      "D.10 logit (prob): CI_theta = expit(CI_u), sin truncado posterior")

# Caso donde el Wald natural ingenuo SI se saldria del soporte: p_hat alto.
set.seed(20260903)
xg2 <- stats::rgeom(60L, 0.9)
fg2 <- .estimate("geometric", xg2, "mle")
if (isTRUE(fg2$converged) && fg2$params$prob < 1) {
  ug2 <- .mle_uncertainty(mk_fit("geometric", fg2), xg2)
  if (isTRUE(ug2$valid)) {
    q <- ug2$parameters$prob
    naive_hi <- q$estimate + ug2$z * q$se
    check(q$ci_upper < 1,
          sprintf("D.11 logit protege el soporte: CI_sup = %.6f < 1 (Wald natural daria %.6f)",
                  q$ci_upper, naive_hi))
  }
}

# Nivel de confianza manual.
un90 <- .mle_uncertainty(mk_fit("normal", fn), xn, confidence_level = 0.90)
un99 <- .mle_uncertainty(mk_fit("normal", fn), xn, confidence_level = 0.99)
check(abs(un90$z - stats::qnorm(0.95)) < 1e-12, "D.12 nivel manual 90 % -> z correcto")
w <- function(o, p) o$parameters[[p]]$ci_upper - o$parameters[[p]]$ci_lower
check(w(un90, "mean") < w(un, "mean") && w(un, "mean") < w(un99, "mean"),
      "D.13 la amplitud crece con el nivel de confianza (90 < 95 < 99)")
check(abs(un99$se_theta[["mean"]] - un$se_theta[["mean"]]) < 1e-15,
      "D.14 el SE no depende del nivel de confianza")

# ------------------------------------------------------------
# E. FALLOS ESTRUCTURALES: nunca un SE aparente
# ------------------------------------------------------------
cat("\n-- E. Fallos estructurales --\n")

# Estencil no finito: Gamma con un cero en la muestra -> logLik = -Inf.
xz <- c(0, stats::rgamma(500L, shape = 2, scale = 500))
oz <- .observed_information("gamma", xz, list(shape = 2, scale = 500))
check(!isTRUE(oz$valid) && is.null(oz$J_u),
      "E.1 logLik no finita en theta_hat -> invalida, sin matriz")
check(grepl("no es finita|no finita", oz$reason), "E.2 el motivo es auditable")

# Matriz no definida positiva.
np <- .validate_information(matrix(c(1, 0, 0, -1), 2, 2), "normal", c(mean = 1, sd = 2))
check(!np$valid && grepl("definida positiva", np$reason) && is.null(np$se_theta),
      "E.3 matriz no PD -> reject via Cholesky, sin SE")

# Matriz singular.
sg <- .validate_information(matrix(c(1, 1, 1, 1), 2, 2), "normal", c(mean = 1, sd = 2))
check(!sg$valid && is.null(sg$se_theta),
      "E.4 matriz singular -> reject, sin SE (sin pseudoinversa)")

# Dimensiones incorrectas.
dm <- .validate_information(matrix(1, 1, 1), "normal", c(mean = 1, sd = 2))
check(!dm$valid && grepl("dimensiones", dm$reason), "E.5 dimensiones incorrectas -> reject")

# Elementos no finitos.
nf <- .validate_information(matrix(c(1, 0, 0, NA), 2, 2), "normal", c(mean = 1, sd = 2))
check(!nf$valid && grepl("no finitos", nf$reason), "E.6 elementos no finitos -> reject")

# Asimetria por encima de la tolerancia.
as_ <- .validate_information(matrix(c(10, 1, 5, 10), 2, 2), "normal", c(mean = 1, sd = 2))
check(!as_$valid && grepl("sim.tric", as_$reason), "E.7 asimetria -> reject")

# Metodo distinto de MLE. (Las comprobaciones de texto usan `.` en lugar de la
# vocal acentuada para no depender de la codificacion del fichero.)
xmom <- stats::rgamma(300L, shape = 2, scale = 500)
u_mom <- .mle_uncertainty(c(list(id = "gamma", method = "mom", converged = TRUE),
                            .estimate("gamma", xmom, "mom")), xmom)
check(!u_mom$valid && identical(u_mom$status, "not_available") &&
      grepl("solo cubre el MLE", u_mom$reason) && length(u_mom$parameters) == 0L,
      "E.8 metodo 'mom' -> no disponible, sin parametros ni SE")

# PM tambien queda fuera, por la misma via.
xpm <- stats::rgamma(400L, shape = 2, scale = 500)
u_pm <- .mle_uncertainty(list(id = "gamma", method = "pm", converged = TRUE,
                              params = .pm_fit("gamma", xpm)$params), xpm)
check(!u_pm$valid && identical(u_pm$status, "not_available"),
      "E.9 metodo 'pm' -> no disponible (theta_PM no anula el score)")

# Ajuste no convergido.
u_nc <- .mle_uncertainty(list(id = "normal", method = "mle", converged = FALSE,
                              params = list(mean = 1, sd = 2),
                              message = "optimo en la frontera numerica"), xn)
check(!u_nc$valid && grepl("frontera", u_nc$reason),
      "E.10 ajuste rechazado por ADR-027 -> no disponible, propagando el motivo")

# params ausentes.
u_np <- .mle_uncertainty(list(id = "normal", method = "mle", converged = TRUE,
                              params = NULL), xn)
check(!u_np$valid && grepl("par.metros", u_np$reason),
      "E.11 params NULL -> no disponible")

# Nivel de confianza invalido.
for (bad in list(0, 1, 1.5, -0.1, NA_real_, NaN, Inf, "0.95", c(0.9, 0.95))) {
  r <- .mle_uncertainty(mk_fit("normal", fn), xn, confidence_level = bad)
  check(!r$valid && identical(r$status, "failed") && length(r$parameters) == 0L,
        sprintf("E.12 confidence_level invalido (%s) -> failed sin CI",
                paste(format(bad), collapse = ",")))
}
check(is.null(.ci_from_transformed_scale("normal", c(1, 2), c(0.1, 0.1), 1.2)),
      "E.13 .ci_from_transformed_scale rechaza un nivel invalido")

# Distribucion sin transformacion declarada.
u_un <- .mle_uncertainty(list(id = "inexistente", method = "mle", converged = TRUE,
                              params = list(a = 1)), xn)
check(!u_un$valid && grepl("transformaci.n", u_un$reason),
      "E.14 distribucion sin transformacion declarada -> no disponible")

# ------------------------------------------------------------
# F. RESTO DE FAMILIAS CONTINUAS
# ------------------------------------------------------------
cat("\n-- F. Gamma, Weibull, Loglogistica, Pareto, Burr --\n")

set.seed(20260903)
u_ <- stats::runif(N_TEST)
fam <- list(
  list("gamma",       stats::rgamma(N_TEST, shape = 2, scale = 500)),
  list("weibull",     stats::rweibull(N_TEST, shape = 1.5, scale = 800)),
  list("loglogistic", 600 * (u_ / (1 - u_))^(1 / 2.5)),
  list("pareto",      1000 * ((1 - stats::runif(N_TEST))^(-1 / 2.5) - 1)),
  list("burr",        500 * ((1 - stats::runif(N_TEST))^(-1 / 1.5) - 1)^(1 / 2))
)
for (cs in fam) {
  id <- cs[[1]]; xx <- cs[[2]]
  ft <- .estimate(id, xx, "mle")
  check(!is.null(ft) && isTRUE(ft$converged), sprintf("F.%s el MLE converge", id))
  uu <- .mle_uncertainty(mk_fit(id, ft), xx)
  check(isTRUE(uu$valid), sprintf("F.%s inferencia valida (%s)", id,
                                  if (isTRUE(uu$valid)) "ok" else uu$reason))
  check(all(is.finite(uu$observed_information)), sprintf("F.%s J_u finita", id))
  check(isTRUE(uu$diagnostics$chol_ok),          sprintf("F.%s Cholesky OK (PD)", id))
  check(uu$diagnostics$asym == 0,                sprintf("F.%s asimetria 0", id))
  check(all(uu$se_theta > 0) && all(is.finite(uu$se_theta)),
        sprintf("F.%s SE positivos y finitos", id))
  for (p in uu$parameters) {
    check(p$ci_lower > 0 && p$ci_lower < p$estimate && p$estimate < p$ci_upper,
          sprintf("F.%s %-7s CI positivo y conteniendo la estimacion", id, p$name))
  }
  check(is.finite(uu$diagnostics$rcond),
        sprintf("F.%s rcond publicado (%.2e) SIN umbral de rechazo", id,
                uu$diagnostics$rcond))
}

# ------------------------------------------------------------
# G. BINOMIAL NEGATIVA — test ESTRUCTURAL (sin verdad analitica)
# ------------------------------------------------------------
cat("\n-- G. Binomial negativa: validacion ESTRUCTURAL, no contra forma cerrada --\n")
cat("     B12.1 no derivo referencia cerrada: la informacion respecto de `size`\n")
cat("     involucra E[trigamma(x + size)], sin forma cerrada elemental. NO se\n")
cat("     inventa ground truth; se comprueba unicamente la estructura.\n")

set.seed(20260903)
nb_sc <- list(list("disp_moderada", 3, 10), list("disp_alta", 0.8, 25))
for (s in nb_sc) {
  lab <- s[[1]]
  xnb <- stats::rnbinom(N_TEST, size = s[[2]], mu = s[[3]])
  fnb <- .estimate("negative_binomial", xnb, "mle")
  check(!is.null(fnb) && isTRUE(fnb$converged),
        sprintf("G.%s el MLE converge", lab))
  check(identical(.dfit_param_names("negative_binomial"), c("size", "mu")) &&
        all(unname(DFIT_PARAM_TRANSFORM$negative_binomial) == "log"),
        sprintf("G.%s parametrizacion (size, mu), ambas en log", lab))
  unb <- .mle_uncertainty(mk_fit("negative_binomial", fnb), xnb)
  check(isTRUE(unb$valid), sprintf("G.%s inferencia valida (%s)", lab,
                                   if (isTRUE(unb$valid)) "ok" else unb$reason))
  check(all(is.finite(unb$observed_information)), sprintf("G.%s J_u finita", lab))
  check(unb$diagnostics$asym == 0,                sprintf("G.%s simetrica", lab))
  check(isTRUE(unb$diagnostics$chol_ok),          sprintf("G.%s Cholesky OK", lab))
  check(all(is.finite(unb$covariance_theta)),     sprintf("G.%s Sigma finita", lab))
  check(all(unb$se_theta > 0),                    sprintf("G.%s SE positivos", lab))
  for (p in unb$parameters)
    check(p$ci_lower > 0 && p$ci_upper > p$ci_lower,
          sprintf("G.%s %-5s CI estrictamente positivo", lab, p$name))
}

# ------------------------------------------------------------
# H. AISLAMIENTO
# ------------------------------------------------------------
cat("\n-- H. Aislamiento: nada de lo anterior cambia --\n")

set.seed(20260903)
df <- data.frame(coste = stats::rgamma(600L, shape = 2, scale = 500))
res <- dist_fit_analyze(df, "coste")
check(identical(res$motor$method, "mle"), "H.1 el analisis por defecto sigue en MLE")
check(all(vapply(res$motor$fits, function(f) is.null(f$inference), TRUE)),
      "H.2 sin `inference` por defecto: el contrato serializado NO cambia")
check(identical(res$meta$decision_engine_version, res$decision_engine$version),
      "H.3 Decision Engine intacto")
check(!is.null(res$assessment) && !is.null(res$diagnostics),
      "H.4 Assessment y Diagnostics presentes e intactos")

# Opt-in: cuando se pide, aparece como capa HERMANA de params.
mo <- .motor(res$sample, res$candidates, method = "mle", inference = TRUE)
check(!is.null(mo$fits$gamma$inference) &&
      identical(mo$fits$gamma$inference$method, "analytic_mle"),
      "H.5 con inference = TRUE aparece fit$inference")
check(identical(mo$fits$gamma$params, res$motor$fits$gamma$params),
      "H.6 fit$params NO cambia de significado ni de valor")
check(identical(mo$fits$gamma$logLik, res$motor$fits$gamma$logLik) &&
      identical(mo$fits$gamma$converged, res$motor$fits$gamma$converged),
      "H.7 logLik, converged y method intactos")

# PM intacto.
check(isTRUE(DFIT_PM$available) && identical(DFIT_PM$default_preset, "p3w"),
      "H.8 registro PM intacto")
check(identical(.pm_fit("gamma", df$coste)$status, "success"),
      "H.9 .pm_fit sigue funcionando")
check(inherits(try(.motor(res$sample, res$candidates, method = "pm"), silent = TRUE),
               "try-error"),
      "H.10 .motor sigue rechazando method = 'pm'")

# .estimate y .fit_auto sin cambios.
check(!is.null(.estimate("gamma", df$coste, "mle")$params),
      "H.11 .estimate(id, x, 'mle') con 3 argumentos posicionales")
check(identical(.fit_auto("gamma", df$coste, list(id = "gamma"))$method, "mle"),
      "H.12 .fit_auto intacto")

# ------------------------------------------------------------
# I. AVISOS
# ------------------------------------------------------------
cat("\n-- I. Avisos --\n")
# Los ajustes MLE se calculan FUERA de la captura: cualquier aviso del optimizador
# es anterior a B12.2 y no debe atribuirsele. Aqui se mide EXCLUSIVAMENTE el ruido
# de consola de la inferencia analitica.
fits_i <- lapply(fam, function(cs) mk_fit(cs[[1]], .estimate(cs[[1]], cs[[2]], "mle")))
cap <- list()
withCallingHandlers({
  for (i in seq_along(fam)) invisible(.mle_uncertainty(fits_i[[i]], fam[[i]][[2]]))
  invisible(.mle_uncertainty(mk_fit("normal", fn), xn))
  invisible(.mle_uncertainty(mk_fit("geometric", fg), xg))
  invisible(.mle_uncertainty(mk_fit("lognormal", fl), xl))
  invisible(.mle_uncertainty(mk_fit("exponential", fe), xe))
  invisible(.mle_uncertainty(mk_fit("poisson", fp), xp))
}, warning = function(w) { cap[[length(cap) + 1L]] <<- conditionMessage(w)
                           invokeRestart("muffleWarning") })
if (length(cap) > 0L) {
  cat("     avisos observados (CLASIFICAR, no silenciar):\n")
  for (m in unique(unlist(cap))) cat(sprintf("       - %s\n", m))
}
check(length(cap) == 0L, "I.1 ninguna aviso en el camino nominal de B12.2")
check(!any(grepl("suppressWarnings", deparse(.observed_information))),
      "I.2 .observed_information no usa suppressWarnings")
check(!any(grepl("1e10|penal", deparse(.observed_information))),
      "I.3 la Hessiana no usa penalizacion artificial")

cat("\nB12.2 — INCERTIDUMBRE ANALITICA DEL MLE VERIFICADA\n")
