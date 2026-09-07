# ============================================================
# Tool-02 (distribution-fitting) — B12.1
# Archivo: experiments/b12_observed_information_benchmark.R
#
# NUMERICAL OBSERVED-INFORMATION BENCHMARK.
#
# PREGUNTA EXPERIMENTAL, unica:
#   Que esquema de diferencias finitas y que regla de paso aproximan la MATRIZ DE
#   INFORMACION OBSERVADA  J(theta_hat) = -Hess l(theta_hat)  con precision y
#   estabilidad suficientes para las parametrizaciones REALES de Tool-02?
#
# ESTE SCRIPT NO ES PRODUCCION. No modifica R/calc.R ni ningun archivo productivo:
# solo lo carga (source) para reutilizar el catalogo y los estimadores MLE.
#
# ------------------------------------------------------------
# MARCO (OD-5, propuesto en docs/tool02_mle_uncertainty.md)
# ------------------------------------------------------------
#   u = T(theta)  declarativo POR PARAMETRO (no "todos positivos")
#   f(u) = -l(T^{-1}(u))          <- se deriva ESTA funcion
#   J_u  = Hess_u f  evaluada en u_hat = T(theta_hat)
#   Sigma_u = J_u^{-1}
#   Sigma_theta = G Sigma_u G'    con G = diag(d theta_j / d u_j) en u_hat
#   SE_j = sqrt(Sigma_theta[j,j])
#
# INDEPENDIENTE DEL OPTIMIZADOR: se deriva la log-verosimilitud alrededor de
# theta_hat, venga de formula cerrada (Normal, Lognormal, Exponencial, Poisson,
# Geometrica) o de optim() (Gamma, Weibull, Loglogistica, Pareto, Burr). NO se
# usa optim(hessian = TRUE).
#
# ------------------------------------------------------------
# EVALUACIONES INVALIDAS: criterio DISTINTO al del optimizador
# ------------------------------------------------------------
# En una funcion OBJETIVO, sustituir una evaluacion no finita por una penalizacion
# grande es correcto: solo dice "no vayas ahi". En una estimacion de DERIVADA es
# inadmisible: la penalizacion inventaria una curvatura enorme y produciria un SE
# con apariencia de validez. Por tanto: si CUALQUIER punto del estencil no es
# finito, la entrada de la Hessiana se marca invalida y la matriz entera se
# rechaza con motivo. Nunca se penaliza, nunca se rellena.
#
# Uso:    Rscript tools/distribution-fitting/experiments/b12_observed_information_benchmark.R
# Salidas (experiments/results/):
#   b12_reference_cases.csv   escalares por caso con referencia analitica
#   b12_reference_entries.csv entrada a entrada de J_u frente a la referencia
#   b12_step_sensitivity.csv  barrido de paso
#   b12_stress_cases.csv      familias sin referencia cerrada
#   b12_warnings.csv          avisos capturados y clasificados
# Autor: BMK — 2026-09-03
# ============================================================

# ------------------------------------------------------------ localizacion
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
source(file.path(.tool_root, "R", "calc.R"))     # SOLO lectura: no se modifica

OUTDIR <- file.path(.tool_root, "experiments", "results")
dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)

MASTER_SEED <- 20260903L
EPS <- .Machine$double.eps

cat("R:", R.version.string, "|", R.version$platform, "\n")
cat("B12.1 — Numerical Observed-Information Benchmark\n")
cat("eps =", format(EPS, digits = 6),
    "| eps^(1/4) =", format(EPS^(1/4), digits = 4),
    "| eps^(1/3) =", format(EPS^(1/3), digits = 4), "\n\n")

# ============================================================
# 1. TRANSFORMACIONES DECLARATIVAS POR PARAMETRO (OD-5)
# ============================================================
# NO se asume que todos los parametros sean positivos. `prob` de la Geometrica
# vive en (0,1) y exige LOGIT: log() no la acota superiormente y permitiria
# p_hat > 1. `mean` y `meanlog` son libres y NO se transforman.
TRANSFORM <- list(
  identity = list(
    to_u      = function(t) t,
    to_theta  = function(u) u,
    dtheta_du = function(t) rep(1, length(t))          # d theta / d u = 1
  ),
  log = list(
    to_u      = function(t) log(t),
    to_theta  = function(u) exp(u),
    dtheta_du = function(t) t                          # d theta / d u = theta
  ),
  logit = list(
    to_u      = function(t) log(t / (1 - t)),
    to_theta  = function(u) 1 / (1 + exp(-u)),
    dtheta_du = function(t) t * (1 - t)                # d theta / d u = p(1-p)
  )
)

# Tabla DFIT_PARAM_TRANSFORM (propuesta; NO implementada en produccion).
# Los nombres son EXACTAMENTE los que devuelven los `.mle_*` de R/calc.R.
PARAM_TRANSFORM <- list(
  exponential       = c(rate = "log"),
  gamma             = c(shape = "log", scale = "log"),
  weibull           = c(shape = "log", scale = "log"),
  lognormal         = c(meanlog = "identity", sdlog = "log"),
  loglogistic       = c(shape = "log", scale = "log"),
  pareto            = c(shape = "log", scale = "log"),
  burr              = c(shape1 = "log", shape2 = "log", scale = "log"),
  normal            = c(mean = "identity", sd = "log"),
  poisson           = c(lambda = "log"),
  geometric         = c(prob = "logit"),
  negative_binomial = c(size = "log", mu = "log")
)

to_u_vec <- function(id, theta) {
  tr <- PARAM_TRANSFORM[[id]]
  vapply(seq_along(theta), function(j) TRANSFORM[[tr[[j]]]]$to_u(theta[[j]]), 0)
}
to_theta_vec <- function(id, u) {
  tr <- PARAM_TRANSFORM[[id]]
  vapply(seq_along(u), function(j) TRANSFORM[[tr[[j]]]]$to_theta(u[[j]]), 0)
}
G_diag <- function(id, theta) {     # jacobiano diagonal d theta / d u en theta_hat
  tr <- PARAM_TRANSFORM[[id]]
  vapply(seq_along(theta), function(j) TRANSFORM[[tr[[j]]]]$dtheta_du(theta[[j]]), 0)
}

# ============================================================
# 2. REGISTRO DE AVISOS (sin suppressWarnings global)
# ============================================================
WLOG <- new.env(parent = emptyenv()); WLOG$rows <- list()
CTX  <- new.env(parent = emptyenv())
CTX$dist <- CTX$scenario <- CTX$scheme <- CTX$where <- NA_character_
CTX$n <- NA_integer_; CTX$point <- NA_character_

w_record <- function(w) {
  WLOG$rows[[length(WLOG$rows) + 1L]] <- data.frame(
    dist = CTX$dist, scenario = CTX$scenario, n = CTX$n, scheme = CTX$scheme,
    where = CTX$where, point = CTX$point,
    message = conditionMessage(w),
    call = paste(deparse(conditionCall(w)), collapse = " "),
    stringsAsFactors = FALSE)
}

# ============================================================
# 3. OBJETIVO f(u) = -l(theta(u))  y ESQUEMAS DE DIFERENCIAS
# ============================================================
# `.dist_loglik()` es la fuente unica de log-verosimilitud (la misma que usa el
# motor). Devuelve NA si la evaluacion no es finita: NO se penaliza.
make_f <- function(id, x) {
  function(u) {
    CTX$point <- paste(signif(u, 8), collapse = ",")
    th <- to_theta_vec(id, u)
    if (any(!is.finite(th))) return(NA_real_)
    v <- tryCatch(-.dist_loglik(id, x, stats::setNames(as.list(th), names(PARAM_TRANSFORM[[id]]))),
                  error = function(e) NA_real_)
    if (is.finite(v)) v else NA_real_
  }
}

# Reglas de paso comparadas. Se escriben explicitamente para poder auditarlas.
#
#   h_j = c * max(|u_j|, 1)
#
# El paso es RELATIVO A LA COORDENADA u, no a theta: es lo que hace que la regla
# no dependa de la magnitud de los datos (una escala de 1e3 en theta es un
# desplazamiento aditivo en log theta).
#
#   A  c = eps^(1/4) ~ 1,22e-4   optimo teorico para SEGUNDAS derivadas por
#                                diferencias centrales: truncamiento ~ h^2 f'''',
#                                redondeo ~ eps|f|/h^2, balance en h ~ eps^(1/4).
#   B  c = eps^(1/3) ~ 6,06e-6   optimo teorico para PRIMERAS derivadas. Se
#                                incluye como CONTRASTE: la hipotesis es que aqui
#                                sea peor por dominancia del redondeo.
#   C  Richardson sobre A con h y h/2: J_R = (4*J(h/2) - J(h))/3, que cancela el
#                                termino O(h^2). Coste 2x. Se incluye porque su
#                                justificacion es analitica, no de ensayo y error.
STEP_C <- c(A = EPS^(1/4), B = EPS^(1/3))
step_vec <- function(u, cc) cc * pmax(abs(u), 1)

#' Hessiana por diferencias centrales.
#' Diagonal:     [f(u+h e_i) - 2 f(u) + f(u-h e_i)] / h_i^2
#' Fuera de diag:[f(++) - f(+-) - f(-+) + f(--)] / (4 h_i h_j)
#' La formula cruzada es SIMETRICA EN (i,j) POR CONSTRUCCION: la matriz resultante
#' es exactamente simetrica y no requiere simetrizacion. Se mide igualmente.
hess_central <- function(f, u, h) {
  k <- length(u); H <- matrix(NA_real_, k, k)
  f0 <- f(u)
  if (!is.finite(f0)) return(list(H = H, invalid = "f(u_hat) no finita", nev = 1L))
  nev <- 1L
  for (i in seq_len(k)) {
    ei <- numeric(k); ei[i] <- h[i]
    fp <- f(u + ei); fm <- f(u - ei); nev <- nev + 2L
    if (!is.finite(fp) || !is.finite(fm))
      return(list(H = H, invalid = sprintf("estencil diagonal no finito en el parametro %d", i),
                  nev = nev))
    H[i, i] <- (fp - 2 * f0 + fm) / (h[i]^2)
  }
  if (k > 1L) for (i in seq_len(k - 1L)) for (j in (i + 1L):k) {
    ei <- numeric(k); ei[i] <- h[i]
    ej <- numeric(k); ej[j] <- h[j]
    fpp <- f(u + ei + ej); fpm <- f(u + ei - ej)
    fmp <- f(u - ei + ej); fmm <- f(u - ei - ej); nev <- nev + 4L
    if (!all(is.finite(c(fpp, fpm, fmp, fmm))))
      return(list(H = H, invalid = sprintf("estencil cruzado no finito en (%d,%d)", i, j),
                  nev = nev))
    v <- (fpp - fpm - fmp + fmm) / (4 * h[i] * h[j])
    H[i, j] <- v; H[j, i] <- v
  }
  list(H = H, invalid = NA_character_, nev = nev)
}

#' Esquema por nombre. Devuelve list(J, invalid, nev).
hess_scheme <- function(f, u, scheme) {
  if (scheme %in% names(STEP_C)) {
    h <- step_vec(u, STEP_C[[scheme]])
    r <- hess_central(f, u, h)
    return(list(J = r$H, invalid = r$invalid, nev = r$nev, h = h))
  }
  if (scheme == "C_richardson") {
    h  <- step_vec(u, STEP_C[["A"]])
    r1 <- hess_central(f, u, h)
    if (!is.na(r1$invalid)) return(list(J = r1$H, invalid = r1$invalid, nev = r1$nev, h = h))
    r2 <- hess_central(f, u, h / 2)
    if (!is.na(r2$invalid)) return(list(J = r2$H, invalid = r2$invalid,
                                        nev = r1$nev + r2$nev, h = h))
    return(list(J = (4 * r2$H - r1$H) / 3, invalid = NA_character_,
                nev = r1$nev + r2$nev, h = h))
  }
  stop("esquema desconocido: ", scheme)
}
SCHEMES <- c("A", "B", "C_richardson")

# ============================================================
# 4. CADENA DE VALIDACION ESTRUCTURAL (OD-4, parte estructural)
# ============================================================
# Sin pseudoinversa. Sin correccion de autovalores. Sin sustituir la matriz por
# una aproximacion. Si algo falla -> valid = FALSE + motivo auditable.
validate_information <- function(J, id, theta) {
  out <- list(valid = FALSE, reason = NA_character_, Sigma_u = NULL,
              Sigma_theta = NULL, se = NULL, rcond = NA_real_,
              chol_ok = FALSE, asym = NA_real_,
              eig_min = NA_real_, eig_max = NA_real_)
  k <- length(theta)
  if (is.null(J) || !is.matrix(J) || any(dim(J) != c(k, k))) {
    out$reason <- "1. dimensiones incorrectas"; return(out)
  }
  if (any(!is.finite(J))) { out$reason <- "2. elementos no finitos"; return(out) }
  out$asym <- max(abs(J - t(J)))
  if (out$asym > 1e-8 * max(1, max(abs(J)))) {
    out$reason <- "3. asimetria numerica por encima de la tolerancia"; return(out)
  }
  ev <- tryCatch(eigen(J, symmetric = TRUE, only.values = TRUE)$values,
                 error = function(e) NULL)
  if (!is.null(ev)) { out$eig_min <- min(ev); out$eig_max <- max(ev) }
  ch <- tryCatch(chol(J), error = function(e) NULL)
  if (is.null(ch)) { out$reason <- "4. no definida positiva (falla Cholesky)"; return(out) }
  out$chol_ok <- TRUE
  out$rcond <- tryCatch(rcond(J), error = function(e) NA_real_)   # DIAGNOSTICO
  Su <- tryCatch(chol2inv(ch), error = function(e) NULL)
  if (is.null(Su)) { out$reason <- "5. no invertible"; return(out) }
  if (any(!is.finite(Su))) { out$reason <- "6. Sigma_u no finita"; return(out) }
  out$Sigma_u <- Su
  g <- G_diag(id, theta)
  if (any(!is.finite(g))) { out$reason <- "7. jacobiano delta no valido"; return(out) }
  St <- diag(g, nrow = k) %*% Su %*% diag(g, nrow = k)
  if (any(!is.finite(St))) { out$reason <- "8. Sigma_theta no finita"; return(out) }
  out$Sigma_theta <- St
  d <- diag(St)
  if (any(!is.finite(d)) || any(d <= 0)) {
    out$reason <- "9. diagonal de Sigma_theta no estrictamente positiva"; return(out)
  }
  se <- sqrt(d)
  if (any(!is.finite(se)) || any(se <= 0)) {
    out$reason <- "10. SE naturales no finitos o no positivos"; return(out)
  }
  out$se <- se; out$valid <- TRUE
  out
}

# ============================================================
# 5. REFERENCIAS ANALITICAS, DERIVADAS BAJO LA PARAMETRIZACION DE calc.R
# ============================================================
# Cada referencia declara `kind`:
#   "observed"  = Hessiana OBSERVADA analitica evaluada en theta_hat.
#   "expected"  = informacion esperada I(theta) = E[J(theta)].
#   "asymptotic"= solo covarianza asintotica del MLE.
# NO son intercambiables. En las cinco familias de abajo la Hessiana observada,
# evaluada EN theta_hat, se reduce a una funcion de theta_hat y n; por eso la
# referencia es del tipo "observed" y no una aproximacion asintotica.
#
# Derivaciones (l = log-verosimilitud; todo evaluado en theta_hat):
#
# EXPONENCIAL, theta = rate = lambda, dexp(x, rate):
#   l = n log L - L Sx ;  l'' = -n/L^2  =>  J_theta = n/L^2
#   u = log L:  d2/du2 [-l] = e^u Sx = L Sx ; en L_hat = n/Sx  =>  J_u = n
#   Sigma_theta = L^2/n
#
# POISSON, theta = lambda, dpois:
#   l'' = -Sx/L^2 ; en L_hat = xbar  =>  J_theta = n/L
#   u = log L:  J_u = n L_hat ;  Sigma_theta = L/n
#
# GEOMETRICA, theta = prob = p, dgeom (soporte {0,1,2,...}: fallos antes del
# primer exito). MLE de calc.R: p_hat = 1/(1+xbar)  =>  Sx = n(1-p)/p
#   l = n log p + Sx log(1-p)
#   l'' = -n/p^2 - Sx/(1-p)^2 ; sustituyendo Sx  =>  J_theta = n / (p^2 (1-p))
#   u = logit p, d theta/du = p(1-p); como el score es cero en p_hat,
#     J_u = J_theta * (p(1-p))^2 = n (1-p)
#   Sigma_theta = p^2 (1-p) / n
#
# NORMAL, theta = (mean, sd) con sd = MLE (divide por n), dnorm:
#   d2l/dmu2      = -n/s^2
#   d2l/dmu ds    = -2 S(x-mu)/s^3 ; en mu_hat, S(x-mu_hat) = 0  =>  EXACTAMENTE 0
#   d2l/ds2       = n/s^2 - 3 S(x-mu)^2/s^4 ; con S(x-mu_hat)^2 = n s_hat^2
#                 = -2n/s^2
#   J_theta = diag(n/s^2, 2n/s^2) ;  Sigma_theta = diag(s^2/n, s^2/(2n))
#   u = (mu, log s):  J_u = diag(n/s^2, 2n)  =>  Var(log s_hat) = 1/(2n)
#   El metodo delta devuelve Var(s_hat) = s^2/(2n): VALIDACION EXPLICITA DE OD-5.
#
# LOGNORMAL, theta = (meanlog, sdlog), dlnorm:
#   log f(x) = log f_N(log x; meanlog, sdlog) - log x. El termino -log x NO
#   depende de los parametros, luego la Hessiana es IDENTICA a la Normal
#   aplicada a log(x). Mismas expresiones con s = sdlog.
#
# BINOMIAL NEGATIVA: NO DISPONIBLE. La informacion respecto de `size` involucra
# E[trigamma(x + size)], que no tiene forma cerrada elemental bajo esta
# parametrizacion (size, mu). No se inventa una referencia; queda como caso de
# stress sin verdad analitica.
REFS <- list(
  exponential = function(th, n) list(
    J_u = matrix(n, 1, 1),
    Sigma_theta = matrix(th[[1]]^2 / n, 1, 1),
    kind = "observed",
    note = "J_u = n exactamente, independiente de los datos y de lambda"),
  poisson = function(th, n) list(
    J_u = matrix(n * th[[1]], 1, 1),
    Sigma_theta = matrix(th[[1]] / n, 1, 1),
    kind = "observed", note = "J_u = n*lambda_hat"),
  geometric = function(th, n) { p <- th[[1]]; list(
    J_u = matrix(n * (1 - p), 1, 1),
    Sigma_theta = matrix(p^2 * (1 - p) / n, 1, 1),
    kind = "observed", note = "escala logit; J_u = n(1-p_hat)") },
  normal = function(th, n) { s <- th[[2]]; list(
    J_u = diag(c(n / s^2, 2 * n)),
    Sigma_theta = diag(c(s^2 / n, s^2 / (2 * n))),
    kind = "observed",
    note = "off-diagonal EXACTAMENTE 0 en el MLE; Var(log sd) = 1/(2n)") },
  lognormal = function(th, n) { s <- th[[2]]; list(
    J_u = diag(c(n / s^2, 2 * n)),
    Sigma_theta = diag(c(s^2 / n, s^2 / (2 * n))),
    kind = "observed",
    note = "identica a la Normal sobre log(x); el termino -log x no depende de theta") }
)

# ============================================================
# 6. ESCENARIOS
# ============================================================
# Diversidad de condiciones por encima de repeticiones Monte Carlo: lo que se
# mide es el ERROR NUMERICO de la Hessiana alrededor de theta_hat, no el RMSE
# estadistico del MLE.
NS <- c(100L, 1000L, 10000L)
REPS <- 3L                      # replicas por (escenario, n): descarta casualidades

gen <- list(
  exponential = function(n, th) stats::rexp(n, th[[1]]),
  poisson     = function(n, th) stats::rpois(n, th[[1]]),
  geometric   = function(n, th) stats::rgeom(n, th[[1]]),
  normal      = function(n, th) stats::rnorm(n, th[[1]], th[[2]]),
  lognormal   = function(n, th) stats::rlnorm(n, th[[1]], th[[2]]),
  gamma       = function(n, th) stats::rgamma(n, shape = th[[1]], scale = th[[2]]),
  weibull     = function(n, th) stats::rweibull(n, shape = th[[1]], scale = th[[2]]),
  loglogistic = function(n, th) { u <- stats::runif(n); th[[2]] * (u / (1 - u))^(1 / th[[1]]) },
  pareto      = function(n, th) th[[2]] * ((1 - stats::runif(n))^(-1 / th[[1]]) - 1),
  burr        = function(n, th) { u <- stats::runif(n)
                                  th[[3]] * ((1 - u)^(-1 / th[[2]]) - 1)^(1 / th[[1]]) }
)

# Escenarios CON referencia analitica. Cubren: parametros ~1, pequenos, grandes,
# escala de severidad ~1e3, y Normal con media positiva, nula y negativa.
SC_REF <- list(
  list("exponential", "rate_1",        c(rate = 1)),
  list("exponential", "rate_pequeno",  c(rate = 0.001)),      # media 1000
  list("exponential", "rate_grande",   c(rate = 500)),
  list("poisson",     "lambda_1",      c(lambda = 1)),
  list("poisson",     "lambda_pequeno",c(lambda = 0.05)),
  list("poisson",     "lambda_grande", c(lambda = 800)),
  list("geometric",   "p_media",       c(prob = 0.5)),
  list("geometric",   "p_pequena",     c(prob = 0.01)),       # cola larga
  list("geometric",   "p_grande",      c(prob = 0.95)),
  list("normal",      "mu_pos",        c(mean = 100,  sd = 15)),
  list("normal",      "mu_cero",       c(mean = 0,    sd = 1)),
  list("normal",      "mu_neg",        c(mean = -50,  sd = 20)),
  list("normal",      "severidad",     c(mean = 5000, sd = 1200)),
  list("normal",      "sd_pequena",    c(mean = 1,    sd = 0.001)),
  list("lognormal",   "tipica",        c(meanlog = 7,   sdlog = 1.3)),
  list("lognormal",   "poca_disp",     c(meanlog = 7,   sdlog = 0.05)),
  list("lognormal",   "muy_dispersa",  c(meanlog = 2,   sdlog = 2.5))
)

# Escenarios SIN referencia cerrada (stress). Parametrizaciones de R/calc.R.
SC_STRESS <- list(
  list("gamma",       "moderada",    c(shape = 2,   scale = 500)),
  list("gamma",       "shape_bajo",  c(shape = 0.5, scale = 1000)),
  list("gamma",       "shape_alto",  c(shape = 9,   scale = 100)),
  list("weibull",     "moderada",    c(shape = 1.5, scale = 800)),
  list("weibull",     "shape_bajo",  c(shape = 0.7, scale = 500)),
  list("loglogistic", "moderada",    c(shape = 2.5, scale = 600)),
  list("loglogistic", "cola_pesada", c(shape = 1.2, scale = 400)),
  list("pareto",      "moderada",    c(shape = 2.5, scale = 1000)),
  list("pareto",      "cola_pesada", c(shape = 1.2, scale = 500)),
  list("burr",        "moderada",    c(shape1 = 2,   shape2 = 1.5, scale = 500)),
  list("burr",        "pesada",      c(shape1 = 1.2, shape2 = 0.8, scale = 400)),
  list("burr",        "shape2_bajo", c(shape1 = 2,   shape2 = 0.5, scale = 500))
)

seed_for <- function(tag, rep) {
  s <- MASTER_SEED
  for (ch in utf8ToInt(paste0(tag, "_", rep))) s <- (s * 31 + ch) %% 2147483647
  as.integer(s)
}

# Error relativo con cero seguro: si el valor de referencia es (casi) cero, el
# error relativo no tiene sentido -> se usa el ABSOLUTO y se marca como tal.
rel_or_abs <- function(num, ref, floor_ref = 1e-12) {
  if (abs(ref) <= floor_ref) list(v = abs(num - ref), type = "abs")
  else list(v = abs(num - ref) / abs(ref), type = "rel")
}
# Norma relativa de Frobenius de la matriz completa.
fro_rel <- function(A, B) sqrt(sum((A - B)^2)) / sqrt(sum(B^2))

# ============================================================
# 7. EJECUCION
# ============================================================
res_cases <- list(); res_entries <- list(); res_step <- list(); res_stress <- list()
t0 <- Sys.time()

run_all <- function() {

  # ---------- 7a. Casos CON referencia analitica ----------
  cat("== Casos con referencia analitica ==\n")
  for (sc in SC_REF) {
    id <- sc[[1]]; lab <- sc[[2]]; th_true <- sc[[3]]
    for (n in NS) for (rep in seq_len(REPS)) {
      CTX$dist <- id; CTX$scenario <- lab; CTX$n <- n; CTX$scheme <- NA_character_
      CTX$where <- "generacion"
      set.seed(seed_for(paste0(id, lab, n), rep))
      x <- gen[[id]](n, th_true)

      CTX$where <- "MLE"
      est <- tryCatch(.estimate(id, x, "mle"), error = function(e) NULL)
      if (is.null(est) || !isTRUE(est$converged)) next
      theta <- unlist(est$params)
      if (any(!is.finite(theta))) next
      # La Geometrica degenera si p_hat toca la frontera; la Normal, si sd = 0.
      if (id == "geometric" && (theta[[1]] <= 0 || theta[[1]] >= 1)) next

      u <- to_u_vec(id, theta)
      # theta_hat en la frontera (p.ej. lambda_hat = 0 con Poisson de media baja y
      # n pequeno, o p_hat = 1 con Geometrica) produce u infinita. No es un fallo
      # del esquema numerico sino un MLE degenerado: se descarta el caso y se
      # registra, en lugar de contaminar las metricas del benchmark.
      if (any(!is.finite(u))) {
        res_cases[[length(res_cases) + 1L]] <<- data.frame(
          dist = id, scenario = lab, n = n, rep = rep, scheme = NA_character_,
          k = length(theta), ref_kind = NA_character_, valid = FALSE,
          reason = "theta_hat en la frontera: u no finita (MLE degenerado)",
          J_fro_rel = NA_real_, var_rel_err_max = NA_real_, se_rel_err_max = NA_real_,
          cov_offdiag_abs_err = NA_real_, chol_ok = FALSE, rcond = NA_real_,
          asym = NA_real_, eig_min = NA_real_, eig_max = NA_real_,
          n_eval = 0L, secs = 0, stringsAsFactors = FALSE)
        next
      }
      f    <- make_f(id, x)
      refs <- REFS[[id]](theta, n)

      for (sch in SCHEMES) {
        CTX$scheme <- sch; CTX$where <- "hessiana"
        tt <- system.time({
          hs <- hess_scheme(f, u, sch)
        })[["elapsed"]]
        val <- if (is.na(hs$invalid)) validate_information(hs$J, id, theta)
               else list(valid = FALSE, reason = hs$invalid, rcond = NA_real_,
                         chol_ok = FALSE, asym = NA_real_, se = NULL,
                         Sigma_theta = NULL, eig_min = NA_real_, eig_max = NA_real_)

        se_ref  <- sqrt(diag(refs$Sigma_theta))
        se_err  <- if (isTRUE(val$valid)) max(abs(val$se - se_ref) / se_ref) else NA_real_
        var_err <- if (isTRUE(val$valid))
                     max(abs(diag(val$Sigma_theta) - diag(refs$Sigma_theta)) /
                         diag(refs$Sigma_theta)) else NA_real_
        offd    <- if (isTRUE(val$valid) && length(theta) > 1L)
                     max(abs(val$Sigma_theta[upper.tri(val$Sigma_theta)] -
                             refs$Sigma_theta[upper.tri(refs$Sigma_theta)])) else NA_real_

        res_cases[[length(res_cases) + 1L]] <<- data.frame(
          dist = id, scenario = lab, n = n, rep = rep, scheme = sch,
          k = length(theta), ref_kind = refs$kind,
          valid = isTRUE(val$valid),
          reason = if (isTRUE(val$valid)) NA_character_ else val$reason,
          J_fro_rel = if (is.na(hs$invalid)) fro_rel(hs$J, refs$J_u) else NA_real_,
          var_rel_err_max = var_err, se_rel_err_max = se_err,
          cov_offdiag_abs_err = offd,
          chol_ok = isTRUE(val$chol_ok), rcond = val$rcond, asym = val$asym,
          eig_min = val$eig_min, eig_max = val$eig_max,
          n_eval = hs$nev, secs = tt,
          stringsAsFactors = FALSE)

        # Entrada a entrada de J_u, con eleccion rel/abs segun la referencia.
        if (is.na(hs$invalid)) {
          k <- length(theta)
          for (i in seq_len(k)) for (j in seq_len(k)) {
            e <- rel_or_abs(hs$J[i, j], refs$J_u[i, j])
            res_entries[[length(res_entries) + 1L]] <<- data.frame(
              dist = id, scenario = lab, n = n, rep = rep, scheme = sch,
              i = i, j = j, entry = paste0("J_u[", i, ",", j, "]"),
              ref = refs$J_u[i, j], num = hs$J[i, j],
              err = e$v, err_type = e$type, stringsAsFactors = FALSE)
          }
        }
      }

      # ---------- 7b. Sensibilidad al paso ----------
      # Barrido de la constante c en h = c * max(|u|,1) para ver DONDE esta el
      # minimo de error y como de plano es. Es la evidencia que decide la regla.
      if (rep == 1L) {
        for (cc in 10^seq(-9, -2, by = 0.5)) {
          CTX$scheme <- sprintf("sweep_%.1e", cc); CTX$where <- "hessiana"
          r <- hess_central(f, u, step_vec(u, cc))
          res_step[[length(res_step) + 1L]] <<- data.frame(
            dist = id, scenario = lab, n = n, c_step = cc,
            log10_c = log10(cc),
            valid = is.na(r$invalid),
            J_fro_rel = if (is.na(r$invalid)) fro_rel(r$H, refs$J_u) else NA_real_,
            stringsAsFactors = FALSE)
        }
      }
    }
    cat(sprintf("  %-12s %-14s hecho\n", id, lab))
  }

  # ---------- 7c. Stress sin referencia cerrada ----------
  cat("\n== Stress (sin verdad analitica) ==\n")
  for (sc in SC_STRESS) {
    id <- sc[[1]]; lab <- sc[[2]]; th_true <- sc[[3]]
    for (n in NS) {
      CTX$dist <- id; CTX$scenario <- lab; CTX$n <- n
      CTX$where <- "generacion"
      set.seed(seed_for(paste0(id, lab, n), 1L))
      x <- gen[[id]](n, th_true)

      CTX$where <- "MLE"
      est <- tryCatch(.estimate(id, x, "mle"), error = function(e) NULL)
      conv <- !is.null(est) && isTRUE(est$converged)
      if (!conv) {
        res_stress[[length(res_stress) + 1L]] <<- data.frame(
          dist = id, scenario = lab, n = n, scheme = NA_character_,
          mle_converged = FALSE, valid = FALSE, reason = "el MLE no convergio",
          rcond = NA_real_, chol_ok = FALSE, asym = NA_real_,
          eig_min = NA_real_, eig_max = NA_real_,
          step_stability = NA_real_, scale_stability = NA_real_,
          se_1 = NA_real_, se_2 = NA_real_, se_3 = NA_real_,
          stringsAsFactors = FALSE)
        next
      }
      theta <- unlist(est$params); u <- to_u_vec(id, theta)
      if (any(!is.finite(theta)) || any(!is.finite(u))) {
        res_stress[[length(res_stress) + 1L]] <<- data.frame(
          dist = id, scenario = lab, n = n, scheme = NA_character_,
          mle_converged = TRUE, valid = FALSE,
          reason = "theta_hat en la frontera: u no finita",
          rcond = NA_real_, chol_ok = FALSE, asym = NA_real_,
          eig_min = NA_real_, eig_max = NA_real_,
          step_stability = NA_real_, scale_stability = NA_real_,
          se_1 = NA_real_, se_2 = NA_real_, se_3 = NA_real_,
          stringsAsFactors = FALSE)
        next
      }
      f <- make_f(id, x)

      for (sch in SCHEMES) {
        CTX$scheme <- sch; CTX$where <- "hessiana"
        hs  <- hess_scheme(f, u, sch)
        val <- if (is.na(hs$invalid)) validate_information(hs$J, id, theta)
               else list(valid = FALSE, reason = hs$invalid, rcond = NA_real_,
                         chol_ok = FALSE, asym = NA_real_, se = NULL,
                         eig_min = NA_real_, eig_max = NA_real_)

        # Estabilidad frente al paso: mismo esquema con h y 2h.
        st <- NA_real_
        if (is.na(hs$invalid)) {
          h2 <- hess_central(f, u, 2 * hs$h)
          if (is.na(h2$invalid)) st <- fro_rel(h2$H, hs$J)
        }
        # Estabilidad bajo cambio de escala del dato: con x -> 1000x, la
        # log-verosimilitud de una familia de escala se desplaza en una constante
        # que NO depende de theta, y el parametro de escala se desplaza en
        # log(1000) EN COORDENADA u. La prediccion es que J_u sea invariante.
        sc_st <- NA_real_
        if (is.na(hs$invalid) && id != "normal") {
          CTX$where <- "hessiana_escalada"
          x2 <- x * 1000
          e2 <- tryCatch(.estimate(id, x2, "mle"), error = function(e) NULL)
          if (!is.null(e2) && isTRUE(e2$converged)) {
            th2 <- unlist(e2$params)
            hs2 <- hess_scheme(make_f(id, x2), to_u_vec(id, th2), sch)
            if (is.na(hs2$invalid)) sc_st <- fro_rel(hs2$J, hs$J)
          }
          CTX$where <- "hessiana"
        }
        se <- if (isTRUE(val$valid)) val$se else rep(NA_real_, length(theta))
        res_stress[[length(res_stress) + 1L]] <<- data.frame(
          dist = id, scenario = lab, n = n, scheme = sch,
          mle_converged = TRUE, valid = isTRUE(val$valid),
          reason = if (isTRUE(val$valid)) NA_character_ else val$reason,
          rcond = val$rcond, chol_ok = isTRUE(val$chol_ok), asym = val$asym,
          eig_min = val$eig_min, eig_max = val$eig_max,
          step_stability = st, scale_stability = sc_st,
          se_1 = se[1], se_2 = if (length(se) > 1L) se[2] else NA_real_,
          se_3 = if (length(se) > 2L) se[3] else NA_real_,
          stringsAsFactors = FALSE)
      }
    }
    cat(sprintf("  %-12s %-14s hecho\n", id, lab))
  }
}

withCallingHandlers(run_all(),
  warning = function(w) { w_record(w); invokeRestart("muffleWarning") })

# ============================================================
# 8. SALIDA
# ============================================================
CA <- do.call(rbind, res_cases); EN <- do.call(rbind, res_entries)
SW <- do.call(rbind, res_step);  ST <- do.call(rbind, res_stress)
utils::write.csv(CA, file.path(OUTDIR, "b12_reference_cases.csv"), row.names = FALSE)
utils::write.csv(EN, file.path(OUTDIR, "b12_reference_entries.csv"), row.names = FALSE)
utils::write.csv(SW, file.path(OUTDIR, "b12_step_sensitivity.csv"), row.names = FALSE)
utils::write.csv(ST, file.path(OUTDIR, "b12_stress_cases.csv"), row.names = FALSE)

cat("\n\n================= RESULTADOS =================\n")

cat("\n-- 1. Exactitud frente a la referencia analitica, por esquema --\n")
cat(sprintf("%-14s | %10s | %12s | %12s | %12s | %8s\n",
            "esquema", "% validos", "medFro(J_u)", "p90Fro(J_u)", "med|err SE|", "med evals"))
for (s in SCHEMES) {
  q <- CA$scheme == s
  cat(sprintf("%-14s | %9.1f%% | %12.3e | %12.3e | %12.3e | %8.0f\n", s,
              100 * mean(CA$valid[q]),
              stats::median(CA$J_fro_rel[q], na.rm = TRUE),
              unname(stats::quantile(CA$J_fro_rel[q], 0.90, na.rm = TRUE, type = 7)),
              stats::median(CA$se_rel_err_max[q], na.rm = TRUE),
              stats::median(CA$n_eval[q], na.rm = TRUE)))
}

cat("\n-- 2. Por familia y esquema: mediana del error relativo de Frobenius de J_u --\n")
for (d in unique(CA$dist)) {
  cat(sprintf("  %-12s", d))
  for (s in SCHEMES)
    cat(sprintf("  %-13s %10.3e", s,
                stats::median(CA$J_fro_rel[CA$dist == d & CA$scheme == s], na.rm = TRUE)))
  cat("\n")
}

cat("\n-- 3. Efecto de n (mediana Fro de J_u) --\n")
for (s in SCHEMES) { cat(sprintf("  %-14s", s))
  for (nn in NS) cat(sprintf("  n=%-6d %10.3e", nn,
        stats::median(CA$J_fro_rel[CA$scheme == s & CA$n == nn], na.rm = TRUE)))
  cat("\n") }

cat("\n-- 4. Off-diagonal de la Normal/Lognormal: la referencia es 0 -> error ABSOLUTO --\n")
q <- EN$i != EN$j & EN$dist %in% c("normal", "lognormal")
if (any(q)) {
  cat(sprintf("     tipo de error usado: %s\n", paste(unique(EN$err_type[q]), collapse = ", ")))
  for (s in SCHEMES)
    cat(sprintf("     %-14s  mediana |J_u[1,2]| = %10.3e   max = %10.3e\n", s,
                stats::median(abs(EN$num[q & EN$scheme == s])),
                max(abs(EN$num[q & EN$scheme == s]))))
}

cat("\n-- 5. Sensibilidad al paso: c optimo por familia (min de Fro) --\n")
cat("     h_j = c * max(|u_j|, 1).  Referencias: eps^(1/4) = 1.22e-4, eps^(1/3) = 6.06e-6\n")
for (d in unique(SW$dist)) {
  q <- SW$dist == d & SW$valid & is.finite(SW$J_fro_rel)
  if (!any(q)) next
  ag <- stats::aggregate(J_fro_rel ~ c_step, data = SW[q, ], FUN = stats::median)
  best <- ag$c_step[which.min(ag$J_fro_rel)]
  # Anchura de la meseta: c donde el error no supera 10x el minimo.
  ok <- ag$c_step[ag$J_fro_rel <= 10 * min(ag$J_fro_rel)]
  cat(sprintf("  %-12s c* = %8.2e  (err %9.3e)   meseta 10x: [%8.2e, %8.2e]\n",
              d, best, min(ag$J_fro_rel), min(ok), max(ok)))
}

cat("\n-- 6. Simetria: la formula cruzada de 4 puntos es simetrica POR CONSTRUCCION --\n")
cat(sprintf("     max asimetria observada en todos los casos: %.3e\n",
            max(CA$asym, na.rm = TRUE)))

cat("\n-- 7. Stress sin verdad analitica --\n")
cat(sprintf("%-12s %-13s %-14s %6s %6s %10s %11s %11s\n", "dist", "escenario",
            "esquema", "valid", "chol", "rcond", "estab.paso", "estab.escala"))
for (i in seq_len(nrow(ST))) {
  cat(sprintf("%-12s %-13s %-14s %6s %6s %10.2e %11.2e %11.2e\n",
              ST$dist[i], ST$scenario[i],
              ifelse(is.na(ST$scheme[i]), "-", ST$scheme[i]),
              ST$valid[i], ST$chol_ok[i], ST$rcond[i],
              ST$step_stability[i], ST$scale_stability[i]))
}

cat("\n-- 8. Avisos --\n")
if (length(WLOG$rows) == 0L) {
  cat("     NINGUN aviso registrado.\n")
} else {
  W <- do.call(rbind, WLOG$rows)
  utils::write.csv(W, file.path(OUTDIR, "b12_warnings.csv"), row.names = FALSE)
  cat(sprintf("     total: %d\n", nrow(W)))
  cat("     por mensaje:\n"); print(sort(table(W$message), decreasing = TRUE))
  cat("     por distribucion:\n"); print(sort(table(W$dist), decreasing = TRUE))
  cat("     por punto del codigo:\n"); print(table(W$where))
  cat("\n     CLASIFICAR A MANO segun la taxonomia: PRODUCT BUG / TEST DEFECT /\n")
  cat("     EXPERIMENTAL SCRIPT DEFECT / EXPECTED NUMERICAL EXPLORATION /\n")
  cat("     ENVIRONMENT WARNING / METHODOLOGICAL LIMITATION.\n")
  cat("     Un aviso en `where = hessiana` NO es exploracion del optimizador:\n")
  cat("     el estencil se evalua cerca de theta_hat y deberia ser valido.\n")
}

cat(sprintf("\nCSV en: %s\ntiempo total: %s\n", OUTDIR, format(Sys.time() - t0)))
cat("\nB12.1 EJECUTADO — la decision de politica numerica requiere revision del owner.\n")
