# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/adr027_guardas.R
# Cierra la RESERVA DE COBERTURA de ADR-027: ejercita el camino de ACTIVACIÓN de
# las dos guardas del optimizador, que `b2_muestra_comun.R` (N10) solo verifica
# en negativo —es decir, comprueba que NO disparan sobre datos legítimos—.
#
# Por qué hace falta un test aparte: desde ADR-026 la muestra común elimina los
# ceros antes de estimar, de modo que la condición que produce la degeneración ya
# no puede darse a través de `dist_fit_analyze()`. Para ejercitar la guarda hay
# que invocar el estimador DIRECTAMENTE, saltándose `build_analysis_sample()`.
# Eso es exactamente lo que hacen estos tests: reproducen el bug original.
#
# Referencia: INCIDENT_2026-08-09_pareto_ceros.md (hallazgo H1).
# Autor: BMK — Última actualización: 2026-08-09
# ============================================================
#
#   Rscript tests/adr027_guardas.R     # desde la raíz de la herramienta
#   Rscript adr027_guardas.R           # desde la carpeta tests/

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

cat("== GUARDAS DE ADR-027 (camino de activación) — distribution-fitting ==\n")

# ------------------------------------------------------------
# Dataset patológico: átomo de probabilidad en cero.
# ------------------------------------------------------------
# Reproduce la estructura de `Cost_claims_year`: 800 pólizas sin siniestro y 200
# severidades positivas. La demostración analítica del informe:
#
#   l(a, s) = n*log(a) + (a*n+ - n0)*log(s) - (a+1)*sum(log(x + s))
#
# Cuando s -> 0, log(s) -> -Inf, de modo que l -> +Inf siempre que el coeficiente
# (a*n+ - n0) sea negativo, es decir, siempre que a < n0/n+ . Aquí ese umbral
# vale 800/200 = 4. La verosimilitud NO está acotada y el MLE no existe.
set.seed(20260809)
n0 <- 800L; np <- 200L
xz <- c(rep(0, n0), pmax(round(stats::rlnorm(np, meanlog = 5.7, sdlog = 1.3), 2), 0.01))
umbral_alpha <- n0 / np

cat(sprintf("\n  [contexto] n0 = %d ceros, n+ = %d positivos, umbral a < n0/n+ = %.2f\n",
            n0, np, umbral_alpha))

# ------------------------------------------------------------
# 1. Guarda (A): el estimador MLE de Pareto rechaza el óptimo de frontera
# ------------------------------------------------------------
# Se invoca `.mle_pareto()` DIRECTAMENTE sobre el vector con ceros, saltándose
# `build_analysis_sample()`. Antes de ADR-027 esto devolvía converged = TRUE con
# scale = 4,94e-324 y logLik = +5,7e7.
cat("\n-- 1. Guarda (A): frontera numérica del espacio paramétrico --\n")
est <- .mle_pareto(xz)

cat(sprintf("     shape = %.8g | scale = %.8g | converged = %s\n",
            est$params$shape, est$params$scale, est$converged))
cat(sprintf("     mensaje: %s\n", est$message))

check(!isTRUE(est$converged),
      "1.1 el ajuste degenerado NO se acepta como convergente")
check(!is.na(est$message) && nzchar(est$message),
      "1.2 el rechazo lleva un motivo explícito (nunca silencioso)")
check(grepl("frontera numérica", est$message, fixed = TRUE),
      "1.3 el motivo identifica la guarda (A): óptimo en la frontera numérica")
check(est$params$scale < .Machine$double.xmin,
      "1.4 el parámetro de escala quedó por debajo del menor doble normalizado")
check(is.na(est$logLik),
      "1.5 no se publica logLik de un ajuste rechazado")

# Demostración del daño evitado: si la guarda no existiera, ESTE es el valor que
# habría entrado en el ranking y habría aplastado la normalización min-máx.
ll_degenerado <- sum(.dpareto_log(xz, est$params$shape, est$params$scale))
aic_degenerado <- -2 * ll_degenerado + 2 * 2
cat(sprintf("     [daño evitado] logLik que se habría publicado = %.2f -> AIC = %.2f\n",
            ll_degenerado, aic_degenerado))
check(is.finite(ll_degenerado) && ll_degenerado > 0,
      "1.6 sin guarda la logLik sería positiva y enorme (verosimilitud no acotada)")
check(aic_degenerado < 0,
      "1.7 sin guarda el AIC sería negativo y de magnitud absurda")
check(est$params$shape < umbral_alpha,
      "1.8 el alfa estimado cae en la región de divergencia (a < n0/n+)")

# ------------------------------------------------------------
# 2. La ruta completa `.fit_one()` también lo rechaza
# ------------------------------------------------------------
# `.fit_one()` es la puerta de entrada al Assessment. Se comprueba que un ajuste
# degenerado sale de ahí marcado como no convergente, de modo que `.assess()` lo
# mande a `excluded` y nunca participe en la normalización del ranking.
cat("\n-- 2. `.fit_one()` no deja pasar el ajuste degenerado --\n")
spec_pareto <- list(id = "pareto", label = "Pareto (Lomax)", n_params = 2L)
f <- .fit_one(spec_pareto, xz, role = "candidate", method = "mle",
              family = "continuous", resolution = .sample_resolution(xz))
check(!isTRUE(f$converged),      "2.1 `.fit_one()` devuelve converged = FALSE")
check(!is.na(f$message),         "2.2 propaga el motivo hasta la capa de decisión")
check(is.na(f$logLik),           "2.3 no propaga logLik")
check(f$n_used == length(xz),    "2.4 n_used refleja la muestra recibida (sin filtrar)")

# ------------------------------------------------------------
# 3. Guarda (B): `.loglik_implausible()` con casos construidos
# ------------------------------------------------------------
# Cota: si el dato tiene resolución d, la verosimilitud correcta es la
# discretizada, P(X in [x +/- d/2]) ~ f(x)*d <= 1, luego mean(log f) <= -log(d).
# Con K = 0 la cota es estricta.
cat("\n-- 3. Guarda (B): plausibilidad por resolución del dato --\n")
cfg   <- dfit_default_config()
delta <- 0.01                       # importes en céntimos
cota  <- -log(delta)                # = 4.6052
check(abs(cfg$loglik_plausibility_k) < 1e-12,
      "3.0 K = 0: la cota se aplica de forma estricta, sin tolerancia")

# (a) Caso PATOLÓGICO — valores reales del incidente (Pareto degenerada sobre las
#     95.554 observaciones con ceros): mean(log f) = 57306028.66 / 95554 = 599.72
malo <- .loglik_implausible(57306028.66, 95554L, delta, cfg)
check(!is.na(malo),
      "3.1 caso patológico del incidente: la guarda (B) lo detecta")
check(grepl("no acotada", malo, fixed = TRUE),
      "3.2 el motivo identifica la guarda (B): verosimilitud no acotada")
check(grepl("599", malo, fixed = TRUE) || grepl("4.61", malo, fixed = TRUE),
      "3.3 el motivo cuantifica la log-densidad media y la cota")

# (b) Caso LEGÍTIMO — Lognormal sobre las 17.678 severidades positivas:
#     mean(log f) = -130804.35 / 17678 = -7.399, muy por debajo de la cota
bueno <- .loglik_implausible(-130804.35, 17678L, delta, cfg)
check(is.na(bueno),
      "3.4 caso legítimo del incidente: la guarda (B) NO se activa")

# (c) Frontera: exactamente sobre la cota. Con K = 0 la condición es
#     `mean(log f) > cota`, luego la igualdad NO debe disparar. Se usa n = 1 para
#     que `loglik / n` reproduzca la cota sin error de redondeo.
check(is.na(.loglik_implausible(cota, 1L, delta, cfg)),
      "3.5 en la cota exacta la guarda no dispara (desigualdad estricta)")
check(!is.na(.loglik_implausible(cota + 1, 1L, delta, cfg)),
      "3.6 por encima de la cota sí dispara")

# (d) Casos en los que la guarda debe OMITIRSE, no inventar un veredicto
check(is.na(.loglik_implausible(1e9, 100L, NA_real_, cfg)),
      "3.7 sin resolución estimable (< 2 valores distintos) la guarda se omite")
check(is.na(.loglik_implausible(NA_real_, 100L, delta, cfg)),
      "3.8 con logLik no finita la guarda se omite")
check(is.na(.loglik_implausible(1e9, 0L, delta, cfg)),
      "3.9 con n = 0 la guarda se omite")

# (e) EQUIVARIANZA DE ESCALA — la propiedad que hace que la guarda no pueda
#     calibrarse a un dataset concreto. Si los datos se multiplican por c, la
#     densidad se divide por c (logLik baja n*log(c)) y la resolución se
#     multiplica por c (la cota baja log(c)). El veredicto debe ser IDÉNTICO.
cat("\n-- 4. Equivarianza de escala de la guarda (B) --\n")
for (cte in c(1e-3, 0.5, 7, 1000)) {
  n_e <- 500L
  for (ll_e in c(-3700, 3000)) {          # un caso legítimo y otro patológico
    v0 <- .loglik_implausible(ll_e, n_e, delta, cfg)
    v1 <- .loglik_implausible(ll_e - n_e * log(cte), n_e, delta * cte, cfg)
    check(is.na(v0) == is.na(v1),
          sprintf("4.x mismo veredicto al reescalar por %g (logLik %g): %s",
                  cte, ll_e, if (is.na(v0)) "plausible" else "no acotada"))
  }
}

# ------------------------------------------------------------
# 5. Coherencia con la muestra común: por la vía normal ya no ocurre
# ------------------------------------------------------------
# Cierra el círculo: el mismo vector, analizado por `dist_fit_analyze()`, pasa
# por `build_analysis_sample()`, pierde los 800 ceros y la Pareto se ajusta con
# normalidad. La guarda queda como defensa en profundidad, no como parche.
cat("\n-- 5. Por la vía normal (con muestra común) la patología no aparece --\n")
res <- dist_fit_analyze(data.frame(coste = xz), "coste")
check(res$sample$n_excluded_zeros == n0,
      "5.1 la capa 0.5 excluye los 800 ceros antes de estimar")
pa <- res$motor$fits$pareto
check(isTRUE(pa$converged),                      "5.2 Pareto converge con normalidad")
check(pa$params$scale > .Machine$double.xmin,    "5.3 escala fuera del rango subnormal")
check(is.finite(pa$logLik) && pa$logLik < 0,     "5.4 logLik finita y negativa")
check(length(Filter(function(e) grepl("no acotada|frontera numérica", e$reason),
                    res$assessment$excluded)) == 0L,
      "5.5 ninguna guarda se activa por la vía normal")

cat("\nGUARDAS DE ADR-027 VERIFICADAS EN AMBOS SENTIDOS\n")
