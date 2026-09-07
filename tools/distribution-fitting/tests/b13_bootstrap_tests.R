# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b13_bootstrap_tests.R
# Tests productivos de B13.1: motor genérico de bootstrap no paramétrico.
#
# Verifica el contrato congelado en ADR-035:
#   P-1 remuestreo de sample$x, n constante
#   P-2 IC percentil con stats::quantile(type = 7)
#   P-3 una única set.seed() al inicio, réplicas secuenciales
#   P-5 se conservan todas las réplicas válidas
#   OD-9  réplica inválida -> FAILED, sin reparación
#   OD-10 motor genérico con estimador INYECTADO (sin switch de métodos)
#   OD-17 resúmenes condicionales al éxito, con contadores siempre presentes
#
# NO valida UI, ranking, AUTO, Assessment ni bootstrap paramétrico de GoF.
#
# Autor: BMK — Última actualización: 2026-09-03
# ============================================================
#
#   Rscript tests/b13_bootstrap_tests.R    # desde la raíz de la herramienta
#   Rscript b13_bootstrap_tests.R          # desde la carpeta tests/

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

SEED <- 20260903L
cat("== B13.1 — MOTOR GENÉRICO DE BOOTSTRAP NO PARAMÉTRICO ==\n")

# Adaptador sintético: demuestra que el motor NO depende de ninguna distribución.
adapter_mean <- function(x_b) list(success = TRUE, params = c(mu = mean(x_b)),
                                   status = "success", reason = NA_character_)

set.seed(1L)
X <- stats::rexp(400L, 0.01)

# ------------------------------------------------------------
# A. VALIDACIÓN DE ENTRADAS
# ------------------------------------------------------------
cat("\n-- A. Validación de entradas --\n")

bad <- function(...) .bootstrap_estimator(...)

r <- bad(numeric(0), adapter_mean, B = 10L, seed = SEED)
check(!r$valid && grepl("al menos 2", r$reason), "A.1 muestra vacía -> reject")
r <- bad(c(1), adapter_mean, B = 10L, seed = SEED)
check(!r$valid, "A.2 muestra de 1 observación -> reject")
r <- bad(letters[1:5], adapter_mean, B = 10L, seed = SEED)
check(!r$valid && grepl("num.rico", r$reason), "A.3 muestra no numérica -> reject")
for (v in list(c(1, 2, NA), c(1, 2, NaN), c(1, 2, Inf), c(1, 2, -Inf))) {
  r <- bad(v, adapter_mean, B = 10L, seed = SEED)
  check(!r$valid && grepl("no finitos", r$reason),
        sprintf("A.4 muestra con valor no finito (%s) -> reject", format(v[3])))
}
check(!bad(X, "no soy una funcion", B = 10L, seed = SEED)$valid,
      "A.5 estimator_fn no es función -> reject")

for (b in list(0, -5, 1.5, NA_real_, Inf, "1000", c(10, 20))) {
  r <- bad(X, adapter_mean, B = b, seed = SEED)
  check(!r$valid, sprintf("A.6 B inválido (%s) -> reject",
                          paste(format(b), collapse = ",")))
}
for (s in list(NA_real_, Inf, 1.5, "abc", c(1, 2), NULL)) {
  r <- bad(X, adapter_mean, B = 10L, seed = s)
  check(!r$valid, sprintf("A.7 seed inválida (%s) -> reject",
                          paste(format(s), collapse = ",")))
}
for (cl in list(0, 1, 1.5, -0.1, NA_real_, "0.95", c(0.9, 0.95))) {
  r <- bad(X, adapter_mean, B = 10L, seed = SEED, confidence_level = cl)
  check(!r$valid, sprintf("A.8 confidence_level inválido (%s) -> reject",
                          paste(format(cl), collapse = ",")))
}
check(is.na(.validate_confidence_level(0.95)),
      "A.9 se reutiliza el validador de nivel de B12, sin duplicar lógica")

# Adaptador que viola el contrato de salida.
r <- .bootstrap_estimator(X, function(x_b) 42, B = 20L, seed = SEED)
check(r$B_success == 0L && identical(names(r$failures$counts), "adapter_contract_violation"),
      "A.10 adaptador que no respeta list(success,...) -> todas FAILED, sin normalizar")

# ------------------------------------------------------------
# B. FINGERPRINT SHA-256 (OD-6)
# ------------------------------------------------------------
cat("\n-- B. Fingerprint SHA-256 --\n")

if (!requireNamespace("digest", quietly = TRUE)) {
  stop(paste("FALLO: el paquete 'digest' no está disponible. OD-6 exige esta",
             "dependencia declarada vía renv; sin ella el fingerprint no puede",
             "validarse y no se sustituye por ninguna otra solución."), call. = FALSE)
}
cat(sprintf("     digest %s disponible\n",
            as.character(utils::packageVersion("digest"))))

fp  <- .data_fingerprint(X)
fp2 <- .data_fingerprint(X)

check(identical(fp$fingerprint, fp2$fingerprint) && !is.na(fp$fingerprint),
      "B.1 el mismo vector exacto produce el mismo fingerprint")
check(is.character(fp$fingerprint) && length(fp$fingerprint) == 1L &&
      nchar(fp$fingerprint) == 64L &&
      grepl("^[0-9a-f]{64}$", fp$fingerprint),
      "B.2 escalar character, 64 caracteres, hexadecimal en minúsculas")
check(identical(fp$algo, "sha256"), "B.3 el algoritmo registrado es sha256")
check(identical(fp$status, "complete") && is.na(fp$reason),
      "B.4 status = complete, sin motivo de fallo")

# B.5 — SENSIBILIDAD AL ORDEN. Permutación DETERMINISTA (rev), no aleatoria.
# Es el requisito decisivo: con semilla fija `sample()` elige ÍNDICES, de modo
# que permutar x cambia las réplicas aunque el multiconjunto sea idéntico.
Xr <- rev(X)
check(identical(sort(X), sort(Xr)) && !identical(X, Xr),
      "B.5a rev(X) es el mismo multiconjunto en distinto orden")
check(!identical(.data_fingerprint(Xr)$fingerprint, fp$fingerprint),
      "B.5b permutación -> fingerprint DISTINTO (sensible al orden)")
idx <- c(2L, 1L, seq(3L, length(X)))          # segunda permutación explícita
check(!identical(.data_fingerprint(X[idx])$fingerprint, fp$fingerprint),
      "B.5c intercambiar dos elementos ya cambia el fingerprint")

# B.6 — cambio de un único valor.
Xm <- X; Xm[7L] <- Xm[7L] + 1e-9
check(!identical(.data_fingerprint(Xm)$fingerprint, fp$fingerprint),
      "B.6 alterar un solo valor (1e-9) -> fingerprint distinto")

# B.7 — dos llamadas independientes, con estado de RNG distinto entre medias.
set.seed(1234L); a1 <- .data_fingerprint(X)$fingerprint
set.seed(4321L); invisible(stats::runif(10L)); a2 <- .data_fingerprint(X)$fingerprint
check(identical(a1, a2),
      "B.7 determinista: no depende del estado del RNG ni de la sesión")

# B.8 - B.11 — entradas inválidas: NUNCA se hashea un objeto inválido.
inval <- list(
  list("B.8  NA",           c(1, 2, NA)),
  list("B.9  NaN",          c(1, 2, NaN)),
  list("B.10 Inf",          c(1, 2, Inf)),
  list("B.10 -Inf",         c(1, 2, -Inf)),
  list("B.11 no numeric",   letters[1:5]),
  list("B.11 lista",        list(1, 2, 3)),
  list("B.11 vacio",        numeric(0))
)
for (cs in inval) {
  r <- .data_fingerprint(cs[[2]])
  check(is.na(r$fingerprint) && identical(r$status, "invalid_input") &&
        !is.na(r$reason),
        sprintf("%s -> rechazado con motivo auditable, sin hash", cs[[1]]))
}
check(grepl("NaN", .data_fingerprint(c(1, NaN))$reason) &&
      grepl("ausentes|NA", .data_fingerprint(c(1, NA))$reason),
      "B.11b NaN y NA se distinguen en el motivo (representaciones distintas)")

# B.12 — el motor propaga EXACTAMENTE el fingerprint de x.
rb <- .bootstrap_estimator(X, adapter_mean, B = 20L, seed = SEED)
check(identical(rb$data_fingerprint, fp$fingerprint) &&
      identical(rb$fingerprint_algo, "sha256") &&
      identical(rb$fingerprint_status, "complete"),
      "B.12 .bootstrap_estimator() propaga el fingerprint de x sin alterarlo")

# B.13 — misma x/seed/B/config -> fingerprint y réplicas idénticos.
rb2 <- .bootstrap_estimator(X, adapter_mean, B = 20L, seed = SEED)
check(identical(rb$data_fingerprint, rb2$data_fingerprint) &&
      identical(rb$replicates, rb2$replicates),
      "B.13 misma configuración -> mismo fingerprint y mismas réplicas")

# B.14 — misma seed/B/config, x permutada.
rbr <- .bootstrap_estimator(Xr, adapter_mean, B = 20L, seed = SEED)
check(!identical(rbr$data_fingerprint, rb$data_fingerprint),
      "B.14a x permutada -> fingerprint distinto: NO es la misma ejecución")
# La desigualdad de réplicas es consecuencia esperada, no el criterio: con la
# misma semilla se eligen los mismos ÍNDICES sobre un vector reordenado. Se
# comprueba de forma robusta (no se exige desigualdad elemento a elemento).
check(!identical(rbr$replicates, rb$replicates),
      "B.14b las réplicas difieren: los mismos índices sobre otro orden")

# B.15 — sin `digest` no hay sustituto. Se verifica el contrato de la rama.
check(any(grepl("requireNamespace", deparse(.data_fingerprint))) &&
      !any(grepl("md5|MD5|md5sum", deparse(.data_fingerprint))),
      "B.15 guarda de dependencia presente y sin fallback a MD5")
check(any(grepl("sha256", deparse(.data_fingerprint))) &&
      any(grepl("serialize", deparse(.data_fingerprint))),
      "B.16 algo y serialize son explícitos, no defectos de digest()")

# ------------------------------------------------------------
# C. REPRODUCIBILIDAD
# ------------------------------------------------------------
cat("\n-- C. Reproducibilidad --\n")

r1 <- .bootstrap_estimator(X, adapter_mean, B = 200L, seed = SEED)
r2 <- .bootstrap_estimator(X, adapter_mean, B = 200L, seed = SEED)
r3 <- .bootstrap_estimator(X, adapter_mean, B = 200L, seed = SEED + 1L)
check(identical(r1$replicates, r2$replicates),
      "C.1 misma x/seed/B/estimador -> réplicas IDÉNTICAS (identical, sin tolerancia)")
check(identical(r1$ci, r2$ci) && identical(r1$se, r2$se),
      "C.2 resúmenes idénticos")
check(!identical(r1$replicates, r3$replicates),
      "C.3 cambiar la semilla cambia la ejecución")
check(identical(r1$seed, SEED), "C.4 la semilla se registra en la salida")

# El RNG global no queda contaminado de forma que impida repetir el experimento:
# el motor fija la semilla al inicio y no depende del estado previo.
set.seed(999L); a <- .bootstrap_estimator(X, adapter_mean, B = 50L, seed = SEED)
set.seed(111L); b <- .bootstrap_estimator(X, adapter_mean, B = 50L, seed = SEED)
check(identical(a$replicates, b$replicates),
      "C.5 el resultado NO depende del estado previo del RNG (P-3: set.seed al inicio)")

# ------------------------------------------------------------
# D. REMUESTREO
# ------------------------------------------------------------
cat("\n-- D. Remuestreo --\n")

adapter_probe <- function(x_b) list(
  success = TRUE,
  params = c(n_b = length(x_b), fuera = sum(!(x_b %in% X)),
             distintos = length(unique(x_b))),
  status = "success", reason = NA_character_)

rp <- .bootstrap_estimator(X, adapter_probe, B = 300L, seed = SEED)
check(all(rp$replicates[, "n_b"] == length(X)),
      "D.1 todas las réplicas tienen exactamente n observaciones")
check(all(rp$replicates[, "fuera"] == 0),
      "D.2 solo se usan valores de x: no se reintroduce nada externo")
check(any(rp$replicates[, "distintos"] < length(X)),
      "D.3 hay reemplazamiento (alguna réplica repite valores)")
check(max(rp$replicates[, "distintos"]) <= length(X),
      "D.4 ninguna réplica tiene más valores distintos que la muestra")

# ------------------------------------------------------------
# E. MOTOR GENÉRICO
# ------------------------------------------------------------
cat("\n-- E. Motor genérico (estimador inyectado) --\n")

check(!any(grepl("switch", deparse(.bootstrap_estimator))),
      "E.1 el motor NO contiene ningún switch de métodos (OD-10)")
for (nm_ in c("mle", "mom", "lmom", "\\.pm_fit", "dgamma", "dweibull")) {
  check(!any(grepl(nm_, deparse(.bootstrap_estimator))),
        sprintf("E.2 el motor no menciona '%s': no conoce los estimadores", nm_))
}
rm_ <- .bootstrap_estimator(X, adapter_mean, B = 100L, seed = SEED,
                            theta_hat = c(mu = mean(X)))
check(rm_$valid && identical(colnames(rm_$replicates), "mu"),
      "E.3 funciona con un estimador sintético (media), sin distribución alguna")
check(nrow(rm_$replicates) == rm_$B_success, "E.4 filas de la matriz == B_success")
check(is.finite(rm_$se[["mu"]]) && rm_$se[["mu"]] > 0, "E.5 SE finito y positivo")
# Contraste independiente contra la teoría: SE bootstrap de la media ~ sd(x)/sqrt(n).
check(abs(rm_$se[["mu"]] - stats::sd(X) / sqrt(length(X))) /
      (stats::sd(X) / sqrt(length(X))) < 0.25,
      "E.6 el SE bootstrap de la media es del orden de sd(x)/sqrt(n)")

# ------------------------------------------------------------
# F. MLE
# ------------------------------------------------------------
cat("\n-- F. MLE --\n")

set.seed(7L)
xe <- stats::rexp(500L, 0.02)
fe <- .estimate("exponential", xe, "mle")
ae <- .bootstrap_adapter_fit("exponential", "mle")
be <- .bootstrap_estimator(xe, ae, B = 300L, seed = SEED, theta_hat = fe$params,
                           estimator = "mle", distribution = "exponential")
check(be$valid && identical(be$status, "complete"), "F.1 exponential MLE: bootstrap válido")
check(be$B_requested == 300L && be$B_success == 300L && be$B_failed == 0L,
      "F.2 contabilidad: 300 = 300 + 0")
check(identical(colnames(be$replicates), "rate"), "F.3 nombre canónico del parámetro")
check(dim(be$replicates)[1] == be$B_success && dim(be$replicates)[2] == 1L,
      "F.4 dimensiones B_success x k")
check(is.finite(be$se[["rate"]]) && be$se[["rate"]] > 0, "F.5 SE finito y positivo")
# Referencia asintótica: SE(rate_hat) ~ rate/sqrt(n). Comparación de ORDEN, no exacta.
check(abs(be$se[["rate"]] - fe$params$rate / sqrt(length(xe))) /
      (fe$params$rate / sqrt(length(xe))) < 0.25,
      "F.6 SE bootstrap coherente con rate_hat/sqrt(n)")
check(is.finite(be$bias[["rate"]]), "F.7 sesgo calculado (diagnóstico)")
check(be$ci["rate", "lower"] > 0 && be$ci["rate", "upper"] > be$ci["rate", "lower"],
      "F.8 IC positivo y ordenado")
check(be$ci["rate", "lower"] < fe$params$rate &&
      fe$params$rate < be$ci["rate", "upper"],
      "F.9 el IC contiene la estimación original")
check(identical(.bootstrap_estimator(xe, ae, B = 300L, seed = SEED)$replicates,
                be$replicates),
      "F.10 reproducible con la misma semilla")

set.seed(11L)
xn <- stats::rnorm(400L, 100, 15)
fn <- .estimate("normal", xn, "mle")
bn <- .bootstrap_estimator(xn, .bootstrap_adapter_fit("normal", "mle"),
                           B = 300L, seed = SEED, theta_hat = fn$params,
                           estimator = "mle", distribution = "normal")
check(bn$valid && identical(colnames(bn$replicates), c("mean", "sd")),
      "F.11 normal MLE: dos parámetros con nombres canónicos")
check(all(bn$se > 0) && all(is.finite(bn$se)), "F.12 ambos SE positivos")
check(abs(bn$se[["mean"]] - fn$params$sd / sqrt(length(xn))) /
      (fn$params$sd / sqrt(length(xn))) < 0.25,
      "F.13 SE(mean) bootstrap coherente con sd/sqrt(n)")
check(bn$ci["sd", "lower"] > 0, "F.14 IC de sd estrictamente positivo")

# ------------------------------------------------------------
# G. PERCENTILE MATCHING
# ------------------------------------------------------------
cat("\n-- G. Percentile Matching --\n")

set.seed(13L)
xg <- stats::rgamma(500L, shape = 2, scale = 500)
P3W <- DFIT_PM$presets$p3w$percentiles
fpm <- .pm_fit("gamma", xg, P3W)
check(identical(fpm$status, "success"), "G.1 el ajuste PM original converge")
apm <- .bootstrap_adapter_pm("gamma", P3W)
bpm <- .bootstrap_estimator(xg, apm, B = 200L, seed = SEED, theta_hat = fpm$params,
                            estimator = "pm", distribution = "gamma",
                            pm_percentiles = P3W)
check(bpm$B_success > 0L, "G.2 PM produce réplicas válidas")
check(identical(bpm$pm_percentiles, P3W),
      "G.3 los percentiles se conservan y se registran en la salida")
check(identical(colnames(bpm$replicates), c("shape", "scale")),
      "G.4 parámetros canónicos de gamma")
# El adaptador ejecuta EXACTAMENTE .pm_fit con la misma configuración: se verifica
# reproduciendo una réplica a mano con la misma secuencia de RNG.
set.seed(SEED); x_b1 <- sample(xg, length(xg), replace = TRUE)
man <- .pm_fit("gamma", x_b1, P3W)
check(identical(man$status, "success") &&
      max(abs(unlist(man$params) - bpm$replicates[1, ])) < 1e-12,
      "G.5 la primera réplica coincide con .pm_fit() ejecutado a mano")
check(identical(bpm$estimator, "pm") && identical(bpm$distribution, "gamma"),
      "G.6 metadatos de trazabilidad registrados")

# Una configuración PM que colapsa debe FALLAR, no repararse.
x_col <- c(rep(1000, 480L), 1, 2, 3, seq(5000, 21000, by = 1000))
bcol <- .bootstrap_estimator(x_col, .bootstrap_adapter_pm("gamma", c(.25, .50, .75)),
                             B = 50L, seed = SEED, estimator = "pm",
                             distribution = "gamma")
check(bcol$B_failed > 0L && "reject_scale_collapse" %in% names(bcol$failures$counts),
      "G.7 reject_scale_collapse se propaga como FAILED, sin reparar")

# ------------------------------------------------------------
# H. MoM / L-MOMENTOS (solo combinaciones realmente soportadas)
# ------------------------------------------------------------
cat("\n-- H. MoM y L-momentos --\n")

check(!is.null(DFIT_MOM$gamma) && !is.null(DFIT_LMOM$exponential),
      "H.1 se usan solo combinaciones existentes en los registros productivos")
bmom <- .bootstrap_estimator(xg, .bootstrap_adapter_fit("gamma", "mom"),
                             B = 150L, seed = SEED, estimator = "mom",
                             distribution = "gamma")
check(bmom$valid && identical(colnames(bmom$replicates), c("shape", "scale")),
      "H.2 gamma por MoM: bootstrap válido")
set.seed(SEED); xb1 <- sample(xg, length(xg), replace = TRUE)
check(max(abs(unlist(.estimate("gamma", xb1, "mom")$params) - bmom$replicates[1, ])) < 1e-12,
      "H.3 el adaptador reutiliza el estimador productivo (.estimate), no lo reimplementa")

blm <- .bootstrap_estimator(xe, .bootstrap_adapter_fit("exponential", "lmom"),
                            B = 150L, seed = SEED, estimator = "lmom",
                            distribution = "exponential")
check(blm$valid && identical(colnames(blm$replicates), "rate"),
      "H.4 exponential por L-momentos: bootstrap válido")
check(is.null(DFIT_LMOM$gamma), "H.5 no se inventa L-momentos para gamma (no existe)")

# ------------------------------------------------------------
# I. CONTABILIDAD DE FALLOS
# ------------------------------------------------------------
cat("\n-- I. Contabilidad de fallos --\n")

# Adaptador controlado: falla de forma determinista por posición de llamada.
make_flaky <- function() {
  i <- 0L
  function(x_b) {
    i <<- i + 1L
    if (i %% 3L == 0L) return(list(success = FALSE, params = NULL,
                                   status = "sintetico_a", reason = "cada 3"))
    if (i %% 5L == 0L) return(list(success = FALSE, params = NULL,
                                   status = "sintetico_b", reason = "cada 5"))
    list(success = TRUE, params = c(mu = mean(x_b)), status = "success",
         reason = NA_character_)
  }
}
B <- 60L
rf <- .bootstrap_estimator(X, make_flaky(), B = B, seed = SEED,
                           theta_hat = c(mu = mean(X)))
esperado_a <- sum(seq_len(B) %% 3L == 0L)
esperado_b <- sum(seq_len(B) %% 5L == 0L & seq_len(B) %% 3L != 0L)
check(rf$B_requested == rf$B_success + rf$B_failed,
      "I.1 B_requested == B_success + B_failed")
check(rf$B_failed == esperado_a + esperado_b,
      sprintf("I.2 fallos exactos: %d", esperado_a + esperado_b))
check(rf$failures$counts[["sintetico_a"]] == esperado_a &&
      rf$failures$counts[["sintetico_b"]] == esperado_b,
      "I.3 motivos agrupados con conteo correcto por estado")
check(abs(rf$success_rate - rf$B_success / rf$B_requested) < 1e-15,
      "I.4 success_rate coherente")
check(nrow(rf$replicates) == rf$B_success,
      "I.5 las réplicas fallidas NO aparecen en la matriz (sin filas NA)")
check(all(is.finite(rf$replicates)), "I.6 la matriz no contiene NA")
check(length(rf$failures$examples) == 2L &&
      identical(rf$failures$examples$sintetico_a$reason, "cada 3"),
      "I.7 un ejemplo por estado, sin duplicar el texto B veces")
# No se reintenta: el número total de llamadas al adaptador es exactamente B.
cnt <- 0L
counting <- function(x_b) { cnt <<- cnt + 1L
  if (cnt %% 2L == 0L) list(success = FALSE, params = NULL, status = "x", reason = NA_character_)
  else list(success = TRUE, params = c(mu = mean(x_b)), status = "success", reason = NA_character_) }
invisible(.bootstrap_estimator(X, counting, B = 40L, seed = SEED))
check(cnt == 40L, "I.8 exactamente B llamadas: no se reintenta ninguna réplica fallida")

# ------------------------------------------------------------
# J. CASOS LÍMITE DE B_success
# ------------------------------------------------------------
cat("\n-- J. B_success = 0, 1 y >= 2 --\n")

r0 <- .bootstrap_estimator(X, function(x_b) list(success = FALSE, params = NULL,
                                                 status = "siempre_falla", reason = "no"),
                           B = 25L, seed = SEED, theta_hat = c(mu = mean(X)))
check(r0$B_success == 0L && !r0$valid && identical(r0$status, "failed"),
      "J.1 B_success = 0 -> failed")
check(is.null(r0$replicates) && is.null(r0$se) && is.null(r0$bias) && is.null(r0$ci),
      "J.2 B_success = 0 -> sin réplicas, SE, sesgo ni IC")
check(r0$B_failed == 25L && r0$failures$counts[["siempre_falla"]] == 25L,
      "J.3 los fallos siguen contabilizándose")

make_one <- function() { i <- 0L
  function(x_b) { i <<- i + 1L
    if (i == 1L) list(success = TRUE, params = c(mu = mean(x_b)), status = "success",
                      reason = NA_character_)
    else list(success = FALSE, params = NULL, status = "solo_la_primera", reason = "no") } }
r1s <- .bootstrap_estimator(X, make_one(), B = 25L, seed = SEED,
                            theta_hat = c(mu = mean(X)))
check(r1s$B_success == 1L, "J.4 B_success = 1")
check(is.finite(r1s$bias[["mu"]]),
      "J.5 B_success = 1 -> el SESGO SÍ es formalmente calculable (la media existe)")
check(is.null(r1s$se),
      "J.6 B_success = 1 -> SE NO disponible (sd muestral no definida), no se inventa")
check(isTRUE(r1s$ci_degenerate) && r1s$ci["mu", "lower"] == r1s$ci["mu", "upper"],
      "J.7 B_success = 1 -> IC computable pero DEGENERADO a un punto, y marcado")
check(!r1s$valid && identical(r1s$status, "partial") && grepl("1 r.plica", r1s$reason),
      "J.8 B_success = 1 -> valid = FALSE con motivo auditable")

r2 <- .bootstrap_estimator(X, adapter_mean, B = 50L, seed = SEED,
                           theta_hat = c(mu = mean(X)))
check(r2$B_success >= 2L && r2$valid && !isTRUE(r2$ci_degenerate),
      "J.9 B_success >= 2 -> SE, sesgo e IC disponibles")

# ------------------------------------------------------------
# K. QUANTILE TYPE 7 — blindaje contra sustitución accidental
# ------------------------------------------------------------
cat("\n-- K. type = 7 --\n")

rk <- .bootstrap_estimator(X, adapter_mean, B = 40L, seed = SEED)
v  <- rk$replicates[, "mu"]
q7 <- stats::quantile(v, probs = c(0.025, 0.975), type = 7, names = FALSE)
q1 <- stats::quantile(v, probs = c(0.025, 0.975), type = 1, names = FALSE)
check(identical(rk$quantile_type, 7L), "K.1 quantile_type = 7 se registra en la salida")
check(max(abs(as.numeric(rk$ci["mu", ]) - q7)) == 0,
      "K.2 el IC coincide EXACTAMENTE con quantile(type = 7)")
check(max(abs(q7 - q1)) > 0,
      "K.3 con estas réplicas type=7 y type=1 difieren: el test discrimina de verdad")
check(max(abs(as.numeric(rk$ci["mu", ]) - q1)) > 0,
      "K.4 el IC NO coincide con type=1 (blindaje ante sustitución)")
# El extremo inferior es interpolado, NO una réplica observada: es exactamente
# la razón por la que el soporte se justifica por convexidad y no por pertenencia.
check(!any(abs(v - rk$ci["mu", "lower"]) < .Machine$double.eps),
      "K.5 el extremo del IC es INTERPOLADO, no una réplica observada")

# Nivel de confianza configurable.
r90 <- .bootstrap_estimator(X, adapter_mean, B = 200L, seed = SEED, confidence_level = 0.90)
r99 <- .bootstrap_estimator(X, adapter_mean, B = 200L, seed = SEED, confidence_level = 0.99)
# Mismo B y misma semilla => mismas réplicas: la comparación aísla el nivel.
w <- function(o) o$ci["mu", "upper"] - o$ci["mu", "lower"]
check(identical(r90$replicates, r99$replicates),
      "K.6a con la misma semilla y B, las réplicas son las mismas")
check(w(r90) < w(r99), "K.6b el IC se ensancha con el nivel de confianza")
check(abs(r90$confidence_level - 0.90) < 1e-12, "K.7 el nivel se registra")

# ------------------------------------------------------------
# L. SOPORTE
# ------------------------------------------------------------
cat("\n-- L. Soporte del IC --\n")

check(all(be$replicates[, "rate"] > 0) && be$ci["rate", "lower"] > 0,
      "L.1 parámetro positivo: réplicas > 0 => IC > 0 (convexidad de (0, Inf))")
check(all(bn$replicates[, "sd"] > 0) && bn$ci["sd", "lower"] > 0,
      "L.2 sd > 0 en todas las réplicas => IC > 0")

set.seed(17L)
xgeo <- stats::rgeom(400L, 0.3)
fgeo <- .estimate("geometric", xgeo, "mle")
bgeo <- .bootstrap_estimator(xgeo, .bootstrap_adapter_fit("geometric", "mle",
                                                          family = "discrete"),
                             B = 200L, seed = SEED, theta_hat = fgeo$params,
                             estimator = "mle", distribution = "geometric")
if (isTRUE(bgeo$valid)) {
  check(all(bgeo$replicates[, "prob"] > 0 & bgeo$replicates[, "prob"] < 1) &&
        bgeo$ci["prob", "lower"] > 0 && bgeo$ci["prob", "upper"] < 1,
        "L.3 probabilidad: IC dentro de (0,1) por convexidad del soporte")
}

# ------------------------------------------------------------
# M. CONTRATO OD-17
# ------------------------------------------------------------
cat("\n-- M. OD-17 --\n")

for (o in list(be, bpm, rf, r0, r1s)) {
  check(isTRUE(o$summaries_conditional_on_success),
        "M.1 summaries_conditional_on_success = TRUE, SIEMPRE (haya fallos o no)")
  check(!is.null(o$B_requested) && !is.null(o$B_success) && !is.null(o$B_failed) &&
        !is.null(o$success_rate) && !is.null(o$failures),
        "M.2 contadores y motivos siempre presentes")
}
check(is.na(be$success_rate) || abs(be$success_rate - 1) < 1e-15,
      "M.3 success_rate = 1 cuando no hay fallos")
# No hay umbral: un bootstrap con tasa baja sigue publicando resúmenes.
check(rf$valid && rf$success_rate < 0.9,
      "M.4 success_rate < 0,9 NO invalida: no hay umbral (OD-11 abierta)")

# ------------------------------------------------------------
# N. AISLAMIENTO
# ------------------------------------------------------------
cat("\n-- N. Aislamiento --\n")

set.seed(19L)
df <- data.frame(coste = stats::rgamma(600L, shape = 2, scale = 500))
res <- dist_fit_analyze(df, "coste")
check(all(vapply(res$motor$fits, function(f) is.null(f$inference), TRUE)),
      "N.1 el análisis por defecto no ejecuta inferencia ni bootstrap")
check(all(vapply(res$motor$fits, function(f) is.null(f$bootstrap), TRUE)),
      "N.2 no aparece ningún bloque bootstrap en los ajustes")
check(identical(res$motor$method, "mle") && !is.null(res$assessment) &&
      !is.null(res$decision_engine),
      "N.3 AUTO, Assessment y Decision Engine intactos")
check(identical(DFIT_SCHEMA_VERSION, "1.1.0"), "N.4 schema sin cambios (1.1.0)")

# B12 sigue funcionando.
u <- .mle_uncertainty(c(list(id = "exponential", method = "mle", converged = TRUE,
                             message = NA_character_), fe), xe)
check(isTRUE(u$valid) && identical(u$method, "analytic_mle"),
      "N.5 la inferencia analítica de B12 sigue operativa")
mo <- .motor(res$sample, res$candidates, method = "mle", inference = TRUE)
check(!is.null(mo$fits$gamma$inference) &&
      identical(mo$fits$gamma$inference$method, "analytic_mle"),
      "N.6 el contrato de fit$inference de B12 NO se ha modificado")
check(identical(mo$fits$gamma$params, res$motor$fits$gamma$params),
      "N.7 fit$params conserva su significado y su valor")

# PM sigue fuera del ranking.
check(inherits(try(.motor(res$sample, res$candidates, method = "pm"), silent = TRUE),
               "try-error"),
      "N.8 .motor sigue rechazando method = 'pm'")
check(identical(DFIT_PM$default_preset, "p3w"), "N.9 registro PM intacto")

# ------------------------------------------------------------
# O. AVISOS
# ------------------------------------------------------------
cat("\n-- O. Avisos --\n")
cap <- list()
withCallingHandlers({
  invisible(.bootstrap_estimator(xe, .bootstrap_adapter_fit("exponential", "mle"),
                                 B = 100L, seed = SEED))
  invisible(.bootstrap_estimator(xn, .bootstrap_adapter_fit("normal", "mle"),
                                 B = 100L, seed = SEED))
  invisible(.bootstrap_estimator(xg, .bootstrap_adapter_pm("gamma", P3W),
                                 B = 100L, seed = SEED))
  invisible(.bootstrap_estimator(X, adapter_mean, B = 100L, seed = SEED))
}, warning = function(w) { cap[[length(cap) + 1L]] <<- conditionMessage(w)
                           invokeRestart("muffleWarning") })
if (length(cap) > 0L) {
  cat("     avisos observados (CLASIFICAR, no silenciar):\n")
  for (m in unique(unlist(cap))) cat(sprintf("       - %s\n", m))
}
check(length(cap) == 0L, "O.1 sin avisos en el camino nominal del bootstrap")
check(!any(grepl("suppressWarnings", deparse(.bootstrap_estimator))),
      "O.2 el motor no usa suppressWarnings")

cat("\nB13.1 — MOTOR DE BOOTSTRAP NO PARAMÉTRICO VERIFICADO\n")
