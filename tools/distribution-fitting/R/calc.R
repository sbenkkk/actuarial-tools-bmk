# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: calc.R — núcleo matemático de la herramienta (sin Shiny, regla 7)
# Autor: BMK
# Última actualización: 2026-07-25
# ============================================================
#
# Motor de Tool-02. Ejecutable con source("R/calc.R") desde una consola de R, sin
# la aplicación: no depende de Shiny ni de los componentes del framework. Las
# funciones locales de la herramienta no llevan prefijo bmk_ (regla 3); los
# helpers internos usan prefijo de punto ".".
#
# Arquitectura por capas del diseño aprobado (§10, §11):
#   Profiler -> Motor -> Diagnostics -> Assessment -> Text Builders -> View Model
#
# ORGANIZACIÓN DEL ARCHIVO (bloques):
#   0. Constantes                         <- B1
#   1. Profiler (capa 0)                  <- B1
#   2. Candidate Distribution Selector    <- B1
#   3. Decision Engine (cableado)         <- B1 (estructura; valores en decision_engine.md)
#   4. Orchestrator + stubs de capas       <- B1 (motor/diagnostics/assessment/... = stubs)
#
# Alcance B1: preparar la base para los bloques siguientes. NO se ajusta ninguna
# distribución, NO se calcula bondad de ajuste y NO se genera texto ni View Model.


# ============================================================
# 0. CONSTANTES
# ============================================================

# Especificaciones estáticas de las distribuciones candidatas (diseño §4).
# Cada registro: id (clave interna), label (nombre legible) y n_params (para la
# parsimonia en bloques posteriores). Fuente única de verdad (regla 8).

# Familia continua recomendable (§4.1).
DFIT_CONTINUOUS_DISTS <- list(
  list(id = "exponential", label = "Exponencial",         n_params = 1L),
  list(id = "gamma",       label = "Gamma",               n_params = 2L),
  list(id = "weibull",     label = "Weibull",             n_params = 2L),
  list(id = "lognormal",   label = "Lognormal",           n_params = 2L),
  list(id = "loglogistic", label = "Loglogística (Fisk)", n_params = 2L),
  list(id = "pareto",      label = "Pareto (Lomax)",      n_params = 2L),
  list(id = "burr",        label = "Burr (tipo XII)",     n_params = 3L)
)

# Control (§4.3): la Normal se ajusta internamente pero NO ocupa puesto en el
# ranking de recomendación.
DFIT_CONTINUOUS_CONTROL <- list(
  list(id = "normal", label = "Normal (control)", n_params = 2L, role = "control")
)

# Familia discreta (§4.2). Zero-inflated / Binomial quedan fuera de v1 (§4.2).
DFIT_DISCRETE_DISTS <- list(
  list(id = "poisson",           label = "Poisson",            n_params = 1L),
  list(id = "negative_binomial", label = "Binomial Negativa",  n_params = 2L),
  list(id = "geometric",         label = "Geométrica",         n_params = 1L)
)

# Etapas del pipeline aún no implementadas (para los stubs). Motor (B2),
# Diagnostics (B3), Assessment (B4) y Text Builders (B5) implementados;
# el View Model llega en B6.
DFIT_PENDING_LAYERS <- c(
  view_model = "B6"
)

#' Configuración de ejecución por defecto de Tool-02
#'
#' Constantes de ejecución (regla 8). La parametrización del CRITERIO (pesos,
#' umbrales de decisión) NO vive aquí, sino en `decision_engine.md` (§7.8).
#'
#' @return Lista de constantes de ejecución nombradas.
dfit_default_config <- function() {
  list(
    # Tolerancia para considerar un valor "entero" (detección de recuento).
    integer_tol = 1e-8,
    # Máximo de valores distintos para clasificar como discreta (refinamiento de
    # "pocos valores distintos", §3.3). CALIBRADO en ADR-020: pasa de Inf a 50.
    # Las candidatas discretas de v1 (Poisson, binomial negativa, geométrica) son
    # para recuentos de valor bajo; por encima de 50 valores distintos la variable
    # se trata como continua (una severidad en euros redondeada a entero cumple la
    # regla §3.3 pero no es un recuento). La familia sigue siendo forzable a mano.
    discrete_max_unique = 50,
    # Esperanza mínima por celda en el chi-cuadrado discreto (ADR-019). Práctica
    # estándar del test: se agrupan categorías adyacentes hasta alcanzarla.
    gof_min_expected = 5,
    # Suelo relajado (regla de Cochran) al que se recurre cuando el suelo estándar
    # deja menos de 1 grado de libertad, típico en muestras pequeñas. Se registra
    # en `gof_note` cuando se usa: el estadístico sigue siendo válido, pero su
    # aproximación a la chi-cuadrado es menos precisa.
    gof_min_expected_relaxed = 1,
    # Tope defensivo de categorías a barrer en el chi-cuadrado antes de agrupar.
    # El soporte se acota por cuantil de la distribución ajustada; este tope solo
    # actúa si el ajuste es tan malo que el cuantil se dispara.
    gof_max_scan = 10000L,
    # Mínimo de observaciones de la muestra común para poder analizar (ADR-026).
    # No es arbitrario: la candidata con más parámetros es Burr (3) y `.fit_one`
    # exige n >= n_params + 1 = 4; 5 es el menor entero que deja estimables las
    # siete candidatas continuas.
    min_obs_analysis = 5L,
    # Guarda (A) de ADR-027: menor doble NORMALIZADO. Por debajo se entra en el
    # rango subnormal, donde la mantisa pierde bits hasta quedarse sin cifras
    # significativas; un parámetro estimado ahí no tiene ninguna cifra válida.
    # Constante del estándar IEEE-754, no un umbral elegido.
    param_min_normal = .Machine$double.xmin,
    # Guarda (B) de ADR-027: tolerancia sobre la cota de plausibilidad
    # mean(log f) <= -log(delta). K = 0 -> cota estricta. No se introduce holgura
    # mientras no haya evidencia de falsos positivos.
    loglik_plausibility_k = 0,
    # B12.2 (ADR-034). Constante del paso de la Hessiana por diferencias centrales:
    #   h_j = hessian_step_c * max(|u_j|, 1)   en la escala computacional u.
    # NO es un umbral elegido: eps^(1/4) es el balance teorico entre truncamiento
    # (~h^2 |f''''|) y redondeo (~eps |f| / h^2) para SEGUNDAS derivadas, y quedo
    # CONFIRMADO por el benchmark B12.1 (mediana del error relativo de Frobenius
    # 9,8e-08 frente a 1,9e-05 con eps^(1/3)), dentro de la meseta de buen
    # comportamiento de las cinco familias con referencia analitica.
    hessian_step_c = .Machine$double.eps^(1/4),
    # Nivel de confianza por defecto de los intervalos analiticos (OD-16).
    confidence_level = 0.95,
    # B14.1 (ADR-037). Tolerancia PURAMENTE COMPUTACIONAL para comparar dos
    # niveles de confianza. NO es un umbral metodologico: existe solo para que
    # 0.95 y 0.95 calculados por caminos distintos no se declaren "distintos"
    # por el ultimo bit de un double. Cualquier diferencia real de nivel es de
    # orden 1e-2, catorce ordenes por encima.
    confidence_level_tol = 1e-12
  )
}


# ============================================================
# 1. PROFILER (capa 0) — diseño §3.4
# ============================================================

#' Asimetría muestral (coeficiente de momento g1)
#'
#' g1 = m3 / m2^(3/2), con m_k el k-ésimo momento central muestral. Implementación
#' propia (política 2.2). Devuelve NA si la varianza es nula o n < 3.
#'
#' @param v Vector numérico sin NA.
#' @return Asimetría (numérico) o NA_real_.
.sample_skewness <- function(v) {
  n <- length(v)
  if (n < 3L) return(NA_real_)
  m <- mean(v)
  m2 <- mean((v - m)^2)
  if (m2 <= 0) return(NA_real_)
  mean((v - m)^3) / (m2^(3 / 2))
}

#' Exceso de curtosis muestral (g2)
#'
#' g2 = m4 / m2^2 - 3 (0 para la Normal). Implementación propia. NA si la
#' varianza es nula o n < 4.
#'
#' @param v Vector numérico sin NA.
#' @return Exceso de curtosis (numérico) o NA_real_.
.sample_kurtosis <- function(v) {
  n <- length(v)
  if (n < 4L) return(NA_real_)
  m <- mean(v)
  m2 <- mean((v - m)^2)
  if (m2 <= 0) return(NA_real_)
  mean((v - m)^4) / (m2^2) - 3
}

#' Soporte observado de la variable
#'
#' @param v Vector numérico sin NA (no vacío).
#' @return "positive" (>0), "nonnegative" (>=0 con algún 0) o "real" (con negativos).
.observed_support <- function(v) {
  mn <- min(v)
  if (mn > 0) "positive" else if (mn == 0) "nonnegative" else "real"
}

#' Detector de tipo de variable (continua vs discreta) — diseño §3.3
#'
#' Regla del diseño: una variable es de recuento (discreta) si todos sus valores
#' son enteros y no negativos. El umbral de "pocos valores distintos"
#' (`discrete_max_unique`) es el refinamiento calibrable previsto por §3.3,
#' calibrado en ADR-020 a 50 (antes Inf = desactivado). No hay heurísticas nuevas:
#' la regla §3.3 no cambia, solo se activa su parámetro.
#'
#' @param v Vector numérico sin NA (no vacío).
#' @param config Lista de configuración (`integer_tol`, `discrete_max_unique`).
#' @return "discrete" o "continuous".
detect_variable_type <- function(v, config = dfit_default_config()) {
  is_integer_valued <- all(abs(v - round(v)) <= config$integer_tol)
  is_non_negative   <- min(v) >= 0
  few_unique        <- length(unique(v)) <= config$discrete_max_unique
  if (is_integer_valued && is_non_negative && few_unique) "discrete" else "continuous"
}

#' Perfilado del dataset sobre la variable seleccionada (capa 0)
#'
#' Construye el objeto descriptivo que consumen los bloques siguientes. Es
#' descriptivo: no ajusta ni decide (§3.4). No genera texto de usuario.
#'
#' @param x Vector numérico de la variable a modelizar (puede contener NA).
#' @param variable Nombre de la variable (para trazabilidad).
#' @param config Lista de configuración de ejecución.
#' @return Lista con el perfil (n, tipo, proporciones, estadísticos, soporte...).
profile_dataset <- function(x, variable, config = dfit_default_config()) {
  stopifnot(is.numeric(x), length(variable) == 1L)
  n     <- length(x)
  n_na  <- sum(is.na(x))
  v     <- x[!is.na(x)]
  if (length(v) == 0L) stop("La variable no tiene valores no ausentes.", call. = FALSE)

  n_valid <- length(v)
  mean_v  <- mean(v)
  sd_v    <- stats::sd(v)

  list(
    variable       = variable,
    n              = n,
    n_valid        = n_valid,
    variable_type  = detect_variable_type(v, config),
    support        = .observed_support(v),
    pct_na         = n_na / n,                 # sobre el total de observaciones
    pct_zeros      = mean(v == 0),             # sobre observaciones no ausentes
    pct_negatives  = mean(v < 0),              # sobre observaciones no ausentes
    min            = min(v),
    max            = max(v),
    mean           = mean_v,
    median         = stats::median(v),
    sd             = sd_v,
    cv             = if (mean_v != 0) sd_v / mean_v else NA_real_,
    skewness       = .sample_skewness(v),
    kurtosis       = .sample_kurtosis(v),
    n_unique       = length(unique(v))
  )
}


# ============================================================
# 2. CANDIDATE DISTRIBUTION SELECTOR — diseño §4
# ============================================================

#' Selección de distribuciones candidatas según el tipo de variable
#'
#' Devuelve únicamente la lista de candidatas (no ajusta). Continua: familia del
#' §4.1 + Normal como control (§4.3). Discreta: familia del §4.2.
#'
#' @param variable_type "continuous" o "discrete".
#' @return Lista con `family`, `distributions` (ids), `control` (ids o NULL) y
#'   `specs` (registros id/label/n_params).
select_candidate_distributions <- function(variable_type) {
  variable_type <- match.arg(variable_type, c("continuous", "discrete"))
  if (variable_type == "continuous") {
    specs   <- DFIT_CONTINUOUS_DISTS
    control <- vapply(DFIT_CONTINUOUS_CONTROL, `[[`, character(1), "id")
  } else {
    specs   <- DFIT_DISCRETE_DISTS
    control <- NULL
  }
  list(
    family        = variable_type,
    distributions = vapply(specs, `[[`, character(1), "id"),
    control       = control,
    specs         = specs
  )
}


# ============================================================
# 2a. ANALYSIS SAMPLE (capa 0.5) — muestra común comparable (ADR-026)
# ============================================================
# Punto ÚNICO donde se decide sobre qué observaciones se ajusta el análisis.
# Antes de ADR-026 cada distribución recortaba la muestra por su cuenta dentro
# del Motor, de modo que el ranking comparaba AIC/BIC y estadísticos de bondad
# de ajuste calculados sobre muestras distintas —comparación inválida por
# definición, porque el AIC solo es comparable entre modelos ajustados a los
# MISMOS datos—.
#
# La regla no es "excluir ceros": es la INTERSECCIÓN DE SOPORTES de las
# candidatas que van a competir. Con el catálogo v1 eso da (0, Inf) en la
# familia continua (5 de 7 exigen soporte estrictamente positivo) y los enteros
# no negativos en la discreta (las 3 admiten el 0, así que los ceros SE
# CONSERVAN). Si en el futuro entra una candidata continua que admita el cero en
# toda la familia, la regla se recalcula sola.

#' Muestra común del análisis (capa 0.5) — ADR-026
#'
#' Restringe la muestra válida al soporte compartido por todas las candidatas que
#' competirán en el ranking, para que verosimilitudes, criterios de información y
#' estadísticos de bondad de ajuste sean comparables entre sí.
#'
#' El control (Normal) NO participa en el cálculo de la intersección: su función
#' es compararse con las candidatas, así que debe vivir en la muestra de ellas,
#' no ensancharla.
#'
#' @param v Vector numérico sin NA (muestra válida de la variable).
#' @param candidates Salida de `select_candidate_distributions()`.
#' @param config Configuración de ejecución.
#' @return list(x, n_input, n_used, n_excluded_zeros, n_excluded_negatives,
#'   requires_positive, support_label, rule, resolution).
build_analysis_sample <- function(v, candidates, config = dfit_default_config()) {
  ids <- candidates$distributions
  # Intersección de soportes: basta con que UNA candidata exija x > 0 para que
  # el soporte común lo exija. Fuente única: DFIT_REQUIRES_POSITIVE.
  requires_positive <- any(vapply(ids, function(id) isTRUE(DFIT_REQUIRES_POSITIVE[[id]]),
                                  logical(1)))

  prep <- .prepare_support(v, requires_positive)   # ÚNICA invocación del filtro
  x    <- prep$x

  support_label <- if (identical(candidates$family, "discrete")) {
    "{0, 1, 2, ...}"
  } else if (requires_positive) "(0, Inf)" else "[0, Inf)"

  rule <- sprintf("soporte común a las %d candidatas de la familia %s: %s",
                  length(ids),
                  if (identical(candidates$family, "discrete")) "discreta" else "continua",
                  support_label)

  if (length(x) < config$min_obs_analysis) {
    stop(sprintf(paste("Muestra insuficiente: tras restringir al soporte común %s quedan %d",
                       "observaciones (se excluyeron %d ceros y %d negativos de %d válidas);",
                       "se necesitan al menos %d."),
                 support_label, length(x), prep$n_excluded_zeros,
                 prep$n_excluded_negatives, length(v), config$min_obs_analysis),
         call. = FALSE)
  }

  list(
    x                    = x,
    n_input              = length(v),
    n_used               = length(x),
    n_excluded_zeros     = prep$n_excluded_zeros,
    n_excluded_negatives = prep$n_excluded_negatives,
    requires_positive    = requires_positive,
    support_label        = support_label,
    rule                 = rule,
    # Resolución empírica del dato: menor salto entre valores distintos. La
    # consume la guarda (B) de ADR-027. NA si no hay al menos 2 valores
    # distintos, en cuyo caso esa guarda se omite (no se inventa un valor).
    resolution           = .sample_resolution(x)
  )
}

#' Resolución empírica de una muestra (menor salto entre valores distintos)
#'
#' Si los datos se registran con resolución `delta`, la verosimilitud correcta es
#' la discretizada: P(X in [x +/- delta/2]) ~ f(x)*delta <= 1. De ahí la cota de
#' plausibilidad `mean(log f) <= -log(delta)` que usa la guarda (B) de ADR-027.
#'
#' @param x Vector numérico sin NA.
#' @return Menor diferencia positiva entre valores distintos, o `NA_real_`.
.sample_resolution <- function(x) {
  u <- sort(unique(x))
  if (length(u) < 2L) return(NA_real_)
  d <- min(diff(u))
  if (is.finite(d) && d > 0) d else NA_real_
}


# ============================================================
# 2b. MOTOR DE ESTIMACIÓN — MLE (Capa 1) — diseño §5
# ============================================================
# B2.1: ajuste por máxima verosimilitud de cada distribución candidata. MoM,
# L-momentos y la selección AUTO de método llegan en B2.2. Implementación propia
# sobre optim()/optimize() (política 2.2); las d*() de base R (dgamma, dweibull,
# dlnorm, dpois, dnbinom, dgeom, dnorm) se usan como primitivas de densidad.

# Soporte requerido por distribución (§3.5). TRUE => estrictamente positiva
# (excluye ceros y negativos); FALSE => admite el 0 (excluye solo negativos).
DFIT_REQUIRES_POSITIVE <- c(
  exponential = FALSE, gamma = TRUE,  weibull = TRUE, lognormal = TRUE,
  loglogistic = TRUE,  pareto = FALSE, burr = TRUE,   normal = FALSE,
  poisson = FALSE, negative_binomial = FALSE, geometric = FALSE
)

# Distribuciones discretas (requieren datos enteros).
DFIT_DISCRETE_IDS <- c("poisson", "negative_binomial", "geometric")

#' Prepara la muestra según el soporte de la distribución (§3.5)
#'
#' @param v Vector numérico sin NA.
#' @param requires_positive TRUE si la distribución es estrictamente positiva.
#' @return list(x, n_excluded_zeros, n_excluded_negatives).
.prepare_support <- function(v, requires_positive) {
  n_neg  <- sum(v < 0)
  n_zero <- sum(v == 0)
  x <- if (requires_positive) v[v > 0] else v[v >= 0]
  list(
    x                    = x,
    n_excluded_zeros     = if (requires_positive) n_zero else 0L,
    n_excluded_negatives = n_neg
  )
}

#' Optimización MLE genérica en escala logarítmica (L-BFGS-B)
#'
#' Todos los parámetros de las distribuciones soportadas son estrictamente
#' positivos, por lo que se optimiza sobre `log(param)`. Esto (a) elimina la
#' necesidad de cotas y (b) **acondiciona el problema**: L-BFGS-B usa gradiente
#' por diferencias finitas y converge de forma prematura cuando los parámetros
#' tienen magnitudes muy dispares (p. ej. shape ~ 1 y scale ~ 1e3), deteniéndose
#' lejos del máximo. En escala log los parámetros son O(1) y el optimizador
#' alcanza el verdadero MLE. La solución es idéntica (mismo óptimo, distinta
#' coordenada), no una aproximación.
#'
#' GUARDA (A) DE ADR-027. Hasta ADR-027 la única salvaguarda era `value >= 1e10`,
#' que protege por el lado de la penalización POSITIVA. Cuando la verosimilitud
#' no está acotada superiormente —caso de Lomax con un átomo de probabilidad en
#' cero—, la -logLik diverge hacia −Inf y esa comprobación no ve nada: el
#' optimizador empuja el parámetro hasta el menor subnormal representable
#' (4,94e−324), se detiene contra el acantilado que crea el desbordamiento de
#' `exp()`, y devuelve `convergence = 0`. Se añade por tanto el rechazo de
#' óptimos situados en la frontera numérica del espacio paramétrico.
#'
#' @param negloglik Función de -log-verosimilitud del vector de parámetros (en
#'   escala natural; positivos).
#' @param start Valores iniciales nombrados, estrictamente positivos.
#' @param config Configuración de ejecución (`param_min_normal`).
#' @return list(par, converged, nll, message).
.mle_optim <- function(negloglik, start, config = dfit_default_config()) {
  # Objetivo en escala log, saneado: penalización finita si la -logLik no es
  # finita, para que L-BFGS-B no evalúe valores no finitos (evita warnings).
  safe <- function(theta) {
    v <- negloglik(exp(theta))
    if (is.finite(v)) v else 1e10
  }
  fit <- tryCatch(
    stats::optim(log(start), safe, method = "L-BFGS-B", control = list(maxit = 500L)),
    error = function(e) NULL
  )
  if (is.null(fit) || !is.finite(fit$value) || fit$value >= 1e10) {
    return(list(par = start, converged = FALSE, nll = NA_real_,
                message = "el optimizador no alcanzó una solución finita"))
  }
  par <- exp(fit$par)
  # Guarda (A): parámetro fuera del rango de dobles normalizados => sin cifras
  # significativas => el óptimo está en la frontera, no en el interior.
  if (any(!is.finite(par)) || any(par < config$param_min_normal)) {
    return(list(par = par, converged = FALSE, nll = NA_real_,
                message = paste("óptimo en la frontera numérica del espacio paramétrico",
                                "(algún parámetro por debajo del menor doble normalizado):",
                                "la verosimilitud no está acotada en este soporte")))
  }
  list(par = par, converged = isTRUE(fit$convergence == 0L), nll = fit$value,
       message = NA_character_)
}

#' Guarda (B) de ADR-027: plausibilidad de la log-verosimilitud
#'
#' Con resolución de dato `delta`, la verosimilitud correcta es la discretizada:
#' `P(X in [x +/- delta/2]) ~ f(x)*delta <= 1`, luego `mean(log f) <= -log(delta)`.
#' Un ajuste que la supere está reclamando más masa de probabilidad de la que
#' existe. La condición es EQUIVARIANTE DE ESCALA: multiplicar los datos por `c`
#' desplaza ambos lados en `-log(c)`, de modo que no puede calibrarse a un
#' dataset concreto.
#'
#' Solo aplica a la familia continua: en la discreta la PMF ya está acotada por 1
#' y `log f <= 0` por construcción.
#'
#' @param loglik Log-verosimilitud del ajuste. @param n Observaciones usadas.
#' @param resolution Resolución empírica (`NA` -> guarda omitida).
#' @param config Configuración (`loglik_plausibility_k`).
#' @return `NA_character_` si el ajuste es plausible; el motivo si no lo es.
.loglik_implausible <- function(loglik, n, resolution, config = dfit_default_config()) {
  if (!is.finite(loglik) || n <= 0L || !is.finite(resolution)) return(NA_character_)
  bound <- -log(resolution) + config$loglik_plausibility_k
  mean_logf <- loglik / n
  if (mean_logf <= bound) return(NA_character_)
  sprintf(paste("verosimilitud no acotada: log-densidad media %.2f por encima de la cota",
                "de plausibilidad %.2f que impone la resolución del dato (%.6g)"),
          mean_logf, bound, resolution)
}

# --- Densidades propias (log) para distribuciones sin d*() en base R ---------

#' log-densidad Loglogística (Fisk): shape (beta), scale (alpha)
.dloglogistic_log <- function(x, shape, scale) {
  log(shape / scale) + (shape - 1) * log(x / scale) - 2 * log1p((x / scale)^shape)
}

#' log-densidad Pareto (Lomax / tipo II): shape (alpha), scale (lambda), x >= 0
.dpareto_log <- function(x, shape, scale) {
  log(shape) + shape * log(scale) - (shape + 1) * log(x + scale)
}

#' log-densidad Burr XII: shape1 (c), shape2 (k), scale (lambda)
.dburr_log <- function(x, c, k, scale) {
  log(c * k / scale) + (c - 1) * log(x / scale) - (k + 1) * log1p((x / scale)^c)
}

# --- Estimadores MLE por distribución (reciben la muestra ya preparada) -------

.mle_exponential <- function(x) {
  rate <- 1 / mean(x)
  list(params = list(rate = rate),
       logLik = sum(stats::dexp(x, rate, log = TRUE)), converged = TRUE)
}

.mle_normal <- function(x) {
  mu <- mean(x); sd_p <- sqrt(mean((x - mu)^2))
  list(params = list(mean = mu, sd = sd_p),
       logLik = sum(stats::dnorm(x, mu, sd_p, log = TRUE)), converged = TRUE)
}

.mle_lognormal <- function(x) {
  lx <- log(x); mu <- mean(lx); sd_p <- sqrt(mean((lx - mu)^2))
  list(params = list(meanlog = mu, sdlog = sd_p),
       logLik = sum(stats::dlnorm(x, mu, sd_p, log = TRUE)), converged = TRUE)
}

.mle_gamma <- function(x) {
  m <- mean(x); v <- stats::var(x)
  nll <- function(p) -sum(stats::dgamma(x, shape = p[1], scale = p[2], log = TRUE))
  o <- .mle_optim(nll, c(shape = m^2 / v, scale = v / m))
  list(params = list(shape = o$par[[1]], scale = o$par[[2]]),
       logLik = if (is.na(o$nll)) NA_real_ else -o$nll, converged = o$converged,
       message = o$message)
}

.mle_weibull <- function(x) {
  cvv <- stats::sd(x) / mean(x)
  shape0 <- max(cvv^(-1.086), 0.5)             # aproximación de Justus
  scale0 <- mean(x) / gamma(1 + 1 / shape0)
  nll <- function(p) -sum(stats::dweibull(x, shape = p[1], scale = p[2], log = TRUE))
  o <- .mle_optim(nll, c(shape = shape0, scale = scale0))
  list(params = list(shape = o$par[[1]], scale = o$par[[2]]),
       logLik = if (is.na(o$nll)) NA_real_ else -o$nll, converged = o$converged,
       message = o$message)
}

.mle_loglogistic <- function(x) {
  nll <- function(p) -sum(.dloglogistic_log(x, p[1], p[2]))
  o <- .mle_optim(nll, c(shape = 1, scale = stats::median(x)))
  list(params = list(shape = o$par[[1]], scale = o$par[[2]]),
       logLik = if (is.na(o$nll)) NA_real_ else -o$nll, converged = o$converged,
       message = o$message)
}

.mle_pareto <- function(x) {
  nll <- function(p) -sum(.dpareto_log(x, p[1], p[2]))
  o <- .mle_optim(nll, c(shape = 2, scale = mean(x)))
  list(params = list(shape = o$par[[1]], scale = o$par[[2]]),
       logLik = if (is.na(o$nll)) NA_real_ else -o$nll, converged = o$converged,
       message = o$message)
}

.mle_burr <- function(x) {
  nll <- function(p) -sum(.dburr_log(x, p[1], p[2], p[3]))
  o <- .mle_optim(nll, c(c = 1, k = 1, scale = stats::median(x)))
  list(params = list(shape1 = o$par[[1]], shape2 = o$par[[2]], scale = o$par[[3]]),
       logLik = if (is.na(o$nll)) NA_real_ else -o$nll, converged = o$converged,
       message = o$message)
}

.mle_poisson <- function(x) {
  lambda <- mean(x)
  list(params = list(lambda = lambda),
       logLik = sum(stats::dpois(x, lambda, log = TRUE)), converged = TRUE)
}

.mle_geometric <- function(x) {
  prob <- 1 / (1 + mean(x))                    # soporte {0,1,2,...}
  list(params = list(prob = prob),
       logLik = sum(stats::dgeom(x, prob, log = TRUE)), converged = TRUE)
}

.mle_negative_binomial <- function(x) {
  mu <- mean(x)                                # mu MLE = media muestral
  nll <- function(size) -sum(stats::dnbinom(x, size = size, mu = mu, log = TRUE))
  o <- stats::optimize(nll, interval = c(1e-3, 1e6))
  list(params = list(size = o$minimum, mu = mu),
       logLik = -o$objective, converged = TRUE)
}

# Registro de estimadores MLE por id de distribución (fuente única).
DFIT_MLE <- list(
  exponential = .mle_exponential, gamma = .mle_gamma, weibull = .mle_weibull,
  lognormal = .mle_lognormal, loglogistic = .mle_loglogistic, pareto = .mle_pareto,
  burr = .mle_burr, normal = .mle_normal, poisson = .mle_poisson,
  negative_binomial = .mle_negative_binomial, geometric = .mle_geometric
)

# ============================================================
# 2c. MÉTODOS ADICIONALES — MoM y L-momentos (Capa 1, B2.2) — diseño §5
# ============================================================
# Método de los Momentos y L-momentos, donde el estimador es estable/está bien
# definido. Un estimador devuelve NULL cuando NO procede para estos datos (p. ej.
# Pareto MoM exige CV^2>1, o Binomial Negativa exige varianza>media): AUTO no lo
# elegirá y en modo manual se marcará no disponible. L-momentos no aplica a las
# discretas (§5.2). Burr no dispone de MoM/L-momentos en v1.

#' L-momentos muestrales l1 y l2 (Hosking, vía PWM)
#' @param x Vector numérico sin NA (n >= 2).
#' @return list(l1, l2).
.sample_lmoments <- function(x) {
  xs <- sort(x); n <- length(xs); i <- seq_len(n)
  b0 <- mean(xs)
  b1 <- sum((i - 1) / (n - 1) * xs) / n
  list(l1 = b0, l2 = 2 * b1 - b0)
}

# --- Estimadores por Método de los Momentos (usan la varianza poblacional) ----
.mom_exponential <- function(x) list(params = list(rate = 1 / mean(x)))
.mom_normal <- function(x) {
  m <- mean(x); list(params = list(mean = m, sd = sqrt(mean((x - m)^2))))
}
.mom_lognormal <- function(x) {
  m <- mean(x); s2 <- log(1 + mean((x - m)^2) / m^2)
  list(params = list(meanlog = log(m) - s2 / 2, sdlog = sqrt(s2)))
}
.mom_gamma <- function(x) {
  m <- mean(x); m2c <- mean((x - m)^2)
  list(params = list(shape = m^2 / m2c, scale = m2c / m))
}
.mom_weibull <- function(x) {
  m <- mean(x); cv <- sqrt(mean((x - m)^2)) / m
  f <- function(k) sqrt(gamma(1 + 2 / k) / gamma(1 + 1 / k)^2 - 1) - cv
  k <- tryCatch(stats::uniroot(f, c(0.1, 50))$root, error = function(e) NA_real_)
  if (is.na(k)) return(NULL)
  list(params = list(shape = k, scale = m / gamma(1 + 1 / k)))
}
.mom_loglogistic <- function(x) {
  m <- mean(x); cv2 <- mean((x - m)^2) / m^2   # exige forma > 2 (varianza finita)
  f <- function(b) { bb <- pi / b; (2 * bb / sin(2 * bb)) / ((bb / sin(bb))^2) - 1 - cv2 }
  b <- tryCatch(stats::uniroot(f, c(2.0001, 50))$root, error = function(e) NA_real_)
  if (is.na(b)) return(NULL)
  list(params = list(shape = b, scale = m * sin(pi / b) / (pi / b)))
}
.mom_pareto <- function(x) {
  m <- mean(x); cv2 <- mean((x - m)^2) / m^2
  if (cv2 <= 1) return(NULL)                    # exige CV^2 > 1 (forma > 2)
  al <- 2 * cv2 / (cv2 - 1)
  list(params = list(shape = al, scale = m * (al - 1)))
}
.mom_poisson <- function(x) list(params = list(lambda = mean(x)))
.mom_geometric <- function(x) list(params = list(prob = 1 / (1 + mean(x))))
.mom_negative_binomial <- function(x) {
  m <- mean(x); m2c <- mean((x - m)^2)
  if (m2c <= m) return(NULL)                    # exige sobredispersión (var > media)
  list(params = list(size = m^2 / (m2c - m), mu = m))
}

# --- Estimadores por L-momentos (continuas; casan l1 y l2) --------------------
.lmom_exponential <- function(x) {
  L <- .sample_lmoments(x); list(params = list(rate = 1 / L$l1))
}
.lmom_normal <- function(x) {
  L <- .sample_lmoments(x); list(params = list(mean = L$l1, sd = sqrt(pi) * L$l2))
}
.lmom_pareto <- function(x) {
  L <- .sample_lmoments(x); k <- L$l1 / L$l2 - 2   # GPD(0, sigma, k); Lomax si k<0
  if (k >= 0) return(NULL)                          # cola ligera: no es Lomax
  sigma <- L$l1 * (1 + k)
  list(params = list(shape = -1 / k, scale = sigma / (-k)))
}

# Registros de estimadores por método (fuente única). Las distribuciones ausentes
# no soportan ese método.
DFIT_MOM <- list(
  exponential = .mom_exponential, normal = .mom_normal, lognormal = .mom_lognormal,
  gamma = .mom_gamma, weibull = .mom_weibull, loglogistic = .mom_loglogistic,
  pareto = .mom_pareto, poisson = .mom_poisson, geometric = .mom_geometric,
  negative_binomial = .mom_negative_binomial
)
DFIT_LMOM <- list(
  exponential = .lmom_exponential, normal = .lmom_normal, pareto = .lmom_pareto
)

#' log-verosimilitud de una distribución en sus parámetros (reutilizable)
#' @param id Id de la distribución. @param x Muestra. @param p Lista de parámetros.
#' @return logLik (numérico).
.dist_loglik <- function(id, x, p) {
  switch(id,
    exponential       = sum(stats::dexp(x, p$rate, log = TRUE)),
    normal            = sum(stats::dnorm(x, p$mean, p$sd, log = TRUE)),
    lognormal         = sum(stats::dlnorm(x, p$meanlog, p$sdlog, log = TRUE)),
    gamma             = sum(stats::dgamma(x, shape = p$shape, scale = p$scale, log = TRUE)),
    weibull           = sum(stats::dweibull(x, shape = p$shape, scale = p$scale, log = TRUE)),
    loglogistic       = sum(.dloglogistic_log(x, p$shape, p$scale)),
    pareto            = sum(.dpareto_log(x, p$shape, p$scale)),
    burr              = sum(.dburr_log(x, p$shape1, p$shape2, p$scale)),
    poisson           = sum(stats::dpois(x, p$lambda, log = TRUE)),
    negative_binomial = sum(stats::dnbinom(x, size = p$size, mu = p$mu, log = TRUE)),
    geometric         = sum(stats::dgeom(x, p$prob, log = TRUE))
  )
}

# ============================================================
# 2c-bis. PERCENTILE MATCHING (Capa 1, B11.2) — contrato congelado en ADR-031
# ============================================================
# Estimación PUNTUAL por igualación de cuantiles. Todo lo que sigue está fijado
# por B11.1 (ADR-031, adendas B11.1-R a B11.1-R4, verificadas en R 4.4.1); no es
# elección de este bloque:
#
#   s_Q(x, p) = max_j q_emp(p_j) - min_j q_emp(p_j)
#   J_PM(theta) = SUM_j [ Q_theta(p_j) - q_emp(p_j) ]^2 / s_Q^2      (w_j = 1)
#   theta_PM = argmin_theta J_PM(theta)              si s_Q es finita y > 0
#
# `s_Q` NO cambia el estimador —es constante respecto de theta, luego conserva el
# argmin de la SSE de cuantiles—: normaliza la ESCALA DEL CRITERIO DE PARADA de
# optim(), cuyas tolerancias son absolutas. `s_Q` generaliza el IQR: con 25/50/75
# vale exactamente Q75 - Q25.
#
# Rechazos (sin epsilon y sin normalizador de recurso):
#   s_Q = 0             -> los cuantiles objetivo colapsan: REJECT
#   m_requested < k     -> menos ecuaciones que parámetros: REJECT
#   m_requested < 2     -> mínimo de producto de la v1.1: REJECT
# `m_effective` (nº de cuantiles empíricos distintos) se calcula y se publica
# como DIAGNÓSTICO, y NO gobierna la aceptación en ninguno de los dos sentidos:
# percentiles distintos pueden compartir valor empírico por empates o redondeo y
# aun así corresponden a probabilidades distintas, de modo que su ecuación no es
# redundante.
#
# B11.2 entrega ESTIMACIÓN PUNTUAL. Sin SE, sin Hessiana, sin IC, sin bootstrap:
# eso es B12-B14.

#' Registro de Percentile Matching: disponibilidad, presets y default.
#'
#' Los tres presets y la elección de `p3w` como default están CONGELADOS en
#' ADR-031 (adenda B11.1-R4) sobre 22 DGP y 13.200 ajustes en R 4.4.1. No es una
#' preferencia: P3w ofrece el mejor compromiso general entre precisión típica,
#' convergencia, simplicidad y robustez frente a errores extremos. P3w y P5 son
#' prácticamente equivalentes en las familias sencillas; la ventaja de P3w está
#' principalmente en la robustez de cola en Pareto y Burr.
#'
#' Aún NO conectado a la interfaz (B16) ni al ranking (ver `.motor`).
DFIT_PM <- list(
  available       = TRUE,
  min_percentiles = 2L,
  default_preset  = "p3w",
  presets = list(
    p3w = list(id = "p3w", label = "Recomendado (10 / 50 / 90)",
               percentiles = c(0.10, 0.50, 0.90), recommended = TRUE),
    p5  = list(id = "p5",  label = "Ampliado (10 / 25 / 50 / 75 / 90)",
               percentiles = c(0.10, 0.25, 0.50, 0.75, 0.90), recommended = FALSE),
    p3c = list(id = "p3c", label = "Central / académico (25 / 50 / 75)",
               percentiles = c(0.25, 0.50, 0.75), recommended = FALSE)
  )
)

# Nombres de parámetros por distribución, EN EL ORDEN del vector de optimización.
# Coinciden con los que devuelven los `.mle_*` y con los que espera
# `.dist_quantile()`, que es la ÚNICA fuente de funciones cuantil (no se duplica
# ninguna definición). OD-3: solo las 7 continuas + Normal como control.
DFIT_PM_PARAMS <- list(
  exponential = "rate",
  gamma       = c("shape", "scale"),
  weibull     = c("shape", "scale"),
  lognormal   = c("meanlog", "sdlog"),
  loglogistic = c("shape", "scale"),
  pareto      = c("shape", "scale"),
  burr        = c("shape1", "shape2", "scale"),
  normal      = c("mean", "sd")
)

# Parámetros estrictamente positivos: se optimizan en escala log (ADR-014). Los
# de localización (`meanlog`, `mean`) NO se transforman.
DFIT_PM_POSITIVE <- list(
  exponential = TRUE,
  gamma       = c(TRUE, TRUE),
  weibull     = c(TRUE, TRUE),
  lognormal   = c(FALSE, TRUE),
  loglogistic = c(TRUE, TRUE),
  pareto      = c(TRUE, TRUE),
  burr        = c(TRUE, TRUE, TRUE),
  normal      = c(FALSE, TRUE)
)

# Arranque de PM: el MISMO punto donde arranca el MLE de cada familia (política
# de inicialización de ADR-031). Espejo deliberado de los `.mle_*`; si allí
# cambiara un arranque, debe cambiar aquí.
DFIT_PM_START <- list(
  exponential = function(x) 1 / mean(x),
  gamma       = function(x) { m <- mean(x); v <- stats::var(x); c(m^2 / v, v / m) },
  weibull     = function(x) { cv <- stats::sd(x) / mean(x)
                              sh <- max(cv^(-1.086), 0.5)   # aproximación de Justus
                              c(sh, mean(x) / gamma(1 + 1 / sh)) },
  lognormal   = function(x) { lx <- log(x)
                              c(mean(lx), sqrt(mean((lx - mean(lx))^2))) },
  loglogistic = function(x) c(1, stats::median(x)),
  pareto      = function(x) c(2, mean(x)),
  burr        = function(x) c(1, 1, stats::median(x)),
  normal      = function(x) { m <- mean(x); c(m, sqrt(mean((x - m)^2))) }
)

#' Vector de parámetros -> lista nombrada que espera `.dist_quantile()`.
.pm_as_params <- function(id, theta) {
  stats::setNames(as.list(theta), DFIT_PM_PARAMS[[id]])
}

#' Evaluación de `Q(p; theta)` con captura LOCAL y ACOTADA de avisos
#'
#' Durante la exploración, `optim()` visita puntos donde la función cuantil no
#' está definida y emite «NaNs produced». Ese aviso es esperado y no informa de
#' nada: el objetivo lo detecta y devuelve la penalización. Se silencia SOLO ese
#' mensaje y SOLO aquí; cualquier otro aviso se propaga sin tocar. No se usa
#' `suppressWarnings()` global en ningún punto (requisito de ADR-031, adenda
#' B11.1-R4: la ejecución normal de PM no debe inundar la consola).
.pm_quantile_guarded <- function(id, prob, params) {
  withCallingHandlers(
    tryCatch(.dist_quantile(id, prob, params),
             error = function(e) rep(NA_real_, length(prob))),
    warning = function(w) {
      if (grepl("NaN", conditionMessage(w), fixed = TRUE)) invokeRestart("muffleWarning")
    }
  )
}

#' Validación de la configuración de percentiles (contrato de ADR-031)
#'
#' @param id Id de la distribución. @param percentiles Vector de probabilidades.
#' @param n_params Número de parámetros `k` de la distribución.
#' @return `NA_character_` si la configuración es válida; el motivo si no lo es.
.pm_validate_config <- function(id, percentiles, n_params) {
  if (is.null(DFIT_PM_PARAMS[[id]])) {
    return(sprintf("Percentile Matching no está disponible para '%s'", id))
  }
  if (!is.numeric(percentiles) || length(percentiles) == 0L) {
    return("los percentiles deben ser un vector numérico no vacío")
  }
  if (any(!is.finite(percentiles))) {
    return("hay percentiles no finitos (NA, NaN o infinito)")
  }
  if (length(percentiles) < DFIT_PM$min_percentiles) {
    return(sprintf("se requieren al menos %d percentiles; se han indicado %d",
                   DFIT_PM$min_percentiles, length(percentiles)))
  }
  if (any(percentiles <= 0) || any(percentiles >= 1)) {
    return("los percentiles deben estar estrictamente entre 0 y 1")
  }
  if (anyDuplicated(percentiles) > 0L) {
    return("hay percentiles repetidos: cada uno debe aportar una ecuación distinta")
  }
  if (length(percentiles) < n_params) {
    # Copy deliberado: "estructuralmente insuficiente", no "no identificable".
    # `m_requested < k` es una insuficiencia de ecuaciones, verificable por
    # conteo; la identificabilidad es una propiedad más fuerte que este motor NO
    # afirma ni niega (ADR-031: `m_requested >= k` es condición necesaria, no
    # suficiente). El mensaje no debe prometer más de lo que se comprueba.
    return(sprintf(paste("configuración estructuralmente insuficiente: hay menos",
                         "percentiles que parámetros (%d percentiles para %d",
                         "parámetros; se necesitan al menos %d)"),
                   length(percentiles), n_params, n_params))
  }
  NA_character_
}

#' Ajuste por Percentile Matching (Shiny-free, estimación puntual)
#'
#' @param id Id de la distribución (una de `names(DFIT_PM_PARAMS)`).
#' @param x Muestra común del análisis (numérica, sin NA, ya restringida al
#'   soporte por `build_analysis_sample()`; ADR-026).
#' @param percentiles Probabilidades objetivo. Por defecto, el preset congelado.
#' @param config Configuración de ejecución (`param_min_normal`).
#' @return Lista con el contrato de salida de PM:
#'   `method`, `id`, `params`, `percentiles`, `q_empirical`, `q_fitted`, `s_Q`,
#'   `objective`, `m_requested`, `m_effective`, `n_params`, `converged`,
#'   `status`, `reason`, `optimizer`.
.pm_fit <- function(id, x, percentiles = DFIT_PM$presets[[DFIT_PM$default_preset]]$percentiles,
                    config = dfit_default_config()) {
  nm <- DFIT_PM_PARAMS[[id]]
  k  <- length(nm)
  out <- list(
    method = "pm", id = id, params = NULL,
    percentiles = percentiles, q_empirical = NULL, q_fitted = NULL,
    s_Q = NA_real_, objective = NA_real_,
    m_requested = if (is.numeric(percentiles)) length(percentiles) else NA_integer_,
    m_effective = NA_integer_, n_params = if (length(nm)) k else NA_integer_,
    converged = FALSE, status = NA_character_, reason = NA_character_,
    optimizer = list(convergence = NA_integer_, counts = NA_integer_,
                     message = NA_character_)
  )

  # --- 1. Validación de la configuración ---
  bad <- .pm_validate_config(id, percentiles, k)
  if (!is.na(bad)) {
    out$status <- "reject_config"; out$reason <- bad
    return(out)
  }
  if (!is.numeric(x) || length(x) < k + 1L || any(!is.finite(x))) {
    out$status <- "reject_sample"
    out$reason <- "la muestra no es numérica finita o no tiene observaciones suficientes"
    return(out)
  }

  # --- 2. Cuantiles empíricos y normalizador ---
  qhat <- stats::quantile(x, percentiles, names = FALSE, type = 7)
  out$q_empirical <- qhat
  out$m_effective <- length(unique(qhat))          # DIAGNÓSTICO, no regla
  s_Q <- max(qhat) - min(qhat)
  out$s_Q <- s_Q
  if (!is.finite(s_Q) || s_Q <= 0) {
    out$status <- "reject_scale_collapse"
    out$reason <- paste("los cuantiles empíricos seleccionados colapsan al mismo valor:",
                        "esta configuración de percentiles no aporta dispersión y no",
                        "permite estimar; pruebe con otros percentiles")
    return(out)
  }
  s2 <- s_Q^2

  # --- 3. Objetivo y reparametrización ---
  pos <- DFIT_PM_POSITIVE[[id]]
  objective <- function(theta) {
    if (any(!is.finite(theta))) return(1e10)
    if (any(theta[pos] <= 0))   return(1e10)       # guarda previa de positividad
    qt <- .pm_quantile_guarded(id, percentiles, .pm_as_params(id, theta))
    if (length(qt) != length(qhat) || any(!is.finite(qt))) return(1e10)
    v <- sum((qt - qhat)^2) / s2                   # pesos uniformes (OD-14 diferida)
    if (is.finite(v)) v else 1e10
  }
  # Transformación log SOLO de las componentes positivas, por INDEXACIÓN. No se
  # usa `ifelse(pos, log(theta), theta)`: evalúa ambas ramas sobre el vector
  # completo y calcula log() de parámetros de localización no positivos, lo que
  # generaba avisos espurios (IMPLEMENTATION DEFECT documentado en ADR-031).
  to_u  <- function(th) { u <- th;  u[pos]  <- log(th[pos]); u }
  to_th <- function(u)  { th <- u;  th[pos] <- exp(u[pos]);  th }

  th0 <- tryCatch(DFIT_PM_START[[id]](x), error = function(e) NULL)
  if (is.null(th0) || length(th0) != k || any(!is.finite(th0)) || any(th0[pos] <= 0)) {
    out$status <- "reject_start"
    out$reason <- "no se pudo construir un punto de arranque válido para esta muestra"
    return(out)
  }
  u0 <- to_u(th0)
  if (any(!is.finite(u0))) {
    out$status <- "reject_start"
    out$reason <- "la reparametrización del punto de arranque no es finita"
    return(out)
  }

  # --- 4. Optimización ---
  fit <- tryCatch(
    stats::optim(u0, function(u) {
      th <- to_th(u)
      if (any(!is.finite(th))) return(1e10)
      objective(th)
    }, method = "L-BFGS-B", control = list(maxit = 500L)),
    error = function(e) NULL
  )
  if (is.null(fit) || !is.finite(fit$value) || fit$value >= 1e10) {
    out$status <- "optimizer_failure"
    out$reason <- "el optimizador no alcanzó una solución finita"
    return(out)
  }
  out$optimizer <- list(convergence = as.integer(fit$convergence),
                        counts = fit$counts,
                        message = if (is.null(fit$message)) NA_character_ else fit$message)

  theta <- to_th(fit$par)
  if (any(!is.finite(theta))) {
    out$status <- "nonfinite"
    out$reason <- "la solución contiene parámetros no finitos"
    return(out)
  }
  # Guarda de frontera, coherente con la guarda (A) de ADR-027: un parámetro
  # positivo por debajo del menor doble normalizado no tiene cifras válidas.
  if (any(theta[pos] < config$param_min_normal)) {
    out$status <- "boundary_guard"
    out$reason <- paste("óptimo en la frontera numérica del espacio paramétrico:",
                        "algún parámetro cae por debajo del menor doble normalizado")
    return(out)
  }

  params <- .pm_as_params(id, theta)
  q_fit  <- .pm_quantile_guarded(id, percentiles, params)
  if (any(!is.finite(q_fit))) {
    out$status <- "nonfinite"
    out$reason <- "los cuantiles ajustados no son finitos en la solución"
    return(out)
  }

  out$params    <- params
  out$q_fitted  <- q_fit
  out$objective <- fit$value
  out$converged <- isTRUE(fit$convergence == 0L)
  out$status    <- if (out$converged) "success" else "optimizer_failure"
  if (!out$converged) out$reason <- "el optimizador agotó las iteraciones sin converger"
  out
}


# ============================================================
# 2c-ter. INCERTIDUMBRE ANALÍTICA DEL MLE (Capa 1, B12.2) — ADR-033 / ADR-034
# ============================================================
# Información OBSERVADA del MLE, covarianza, errores estándar e intervalos de
# confianza. Todo lo que sigue está congelado por ADR-033 (contrato) y por la
# evidencia de B12.1 (benchmark ejecutado en R 4.4.1); no es elección de este
# bloque.
#
#   J(theta_hat) = -Hess l(theta_hat)        INFORMACIÓN OBSERVADA
#
# NO es la información esperada de Fisher I(theta) = E[J(theta)], que es otra
# cosa y no se calcula aquí. La distinción importa: J depende de la muestra
# concreta, I es una esperanza sobre el modelo, y bajo mala especificación
# divergen (la varianza correcta sería la sándwich, fuera del alcance de B12).
#
# ESCALA DE CÁLCULO (OD-5, RESUELTA). Se deriva en la escala computacional u y se
# traslada a escala natural por método delta:
#
#   u = T(theta)        f(u) = -l(T^-1(u))        J_u = Hess_u f  en u_hat
#   Sigma_u = J_u^-1    Sigma_theta = G Sigma_u G'   con G = d theta / d u
#
# G es DIAGONAL porque las transformaciones son componente a componente. El
# método delta no es una aproximación aquí: T es un difeomorfismo por componente.
#
# ALCANCE: SOLO MLE. Percentile Matching queda FUERA por una razón de fondo, no
# por convención: toda esta construcción descansa en que el score se anule en
# theta_hat, y theta_PM minimiza J_PM, no l. En theta_PM el score NO es cero, de
# modo que J^-1 no es la covarianza del estimador y la aproximación cuadrática
# está centrada en un punto que no es el óptimo. MoM y L-momentos quedan fuera
# por el mismo motivo. Su incertidumbre llega por bootstrap en B13.

#' Catálogo de transformaciones de parámetro. Fuente única de `to_u`, `to_theta`
#' y `dtheta_du`. `dtheta_du` es la derivada de la INVERSA, evaluada en theta.
DFIT_TRANSFORMS <- list(
  identity = list(
    label = "identity", support = "real",
    to_u = function(t) t, to_theta = function(u) u,
    dtheta_du = function(t) 1
  ),
  log = list(
    label = "log", support = "positive",
    to_u = function(t) log(t), to_theta = function(u) exp(u),
    dtheta_du = function(t) t                      # d exp(u)/du = theta
  ),
  logit = list(
    label = "logit", support = "unit_interval",
    to_u = function(t) log(t / (1 - t)),
    to_theta = function(u) 1 / (1 + exp(-u)),
    dtheta_du = function(t) t * (1 - t)            # d/du de 1/(1+e^-u)
  )
)

#' Tabla DECLARATIVA por parámetro (OD-5). Los nombres son EXACTAMENTE los que
#' devuelven los `.mle_*`, y el ORDEN es el del vector de optimización.
#'
#' No es una regla global: `log` no sirve para todo. `mean` y `meanlog` viven en
#' R —`log` no está definida—, y `prob` vive en (0,1) —`log` no la acota
#' superiormente y admitiría p_hat > 1—, de ahí la logit.
DFIT_PARAM_TRANSFORM <- list(
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

#' Nombres de parámetro de una distribución, en orden. NULL si no está en tabla.
.dfit_param_names <- function(id) names(DFIT_PARAM_TRANSFORM[[id]])

#' Aplica una operación del catálogo de transformaciones componente a componente.
#' @param op "to_u", "to_theta" o "dtheta_du".
.dfit_transform_apply <- function(id, v, op) {
  tr <- DFIT_PARAM_TRANSFORM[[id]]
  if (is.null(tr) || length(v) != length(tr)) return(NULL)
  out <- vapply(seq_along(v), function(j) {
    f <- DFIT_TRANSFORMS[[tr[[j]]]][[op]]
    tryCatch(as.numeric(f(v[[j]])), error = function(e) NA_real_)
  }, 0)
  stats::setNames(out, names(tr))
}
.dfit_to_u        <- function(id, theta) .dfit_transform_apply(id, theta, "to_u")
.dfit_to_theta    <- function(id, u)     .dfit_transform_apply(id, u,     "to_theta")
.dfit_dtheta_du   <- function(id, theta) .dfit_transform_apply(id, theta, "dtheta_du")

#' Vector de parámetros -> lista nombrada que esperan `.dist_loglik()` y `.dist_quantile()`.
.dfit_as_params <- function(id, v) stats::setNames(as.list(v), .dfit_param_names(id))

#' Información observada por diferencias centrales en la escala u
#'
#' POLÍTICA NUMÉRICA CONGELADA (B12.1, evidencia en `docs/tool02_b12_benchmark.md`):
#'
#'   h_j = c * max(|u_j|, 1)     con c = eps^(1/4)  (`config$hessian_step_c`)
#'
#'   J_ii = [ f(u+h_i e_i) - 2 f(u) + f(u-h_i e_i) ] / h_i^2
#'   J_ij = [ f(++) - f(+-) - f(-+) + f(--) ] / (4 h_i h_j)
#'
#' El paso es relativo a la coordenada **u**, no a theta: una escala de datos de
#' 1e3 es un desplazamiento ADITIVO en log(theta), de modo que la regla es
#' insensible a la magnitud de los datos.
#'
#' La fórmula cruzada de 4 puntos es SIMÉTRICA POR CONSTRUCCIÓN. No se
#' simetriza: la asimetría se MIDE (`asym`) y debe ser exactamente 0; parchearla
#' ocultaría un fallo real si algún día dejara de serlo.
#'
#' NO se usa `optim(hessian = TRUE)` —cinco familias tienen MLE cerrado y no
#' pasan por el optimizador— ni `numDeriv` ni extrapolación de Richardson
#' (B12.1: no compensa el doble de evaluaciones).
#'
#' EVALUACIÓN NO FINITA: criterio DISTINTO al de una función objetivo. Allí
#' sustituir por una penalización grande es correcto —solo dice "no vayas ahí"—;
#' en una estimación de DERIVADA sería inadmisible, porque inventaría curvatura y
#' produciría un SE minúsculo con apariencia de validez. Por tanto, si cualquier
#' punto del estencil no es finito, la matriz entera se invalida con motivo.
#'
#' @param id Id de la distribución. @param x Muestra. @param theta_hat Lista o
#'   vector nombrado de parámetros estimados. @param config Configuración.
#' @return list(valid, reason, J_u, u_hat, theta_hat, step, n_eval, asym,
#'   eig_min, eig_max, rcond).
.observed_information <- function(id, x, theta_hat, config = dfit_default_config()) {
  nm <- .dfit_param_names(id)
  out <- list(valid = FALSE, reason = NA_character_, J_u = NULL, u_hat = NULL,
              theta_hat = NULL, step = NULL, n_eval = 0L, asym = NA_real_,
              eig_min = NA_real_, eig_max = NA_real_, rcond = NA_real_)
  if (is.null(nm)) {
    out$reason <- sprintf("no hay transformación declarada para '%s'", id); return(out)
  }
  th <- if (is.list(theta_hat)) unlist(theta_hat) else theta_hat
  if (is.null(th) || length(th) != length(nm) || any(!is.finite(th))) {
    out$reason <- "parámetros estimados ausentes, incompletos o no finitos"; return(out)
  }
  th <- stats::setNames(as.numeric(th), nm)
  out$theta_hat <- th
  if (!is.numeric(x) || length(x) < length(nm) + 1L || any(!is.finite(x))) {
    out$reason <- "la muestra no es numérica finita o no tiene observaciones suficientes"
    return(out)
  }
  u <- .dfit_to_u(id, th)
  if (is.null(u) || any(!is.finite(u))) {
    # theta_hat en la frontera del soporte (p.ej. lambda = 0, prob = 1): la
    # aproximación cuadrática presupone un óptimo INTERIOR y allí no existe.
    out$reason <- "theta_hat en la frontera del soporte: la escala transformada no es finita"
    return(out)
  }
  out$u_hat <- u

  # f(u) = -logLik. Devuelve NA si no es finita: NO se penaliza, NO se rellena.
  nev <- 0L
  f <- function(uu) {
    tt <- .dfit_to_theta(id, uu)
    if (is.null(tt) || any(!is.finite(tt))) return(NA_real_)
    v <- tryCatch(-.dist_loglik(id, x, .dfit_as_params(id, tt)),
                  error = function(e) NA_real_)
    nev <<- nev + 1L
    if (is.finite(v)) v else NA_real_
  }

  k <- length(u)
  h <- config$hessian_step_c * pmax(abs(u), 1)
  out$step <- stats::setNames(h, nm)
  J <- matrix(NA_real_, k, k, dimnames = list(nm, nm))

  f0 <- f(u)
  if (!is.finite(f0)) {
    out$n_eval <- nev
    out$reason <- "la log-verosimilitud no es finita en theta_hat"; return(out)
  }
  for (i in seq_len(k)) {
    ei <- numeric(k); ei[i] <- h[i]
    fp <- f(u + ei); fm <- f(u - ei)
    if (!is.finite(fp) || !is.finite(fm)) {
      out$n_eval <- nev
      out$reason <- sprintf(paste("evaluación no finita en el estencil del parámetro '%s':",
                                  "la log-verosimilitud no es evaluable en el entorno de theta_hat"),
                            nm[i])
      return(out)
    }
    J[i, i] <- (fp - 2 * f0 + fm) / (h[i]^2)
  }
  if (k > 1L) for (i in seq_len(k - 1L)) for (j in (i + 1L):k) {
    ei <- numeric(k); ei[i] <- h[i]
    ej <- numeric(k); ej[j] <- h[j]
    fpp <- f(u + ei + ej); fpm <- f(u + ei - ej)
    fmp <- f(u - ei + ej); fmm <- f(u - ei - ej)
    if (!all(is.finite(c(fpp, fpm, fmp, fmm)))) {
      out$n_eval <- nev
      out$reason <- sprintf(paste("evaluación no finita en el estencil cruzado ('%s','%s'):",
                                  "la log-verosimilitud no es evaluable en el entorno de theta_hat"),
                            nm[i], nm[j])
      return(out)
    }
    v <- (fpp - fpm - fmp + fmm) / (4 * h[i] * h[j])
    J[i, j] <- v; J[j, i] <- v
  }
  out$n_eval <- nev
  if (any(!is.finite(J))) {
    out$reason <- "la Hessiana contiene elementos no finitos"; return(out)
  }
  out$J_u  <- J
  out$asym <- max(abs(J - t(J)))
  ev <- tryCatch(eigen(J, symmetric = TRUE, only.values = TRUE)$values,
                 error = function(e) NULL)
  if (!is.null(ev)) { out$eig_min <- min(ev); out$eig_max <- max(ev) }
  # DIAGNÓSTICO CUANTITATIVO, no regla de rechazo (OD-4: sin umbral en B12).
  out$rcond <- tryCatch(rcond(J), error = function(e) NA_real_)
  out$valid <- TRUE
  out
}

#' Cadena de validación estructural de la información observada (OD-4)
#'
#' Diez pasos, en orden. Cualquier fallo produce `valid = FALSE` con motivo
#' auditable y NINGÚN SE. Prohibiciones explícitas: sin pseudoinversa, sin
#' recorte de autovalores, sin regularización silenciosa, sin sustituir la matriz
#' por una aproximación más conveniente, sin inventar un SE.
#'
#' `rcond` se PUBLICA como diagnóstico y NO invalida: Burr puede dar un `rcond`
#' pequeño y aun así información estructuralmente válida. La relación entre
#' condicionamiento y fiabilidad práctica se evalúa contra bootstrap en B15.
#'
#' @return list(valid, reason, Sigma_u, Sigma_theta, se_u, se_theta, chol_ok).
.validate_information <- function(J_u, id, theta_hat) {
  out <- list(valid = FALSE, reason = NA_character_, Sigma_u = NULL,
              Sigma_theta = NULL, se_u = NULL, se_theta = NULL, chol_ok = FALSE)
  nm <- .dfit_param_names(id); k <- length(nm)
  th <- if (is.list(theta_hat)) unlist(theta_hat) else theta_hat
  # 1. dimensiones
  if (is.null(J_u) || !is.matrix(J_u) || any(dim(J_u) != c(k, k))) {
    out$reason <- "la información observada no tiene las dimensiones esperadas"; return(out)
  }
  # 2. finitud
  if (any(!is.finite(J_u))) {
    out$reason <- "la información observada contiene elementos no finitos"; return(out)
  }
  # 3. simetría numérica
  if (max(abs(J_u - t(J_u))) > 1e-8 * max(1, max(abs(J_u)))) {
    out$reason <- "la información observada no es simétrica dentro de la tolerancia"; return(out)
  }
  # 4. definida positiva, vía Cholesky
  ch <- tryCatch(chol(J_u), error = function(e) NULL)
  if (is.null(ch)) {
    # PRODUCT DIAGNOSTIC COPY DEFECT corregido (ADR-034). El mensaje anterior
    # concluía que "theta_hat no es un máximo local estricto de la verosimilitud".
    # El fallo de Cholesky NO sostiene esa causa: solo establece que ESTA matriz
    # numérica no es definida positiva. Son compatibles con el mismo síntoma la
    # identificación débil, una curvatura prácticamente singular, una aproximación
    # numérica insuficiente o un mal condicionamiento. El diagnóstico se limita a
    # lo que se puede concluir. El cálculo no cambia.
    out$reason <- paste("la información observada no es definida positiva:",
                        "no puede obtenerse una covarianza analítica fiable",
                        "a partir de esta matriz")
    return(out)
  }
  out$chol_ok <- TRUE
  # 5. invertible (a través del factor de Cholesky ya calculado)
  Su <- tryCatch(chol2inv(ch), error = function(e) NULL)
  if (is.null(Su)) { out$reason <- "la información observada no es invertible"; return(out) }
  # 6. Sigma_u finita
  if (any(!is.finite(Su))) {
    out$reason <- "la covarianza en escala transformada no es finita"; return(out)
  }
  dimnames(Su) <- list(nm, nm); out$Sigma_u <- Su
  du <- diag(Su)
  if (any(!is.finite(du)) || any(du <= 0)) {
    out$reason <- "la diagonal de la covarianza en escala transformada no es positiva"
    return(out)
  }
  out$se_u <- stats::setNames(sqrt(du), nm)
  # 7. jacobiano delta válido
  g <- .dfit_dtheta_du(id, th)
  if (is.null(g) || any(!is.finite(g)) || any(g == 0)) {
    out$reason <- "el jacobiano del método delta no es válido en theta_hat"; return(out)
  }
  # 8. Sigma_theta finita.  Sigma_theta = G Sigma_u G'  con G diagonal.
  G  <- diag(as.numeric(g), nrow = k)
  St <- G %*% Su %*% t(G)
  if (any(!is.finite(St))) {
    out$reason <- "la covarianza en escala natural no es finita"; return(out)
  }
  dimnames(St) <- list(nm, nm); out$Sigma_theta <- St
  # 9. diagonal de Sigma_theta estrictamente positiva
  dt <- diag(St)
  if (any(!is.finite(dt)) || any(dt <= 0)) {
    out$reason <- "la diagonal de la covarianza en escala natural no es estrictamente positiva"
    return(out)
  }
  # 10. SE naturales finitos y estrictamente positivos
  se <- sqrt(dt)
  if (any(!is.finite(se)) || any(se <= 0)) {
    out$reason <- "los errores estándar en escala natural no son finitos y positivos"; return(out)
  }
  out$se_theta <- stats::setNames(se, nm)
  out$valid <- TRUE
  out
}

#' Nivel de confianza válido: numérico, escalar, finito y estrictamente en (0,1)
#' @return `NA_character_` si es válido; el motivo si no lo es.
.validate_confidence_level <- function(cl) {
  if (!is.numeric(cl) || length(cl) != 1L) {
    return("el nivel de confianza debe ser un único valor numérico")
  }
  if (!is.finite(cl)) return("el nivel de confianza no es finito")
  # Rango no arbitrario: es el dominio donde qnorm(1 - alpha/2) está definido y
  # es finito. No se inventa un mínimo del tipo 0,5.
  if (cl <= 0 || cl >= 1) {
    return("el nivel de confianza debe estar estrictamente entre 0 y 1")
  }
  NA_character_
}

#' Intervalo de Wald marginal construido en escala transformada (OD-16)
#'
#'   CI_u     = u_hat_j  +/-  z * SE_u_j
#'   CI_theta = T_j^-1( CI_u )
#'
#' Se construye en la escala u y se retrotransforma, NO al revés. El motivo es
#' que `theta_hat +/- z * SE_theta` puede producir valores IMPOSIBLES para un
#' parámetro restringido —un `scale` con extremo inferior negativo, un `prob`
#' mayor que 1—, y un intervalo fuera del espacio paramétrico no es conservador:
#' es incorrecto. Retrotransformar respeta el soporte POR CONSTRUCCIÓN, porque
#' `T^-1` es monótona. NO se trunca a posteriori a 0 ni a 1.
#'
#' Consecuencia esperada y deliberada: con `log` y `logit` el intervalo es
#' ASIMÉTRICO en escala natural y no está centrado en `theta_hat`.
#'
#' Los extremos se ordenan en lugar de asignarse posicionalmente: las tres
#' transformaciones actuales son crecientes, pero ordenar mantiene el resultado
#' correcto si alguna vez se declara una decreciente.
#'
#' @return list(lower, upper, lower_u, upper_u, z) o NULL si algo no es válido.
.ci_from_transformed_scale <- function(id, u_hat, se_u, confidence_level) {
  if (!is.na(.validate_confidence_level(confidence_level))) return(NULL)
  nm <- .dfit_param_names(id)
  if (is.null(nm) || length(u_hat) != length(nm) || length(se_u) != length(nm)) return(NULL)
  if (any(!is.finite(u_hat)) || any(!is.finite(se_u)) || any(se_u <= 0)) return(NULL)
  z  <- stats::qnorm(1 - (1 - confidence_level) / 2)
  lo_u <- u_hat - z * se_u
  hi_u <- u_hat + z * se_u
  lo <- .dfit_to_theta(id, lo_u)
  hi <- .dfit_to_theta(id, hi_u)
  if (is.null(lo) || is.null(hi) || any(!is.finite(lo)) || any(!is.finite(hi))) return(NULL)
  lower <- pmin(lo, hi); upper <- pmax(lo, hi)
  list(lower = stats::setNames(lower, nm), upper = stats::setNames(upper, nm),
       lower_u = stats::setNames(lo_u, nm), upper_u = stats::setNames(hi_u, nm), z = z)
}

#' Incertidumbre analítica de un ajuste MLE (B12.2)
#'
#' SOLO MLE. Devuelve un bloque no disponible —nunca un SE inventado— cuando el
#' método no es MLE, el ajuste no convergió, faltan parámetros, una guarda de
#' ADR-027 rechazó el ajuste (un óptimo en la frontera numérica o una
#' verosimilitud implausible NO admiten aproximación cuadrática interior), la
#' información observada no es calculable, o la cadena estructural falla.
#'
#' @param fit Ajuste tal como lo devuelve `.fit_one()` / `.estimate()`.
#' @param x Muestra común del análisis (ADR-026).
#' @param confidence_level Nivel de confianza. Por defecto `config$confidence_level`.
#' @param config Configuración de ejecución.
#' @return Bloque `inference` (ver `docs/tool02_inference_contract.md` §3.2).
.mle_uncertainty <- function(fit, x, confidence_level = NULL,
                             config = dfit_default_config()) {
  if (is.null(confidence_level)) confidence_level <- config$confidence_level
  id <- if (!is.null(fit$id)) fit$id else NA_character_
  # OD-18: identidad de la muestra EFECTIVAMENTE modelizada. Se reutiliza el
  # MISMO helper que usa B13 —`.data_fingerprint()`, SHA-256 sobre el vector
  # serializado—, de modo que no existen dos mecanismos que puedan divergir.
  # Es metadata: NO interviene en ningún cálculo estadístico de B12.
  .fp <- .data_fingerprint(x)
  sample_id <- list(n_used = if (is.numeric(x)) length(x) else NA_integer_,
                    fingerprint = .fp$fingerprint,
                    fingerprint_algo = .fp$algo,
                    fingerprint_status = .fp$status)

  na_block <- function(status, reason, cl = confidence_level) list(
    method = "analytic_mle", status = status, valid = FALSE, reason = reason,
    confidence_level = cl, n = if (is.numeric(x)) length(x) else NA_integer_,
    sample = sample_id,
    observed_information = NULL, covariance_u = NULL, covariance_theta = NULL,
    se_u = NULL, se_theta = NULL, parameters = list(),
    diagnostics = list(step = NULL, n_eval = 0L, asym = NA_real_,
                       eig_min = NA_real_, eig_max = NA_real_, rcond = NA_real_,
                       chol_ok = FALSE)
  )

  bad_cl <- .validate_confidence_level(confidence_level)
  if (!is.na(bad_cl)) return(na_block("failed", bad_cl, cl = NA_real_))
  if (!identical(fit$method, "mle")) {
    return(na_block("not_available", sprintf(paste("la inferencia analítica de B12 solo",
      "cubre el MLE; este ajuste usa el método '%s'. La incertidumbre de los demás",
      "métodos se obtendrá por bootstrap"), as.character(fit$method)[1])))
  }
  if (!isTRUE(fit$converged)) {
    return(na_block("not_available", if (!is.null(fit$message) && !is.na(fit$message))
      sprintf("el ajuste MLE no es válido: %s", fit$message)
      else "el ajuste MLE no convergió"))
  }
  if (is.null(fit$params) || length(fit$params) == 0L) {
    return(na_block("not_available", "el ajuste no tiene parámetros estimados"))
  }
  if (is.null(.dfit_param_names(id))) {
    return(na_block("not_available",
                    sprintf("no hay transformación declarada para '%s'", id)))
  }

  oi <- .observed_information(id, x, fit$params, config)
  diagnostics <- list(step = oi$step, n_eval = oi$n_eval, asym = oi$asym,
                      eig_min = oi$eig_min, eig_max = oi$eig_max,
                      rcond = oi$rcond, chol_ok = FALSE)
  if (!isTRUE(oi$valid)) {
    b <- na_block("failed", oi$reason); b$diagnostics <- diagnostics; return(b)
  }
  vi <- .validate_information(oi$J_u, id, oi$theta_hat)
  diagnostics$chol_ok <- isTRUE(vi$chol_ok)
  if (!isTRUE(vi$valid)) {
    b <- na_block("failed", vi$reason)
    b$observed_information <- oi$J_u; b$diagnostics <- diagnostics; return(b)
  }
  ci <- .ci_from_transformed_scale(id, oi$u_hat, vi$se_u, confidence_level)
  if (is.null(ci)) {
    b <- na_block("failed", "no se pudo construir el intervalo en escala transformada")
    b$observed_information <- oi$J_u; b$covariance_u <- vi$Sigma_u
    b$covariance_theta <- vi$Sigma_theta; b$diagnostics <- diagnostics; return(b)
  }

  nm <- .dfit_param_names(id); tr <- DFIT_PARAM_TRANSFORM[[id]]
  params <- lapply(seq_along(nm), function(j) list(
    name       = nm[j],
    estimate   = unname(oi$theta_hat[j]),
    se         = unname(vi$se_theta[j]),
    ci_lower   = unname(ci$lower[j]),
    ci_upper   = unname(ci$upper[j]),
    transform  = unname(tr[[j]]),
    support    = DFIT_TRANSFORMS[[tr[[j]]]]$support,
    # Auditoría: permite reconstruir el intervalo sin recalcular la Hessiana.
    u_hat      = unname(oi$u_hat[j]),
    se_u       = unname(vi$se_u[j]),
    ci_lower_u = unname(ci$lower_u[j]),
    ci_upper_u = unname(ci$upper_u[j])
  ))
  names(params) <- nm

  list(
    method = "analytic_mle", status = "complete", valid = TRUE,
    reason = NA_character_, confidence_level = confidence_level,
    n = length(x), sample = sample_id, z = ci$z,
    observed_information = oi$J_u,      # en escala u
    covariance_u = vi$Sigma_u, covariance_theta = vi$Sigma_theta,
    se_u = vi$se_u, se_theta = vi$se_theta,
    parameters = params, diagnostics = diagnostics
  )
}


# ============================================================
# 2c-quater. BOOTSTRAP NO PARAMÉTRICO (Capa 1, B13.1) — ADR-035 / ADR-036
# ============================================================
# Motor GENÉRICO de incertidumbre de estimadores por bootstrap no paramétrico iid.
# Todo lo que sigue está congelado por ADR-035; no es elección de este bloque.
#
#   para b = 1..B:   x*_b = sample(x, size = n, replace = TRUE)
#                    theta*_b = estimator_fn(x*_b)
#
# ESTE MOTOR NO ES EL BOOTSTRAP PARAMÉTRICO DE GoF (ADR-008). Son dos motores
# distintos y no comparten estado, semilla, configuración ni salida:
#   - B13   : NO paramétrico; remuestrea OBSERVACIONES; reestima; NO asume el
#             modelo; responde "¿cuánto varía theta_hat?".
#   - ADR-008: puede exigir simulación PARAMÉTRICA bajo el modelo ajustado; lo
#             ASUME cierto; recalibra estadísticos GoF.
#
# REQUISITO ARQUITECTÓNICO (OD-10): el motor NO conoce los estimadores. No hay
# ningún `switch(method, ...)` aquí dentro. El estimador se INYECTA como función
# adaptadora, construida fuera, que devuelve
#   list(success, params, status, reason)
# Así las reglas productivas siguen teniendo una sola fuente de verdad, el motor
# sirve a MLE/MoM/L-momentos/PM sin conocerlos, la promoción futura a `shared/`
# es un movimiento de fichero, y queda reutilizable para VaR/TVaR (donde el
# "estimador" sería una función de riesgo sobre theta_hat).
#
# MUESTRA (P-1): se remuestrea EXCLUSIVAMENTE la muestra común `sample$x`
# (ADR-026), con `n` constante. No se vuelve al dato original ni se reintroducen
# los ceros excluidos. CONSECUENCIA SEMÁNTICA declarada: en severidad continua
# con ceros excluidos, el bootstrap cuantifica la incertidumbre del MODELO
# CONDICIONAL POSITIVO, no de la distribución completa con su átomo en cero.
#
# FALLOS (OD-9): una réplica que no produce un ajuste válido según las MISMAS
# reglas productivas se clasifica FAILED. No se repara, no se cambia de método,
# no se relajan guardas, no se imputan parámetros, no se reintenta.
#
# OD-17: los resúmenes son CONDICIONALES a las réplicas válidas. No se corrige
# esa selección (sin ponderación, sin imputación, sin umbral); se publica la
# información necesaria para analizarla después.

#' Estados canónicos de fallo de una réplica. Agrupan los mensajes productivos
#' existentes; no se inventa taxonomía nueva.
.bootstrap_failure_status <- function(msg) {
  if (is.null(msg) || length(msg) != 1L || is.na(msg)) return("estimator_failure")
  if (grepl("frontera num", msg))          return("boundary_guard")        # ADR-027 (A)
  if (grepl("no acotada", msg))            return("loglik_implausible")    # ADR-027 (B)
  if (grepl("optimizador no alcan", msg))  return("optimizer_failure")
  if (grepl("insuficientes", msg))         return("insufficient_data")
  if (grepl("no disponible", msg))         return("estimator_unavailable")
  if (grepl("requiere datos enteros", msg)) return("non_integer_sample")
  "estimator_failure"
}

#' Adaptador para los estimadores que pasan por `.fit_one()` (MLE, MoM, L-mom)
#'
#' Reutiliza **la misma función productiva** que usa el motor de estimación, de
#' modo que las guardas de ADR-027 —incluida la de plausibilidad (B)— se aplican
#' exactamente igual dentro del bootstrap. No se relajan ni se reimplementan.
#'
#' `resolution` es la de la muestra ORIGINAL, no la de la réplica: el remuestreo
#' no crea valores nuevos (`unique(x*) ⊆ unique(x)`), de modo que la resolución
#' por réplica solo puede ser MAYOR, lo que aflojaría la guarda de forma
#' inconsistente entre réplicas. La resolución es propiedad del dato.
#'
#' @return `function(x_b)` -> list(success, params, status, reason).
.bootstrap_adapter_fit <- function(id, method, family = "continuous",
                                   resolution = NA_real_,
                                   config = dfit_default_config()) {
  k <- length(.dfit_param_names(id))
  spec <- list(id = id, label = id, n_params = if (k > 0L) k else 1L)
  function(x_b) {
    fit <- tryCatch(.fit_one(spec, x_b, role = "candidate", method = method,
                             family = family, resolution = resolution, config = config),
                    error = function(e) NULL)
    if (is.null(fit)) {
      return(list(success = FALSE, params = NULL, status = "estimator_error",
                  reason = "el estimador produjo un error en la réplica"))
    }
    if (!isTRUE(fit$converged) || is.null(fit$params) || length(fit$params) == 0L) {
      return(list(success = FALSE, params = NULL,
                  status = .bootstrap_failure_status(fit$message),
                  reason = if (is.null(fit$message)) NA_character_ else fit$message))
    }
    p <- unlist(fit$params)
    if (any(!is.finite(p))) {
      return(list(success = FALSE, params = NULL, status = "nonfinite_params",
                  reason = "el ajuste devolvió parámetros no finitos"))
    }
    list(success = TRUE, params = p, status = "success", reason = NA_character_)
  }
}

#' Adaptador para Percentile Matching (B11.2)
#'
#' Conserva EXACTAMENTE la configuración original: distribución, percentiles,
#' objetivo congelado (`s_Q`, pesos uniformes) y guardas. Los estados de rechazo
#' de `.pm_fit()` ya son canónicos y se propagan tal cual: `reject_config`,
#' `reject_sample`, `reject_scale_collapse`, `reject_start`, `optimizer_failure`,
#' `nonfinite`, `boundary_guard`. Ninguno se repara.
.bootstrap_adapter_pm <- function(id, percentiles = NULL,
                                  config = dfit_default_config()) {
  if (is.null(percentiles)) {
    percentiles <- DFIT_PM$presets[[DFIT_PM$default_preset]]$percentiles
  }
  function(x_b) {
    r <- tryCatch(.pm_fit(id, x_b, percentiles, config), error = function(e) NULL)
    if (is.null(r)) {
      return(list(success = FALSE, params = NULL, status = "estimator_error",
                  reason = "Percentile Matching produjo un error en la réplica"))
    }
    if (!isTRUE(r$converged) || is.null(r$params)) {
      return(list(success = FALSE, params = NULL,
                  status = if (is.na(r$status)) "estimator_failure" else r$status,
                  reason = r$reason))
    }
    p <- unlist(r$params)
    if (any(!is.finite(p))) {
      return(list(success = FALSE, params = NULL, status = "nonfinite_params",
                  reason = "PM devolvió parámetros no finitos"))
    }
    list(success = TRUE, params = p, status = "success", reason = NA_character_)
  }
}

#' Validación de `B`: escalar, finito, entero y positivo.
#' @return `NA_character_` si es válido; el motivo si no lo es.
.validate_bootstrap_B <- function(B, config = dfit_default_config()) {
  if (!is.numeric(B) || length(B) != 1L) return("B debe ser un único valor numérico")
  if (!is.finite(B)) return("B no es finito")
  if (abs(B - round(B)) > config$integer_tol) return("B debe ser un número entero")
  if (B < 1) return("B debe ser estrictamente positivo")
  NA_character_
}

#' Validación de la semilla: escalar, finita y entera.
.validate_bootstrap_seed <- function(seed, config = dfit_default_config()) {
  if (!is.numeric(seed) || length(seed) != 1L) {
    return("la semilla debe ser un único valor numérico")
  }
  if (!is.finite(seed)) return("la semilla no es finita")
  if (abs(seed - round(seed)) > config$integer_tol) {
    return("la semilla debe ser un número entero")
  }
  NA_character_
}

#' Huella reproducible de la muestra de análisis (OD-6)
#'
#' Identidad práctica del vector EXACTO que consume el bootstrap. **No es un hash
#' con finalidad adversarial**: no hay adversario en el modelo de amenazas, solo
#' el riesgo de sustitución accidental de datos.
#'
#'   `digest::digest(x, algo = "sha256", serialize = TRUE)`
#'
#' **`algo` y `serialize` se pasan EXPLÍCITAMENTE.** No se depende de los
#' defectos de `digest()`: su algoritmo por defecto es MD5, no SHA-256.
#'
#' **`serialize = TRUE`** hashea la representación binaria del objeto R —tipo,
#' longitud y valores en su orden— en lugar de una representación de texto, que
#' dependería de las opciones de formato de la sesión.
#'
#' **SENSIBLE AL ORDEN, y es el requisito decisivo.** Con la semilla fija,
#' `sample()` selecciona ÍNDICES: permutar `x` produce réplicas distintas aunque
#' el multiconjunto sea el mismo. Una huella insensible al orden —momentos,
#' cuantiles, `sum`— declararía «mismos datos» para un bootstrap distinto, que es
#' exactamente el fallo que esta función existe para detectar. Por eso NO se
#' ordena, ni se deduplica, ni se redondea, ni se resume: se hashea `x` tal cual.
#'
#' **LIMITACIÓN DECLARADA.** La estabilidad de la huella entre versiones de R
#' descansa en que `digest` omite la cabecera de serialización (`skip = "auto"`,
#' su valor por defecto). Si el formato de serialización de R cambiara, la huella
#' de los mismos datos podría cambiar. Es aceptable para el propósito —detectar
#' que un bootstrap guardado corresponde a OTROS datos— y no debe presentarse
#' como identidad universal.
#'
#' **Sin sustitutos.** Si `digest` no está disponible, se devuelve un estado
#' auditable: no se instala nada en tiempo de ejecución, no se cae a MD5, no se
#' recurre a herramientas base ni se fabrica una huella.
#'
#' @param x Vector numérico de análisis (`sample$x`, ADR-026).
#' @return list(fingerprint, algo, status, reason, n).
.data_fingerprint <- function(x) {
  out <- list(fingerprint = NA_character_, algo = "sha256",
              status = "failed", reason = NA_character_,
              n = if (is.numeric(x)) length(x) else NA_integer_)
  bad <- function(status, reason) { out$status <- status; out$reason <- reason; out }

  if (!requireNamespace("digest", quietly = TRUE)) {
    return(bad("dependency_unavailable",
               paste("el paquete 'digest' no está disponible: la huella no puede",
                     "calcularse. No se instala en tiempo de ejecución ni se",
                     "sustituye por otro algoritmo")))
  }
  if (!is.numeric(x)) {
    return(bad("invalid_input", "la muestra debe ser un vector numérico"))
  }
  if (length(x) == 0L) {
    return(bad("invalid_input", "la muestra está vacía"))
  }
  # Se distinguen los tres casos para que el motivo sea auditable. `NaN` y `NA_real_`
  # tienen representaciones distintas y producirían huellas distintas: hashear un
  # vector inválido daría una identidad válida de un objeto inválido.
  if (any(is.nan(x))) {
    return(bad("invalid_input", "la muestra contiene NaN"))
  }
  if (anyNA(x)) {
    return(bad("invalid_input", "la muestra contiene valores ausentes (NA)"))
  }
  if (any(is.infinite(x))) {
    return(bad("invalid_input", "la muestra contiene valores infinitos"))
  }

  h <- tryCatch(digest::digest(x, algo = "sha256", serialize = TRUE),
                error = function(e) NULL)
  if (is.null(h) || !is.character(h) || length(h) != 1L ||
      !grepl("^[0-9a-f]{64}$", h)) {
    return(bad("failed",
               "digest no devolvió un SHA-256 hexadecimal de 64 caracteres"))
  }
  list(fingerprint = h, algo = "sha256", status = "complete",
       reason = NA_character_, n = length(x))
}

#' Motor genérico de bootstrap no paramétrico (Shiny-free)
#'
#' @param x Muestra común del análisis (`sample$x`, ADR-026).
#' @param estimator_fn Adaptador `function(x_b) -> list(success, params, status, reason)`.
#' @param B Número de réplicas solicitadas. Argumento, sin defecto interno impuesto.
#' @param seed Semilla. **Una única** `set.seed()` al inicio (P-3).
#' @param confidence_level Nivel del intervalo percentil. Por defecto el de `config`.
#' @param theta_hat Estimación original, para el sesgo. Vector o lista nombrada.
#' @param estimator,distribution,pm_percentiles Metadatos de trazabilidad.
#' @param config Configuración de ejecución.
#' @return Bloque `bootstrap` del contrato de inferencia (ver ADR-035 §6).
.bootstrap_estimator <- function(x, estimator_fn, B = 1000L, seed = NULL,
                                 confidence_level = NULL, theta_hat = NULL,
                                 estimator = NA_character_,
                                 distribution = NA_character_,
                                 pm_percentiles = NULL,
                                 config = dfit_default_config()) {
  if (is.null(confidence_level)) confidence_level <- config$confidence_level
  fp <- .data_fingerprint(x)

  out <- list(
    method = "nonparametric_bootstrap", status = "failed", valid = FALSE,
    reason = NA_character_,
    B_requested = NA_integer_, B_success = 0L, B_failed = 0L,
    success_rate = NA_real_,
    seed = if (is.numeric(seed) && length(seed) == 1L) seed else NA_real_,
    confidence_level = confidence_level, quantile_type = 7L,
    estimator = estimator, distribution = distribution,
    pm_percentiles = pm_percentiles, parameter_names = NULL,
    data_fingerprint = fp$fingerprint, fingerprint_algo = fp$algo,
    fingerprint_status = fp$status, fingerprint_reason = fp$reason,
    n = if (is.numeric(x)) length(x) else NA_integer_,
    replicates = NULL, se = NULL, bias = NULL, ci = NULL,
    ci_degenerate = NA, failures = list(counts = integer(0), examples = list()),
    # OD-17: los resúmenes son condicionales a las réplicas válidas. Se declara
    # SIEMPRE, no solo cuando hay fallos.
    summaries_conditional_on_success = TRUE,
    warnings = character(0)
  )
  fail <- function(reason) { out$reason <- reason; out }

  # ---- 1. Validación de entradas ----
  if (!is.numeric(x) || length(x) < 2L) {
    return(fail("la muestra debe ser un vector numérico con al menos 2 observaciones"))
  }
  if (any(!is.finite(x))) {
    return(fail("la muestra contiene valores no finitos (NA, NaN o infinito)"))
  }
  if (!is.function(estimator_fn)) {
    return(fail("estimator_fn debe ser una función adaptadora del estimador"))
  }
  bad <- .validate_bootstrap_B(B, config);    if (!is.na(bad)) return(fail(bad))
  bad <- .validate_bootstrap_seed(seed, config); if (!is.na(bad)) return(fail(bad))
  bad <- .validate_confidence_level(confidence_level); if (!is.na(bad)) return(fail(bad))

  B <- as.integer(round(B))
  out$B_requested <- B
  out$seed <- as.integer(round(seed))

  # ---- 2. Remuestreo (P-3: UNA sola semilla, réplicas secuenciales) ----
  set.seed(out$seed)
  n <- length(x)
  acc <- vector("list", B)          # parámetros de las réplicas válidas
  st  <- character(B)               # estado por réplica
  rs  <- character(B)               # motivo por réplica
  nm  <- NULL                       # nombres canónicos, del primer éxito
  nsucc <- 0L

  for (b in seq_len(B)) {
    x_b <- sample(x, size = n, replace = TRUE)
    r <- tryCatch(estimator_fn(x_b),
                  error = function(e) list(success = FALSE, params = NULL,
                                           status = "estimator_error",
                                           reason = conditionMessage(e)))
    if (!is.list(r) || is.null(r$success) || !is.logical(r$success) ||
        length(r$success) != 1L) {
      st[b] <- "adapter_contract_violation"
      rs[b] <- "el adaptador no devolvió list(success, params, status, reason)"
      next
    }
    if (!isTRUE(r$success)) {
      st[b] <- if (is.null(r$status) || is.na(r$status)) "estimator_failure" else r$status
      rs[b] <- if (is.null(r$reason)) NA_character_ else as.character(r$reason)[1]
      next
    }
    p <- unlist(r$params)
    if (is.null(p) || !is.numeric(p) || any(!is.finite(p))) {
      st[b] <- "nonfinite_params"
      rs[b] <- "la réplica declaró éxito pero sus parámetros no son numéricos finitos"
      next
    }
    if (is.null(nm)) {
      nm <- names(p)
      if (is.null(nm)) nm <- paste0("param", seq_along(p))
    } else if (length(p) != length(nm) ||
               (!is.null(names(p)) && !identical(names(p), nm))) {
      # No se normaliza en silencio: una réplica con otra forma no es el mismo
      # estimador y no puede entrar en la misma matriz.
      st[b] <- "param_names_mismatch"
      rs[b] <- "la réplica devolvió parámetros con nombre u orden distintos"
      next
    }
    nsucc <- nsucc + 1L
    acc[[nsucc]] <- unname(p)
    st[b] <- "success"; rs[b] <- NA_character_
  }

  # ---- 3. Contabilidad de fallos (OD-9 / OD-17) ----
  out$B_success    <- nsucc
  out$B_failed     <- B - nsucc
  out$success_rate <- nsucc / B
  fst <- st[st != "success" & nzchar(st)]
  if (length(fst) > 0L) {
    tb <- table(fst)
    out$failures$counts <- stats::setNames(as.integer(tb), names(tb))
    # Un ejemplo de motivo POR ESTADO, no el texto repetido B veces.
    ex <- list()
    for (s in names(tb)) {
      i <- which(st == s)[1]
      ex[[s]] <- list(replicate = i, status = s, reason = rs[i])
    }
    out$failures$examples <- ex
  }
  out$parameter_names <- nm

  # ---- 4. Imposibilidad matemática (§10.1 de ADR-035) ----
  if (nsucc == 0L) {
    out$status <- "failed"
    out$reason <- paste("ninguna réplica produjo un ajuste válido: no existe",
                        "distribución bootstrap empírica")
    return(out)
  }

  M <- matrix(unlist(acc[seq_len(nsucc)]), nrow = nsucc, ncol = length(nm),
              byrow = TRUE, dimnames = list(NULL, nm))
  out$replicates <- M

  th <- if (is.list(theta_hat)) unlist(theta_hat) else theta_hat

  # Sesgo: la media existe con una sola réplica, luego es FORMALMENTE calculable.
  # Que con B_success = 1 carezca de utilidad inferencial es una cuestión de
  # CALIDAD, no de existencia (OD-11), y no se resuelve aquí.
  if (!is.null(th) && length(th) == length(nm) && all(is.finite(th))) {
    out$bias <- stats::setNames(colMeans(M) - as.numeric(th), nm)
  }

  # SE: la desviación típica MUESTRAL exige al menos 2 réplicas.
  if (nsucc >= 2L) {
    out$se <- stats::setNames(apply(M, 2, stats::sd), nm)
  }

  # IC percentil, type = 7 (P-2, congelado). Con una sola réplica es
  # computable pero degenera a un punto: se marca, no se juzga.
  alpha <- 1 - confidence_level
  ci <- matrix(NA_real_, nrow = length(nm), ncol = 2L,
               dimnames = list(nm, c("lower", "upper")))
  for (j in seq_along(nm)) {
    q <- stats::quantile(M[, j], probs = c(alpha / 2, 1 - alpha / 2),
                         type = 7, names = FALSE)
    ci[j, ] <- q
  }
  out$ci <- ci
  out$ci_degenerate <- (nsucc < 2L)

  if (nsucc < 2L) {
    out$status <- "partial"; out$valid <- FALSE
    out$reason <- paste("solo 1 réplica válida: la desviación típica muestral no",
                        "está definida y el intervalo percentil degenera a un punto")
    return(out)
  }
  out$valid  <- TRUE
  out$status <- if (out$B_failed > 0L) "partial" else "complete"
  out
}


# ============================================================
# 2c-quinquies. CAPA DE VALIDACIÓN DEL ESTIMADOR (Capa 1, B14.1) — ADR-037
# ============================================================
# B14 NO CALCULA INFERENCIA. Consume y organiza lo que ya produjeron B12 y B13,
# y valida su coherencia. No ejecuta `.estimate()`, `.mle_uncertainty()`,
# `.bootstrap_estimator()`, `.pm_fit()` ni `.motor()`, y no recalcula SE, sesgo,
# intervalos, Hessiana, cuantiles bootstrap, réplicas ni estimaciones puntuales.
#
# FUNCIÓN PURA (I11): sin RNG, sin E/S, sin estado; dos llamadas con las mismas
# entradas devuelven salidas `identical()`. No emite avisos en el camino nominal.
#
# AISLAMIENTO: NO se conecta a `.motor()`, AUTO, Assessment, Decision Engine,
# ranking, UI ni export, y NO se añade `fit$validation`. La integración pública
# es B16. B14.1 es un motor interno invocable directamente.

#' Estados canónicos de la vía analítica y de la vía bootstrap (ADR-037 §6.1).
DFIT_VALIDATION_ANALYTIC_STATUS  <- c("not_applicable", "not_requested",
                                      "failed", "not_available", "complete")
DFIT_VALIDATION_BOOTSTRAP_STATUS <- c("not_requested", "failed", "insufficient",
                                      "partial", "complete")
DFIT_VALIDATION_GLOBAL_STATUS    <- c("no_point_estimate", "incompatible",
                                      "point_only", "uncertainty_analytic",
                                      "uncertainty_bootstrap", "uncertainty_both")

#' Estimadores para los que la vía analítica de B12 NO está definida.
#'
#' No es un fallo de ejecución sino una frontera de diseño: toda la construcción
#' de B12 exige que el score se anule en theta_hat, y estos estimadores no lo
#' anulan —PM minimiza J_PM, no la log-verosimilitud—. Presentarlo como `failed`
#' sugeriría un defecto donde hay una decisión metodológica.
DFIT_ANALYTIC_NOT_APPLICABLE <- c("mom", "lmom", "pm")

#' Valor por defecto de la tolerancia COMPUTACIONAL de comparación de niveles.
#' Se declara como constante para que `dfit_default_config()` y el fallback de
#' `.dfit_confidence_tol()` no puedan divergir.
DFIT_CONFIDENCE_LEVEL_TOL_DEFAULT <- 1e-12

#' Resuelve la tolerancia de comparación de niveles frente a una `config` custom
#'
#' Una configuración externa podría traer `confidence_level_tol` ausente, `NA`,
#' negativa o no finita. Eso rompería la comparación en silencio. Se valida y, si
#' no es utilizable, se emplea el valor por defecto documentado y se **declara**
#' —no se acepta a ciegas ni se convierte en política metodológica—.
#' @return list(tol, valid).
.dfit_confidence_tol <- function(config = dfit_default_config()) {
  tol <- if (is.list(config)) config$confidence_level_tol else NULL
  ok <- !is.null(tol) && is.numeric(tol) && length(tol) == 1L &&
        is.finite(tol) && tol >= 0
  if (isTRUE(ok)) list(tol = tol, valid = TRUE)
  else list(tol = DFIT_CONFIDENCE_LEVEL_TOL_DEFAULT, valid = FALSE)
}

#' Comparación de niveles de confianza con tolerancia COMPUTACIONAL
#' @return TRUE si son el mismo nivel; NA si alguno no es utilizable.
.dfit_same_confidence_level <- function(a, b, config = dfit_default_config()) {
  if (!is.numeric(a) || !is.numeric(b) || length(a) != 1L || length(b) != 1L) return(NA)
  if (!is.finite(a) || !is.finite(b)) return(NA)
  abs(a - b) <= .dfit_confidence_tol(config)$tol
}

#' Validación ESTRUCTURAL de los contadores del bloque bootstrap (B14.1)
#'
#' CONTRACT VALIDATION. Se ejecuta ANTES de derivar `bootstrap.status`, porque la
#' derivación necesita los tres contadores y, sin ellos, comparaciones como
#' `is.finite(NULL)` producen `logical(0)` y hacen fallar el `if` con un error de
#' longitud cero en lugar de una incompatibilidad auditable.
#'
#' **No repara ni completa el bloque recibido**: no infiere
#' `B_failed = B_requested − B_success`, no rellena ausentes y no corrige valores.
#' Solo dictamina si los contadores permiten derivar la taxonomía congelada.
#'
#' `success_rate` se valida como contrato, pero **no interviene en la
#' clasificación** ni introduce umbral alguno (OD-11 sigue OPEN).
#'
#' @return list(ok, problems).
.validate_bootstrap_counters <- function(b, config = dfit_default_config()) {
  p <- character(0)
  chk <- function(nm) {
    v <- b[[nm]]
    if (is.null(v)) { p <<- c(p, sprintf("falta `%s` en el bloque bootstrap", nm)); return(NA_real_) }
    if (!is.numeric(v) || length(v) != 1L) {
      p <<- c(p, sprintf("`%s` no es un escalar numérico", nm)); return(NA_real_)
    }
    if (!is.finite(v)) { p <<- c(p, sprintf("`%s` no es finito", nm)); return(NA_real_) }
    if (abs(v - round(v)) > config$integer_tol) {
      p <<- c(p, sprintf("`%s` no es un valor entero", nm)); return(NA_real_)
    }
    if (v < 0) { p <<- c(p, sprintf("`%s` es negativo", nm)); return(NA_real_) }
    as.numeric(v)
  }
  Bq <- chk("B_requested"); Bs <- chk("B_success"); Bf <- chk("B_failed")

  if (all(is.finite(c(Bq, Bs, Bf)))) {
    if (Bs > Bq) p <- c(p, sprintf("B_success (%g) > B_requested (%g)", Bs, Bq))
    if ((Bs + Bf) != Bq) {
      p <- c(p, sprintf("B_success + B_failed (%g) != B_requested (%g)", Bs + Bf, Bq))
    }
  }
  # Contrato de `success_rate`: se COMPRUEBA pero NO condiciona la clasificación.
  # Va en un cubo separado (`rate_problems`) precisamente para que un
  # `success_rate` incoherente se registre como incompatibilidad sin impedir que
  # la taxonomía se derive de B_success y B_failed, que es lo único que ADR-037
  # autoriza a usar. Mezclarlo con `problems` lo convertiría de facto en un
  # criterio de clasificación.
  rp <- character(0)
  sr <- b$success_rate
  if (!is.null(sr)) {
    if (!is.numeric(sr) || length(sr) != 1L) {
      rp <- c(rp, "`success_rate` no es un escalar numérico")
    } else if (is.finite(sr)) {
      if (sr < 0 || sr > 1) rp <- c(rp, "`success_rate` fuera de [0, 1]")
      else if (all(is.finite(c(Bq, Bs))) && Bq > 0 &&
               abs(sr - Bs / Bq) > config$integer_tol) {
        rp <- c(rp, "`success_rate` no coincide con B_success / B_requested")
      }
    }
  }
  list(ok = length(p) == 0L, problems = p, rate_problems = rp,
       B_requested = Bq, B_success = Bs, B_failed = Bf)
}

#' Vector de parámetros nombrado a partir de una lista o vector.
.dfit_named_numeric <- function(p) {
  if (is.null(p)) return(NULL)
  v <- if (is.list(p)) unlist(p) else p
  if (!is.numeric(v) || is.null(names(v))) return(NULL)
  v
}

#' Adaptador de metadatos de muestra (ADR-037 §11)
#'
#' ADAPTACIÓN EXPLÍCITA DE NOMBRES: el contrato conceptual de ADR-037 llama
#' `support` a lo que `build_analysis_sample()` devuelve como `support_label`.
#' Se mapea aquí y se documenta; no se inventa ningún campo.
#'
#' FUENTE OBLIGATORIA: el objeto de `build_analysis_sample()`. **NO** se usa
#' `fit$n_excluded`, que desde ADR-026 es vestigial y vale siempre 0 —la
#' exclusión ocurre una sola vez en la capa 0.5—; leerlo daría «0 excluidos» en
#' todos los casos y ocultaría precisamente lo que hay que exponer.
.dfit_sample_meta <- function(sample_meta) {
  if (is.null(sample_meta) || !is.list(sample_meta)) {
    return(list(available = FALSE, reason = "no se aportaron metadatos de muestra",
                n_input = NA_integer_, n_used = NA_integer_,
                n_excluded_zeros = NA_integer_, n_excluded_negatives = NA_integer_,
                support = NA_character_, requires_positive = NA,
                conditional = NA, conditional_note = NA_character_))
  }
  g <- function(nm, default) if (!is.null(sample_meta[[nm]])) sample_meta[[nm]] else default
  nz <- g("n_excluded_zeros", NA_integer_)
  nn <- g("n_excluded_negatives", NA_integer_)
  cond <- if (is.na(nz) && is.na(nn)) NA else
    isTRUE(sum(c(nz, nn), na.rm = TRUE) > 0)
  note <- if (isTRUE(cond)) {
    paste("la inferencia corresponde a los parámetros de la distribución",
          "condicional restringida al soporte común del análisis (ADR-026),",
          "no a la variable original completa")
  } else NA_character_
  list(
    available            = TRUE, reason = NA_character_,
    n_input              = g("n_input", NA_integer_),
    n_used               = g("n_used", NA_integer_),
    n_excluded_zeros     = nz,
    n_excluded_negatives = nn,
    support              = g("support_label", NA_character_),   # adaptación de nombre
    requires_positive    = g("requires_positive", NA),
    conditional          = cond,
    conditional_note     = note
  )
}

#' Capa de validación del estimador (B14.1) — Shiny-free y pura
#'
#' @param point_estimate `list(params = <lista/vector nombrado>, estimator = ,
#'   distribution = )`. La estimación oficial; se copia VERBATIM.
#' @param analytic_inference Bloque de `.mle_uncertainty()` (B12) o `NULL`.
#' @param bootstrap_inference Bloque de `.bootstrap_estimator()` (B13) o `NULL`.
#' @param sample_meta Objeto de `build_analysis_sample()` o `NULL`.
#' @param config Configuración de ejecución.
#' @return Objeto `validation` (ADR-037 §15).
.validate_estimator <- function(point_estimate,
                                analytic_inference = NULL,
                                bootstrap_inference = NULL,
                                sample_meta = NULL,
                                config = dfit_default_config()) {

  est  <- if (is.list(point_estimate) && !is.null(point_estimate$estimator))
            as.character(point_estimate$estimator)[1] else NA_character_
  dist <- if (is.list(point_estimate) && !is.null(point_estimate$distribution))
            as.character(point_estimate$distribution)[1] else NA_character_
  pv   <- if (is.list(point_estimate)) .dfit_named_numeric(point_estimate$params) else NULL
  pnames <- names(pv)

  incompat <- character(0)
  add_incompat <- function(msg) incompat <<- c(incompat, msg)

  # ---------------------------------------------------------------- 1. Analítico
  a_block <- analytic_inference
  if (est %in% DFIT_ANALYTIC_NOT_APPLICABLE && !is.na(est)) {
    # Precedencia: la no aplicabilidad es una propiedad del estimador y prevalece
    # sobre cualquier estado que traiga un bloque analítico mal dirigido.
    a_status <- "not_applicable"
    a_reason <- sprintf(paste("la inferencia analítica de B12 no está definida para '%s':",
                              "su construcción exige que el score se anule en theta_hat"), est)
    if (!is.null(a_block)) {
      add_incompat(sprintf("se aportó inferencia analítica para el estimador '%s', que no la admite", est))
    }
    a_block <- NULL
  } else if (is.null(a_block)) {
    a_status <- "not_requested"; a_reason <- NA_character_
  } else if (!is.list(a_block) || is.null(a_block$status)) {
    a_status <- "failed"; a_reason <- "el bloque analítico no respeta el contrato de B12"
    add_incompat("bloque analítico sin campo `status`")
    a_block <- NULL
  } else {
    a_status <- as.character(a_block$status)[1]
    a_reason <- if (is.null(a_block$reason)) NA_character_ else a_block$reason
    if (!a_status %in% DFIT_VALIDATION_ANALYTIC_STATUS) {
      add_incompat(sprintf("estado analítico desconocido: '%s'", a_status))
    }
  }
  a_level <- if (!is.null(a_block) && !is.null(a_block$confidence_level))
               a_block$confidence_level else NA_real_

  # --------------------------------------------------------------- 2. Bootstrap
  # CONTRACT VALIDATION antes de derivar nada: la taxonomía congelada necesita
  # los tres contadores, y sin validarlos una comparación como `is.finite(NULL)`
  # devuelve `logical(0)` y hace fallar el `if` con un error de longitud cero en
  # lugar de producir una incompatibilidad auditable.
  b_block <- bootstrap_inference
  b_status <- "not_requested"; b_reason <- NA_character_
  b_counters_ok <- FALSE
  # Los valores se conservan TAL COMO LLEGAN (NULL se representa como NA, I12).
  keep <- function(v) if (is.null(v)) NA else v
  Bq <- Bs <- Bf <- NA; b_rate <- NA_real_
  if (!is.null(b_block)) {
    if (!is.list(b_block)) {
      b_status <- "failed"
      b_reason <- "el bloque bootstrap no es una lista: no respeta el contrato de B13"
      add_incompat("el bloque bootstrap no es una lista")
    } else {
      Bq <- keep(b_block$B_requested); Bs <- keep(b_block$B_success)
      Bf <- keep(b_block$B_failed);    b_rate <- keep(b_block$success_rate)
      b_reason <- if (is.null(b_block$reason)) NA_character_ else b_block$reason

      cv <- .validate_bootstrap_counters(b_block, config)
      b_counters_ok <- isTRUE(cv$ok)
      # `success_rate` incoherente SÍ es incompatibilidad contractual, pero NO
      # impide derivar el estado: la taxonomía sigue saliendo de B_success/B_failed.
      for (msg in cv$rate_problems) add_incompat(msg)
      if (!b_counters_ok) {
        for (msg in cv$problems) add_incompat(msg)
        # Fallback local dentro de la taxonomía CONGELADA: no se inventa una
        # categoría nueva y, sobre todo, NO se finge "complete". El global pasa
        # a "incompatible" por la vía de `incompat`.
        b_status <- "failed"
        b_reason <- paste("los contadores del bloque bootstrap no permiten derivar",
                          "el estado: contrato incompleto o incoherente")
      } else {
        # Derivación CONGELADA (ADR-037 §6.1). Solo B_success y B_failed.
        # `success_rate` NO interviene: no hay umbral (OD-11 sigue OPEN).
        b_status <-
          if (cv$B_success == 0)                          "failed"
          else if (cv$B_success == 1)                     "insufficient"
          else if (cv$B_success >= 2 && cv$B_failed > 0)  "partial"
          else if (cv$B_success == cv$B_requested &&
                   cv$B_failed == 0 && cv$B_success >= 2) "complete"
          else                                            NA_character_
        if (is.na(b_status)) {
          # Inalcanzable si la coherencia se cumple; se deja explícito en lugar
          # de dejar que caiga en "complete" por descarte.
          b_status <- "failed"
          b_reason <- "combinación de contadores estructuralmente imposible"
          add_incompat(sprintf(paste("contadores no clasificables: B_requested = %g,",
                                     "B_success = %g, B_failed = %g"),
                               cv$B_requested, cv$B_success, cv$B_failed))
        }
        # I7: filas de la matriz de réplicas = B_success.
        if (!is.null(b_block$replicates) && is.matrix(b_block$replicates) &&
            nrow(b_block$replicates) != cv$B_success) {
          add_incompat(sprintf("nrow(replicates) (%d) != B_success (%g)",
                               nrow(b_block$replicates), cv$B_success))
        }
        # I15: bootstrap$valid == TRUE  <=>  B_success >= 2. Si el input lo
        # contradice NO se corrige en silencio: es incompatibilidad contractual.
        b_valid_in <- isTRUE(b_block$valid)
        if (b_valid_in != (cv$B_success >= 2)) {
          add_incompat(sprintf(paste("I15 violado por el input: bootstrap$valid = %s con",
                                     "B_success = %g"), b_valid_in, cv$B_success))
        }
      }
    }
  }
  b_level <- if (!is.null(b_block) && is.list(b_block) &&
                 !is.null(b_block$confidence_level))
               b_block$confidence_level else NA_real_
  # Config custom no utilizable: se declara aparte, NO como incompatibilidad de
  # datos —el problema es de configuración y no debe alterar el estado global—.
  ctol <- .dfit_confidence_tol(config)
  cfg_issues <- if (isTRUE(ctol$valid)) character(0) else
    sprintf(paste("`confidence_level_tol` de la configuración no es utilizable;",
                  "se emplea el valor por defecto documentado (%g)"), ctol$tol)

  # ------------------------------------------------- 3. Identidad de parámetros
  # `b_is_list` protege todos los accesos `$` posteriores: sobre un atómico el
  # operador `$` es un error, no un NULL.
  b_is_list <- !is.null(b_block) && is.list(b_block)
  a_names <- if (!is.null(a_block) && !is.null(a_block$parameters))
               names(a_block$parameters) else NULL
  b_names <- if (b_is_list) b_block$parameter_names else NULL
  same_names <- TRUE
  if (is.null(pv)) {
    same_names <- NA
  } else {
    # Identidad EXACTA: nombres, orden y cardinalidad. Nunca se reordena, y dos
    # vectores de igual longitud NO se asumen equivalentes.
    if (!is.null(a_names) && !identical(a_names, pnames)) {
      same_names <- FALSE
      add_incompat("los nombres/orden de parámetros del bloque analítico no coinciden con la estimación puntual")
    }
    if (!is.null(b_names) && !identical(as.character(b_names), pnames)) {
      same_names <- FALSE
      add_incompat("los nombres/orden de parámetros del bloque bootstrap no coinciden con la estimación puntual")
    }
  }
  if (b_is_list && !is.na(est) && !is.null(b_block$estimator) &&
      !identical(as.character(b_block$estimator)[1], est)) {
    add_incompat(sprintf("el bootstrap declara estimador '%s' y la estimación puntual '%s'",
                         b_block$estimator, est))
  }
  if (b_is_list && !is.na(dist) && !is.null(b_block$distribution) &&
      !identical(as.character(b_block$distribution)[1], dist)) {
    add_incompat(sprintf("el bootstrap declara distribución '%s' y la estimación puntual '%s'",
                         b_block$distribution, dist))
  }

  # ------------------------------------------------------- 4. Estado global (§6)
  a_ok <- identical(a_status, "complete")
  b_ok <- b_status %in% c("partial", "complete")
  global <- if (is.null(pv) || length(pv) == 0L) "no_point_estimate"
            else if (length(incompat) > 0L) "incompatible"
            else if ( a_ok &&  b_ok) "uncertainty_both"
            else if ( a_ok && !b_ok) "uncertainty_analytic"
            else if (!a_ok &&  b_ok) "uncertainty_bootstrap"
            else "point_only"

  # ------------------------------------------------------- 5. Comparabilidad (§10)
  same_level <- if (!is.null(a_block) && b_is_list)
                  .dfit_same_confidence_level(a_level, b_level, config) else NA
  smeta <- .dfit_sample_meta(sample_meta)
  # OD-18: n coincidente es condición NECESARIA y NO SUFICIENTE. El bloque
  # analítico de B12 no lleva huella, de modo que la identidad NO es verificable.
  same_n <- if (!is.null(a_block) && b_is_list &&
                is.numeric(a_block$n) && is.numeric(b_block$n))
              isTRUE(a_block$n == b_block$n) else NA
  # --------------------------------------------------- 5b. Identidad de muestra (OD-18)
  # Regla: `sample_identity_verified = TRUE` exige IGUALDAD DE FINGERPRINT **y**
  # de `n_used`. La coincidencia de `n` es NECESARIA pero NO SUFICIENTE, y no se
  # admite ningún sustituto —media, sd, min/max, cuantiles— como prueba de
  # identidad. Si falta alguna huella, la identidad NO se infiere: se declara
  # «no verificable», que no es lo mismo que «muestras distintas».
  # Una huella solo cuenta como IDENTIDAD si es utilizable bajo el contrato
  # congelado de B13. No basta con que dos cadenas sean iguales: `"abc" == "abc"`
  # no es evidencia de nada. Se exige SHA-256 bien formado (64 hex), estado
  # `complete` y algoritmo declarado `sha256` en AMBAS vías.
  fp_take <- function(v) {
    if (is.null(v) || !is.character(v) || length(v) != 1L) NA_character_ else v
  }
  st_take <- function(v) {
    if (is.null(v) || !is.character(v) || length(v) != 1L) NA_character_ else v
  }
  fp_problems <- function(fp, status, algo, lbl) {
    q <- character(0)
    if (is.na(fp)) q <- c(q, sprintf("falta la huella de la vía %s", lbl))
    else if (!grepl("^[0-9a-f]{64}$", fp)) {
      q <- c(q, sprintf("la huella de la vía %s no es un SHA-256 de 64 hexadecimales", lbl))
    }
    if (!identical(status, "complete")) {
      q <- c(q, sprintf("la huella de la vía %s no está en estado 'complete' (%s)",
                        lbl, if (is.na(status)) "ausente" else status))
    }
    if (!identical(algo, "sha256")) {
      q <- c(q, sprintf("la vía %s no declara algoritmo 'sha256' (%s)",
                        lbl, if (is.na(algo)) "ausente" else algo))
    }
    q
  }
  a_sm  <- if (!is.null(a_block) && is.list(a_block$sample)) a_block$sample else list()
  a_fp  <- fp_take(a_sm$fingerprint)
  a_st  <- st_take(a_sm$fingerprint_status)
  a_alg <- st_take(a_sm$fingerprint_algo)
  b_fp  <- if (b_is_list) fp_take(b_block$data_fingerprint)   else NA_character_
  b_st  <- if (b_is_list) st_take(b_block$fingerprint_status) else NA_character_
  b_alg <- if (b_is_list) st_take(b_block$fingerprint_algo)   else NA_character_
  a_nu <- if (!is.null(a_block) && is.list(a_block$sample) &&
              is.numeric(a_sm$n_used) && length(a_sm$n_used) == 1L)
            a_sm$n_used else NA_real_
  b_nu <- if (b_is_list && is.numeric(b_block$n) && length(b_block$n) == 1L)
            b_block$n else NA_real_

  id_problems <- character(0)
  identity_status <- if (is.null(a_block) || !b_is_list) {
    "not_applicable"
  } else {
    id_problems <- c(fp_problems(a_fp, a_st, a_alg, "analítica"),
                     fp_problems(b_fp, b_st, b_alg, "bootstrap"))
    if (length(id_problems) == 0L && !identical(a_alg, b_alg)) {
      id_problems <- c(id_problems, "las dos vías declaran algoritmos distintos")
    }
    if (length(id_problems) > 0L) "not_verifiable"
    else if (!is.finite(a_nu) || !is.finite(b_nu)) {
      id_problems <- "algún tamaño de muestra declarado no es un escalar finito"
      "different_n"
    }
    else if (a_nu != b_nu)          "different_n"
    else if (!identical(a_fp, b_fp)) "mismatch"
    else                             "verified"
  }
  identity_verified <- identical(identity_status, "verified")   # I16: nunca por omisión
  identity_reason <- switch(identity_status,
    not_applicable = NA_character_,
    verified       = NA_character_,
    not_verifiable = paste0("la identidad de muestra NO es verificable: ",
                            paste(id_problems, collapse = "; "),
                            ". La coincidencia de n sería necesaria pero no",
                            " suficiente (OD-18)"),
    different_n    = if (length(id_problems) > 0L) id_problems[1] else
                       sprintf(paste("las dos vías declaran tamaños de muestra distintos",
                                     "(%g frente a %g): no corresponden a la misma",
                                     "muestra de análisis"), a_nu, b_nu),
    mismatch       = paste("las huellas SHA-256 de la muestra difieren entre la vía",
                           "analítica y la bootstrap: son identidades válidas de",
                           "muestras DISTINTAS"))

  # La falta o el fallo de identidad bloquean la COMPARACIÓN entre vías, no el
  # uso independiente de cada inferencia: por eso degrada `comparability` y NO
  # el estado global, que sigue reflejando qué incertidumbre es publicable.
  comp_status <- if (length(incompat) > 0L) "incompatible"
                 else if (is.null(a_block) || !b_is_list) "not_applicable"
                 else if (identity_status %in% c("mismatch", "different_n")) "incompatible"
                 else if (identical(identity_status, "not_verifiable")) "limited"
                 else if (isTRUE(same_level)) "comparable"
                 else "limited"

  # -------------------------------------------------------- 6. Por parámetro (§7)
  na_analytic <- function() list(available = FALSE, valid = FALSE, status = a_status,
                                 reason = a_reason, se = NA_real_, ci_lower = NA_real_,
                                 ci_upper = NA_real_, confidence_level = NA_real_,
                                 transform = NA_character_, support = NA_character_)
  na_boot <- function() list(calculated = !is.null(bootstrap_inference), valid = FALSE,
                             status = b_status, reason = b_reason,
                             se = NA_real_, bias = NA_real_, ci_lower = NA_real_,
                             ci_upper = NA_real_, confidence_level = NA_real_,
                             se_available = FALSE, bias_available = FALSE,
                             ci_degenerate = NA)
  pick <- function(v, j) {
    if (is.null(v)) return(NA_real_)
    if (is.matrix(v)) return(NA_real_)
    if (length(v) < j) return(NA_real_)
    as.numeric(v[[j]])
  }
  params_out <- list()
  if (!is.null(pv)) {
    params_out <- lapply(seq_along(pv), function(j) {
      nm <- pnames[j]
      an <- na_analytic()
      if (!is.null(a_block) && identical(a_status, "complete") &&
          !is.null(a_block$parameters[[nm]])) {
        p <- a_block$parameters[[nm]]
        an <- list(available = TRUE, valid = TRUE, status = a_status,
                   reason = NA_character_,
                   se = p$se, ci_lower = p$ci_lower, ci_upper = p$ci_upper,
                   confidence_level = a_level,
                   transform = p$transform, support = p$support)
      }
      bo <- na_boot()
      # Solo se mapea cuando los contadores son válidos: con un contrato roto no
      # puede afirmarse que se/bias/ci correspondan a lo que dicen ser.
      if (b_is_list && b_counters_ok && identical(same_names, TRUE)) {
        se_j   <- pick(b_block$se, j)
        bias_j <- pick(b_block$bias, j)
        ci_l <- NA_real_; ci_u <- NA_real_
        if (is.matrix(b_block$ci) && nm %in% rownames(b_block$ci)) {
          ci_l <- as.numeric(b_block$ci[nm, "lower"])
          ci_u <- as.numeric(b_block$ci[nm, "upper"])
        }
        bo <- list(calculated = TRUE, valid = isTRUE(b_block$valid),
                   status = b_status, reason = b_reason,
                   se = se_j, bias = bias_j, ci_lower = ci_l, ci_upper = ci_u,
                   confidence_level = b_level,
                   se_available   = is.finite(se_j),
                   bias_available = is.finite(bias_j),
                   ci_degenerate  = if (is.null(b_block$ci_degenerate)) NA
                                    else b_block$ci_degenerate)
      }
      list(name = nm, estimate = unname(pv[[j]]), analytic = an, bootstrap = bo)
    })
    names(params_out) <- pnames
  }

  # --------------------------------------------------------- 7. Limitaciones (§15.1)
  lim <- character(0)
  if (isTRUE(smeta$conditional)) lim <- c(lim, smeta$conditional_note)
  if (b_is_list && isTRUE(b_block$summaries_conditional_on_success)) {
    lim <- c(lim, paste("los resúmenes bootstrap se calculan sobre las réplicas válidas;",
                        "si la probabilidad de éxito depende del valor que habría tomado",
                        "el estimador, pueden no representar la distribución bootstrap no",
                        "condicionada. La dirección y magnitud de esa distorsión dependen",
                        "del mecanismo de fallo"))
  }
  if (!is.null(a_block) && b_is_list && !is.na(identity_reason)) {
    lim <- c(lim, paste(identity_reason,
                        "— esto impide comparar la vía analítica con la bootstrap;",
                        "cada una sigue siendo utilizable por separado"))
  }
  if (identical(comp_status, "limited")) {
    lim <- c(lim, paste("los niveles de confianza analítico y bootstrap difieren:",
                        "cada intervalo es válido individualmente, pero no deben",
                        "compararse amplitudes ni extremos entre sí"))
  }
  if (identical(a_status, "not_applicable")) {
    lim <- c(lim, sprintf("no hay inferencia analítica para el estimador '%s'", est))
  }
  if (identical(b_status, "insufficient")) {
    lim <- c(lim, paste("una sola réplica bootstrap válida: la desviación típica muestral",
                        "no está definida y el intervalo percentil degenera a un punto"))
  }

  # ------------------------------------------------------------------- 8. Salida
  list(
    status         = global,
    estimator      = est,
    distribution   = dist,
    point_estimate = if (is.list(point_estimate)) point_estimate$params else NULL,
    sample         = smeta,
    analytic = list(
      status = a_status, reason = a_reason, confidence_level = a_level,
      available = !is.null(a_block)
    ),
    bootstrap = list(
      status = b_status, reason = b_reason, confidence_level = b_level,
      available = !is.null(bootstrap_inference),
      # `counters_valid` distingue «el bootstrap dice que falló» de «el bloque
      # recibido no permite decir nada»: sin él, ambos casos se leerían igual.
      counters_valid = b_counters_ok,
      valid = if (!b_is_list) NA else isTRUE(b_block$valid),
      # Contadores VERBATIM: se conservan tal como llegaron, incluso si son
      # incoherentes. NA representa ausencia; no se infiere ningún valor.
      B_requested = Bq, B_success = Bs, B_failed = Bf, success_rate = b_rate,
      seed = if (!b_is_list) NA_real_ else keep(b_block$seed),
      quantile_type = if (!b_is_list) NA_integer_ else keep(b_block$quantile_type),
      data_fingerprint = if (!b_is_list) NA_character_ else keep(b_block$data_fingerprint),
      fingerprint_algo = if (!b_is_list) NA_character_ else keep(b_block$fingerprint_algo),
      failures = if (!b_is_list || is.null(b_block$failures))
                   list(counts = integer(0), examples = list()) else b_block$failures,
      summaries_conditional_on_success =
        if (!b_is_list) NA else isTRUE(b_block$summaries_conditional_on_success),
      ci_degenerate = if (!b_is_list) NA else keep(b_block$ci_degenerate)
    ),
    parameters = params_out,
    comparability = list(
      status = comp_status,
      same_confidence_level = same_level,
      analytic_level = a_level, bootstrap_level = b_level,
      same_parameter_names = same_names,
      same_sample_n = same_n,
      # OD-18. `sample_identity_verified` exige huella IGUAL y `n_used` igual.
      # `sample_identity_status` distingue por qué no se verifica: falta de
      # evidencia (`not_verifiable`) no es lo mismo que evidencia de muestras
      # distintas (`mismatch` / `different_n`).
      sample_identity_verified = identity_verified,
      sample_identity_status = identity_status,
      sample_identity_reason = identity_reason,
      # Auditoría: se PROPAGAN, no se recalculan.
      analytic_sample_fingerprint = a_fp,
      bootstrap_sample_fingerprint = b_fp,
      analytic_fingerprint_status = a_st,  bootstrap_fingerprint_status = b_st,
      analytic_fingerprint_algo   = a_alg, bootstrap_fingerprint_algo   = b_alg,
      analytic_n_used = a_nu, bootstrap_n_used = b_nu
    ),
    diagnostics = list(
      incompatibilities = incompat,
      # Problemas de CONFIGURACIÓN, separados de las incompatibilidades de datos:
      # no alteran el estado global porque no dicen nada sobre el ajuste.
      config_issues = cfg_issues,
      analytic_not_applicable = identical(a_status, "not_applicable"),
      n_parameters = if (is.null(pv)) 0L else length(pv)
    ),
    limitations = lim
  )
}


# ============================================================
# 2c-sexies. COMPARACIÓN DESCRIPTIVA ANALÍTICO vs BOOTSTRAP (Capa 1, B15)
# ============================================================
# B15 NO HACE INFERENCIA NUEVA. Consume el objeto de validación de B14 —que a su
# vez consume B12 y B13—, lo organiza en una tabla comparable y lo deja listo
# para que B16 lo represente. Nada se recalcula: ni MLE, ni Hessiana, ni
# covarianza, ni SE, ni IC, ni bootstrap, ni percentiles, ni huellas.
#
# ES UNA CAPA DESCRIPTIVA, NO UN MOTOR DE EVALUACIÓN. No se introduce ninguna
# puntuación de acuerdo o concordancia, ninguna etiqueta de estabilidad, ningún
# semáforo, ningún umbral, ningún cociente de SE ni solapamiento de intervalos
# como criterio, ninguna selección automática de método. **B15 describe; no
# interpreta calidad estadística.** Las métricas avanzadas de concordancia
# quedan DIFERIDAS a v1.2+.
#
# PRECONDICIÓN DE COMPARABILIDAD: la comparación directa solo se declara
# disponible cuando B14 verificó `sample_identity_verified == TRUE` (OD-18).
# `same_sample_n` es información secundaria y NO se usa como prueba de identidad.

#' Estados de comparación de B15. Catálogo deliberadamente pequeño.
DFIT_COMPARISON_STATUS <- c("available", "analytic_only", "bootstrap_only",
                            "point_only", "not_comparable", "incompatible")

#' Comparación descriptiva de incertidumbre analítica y bootstrap (B15)
#'
#' @param validation Objeto devuelto por `.validate_estimator()` (B14).
#' @return list(comparison_status, estimator, distribution, parameters,
#'   sample_identity_verified, sample_identity_status, confidence_levels,
#'   bootstrap_counts, diagnostics, limitations).
.compare_uncertainty <- function(validation) {
  cols <- c("parameter", "estimate",
            "analytic_available", "analytic_se",
            "analytic_ci_lower", "analytic_ci_upper", "analytic_confidence_level",
            "bootstrap_available", "bootstrap_se",
            "bootstrap_ci_lower", "bootstrap_ci_upper", "bootstrap_confidence_level")
  empty_df <- stats::setNames(
    data.frame(character(0), numeric(0), logical(0), numeric(0), numeric(0),
               numeric(0), numeric(0), logical(0), numeric(0), numeric(0),
               numeric(0), numeric(0), stringsAsFactors = FALSE), cols)

  out <- list(comparison_status = "incompatible",
              estimator = NA_character_, distribution = NA_character_,
              parameters = empty_df,
              sample_identity_verified = FALSE,
              sample_identity_status = NA_character_,
              confidence_levels = list(analytic = NA_real_, bootstrap = NA_real_,
                                       same = NA),
              bootstrap_counts = list(B_requested = NA, B_success = NA,
                                      B_failed = NA, success_rate = NA_real_),
              diagnostics = character(0), limitations = character(0))

  if (is.null(validation) || !is.list(validation) || is.null(validation$status)) {
    out$diagnostics <- "el objeto de validación de B14 no respeta su contrato"
    return(out)
  }

  cmp  <- if (is.list(validation$comparability)) validation$comparability else list()
  boot <- if (is.list(validation$bootstrap)) validation$bootstrap else list()
  ana  <- if (is.list(validation$analytic)) validation$analytic else list()

  out$estimator    <- validation$estimator
  out$distribution <- validation$distribution
  out$sample_identity_verified <- isTRUE(cmp$sample_identity_verified)
  out$sample_identity_status   <- if (is.null(cmp$sample_identity_status))
                                    NA_character_ else cmp$sample_identity_status
  out$confidence_levels <- list(
    analytic  = if (is.null(ana$confidence_level))  NA_real_ else ana$confidence_level,
    bootstrap = if (is.null(boot$confidence_level)) NA_real_ else boot$confidence_level,
    # Se PROPAGA el diagnóstico de B14; B15 no recalcula ni armoniza niveles.
    same      = if (is.null(cmp$same_confidence_level)) NA else cmp$same_confidence_level)
  out$bootstrap_counts <- list(
    B_requested  = if (is.null(boot$B_requested))  NA else boot$B_requested,
    B_success    = if (is.null(boot$B_success))    NA else boot$B_success,
    B_failed     = if (is.null(boot$B_failed))     NA else boot$B_failed,
    success_rate = if (is.null(boot$success_rate)) NA_real_ else boot$success_rate)
  out$limitations <- if (is.character(validation$limitations))
                       validation$limitations else character(0)

  # ---- 1. Disponibilidad de cada vía, tal como la dictaminó B14 ----
  a_ok <- identical(ana$status, "complete")
  b_ok <- !is.null(boot$status) && boot$status %in% c("partial", "complete")

  # ---- 2. Estado de comparación ----
  # `no_point_estimate` de B14 se traduce a `incompatible`: es una anomalía
  # contractual detectada aguas arriba y no procede abrir un estado nuevo.
  out$comparison_status <-
    if (identical(validation$status, "incompatible") ||
        identical(validation$status, "no_point_estimate")) "incompatible"
    else if (a_ok && b_ok) {
      # OD-18: la identidad la certifica B14. `same_sample_n` NO sirve.
      if (isTRUE(cmp$sample_identity_verified)) "available" else "not_comparable"
    }
    else if (a_ok)  "analytic_only"
    else if (b_ok)  "bootstrap_only"
    else            "point_only"

  # ---- 3. Tabla descriptiva, en el ORDEN OFICIAL de parámetros ----
  # Se construye siempre que haya parámetros, no solo con `available`: con una
  # sola vía sigue siendo útil para B16, con la otra columna a NA.
  ps <- validation$parameters
  if (is.list(ps) && length(ps) > 0L) {
    num <- function(v) if (is.null(v) || length(v) != 1L) NA_real_ else as.numeric(v)
    rows <- lapply(ps, function(p) {
      a <- if (is.list(p$analytic))  p$analytic  else list()
      b <- if (is.list(p$bootstrap)) p$bootstrap else list()
      data.frame(
        parameter = as.character(p$name),
        estimate  = num(p$estimate),
        analytic_available        = isTRUE(a$available) && a_ok,
        analytic_se               = num(a$se),
        analytic_ci_lower         = num(a$ci_lower),
        analytic_ci_upper         = num(a$ci_upper),
        analytic_confidence_level = num(a$confidence_level),
        bootstrap_available       = isTRUE(b$calculated) && b_ok,
        bootstrap_se              = num(b$se),
        bootstrap_ci_lower        = num(b$ci_lower),
        bootstrap_ci_upper        = num(b$ci_upper),
        bootstrap_confidence_level = num(b$confidence_level),
        stringsAsFactors = FALSE)
    })
    df <- do.call(rbind, rows)
    rownames(df) <- NULL
    out$parameters <- df
  }

  # ---- 4. Diagnósticos: DESCRIPTIVOS y CONTRACTUALES ----
  d <- character(0)
  if (!a_ok) {
    d <- c(d, switch(if (is.null(ana$status)) "" else ana$status,
      not_applicable = sprintf("analytic uncertainty not applicable for estimator '%s'",
                               as.character(validation$estimator)[1]),
      not_requested  = "analytic uncertainty not calculated",
      failed         = "analytic uncertainty unavailable: computation failed",
      not_available  = "analytic uncertainty unavailable",
      "analytic uncertainty unavailable"))
  }
  if (!b_ok) {
    d <- c(d, switch(if (is.null(boot$status)) "" else boot$status,
      not_requested = "bootstrap uncertainty not calculated",
      failed        = "bootstrap uncertainty unavailable: no valid replicates",
      insufficient  = "bootstrap uncertainty unavailable: a single valid replicate",
      "bootstrap uncertainty unavailable"))
  }
  if (a_ok && b_ok && !isTRUE(cmp$sample_identity_verified)) {
    d <- c(d, sprintf("sample identity not verified (%s): direct comparison not available",
                      out$sample_identity_status))
  }
  if (identical(cmp$same_parameter_names, FALSE)) {
    d <- c(d, "parameter identity mismatch reported by B14")
  }
  if (identical(cmp$same_confidence_level, FALSE)) {
    d <- c(d, "analytic and bootstrap confidence levels differ")
  }
  if (b_ok && is.numeric(out$bootstrap_counts$B_failed) &&
      isTRUE(out$bootstrap_counts$B_failed > 0)) {
    d <- c(d, sprintf("bootstrap inference based on %s of %s replicates",
                      out$bootstrap_counts$B_success, out$bootstrap_counts$B_requested))
  }
  if (length(validation$diagnostics$incompatibilities) > 0L) {
    d <- c(d, paste("contract incompatibility reported by B14:",
                    validation$diagnostics$incompatibilities))
  }
  out$diagnostics <- d
  out
}


#' Estima una distribución por un método concreto. Devuelve NULL si el método no
#' está definido o no procede para estos datos.
#'
#' B11.2: admite `method = "pm"` (Percentile Matching). El argumento `pm` es
#' OPCIONAL y solo lo consume ese método, de modo que las llamadas existentes
#' —incluida la de `.fit_auto`, que NO se modifica— siguen siendo válidas sin
#' cambios. Con `pm = NULL` se usa el preset por defecto congelado (`p3w`).
#'
#' @param id Id de la distribución. @param x Muestra. @param method Método.
#' @param pm Vector de percentiles para `method = "pm"`.
#' @param config Configuración de ejecución.
#' @return list(params, logLik, converged, message) —y `pm` con el detalle del
#'   ajuste cuando el método es PM— o NULL si el método no aplica.
.estimate <- function(id, x, method, pm = NULL, config = dfit_default_config()) {
  if (identical(method, "pm")) {
    if (is.null(DFIT_PM_PARAMS[[id]])) return(NULL)
    p <- if (is.null(pm)) DFIT_PM$presets[[DFIT_PM$default_preset]]$percentiles else pm
    fit <- .pm_fit(id, x, p, config)
    if (!isTRUE(fit$converged)) {
      return(list(params = fit$params, logLik = NA_real_, converged = FALSE,
                  message = fit$reason, pm = fit))
    }
    # La log-verosimilitud se publica por coherencia con MoM y L-momentos, que ya
    # la calculan igual. NO se usa para comparar PM con MLE: PM no entra en el
    # ranking en B11.2 (ver la guarda de `.motor`).
    return(list(params = fit$params, logLik = .dist_loglik(id, x, fit$params),
                converged = TRUE, message = NA_character_, pm = fit))
  }
  reg <- switch(method, mle = DFIT_MLE, mom = DFIT_MOM, lmom = DFIT_LMOM, NULL)
  fn <- reg[[id]]
  if (is.null(fn)) return(NULL)
  est <- fn(x)
  if (is.null(est)) return(NULL)
  if (method == "mle") {
    # Los estimadores cerrados no pasan por `.mle_optim` y no traen `message`.
    if (is.null(est$message)) est$message <- NA_character_
    return(est)
  }
  list(params = est$params, logLik = .dist_loglik(id, x, est$params),
       converged = TRUE, message = NA_character_)
}


# ============================================================
# 2d. AJUSTE DE UNA CANDIDATA CON SELECCIÓN DE MÉTODO (B2.2)
# ============================================================

#' Selección AUTO de método (opt-in): MLE-first con fallback por convergencia
#'
#' Usa MLE (eficiente y robusto tras ADR-014); si MLE no converge, cae al mejor
#' método disponible (MoM -> L-momentos), registrando el motivo. El refinamiento
#' por tamaño muestral / cola pesada y por estabilidad (bootstrap) se difiere a B3.
#'
#' @return Campos de ajuste (method, method_reason, params, logLik, converged, message).
.fit_auto <- function(id, x, base) {
  est <- .estimate(id, x, "mle")
  if (!is.null(est) && isTRUE(est$converged)) {
    return(c(base, list(method = "mle", method_reason = "AUTO: MLE convergió",
                        params = est$params, logLik = est$logLik,
                        converged = TRUE, message = NA_character_)))
  }
  for (meth in c("mom", "lmom")) {
    alt <- .estimate(id, x, meth)
    if (!is.null(alt)) {
      return(c(base, list(method = meth,
                          method_reason = sprintf("AUTO: MLE no convergió -> %s", meth),
                          params = alt$params, logLik = alt$logLik,
                          converged = TRUE, message = NA_character_)))
    }
  }
  c(base, list(method = "mle", method_reason = "AUTO: sin método disponible",
               params = if (!is.null(est)) est$params else NULL,
               logLik = if (!is.null(est)) est$logLik else NA_real_,
               converged = FALSE,
               message = if (!is.null(est) && !is.null(est$message) && !is.na(est$message)) {
                 est$message
               } else "ningún método produjo un ajuste válido"))
}

#' Ajuste de una distribución candidata por el método indicado
#'
#' ADR-026: **ya no prepara el soporte**. Recibe la muestra común del análisis,
#' construida una única vez por `build_analysis_sample()`. `n_excluded` se
#' conserva en el contrato por compatibilidad, pero queda vestigial (siempre 0):
#' la exclusión efectiva se registra en `analysis$sample`.
#'
#' ADR-027: aplica la guarda (B) de plausibilidad sobre la log-verosimilitud
#' obtenida, de modo que un ajuste degenerado nunca entre silenciosamente en el
#' ranking.
#'
#' @param spec Registro de la candidata (id, label, n_params).
#' @param x Muestra común del análisis (vector numérico sin NA).
#' @param role "candidate" o "control".
#' @param method Método de estimación.
#' @param family Familia del análisis ("continuous"/"discrete"); la guarda (B)
#'   solo aplica a la continua (en la discreta la PMF ya está acotada por 1).
#' @param resolution Resolución empírica de la muestra (`sample$resolution`).
#' @param config Configuración de ejecución.
#' @return Lista estructurada con el ajuste.
#' B12.2: `inference` es OPT-IN y por defecto `FALSE`. Con `FALSE` la salida de
#' `.fit_one()` es byte a byte la de antes de B12.2, de modo que el contrato
#' serializado productivo —View Model, export, `schema_version`— NO cambia y no
#' procede ningún bump. Con `TRUE` se añade `fit$inference` como capa HERMANA de
#' `fit$params`, sin alterar el significado de `fit$params`. La conexión efectiva
#' a la interfaz es B16.
.fit_one <- function(spec, x, role = "candidate", method = "mle",
                     family = "continuous", resolution = NA_real_,
                     config = dfit_default_config(),
                     inference = FALSE, confidence_level = NULL) {
  id <- spec$id
  base <- list(
    id = id, label = spec$label, n_params = spec$n_params, role = role,
    n_used = length(x),
    # Vestigial (ADR-026): la muestra llega ya restringida al soporte común.
    n_excluded = list(zeros = 0L, negatives = 0L)
  )
  not_fittable <- function(msg, meth = method, reason = NA_character_) {
    c(base, list(method = meth, method_reason = reason, params = NULL,
                 logLik = NA_real_, converged = FALSE, message = msg))
  }
  if (length(x) < spec$n_params + 1L) {
    return(not_fittable("datos insuficientes para estimar sus parámetros"))
  }
  if (id %in% DFIT_DISCRETE_IDS && any(abs(x - round(x)) > config$integer_tol)) {
    return(not_fittable("la distribución discreta requiere datos enteros"))
  }

  fit <- if (method == "auto") {
    .fit_auto(id, x, base)
  } else {
    est <- .estimate(id, x, method)
    if (is.null(est)) {
      return(not_fittable(sprintf("método '%s' no disponible para '%s'", method, id),
                          reason = "método no disponible"))
    }
    c(base, list(method = method, method_reason = "solicitado", params = est$params,
                 logLik = est$logLik, converged = est$converged,
                 message = if (is.null(est$message)) NA_character_ else est$message))
  }

  # Guarda (B) de ADR-027, aplicada al ajuste ya obtenido.
  if (isTRUE(fit$converged) && identical(family, "continuous")) {
    bad <- .loglik_implausible(fit$logLik, length(x), resolution, config)
    if (!is.na(bad)) {
      fit$converged <- FALSE
      fit$message   <- bad
    }
  }
  # B12.2: capa hermana de `params`. Se calcula DESPUÉS de las guardas de
  # ADR-027, de modo que un ajuste rechazado por ellas llega aquí con
  # `converged = FALSE` y `.mle_uncertainty()` devuelve no disponible con motivo,
  # en lugar de un SE sobre un óptimo de frontera.
  if (isTRUE(inference)) {
    fit$inference <- .mle_uncertainty(fit, x, confidence_level, config)
  }
  fit
}

#' Motor de estimación (Capa 1): ajusta todas las candidatas por el método dado
#'
#' ADR-026: recibe la **muestra común** ya construida, no el vector válido. El
#' control (Normal) se ajusta sobre esa misma muestra, no sobre la suya: su
#' función es compararse con las candidatas, así que debe compartir sus datos.
#'
#' @param sample Salida de `build_analysis_sample()`.
#' @param candidates Salida de `select_candidate_distributions()`.
#' @param config Configuración de ejecución.
#' @param method Método de estimación: "mle" | "mom" | "lmom" | "auto".
#' @return list(method, family, fits, control_fits, n_used). `method` es el
#'   solicitado; cada ajuste registra además el método efectivamente usado.
.motor <- function(sample, candidates, config = dfit_default_config(), method = "mle",
                   inference = FALSE, confidence_level = NULL) {
  # B11.2: PM se expone en `.estimate()` pero NO entra aquí. Todo lo que pasa por
  # `.motor` alimenta Assessment, ranking y recomendación, y comparar un ajuste
  # PM con uno MLE por AIC exigiría una decisión que B11.1 no tomó. La guarda es
  # deliberada: impide que PM llegue al ranking por accidente en lugar de por
  # diseño. Ver ADR-032 (OD-15).
  if (identical(method, "pm")) {
    stop(paste("Percentile Matching no está integrado en el motor de ranking.",
               "B11.2 entrega estimación puntual vía .estimate(id, x, \"pm\").",
               "La integración en Assessment/ranking se decide en un bloque posterior."),
         call. = FALSE)
  }
  x      <- sample$x
  family <- candidates$family
  fit_args <- list(x = x, role = "candidate", method = method, family = family,
                   resolution = sample$resolution, config = config,
                   inference = inference, confidence_level = confidence_level)

  fits <- lapply(candidates$specs, function(spec) {
    do.call(.fit_one, c(list(spec = spec), fit_args))
  })
  names(fits) <- candidates$distributions

  control_fits <- list()
  if (identical(candidates$control, "normal")) {
    control_fits$normal <- do.call(.fit_one, c(
      list(spec = list(id = "normal", label = "Normal (control)", n_params = 2L)),
      utils::modifyList(fit_args, list(role = "control"))
    ))
  }

  list(method = method, family = family, fits = fits,
       control_fits = control_fits, n_used = sample$n_used)
}


# ============================================================
# 2e. DIAGNOSTICS (Capa 2) — bondad de ajuste + criterios de información
#     diseño §6 (Pilares A y B + adaptación por familia). B3.
# ============================================================
# Calcula, por ajuste convergente: estadísticos de bondad de ajuste y AIC/AICc/
# BIC. NO calcula p-valores (con parámetros estimados exigen calibración por
# bootstrap paramétrico, ADR-008; diferido). NO rankea ni recomienda (B4+).

#' CDF ajustada de una distribución continua
#' @return F(x) evaluada en x.
.dist_cdf <- function(id, x, p) {
  switch(id,
    exponential = stats::pexp(x, p$rate),
    normal      = stats::pnorm(x, p$mean, p$sd),
    lognormal   = stats::plnorm(x, p$meanlog, p$sdlog),
    gamma       = stats::pgamma(x, shape = p$shape, scale = p$scale),
    weibull     = stats::pweibull(x, shape = p$shape, scale = p$scale),
    loglogistic = { z <- (x / p$scale)^p$shape; z / (1 + z) },
    pareto      = 1 - (p$scale / (x + p$scale))^p$shape,
    burr        = 1 - (1 + (x / p$scale)^p$shape1)^(-p$shape2)
  )
}

#' PMF y CDF de una distribución discreta
.dist_pmf <- function(id, k, p) {
  switch(id,
    poisson           = stats::dpois(k, p$lambda),
    negative_binomial = stats::dnbinom(k, size = p$size, mu = p$mu),
    geometric         = stats::dgeom(k, p$prob)
  )
}
.dist_cdf_discrete <- function(id, k, p) {
  switch(id,
    poisson           = stats::ppois(k, p$lambda),
    negative_binomial = stats::pnbinom(k, size = p$size, mu = p$mu),
    geometric         = stats::pgeom(k, p$prob)
  )
}

#' Criterios de información (AIC, AICc, BIC)
#' @param loglik logLik. @param k nº de parámetros. @param n tamaño muestral.
.information_criteria <- function(loglik, k, n) {
  aic <- -2 * loglik + 2 * k
  list(
    aic  = aic,
    aicc = if (n - k - 1 > 0) aic + 2 * k * (k + 1) / (n - k - 1) else NA_real_,
    bic  = -2 * loglik + k * log(n)
  )
}

#' Bondad de ajuste (continua): KS (D), Cramér-von Mises (W²), Anderson-Darling (A²)
#' Estadísticos sobre la CDF ajustada y los estadísticos de orden. Sin p-valor.
.gof_continuous <- function(id, x, p) {
  n <- length(x); xs <- sort(x); u <- .dist_cdf(id, xs, p); i <- seq_len(n)
  ks  <- max(max(i / n - u), max(u - (i - 1) / n))
  cvm <- 1 / (12 * n) + sum((u - (2 * i - 1) / (2 * n))^2)
  ue  <- pmin(pmax(u, 1e-12), 1 - 1e-12)   # evita log(0)/log(1)
  ad  <- -n - sum((2 * i - 1) * (log(ue) + log(1 - rev(ue)))) / n
  list(ks = ks, cvm = cvm, ad = ad)
}

#' Bondad de ajuste (discreta): chi-cuadrado con agrupación de categorías
#'
#' ADR-019. Las categorías individuales del soporte se agrupan en celdas hasta
#' que cada una alcanza una esperanza mínima (`min_expected`, práctica estándar
#' del test chi-cuadrado); la última celda es siempre la cola superior. Esto evita
#' (a) celdas con esperanza 0 -> `0/0` -> chi² = NaN, y (b) un número de celdas
#' proporcional a `max(x)` en lugar de a `n` (200 observaciones no pueden generar
#' 48.828 celdas). El soporte a barrer se acota con el cuantil de la distribución
#' AJUSTADA que deja en la cola menos de `min_expected` esperados: coste O(1), no
#' se recorre el soporte observado entero.
#'
#' @param id Identificador de la distribución discreta.
#' @param x Vector de recuentos (enteros no negativos).
#' @param p Parámetros ajustados.
#' @param n_params Nº de parámetros estimados (para los grados de libertad).
#' @param config Configuración de ejecución (`gof_min_expected`, `gof_max_scan`).
#' @return list(chisq, df, overdispersion, n_cells, gof_note). `chisq`/`df` son
#'   `NA` —nunca `NaN`— si no se pueden formar al menos 2 celdas válidas.
.gof_discrete <- function(id, x, p, n_params, config = dfit_default_config()) {
  n <- length(x)
  m <- mean(x)
  overdispersion <- if (m > 0) mean((x - m)^2) / m else NA_real_

  # Agrupa las categorías del soporte en celdas con esperanza >= eps.
  cells_at <- function(eps) {
    # Cota superior del barrido: cuantil de la distribución AJUSTADA que deja en
    # la cola < eps esperados. O(1): no se recorre el soporte observado entero.
    kmax <- suppressWarnings(.dist_quantile(id, 1 - eps / n, p))
    if (!is.finite(kmax)) kmax <- max(x)
    kmax <- min(max(as.integer(kmax), 1L, max(x)), config$gof_max_scan)

    k  <- 0:kmax
    pk <- .dist_pmf(id, k, p)
    Ei <- c(n * pk, n * max(0, 1 - sum(pk)))                # categorías + cola
    Oi <- c(tabulate(as.integer(x) + 1L, nbins = kmax + 1L), sum(x > kmax))

    # Agrupación voraz de categorías adyacentes. El resto que no alcanza el
    # mínimo se funde con la última celda (siempre queda una celda de cola).
    Oc <- numeric(0); Ec <- numeric(0)
    accO <- 0; accE <- 0
    for (i in seq_along(Ei)) {
      accO <- accO + Oi[i]
      accE <- accE + Ei[i]
      if (accE >= eps) {
        Oc <- c(Oc, accO); Ec <- c(Ec, accE)
        accO <- 0; accE <- 0
      }
    }
    if (accE > 0 || accO > 0) {
      if (length(Ec) > 0L) {
        Oc[length(Oc)] <- Oc[length(Oc)] + accO
        Ec[length(Ec)] <- Ec[length(Ec)] + accE
      } else {
        Oc <- accO; Ec <- accE
      }
    }
    list(O = Oc, E = Ec, df = length(Ec) - 1L - n_params)
  }

  eps <- config$gof_min_expected
  cl  <- cells_at(eps)
  note <- NA_character_

  # Muestras pequeñas: con el suelo estándar pueden no quedar grados de libertad.
  # Se recurre entonces al suelo relajado (regla de Cochran), dejando constancia.
  if (cl$df < 1L) {
    eps_r <- config$gof_min_expected_relaxed
    cl_r  <- cells_at(eps_r)
    if (cl_r$df >= 1L) {
      cl   <- cl_r
      note <- sprintf(paste("esperanza mínima relajada de %g a %g (regla de Cochran):",
                            "con n = %d el suelo estándar no deja grados de libertad"),
                      eps, eps_r, n)
    }
  }

  if (length(cl$E) < 2L || cl$df < 1L) {
    return(list(
      chisq = NA_real_, df = NA_integer_, overdispersion = overdispersion,
      n_cells = length(cl$E),
      gof_note = sprintf(paste("chi-cuadrado no calculable: con n = %d solo se forman",
                               "%d celdas y %d parámetros estimados (0 grados de libertad)"),
                         n, length(cl$E), n_params)
    ))
  }

  list(
    chisq          = sum((cl$O - cl$E)^2 / cl$E),
    df             = as.integer(cl$df),
    overdispersion = overdispersion,
    n_cells        = length(cl$E),
    gof_note       = note
  )
}

#' Diagnostics (Capa 2): métricas por ajuste convergente
#'
#' ADR-026: recibe la **muestra común** y la usa tal cual. Antes volvía a
#' aplicar `.prepare_support()` por distribución, de modo que los estadísticos de
#' bondad de ajuste y los criterios de información de unas candidatas se
#' calculaban sobre muestras distintas de los de otras y luego se comparaban
#' entre sí en el Assessment.
#'
#' @param sample Salida de `build_analysis_sample()`.
#' @param motor Salida de `.motor()`.
#' @param config Configuración de ejecución (parámetros del chi², ADR-019).
#' @return list(family, per_fit, control, n_used). Cada elemento con
#'   `information` y `gof`, todos sobre la misma muestra.
.diagnostics <- function(sample, motor, config = dfit_default_config()) {
  family <- motor$family
  x_common <- sample$x
  diag_one <- function(fit) {
    if (!isTRUE(fit$converged) || is.null(fit$params)) {
      return(list(id = fit$id, converged = FALSE, information = NULL, gof = NULL))
    }
    x <- x_common
    gof <- if (family == "continuous") {
      .gof_continuous(fit$id, x, fit$params)
    } else {
      .gof_discrete(fit$id, x, fit$params, fit$n_params, config)
    }
    list(
      id = fit$id, converged = TRUE, n_used = fit$n_used, n_params = fit$n_params,
      information = .information_criteria(fit$logLik, fit$n_params, length(x)),
      gof = gof
    )
  }
  list(
    family  = family,
    n_used  = length(x_common),
    per_fit = lapply(motor$fits, diag_one),
    control = lapply(motor$control_fits, diag_one)
  )
}


# ============================================================
# 3. DECISION ENGINE (cableado) — decision_engine.md (§7.8)
# ============================================================

#' Estructura del motor de decisión (solo cableado; valores en decision_engine.md)
#'
#' Expone las siete secciones que `decision_engine.md` parametriza, con
#' marcadores de posición. B1 NO implementa decisiones estadísticas: los valores
#' calibrados se incorporan en bloques posteriores leyendo `decision_engine.md`.
#'
#' @return Lista con `version` y las siete secciones del criterio (placeholders).
decision_engine_spec <- function() {
  list(
    # decision_engine_version. Pasa a "0.2" en ADR-021: cambia la regla del nivel
    # de confianza (separación del compuesto -> ΔAIC). Los valores están
    # documentados en decision_engine.md.
    version = "0.2",

    # 1. Pesos por pilar (Fase 2). Solo A y B activos en B4; C/D/E definidos con
    #    peso 0 hasta que existan sus métricas (bloques posteriores). Provisional.
    pillar_weights = list(A = 0.7, B = 0.3, C = 0, D = 0, E = 0),

    # 6. Orden de desempate (§7.5). Estabilidad (D) y cola (C) se insertarán cuando
    #    existan; por ahora: parsimonia -> AIC -> id.
    tie_break_order = c("parsimony", "aic", "id"),

    # Umbrales de ΔAIC para el nivel de confianza (ADR-021). Criterio estándar de
    # Burnham & Anderson (2002): <2 modelos indistinguibles, 2-10 evidencia
    # moderada, >=10 evidencia fuerte. Sustituye a `confidence_separation`, que
    # umbralizaba una magnitud sin escala estable entre datasets. Sigue siendo
    # provisional: la confianza corresponde al pilar D (estabilidad), diferido.
    confidence_delta_aic = list(high = 10, medium = 2),

    # 5. Bandas de presentación para los Text Builders (B5): clasifican un score
    #    de pilar (0-100) como fortaleza o limitación. Son reglas de TEXTO, no de
    #    decisión: no alteran el ranking ni la recomendación.
    text_bands = list(strong = 75, weak = 25),

    # Diferencia de puntuación global por debajo de la cual una candidata se
    # describe como "próxima a la recomendada" (presentación, no decisión).
    close_score_gap = 10,

    # Pendientes de calibrar / de métricas posteriores:
    absolute_thresholds  = NULL,   # 2. categorías absolutas (Fase 1) — requiere p-valores
    admissibility_limits = NULL,   # 3. (§7.4) — la inestabilidad requiere Pilar D
    evt_threshold        = NULL,   # 4. (§7.6) — requiere Pilar C
    conflict_rules       = NULL,   # 5. conflictos entre insights (texto, B5)
    use_case_pillar_map  = NULL    # 7. mapa uso -> pilares del Nivel 2 (§7.7) — requiere C/D
  )
}


# ============================================================
# 3b. ASSESSMENT (Capa 3) — evaluación y ranking — diseño §7. B4.
# ============================================================
# Transforma las métricas de Diagnostics en una evaluación objetiva. Alcance B4
# (por decisión de proyecto): normalización, pilares A y B, score compuesto,
# RANKING RELATIVO (Fase 2), desempates y recomendación Nivel 1 + confianza.
# DIFERIDO (requiere pilares C/D o p-valores): categorías absolutas (Fase 1),
# detección EVT, adecuación por uso (Nivel 2), estabilidad. No genera texto (B5).

#' Normaliza un vector a [0, 100] con "menor = mejor" (100 al mínimo, 0 al máximo)
#'
#' Tolerante a métricas no disponibles (ADR-019: el chi² puede ser `NA` si no se
#' pueden formar celdas válidas). Los valores no finitos se ignoran para fijar la
#' escala y salen como `NA_real_`, nunca como `NaN` propagado.
.norm_lower_better <- function(vals) {
  ok <- is.finite(vals)
  out <- rep(NA_real_, length(vals))
  if (!any(ok)) return(out)
  lo <- min(vals[ok]); hi <- max(vals[ok])
  out[ok] <- if (hi == lo) 100 else 100 * (hi - vals[ok]) / (hi - lo)
  out
}

#' Marcadores de las piezas del §7 diferidas en B4
.assessment_deferred <- function() {
  list(
    absolute_categories = "diferido: requiere p-valores (bootstrap paramétrico, ADR-008)",
    evt_detection       = "diferido: requiere Pilar C (cola)",
    level2_use_case     = "diferido: requiere Pilares C y D",
    stability           = "diferido: requiere Pilar D (bootstrap)"
  )
}

#' Assessment (Capa 3): score compuesto, ranking relativo y recomendación Nivel 1
#'
#' @param diagnostics Salida de `.diagnostics()`.
#' @param motor Salida de `.motor()`.
#' @param engine Salida de `decision_engine_spec()`.
#' @return list(family, weights, ranking, excluded, recommendation, control_check,
#'   deferred, decision_engine_version).
.assess <- function(diagnostics, motor, engine) {
  family <- diagnostics$family
  fits   <- diagnostics$per_fit
  w      <- engine$pillar_weights

  conv_ids <- names(fits)[vapply(fits, function(f) isTRUE(f$converged), logical(1))]
  excluded <- lapply(setdiff(names(fits), conv_ids), function(id) {
    msg <- motor$fits[[id]]$message
    list(id = id, reason = if (is.null(msg) || is.na(msg)) "no convergió" else msg)
  })

  # ADR-026 — aserción defensiva del invariante de comparabilidad. La
  # normalización min-máx de este bloque solo tiene sentido si todas las
  # candidatas se han ajustado sobre la MISMA muestra: el AIC solo es comparable
  # entre modelos ajustados a datos idénticos. Con la muestra común (capa 0.5) el
  # invariante se cumple por construcción; esta comprobación existe para que, si
  # alguna vez dejara de cumplirse, el fallo sea ruidoso e inmediato en vez de
  # producir un ranking silenciosamente inválido.
  if (length(conv_ids) > 0L) {
    n_by_fit <- vapply(conv_ids, function(id) as.integer(fits[[id]]$n_used), integer(1))
    if (length(unique(n_by_fit)) > 1L) {
      stop(sprintf(paste("Invariante de muestra común roto (ADR-026): las candidatas",
                         "convergentes se han ajustado sobre muestras distintas (n = %s).",
                         "El ranking por AIC sería inválido."),
                   paste(sprintf("%s=%d", conv_ids, n_by_fit), collapse = ", ")),
           call. = FALSE)
    }
  }

  deferred <- .assessment_deferred()
  if (length(conv_ids) == 0L) {
    return(list(family = family, weights = w, ranking = list(), excluded = excluded,
                recommendation = list(level1 = NULL, note = "sin ajustes convergentes"),
                control_check = NULL, deferred = deferred,
                decision_engine_version = engine$version))
  }

  a_metrics <- if (family == "continuous") c("ks", "cvm", "ad") else c("chisq")
  b_metrics <- c("aic", "aicc", "bic")

  # Score de un pilar: media de sus métricas normalizadas entre los convergentes.
  # Una métrica ausente (NA) se ignora; si TODAS lo están, el pilar sale NA.
  score_pillar <- function(metrics, getter) {
    mat <- vapply(metrics, function(m) {
      vals <- vapply(conv_ids, function(id) {
        v <- getter(id, m)
        if (is.null(v) || length(v) != 1L) NA_real_ else as.numeric(v)
      }, numeric(1))
      .norm_lower_better(vals)
    }, numeric(length(conv_ids)))
    dim(mat) <- c(length(conv_ids), length(metrics))
    out <- rowMeans(mat, na.rm = TRUE)
    out[is.nan(out)] <- NA_real_          # todas las métricas ausentes
    out
  }
  scoreA <- score_pillar(a_metrics, function(id, m) fits[[id]]$gof[[m]])
  scoreB <- score_pillar(b_metrics, function(id, m) fits[[id]]$information[[m]])
  names(scoreA) <- conv_ids; names(scoreB) <- conv_ids

  # Compuesto (C/D/E con peso 0 en B4). Si una candidata no tiene pilar A —caso
  # del chi² no calculable (ADR-019)— su compuesto se apoya solo en el pilar B,
  # en lugar de propagar NaN y anular el ranking entero.
  composite <- vapply(conv_ids, function(id) {
    a <- scoreA[[id]]; b <- scoreB[[id]]
    if (is.finite(a)) w$A * a + w$B * b else b
  }, numeric(1))
  names(composite) <- conv_ids
  pillar_a_missing <- conv_ids[!is.finite(scoreA)]

  nparams <- vapply(conv_ids, function(id) fits[[id]]$n_params, numeric(1))
  aic     <- vapply(conv_ids, function(id) fits[[id]]$information$aic, numeric(1))
  ord <- order(-composite, nparams, aic, conv_ids)   # desempate: parsimonia -> AIC -> id

  ranking <- lapply(seq_along(ord), function(r) {
    id <- conv_ids[ord[r]]
    list(id = id, rank = r, composite = unname(composite[id]),
         pillar_scores = list(A = unname(scoreA[id]), B = unname(scoreB[id])),
         n_params = fits[[id]]$n_params)
  })

  top <- ranking[[1]]
  sep <- if (length(ranking) >= 2L) top$composite - ranking[[2]]$composite else NA_real_

  # --- Nivel de confianza (ADR-021) ---------------------------------------
  # Se basa en ΔAIC, no en la separación del compuesto: el compuesto sale de una
  # normalización min-máx cuya escala fija la PEOR candidata, por lo que `sep` no
  # es comparable entre datasets. ΔAIC sí lo es (criterio de Burnham & Anderson,
  # 2002). Se mide entre la candidata recomendada y la mejor de las restantes: si
  # la recomendada no es la mejor por AIC, ΔAIC sale negativo y la confianza baja.
  cth       <- engine$confidence_delta_aic
  aic_top   <- unname(aic[top$id])
  aic_rest  <- aic[setdiff(conv_ids, top$id)]
  delta_aic <- if (length(aic_rest) == 0L) NA_real_ else min(aic_rest) - aic_top

  confidence <- if (!is.finite(delta_aic)) "media"
                else if (delta_aic >= cth$high) "alta"
                else if (delta_aic >= cth$medium) "media" else "baja"

  # Coherencia entre criterios: si la recomendada no es la mejor ni por AIC ni por
  # el pilar A, la confianza no puede ser "alta" aunque ΔAIC lo sugiera.
  best_by_aic <- conv_ids[which.min(aic)]
  best_by_a   <- if (any(is.finite(scoreA))) {
    conv_ids[which.max(replace(scoreA, !is.finite(scoreA), -Inf))]
  } else NA_character_
  coherent <- identical(top$id, best_by_aic) ||
              (!is.na(best_by_a) && identical(top$id, best_by_a))
  if (!coherent && identical(confidence, "alta")) confidence <- "media"

  conf_reason <- if (!is.finite(delta_aic)) {
    "candidata única"
  } else {
    paste0(
      sprintf("ΔAIC con la siguiente mejor candidata = %.2f (umbrales alta>=%g / media>=%g)",
              delta_aic, cth$high, cth$medium),
      sprintf("; separación del compuesto = %.2f puntos (descriptiva, no decide)", sep),
      if (!coherent) "; la recomendada no es la mejor por AIC ni por el pilar A" else "",
      "; el componente de estabilidad (pilar D) queda diferido"
    )
  }

  # Control (Normal): ¿mejor AIC que la mejor candidata? Señal para B5.
  nf <- diagnostics$control$normal
  control_check <- if (!is.null(nf) && isTRUE(nf$converged)) {
    list(normal_aic = nf$information$aic,
         normal_better_than_best = nf$information$aic < aic[ord[1]])
  } else NULL

  list(
    family = family, weights = w,
    ranking = ranking, excluded = excluded,
    recommendation = list(
      level1 = list(id = top$id, composite = top$composite,
                    confidence = confidence, confidence_reason = conf_reason,
                    delta_aic = delta_aic, composite_separation = sep)
    ),
    pillar_a_missing = pillar_a_missing,
    control_check = control_check,
    deferred = deferred,
    decision_engine_version = engine$version
  )
}


# ============================================================
# 3c. TEXT BUILDERS (Capa 4) — diseño §9. B5.
# ============================================================
# Consumidor PURO de profile / candidates / motor / diagnostics / assessment.
# No calcula estadística, no rankea y no llama hacia atrás: solo traduce la
# salida estructurada de B4 a mensajes deterministas en lenguaje natural.
# Texto plano: sin HTML, markdown, iconos, colores ni i18n (eso es B6).

#' Formatea un número para texto (base R; sin dependencias del framework)
.fmt_num <- function(x, digits = 2) {
  if (!is.finite(x)) return("no disponible")
  formatC(round(x, digits), format = "f", digits = digits, big.mark = ".",
          decimal.mark = ",")
}

#' Etiqueta legible de una distribución a partir del motor (con id de reserva)
.label_of <- function(motor, id) {
  f <- motor$fits[[id]]
  if (is.null(f) || is.null(f$label)) id else f$label
}

#' Clasifica un score de pilar como fortaleza / limitación / intermedio
.band_of <- function(score, bands) {
  if (!is.finite(score)) return("desconocido")
  if (score >= bands$strong) "fuerte" else if (score <= bands$weak) "débil" else "intermedio"
}

#' Recommendation Builder: resumen ejecutivo de la recomendación
#'
#' @return list(headline, confidence, main_reason, alternatives).
.build_recommendation_text <- function(motor, assessment, bands) {
  lvl1 <- assessment$recommendation$level1
  if (is.null(lvl1)) {
    return(list(headline = "No se ha podido recomendar ninguna distribución.",
                confidence = NA_character_,
                main_reason = "Ningún ajuste convergió sobre estos datos.",
                alternatives = character(0)))
  }
  top   <- assessment$ranking[[1]]
  label <- .label_of(motor, lvl1$id)
  alts  <- vapply(assessment$ranking[-1][seq_len(min(2L, length(assessment$ranking) - 1L))],
                  function(e) sprintf("%s (puntuación %s)", .label_of(motor, e$id),
                                      .fmt_num(e$composite, 1)),
                  character(1))
  list(
    headline = sprintf("Distribución recomendada: %s (puntuación global %s sobre 100).",
                       label, .fmt_num(lvl1$composite, 1)),
    confidence = sprintf("Confianza %s: %s.", lvl1$confidence, lvl1$confidence_reason),
    main_reason = sprintf(
      "Es la mejor combinación de ajuste y parsimonia entre las %d candidatas evaluadas (ajuste %s, parsimonia %s).",
      length(assessment$ranking),
      .band_of(top$pillar_scores$A, bands),
      .band_of(top$pillar_scores$B, bands)),
    alternatives = if (length(alts) == 0L) character(0) else alts
  )
}

#' Insight Builder: por qué ganó, fortalezas, debilidades y observaciones
#'
#' @return list(why_won, strengths, weaknesses, observations).
.build_insights <- function(motor, assessment, bands) {
  if (length(assessment$ranking) == 0L) {
    return(list(why_won = character(0), strengths = character(0),
                weaknesses = character(0), observations = character(0)))
  }
  top <- assessment$ranking[[1]]
  lab <- .label_of(motor, top$id)
  w   <- assessment$weights

  why <- sprintf(
    "%s obtiene la puntuación más alta (%s) combinando el pilar de ajuste (%s) y el de parsimonia (%s), con pesos %s y %s.",
    lab, .fmt_num(top$composite, 1), .fmt_num(top$pillar_scores$A, 1),
    .fmt_num(top$pillar_scores$B, 1), .fmt_num(w$A, 1), .fmt_num(w$B, 1))
  if (length(assessment$ranking) >= 2L) {
    second <- assessment$ranking[[2]]
    why <- c(why, sprintf("Aventaja en %s puntos a la siguiente candidata, %s.",
                          .fmt_num(top$composite - second$composite, 1),
                          .label_of(motor, second$id)))
  }

  strengths <- character(0); weaknesses <- character(0)
  if (.band_of(top$pillar_scores$A, bands) == "fuerte") {
    strengths <- c(strengths, "Reproduce bien la distribución observada de los datos.")
  }
  if (.band_of(top$pillar_scores$B, bands) == "fuerte") {
    strengths <- c(strengths, sprintf("Es parsimoniosa: %d parámetro(s).", top$n_params))
  }
  if (.band_of(top$pillar_scores$A, bands) == "débil") {
    weaknesses <- c(weaknesses, "El ajuste global es pobre en comparación con las demás candidatas.")
  }
  if (.band_of(top$pillar_scores$B, bands) == "débil") {
    weaknesses <- c(weaknesses,
                    sprintf("Penaliza en parsimonia: %d parámetro(s) frente a alternativas más simples.",
                            top$n_params))
  }

  obs <- character(0)
  if (isTRUE(assessment$control_check$normal_better_than_best)) {
    obs <- c(obs, paste("La distribución Normal (prueba de control) obtiene mejor AIC que la",
                        "candidata recomendada: conviene revisar si la variable es una severidad",
                        "clásica o ya está transformada."))
  }
  obs <- c(obs, paste("Alcance actual: la evaluación pondera ajuste y parsimonia. El",
                      "comportamiento en cola, la estabilidad de los parámetros y la adecuación",
                      "por caso de uso no se han evaluado todavía."))
  list(why_won = why, strengths = strengths, weaknesses = weaknesses, observations = obs)
}

# Veredicto por combinación de bandas (ajuste | parsimonia). Determinista: una
# frase fija por celda de la matriz 3x3. Sin IA y sin cálculo: solo traduce las
# bandas que ya produjo el Assessment.
DFIT_VERDICTS <- c(
  "fuerte|fuerte"           = "Muy buen ajuste global con alta parsimonia.",
  "fuerte|intermedio"       = "Muy buen ajuste global con una complejidad razonable.",
  "fuerte|débil"            = "Muy buen ajuste global, penalizado por su mayor complejidad.",
  "intermedio|fuerte"       = "Ajuste competitivo y modelo muy parsimonioso.",
  "intermedio|intermedio"   = "Ajuste y complejidad intermedios frente a las demás candidatas.",
  "intermedio|débil"        = "Ajuste competitivo, penalizado por su mayor complejidad.",
  "débil|fuerte"            = "Ajuste global pobre pese a su simplicidad.",
  "débil|intermedio"        = "Ajuste global pobre frente a las demás candidatas.",
  "débil|débil"             = "Ajuste global pobre y además poco parsimonioso."
)

#' Veredicto breve de una candidata a partir de sus bandas de pilar
#' @return Frase determinista (character(1)).
.verdict_of <- function(score_a, score_b, bands) {
  key <- paste(.band_of(score_a, bands), .band_of(score_b, bands), sep = "|")
  v <- DFIT_VERDICTS[[key]]
  if (is.null(v)) "Evaluación no concluyente con la información disponible." else v
}

#' Comparación de una candidata frente a la recomendada (determinista)
#'
#' Combina información YA calculada por el Assessment (pilares y puntuación) para
#' explicar qué se gana y qué se pierde al usar otra distribución. Cada elemento
#' es `list(ok, text)`: `ok = TRUE` es una ventaja o equivalencia; `FALSE`, una
#' desventaja. Para la propia recomendada devuelve una lista vacía.
#'
#' @param e Entrada del ranking de la candidata.
#' @param rec Entrada del ranking de la recomendada.
#' @param close_gap Diferencia de puntuación por debajo de la cual se considera
#'   "próxima" (parámetro de presentación, `decision_engine.md`).
#' @return Lista de `list(ok, text)`.
.compare_to_recommended <- function(e, rec, close_gap) {
  if (identical(e$id, rec$id)) return(list())
  items <- list()
  add <- function(ok, text) items[[length(items) + 1L]] <<- list(ok = ok, text = text)

  if (e$pillar_scores$A >= rec$pillar_scores$A) {
    add(TRUE,  "Ajuste a la muestra igual o mejor que el de la recomendada.")
  } else {
    add(FALSE, "Peor ajuste a la muestra que la recomendada.")
  }
  if (e$pillar_scores$B >= rec$pillar_scores$B) {
    add(TRUE,  "Igual o más parsimoniosa que la recomendada.")
  } else {
    add(FALSE, "Penalizada por su mayor complejidad frente a la recomendada.")
  }
  if ((rec$composite - e$composite) <= close_gap) {
    add(TRUE,  "Muy próxima a la recomendada en puntuación global.")
  } else {
    add(FALSE, "Puntuación global claramente inferior a la de la recomendada.")
  }
  items
}

#' Distribution Cards: texto estructurado por distribución (incluidas descartadas)
#'
#' @return Lista de cards: id, name, score, rank, verdict, vs_recommended,
#'   strengths, limitations, observations.
.build_distribution_cards <- function(motor, diagnostics, assessment, bands,
                                      close_gap = 10) {
  rec_entry <- if (length(assessment$ranking) > 0L) assessment$ranking[[1]] else NULL
  ranked <- lapply(assessment$ranking, function(e) {
    fit <- motor$fits[[e$id]]
    st <- character(0); lim <- character(0)
    if (.band_of(e$pillar_scores$A, bands) == "fuerte") st <- c(st, "Buen ajuste a los datos observados.")
    if (.band_of(e$pillar_scores$B, bands) == "fuerte") st <- c(st, "Modelo parsimonioso.")
    if (.band_of(e$pillar_scores$A, bands) == "débil")  lim <- c(lim, "Ajuste débil frente a las demás candidatas.")
    if (.band_of(e$pillar_scores$B, bands) == "débil")  lim <- c(lim, "Menos parsimoniosa que las alternativas.")
    obs <- sprintf("Estimada por %s (%s); %d observación(es) utilizada(s).",
                   toupper(fit$method), fit$method_reason, fit$n_used)
    aic <- diagnostics$per_fit[[e$id]]$information$aic   # copiado de B3, no recalculado
    if (!is.null(aic) && is.finite(aic)) {
      obs <- paste(obs, sprintf("AIC %s.", .fmt_num(aic, 2)))
    }
    list(id = e$id, name = .label_of(motor, e$id), rank = e$rank,
         score = e$composite, status = "evaluada",
         verdict = .verdict_of(e$pillar_scores$A, e$pillar_scores$B, bands),
         vs_recommended = if (is.null(rec_entry)) list() else {
           .compare_to_recommended(e, rec_entry, close_gap)
         },
         strengths = st, limitations = lim, observations = obs)
  })
  excluded <- lapply(assessment$excluded, function(e) {
    list(id = e$id, name = .label_of(motor, e$id), rank = NA_integer_,
         score = NA_real_, status = "descartada",
         verdict = "No evaluada: queda fuera del ranking.",
         vs_recommended = list(),
         strengths = character(0),
         limitations = sprintf("No evaluada: %s.", e$reason),
         observations = "No participa en el ranking ni en la recomendación.")
  })
  c(ranked, excluded)
}

#' Warnings Builder: avisos derivados EXCLUSIVAMENTE de flags ya existentes
#'
#' @return Vector de mensajes (character).
.build_warnings <- function(profile, motor, assessment, sample = NULL) {
  w <- character(0)
  if (profile$pct_na > 0) {
    w <- c(w, sprintf("Se han descartado %s%% de valores ausentes (NA) de la variable.",
                      .fmt_num(100 * profile$pct_na, 1)))
  }
  # ADR-026 — aviso ÚNICO y global de la exclusión por soporte común. Antes se
  # emitía uno por distribución estrictamente positiva (cinco avisos idénticos en
  # la familia continua) y ninguno declaraba que las candidatas estaban
  # compitiendo sobre muestras distintas.
  if (!is.null(sample)) {
    if (isTRUE(sample$n_excluded_zeros > 0)) {
      w <- c(w, sprintf(paste("Se han excluido %d observaciones iguales a cero (%s%% de las",
                              "%d válidas) para que las %d candidatas compitan sobre la misma",
                              "muestra. El análisis modeliza %d observaciones estrictamente",
                              "positivas: es una distribución de severidad CONDICIONADA a que",
                              "exista coste, no la distribución de la variable completa."),
                        sample$n_excluded_zeros,
                        .fmt_num(100 * sample$n_excluded_zeros / max(1L, sample$n_input), 1),
                        sample$n_input, length(motor$fits), sample$n_used))
    }
    if (isTRUE(sample$n_excluded_negatives > 0)) {
      w <- c(w, sprintf(paste("Se han excluido %d observaciones negativas, incompatibles con",
                              "el soporte común %s de las candidatas."),
                        sample$n_excluded_negatives, sample$support_label))
    }
  }
  for (fit in motor$fits) {
    if (isTRUE(fit$converged) && !identical(fit$method, "mle")) {
      w <- c(w, sprintf("%s: se ha utilizado el método %s (%s).",
                        fit$label, toupper(fit$method), fit$method_reason))
    }
    if (!is.null(fit$message) && !is.na(fit$message)) {
      w <- c(w, sprintf("%s: %s.", fit$label, fit$message))
    }
  }
  for (e in assessment$excluded) {
    w <- c(w, sprintf("%s se ha descartado del ranking (%s).", .label_of(motor, e$id), e$reason))
  }
  unique(w)
}

#' Summary Builder: objeto final de la capa de texto
#'
#' Consumidor puro: recibe las salidas de las capas anteriores y devuelve el
#' bloque textual completo. No recalcula nada.
#'
#' @param profile Salida de `profile_dataset()`.
#' @param candidates Salida de `select_candidate_distributions()`.
#' @param motor Salida de `.motor()`.
#' @param diagnostics Salida de `.diagnostics()`.
#' @param assessment Salida de `.assess()`.
#' @param engine Salida de `decision_engine_spec()` (bandas de texto).
#' @param sample Salida de `build_analysis_sample()` (ADR-026). `NULL` mantiene
#'   el comportamiento previo, para consumidores sintéticos de los tests.
#' @return list(summary, recommendation, insights, warnings, distribution_cards).
.text_builders <- function(profile, candidates, motor, diagnostics, assessment,
                           engine = decision_engine_spec(), sample = NULL) {
  bands <- engine$text_bands
  family_txt <- if (identical(assessment$family, "continuous")) "continua" else "discreta (recuentos)"
  n_offered <- if (!is.null(candidates$distributions)) {
    length(candidates$distributions)
  } else {
    length(assessment$ranking) + length(assessment$excluded)
  }
  # ADR-026 — el summary declara la muestra REALMENTE modelizada, no el total de
  # válidas. Anunciar 95.554 observaciones cuando se modelizan 17.678 severidades
  # positivas induce a error sobre qué magnitud se ha ajustado.
  summary_txt <- if (!is.null(sample) && sample$n_used < sample$n_input) {
    sprintf(
      paste("Variable '%s': %d observaciones válidas, de las que se modelizan %d",
            "tras restringir al soporte común %s de las candidatas; tratada como %s.",
            "Se han evaluado %d de las %d distribuciones candidatas de la familia %s."),
      profile$variable, sample$n_input, sample$n_used, sample$support_label, family_txt,
      length(assessment$ranking), n_offered, family_txt)
  } else {
    sprintf(
      paste("Variable '%s': %d observaciones válidas, tratada como %s.",
            "Se han evaluado %d de las %d distribuciones candidatas de la familia %s."),
      profile$variable,
      if (is.null(sample)) profile$n_valid else sample$n_used, family_txt,
      length(assessment$ranking), n_offered, family_txt)
  }

  list(
    summary            = summary_txt,
    recommendation     = .build_recommendation_text(motor, assessment, bands),
    insights           = .build_insights(motor, assessment, bands),
    warnings           = .build_warnings(profile, motor, assessment, sample),
    distribution_cards = .build_distribution_cards(motor, diagnostics, assessment, bands,
                                                   close_gap = engine$close_score_gap)
  )
}


# ============================================================
# 3d. VIEW MODEL (Capa 5) — payload de presentación — diseño §12. B6.
# ============================================================
# Transforma la salida de las capas anteriores en la ÚNICA estructura que la UI
# consume (§12). Capa de presentación pura: no calcula estadística, no altera el
# ranking, no genera texto nuevo (todo el texto viene de B5) y no introduce
# reglas de negocio. Solo estructura, etiquetas, iconos, tokens de color y orden.
#
# Colores: se emiten TOKENS SEMÁNTICOS ("brand", "neutral", "muted"), nunca
# literales hex: calc.R no depende de shared/theme y la UI los resuelve con
# theme_bmk() (regla 16). Iconos: nombres de bsicons (contrato técnico 12).
# La sección `plots` es ESPECIFICACIÓN (qué gráficos y su configuración); la
# evaluación de las funciones ajustadas corresponde al Visual Engine (B7).

# Versión del contrato del View Model (§12.11). Independiente de
# decision_engine_version: versiona la FORMA, no el criterio.
# 1.1.0 (ADR-026): cambio ADITIVO — nuevo bloque `sample` con la muestra común
# efectiva y las exclusiones. Ningún consumidor previo se rompe.
DFIT_SCHEMA_VERSION <- "1.1.0"

# Especificación de los gráficos previstos (§12.7). `status`:
#   "pending_visual_engine" -> definido; sus datos los generará B7.
#   "deferred"              -> requiere métricas aún no implementadas (Pilar C).
DFIT_PLOT_SPECS <- list(
  list(id = "histogram_density", title = "Histograma y densidades ajustadas",
       type = "histogram+lines", purpose = "Ajuste global del cuerpo",
       family = "both", status = "pending_visual_engine"),
  list(id = "qq_plot", title = "QQ-plot de la distribución recomendada",
       type = "scatter+reference_line", purpose = "Desviación en cuantiles",
       family = "both", status = "pending_visual_engine"),
  list(id = "pp_plot", title = "PP-plot",
       type = "scatter+reference_line", purpose = "Ajuste de la CDF",
       family = "both", status = "pending_visual_engine"),
  list(id = "mean_excess", title = "Función de exceso medio",
       type = "line", purpose = "Diagnóstico de cola / EVT",
       family = "continuous", status = "deferred"),
  list(id = "var_tvar", title = "Comparativa de VaR/TVaR por nivel",
       type = "grouped_bars", purpose = "Ajuste en cuantiles actuariales",
       family = "continuous", status = "deferred")
)

#' Metadatos de la ejecución (§12.1)
.vm_meta <- function(analysis, manifest, generated_at) {
  m <- analysis$meta
  list(
    tool_name = if (is.null(manifest$name)) NA_character_ else manifest$name,
    tool_version = if (is.null(manifest$version)) NA_character_ else manifest$version,
    generated_at = generated_at,
    variable = m$variable, family = m$family, mode = m$mode,
    method = m$method, analysis_depth = m$analysis_depth,
    seed = NA_integer_,   # sin remuestreo todavía: aplicará con bootstrap/CV
    schema_version = DFIT_SCHEMA_VERSION,
    decision_engine_version = m$decision_engine_version
  )
}

#' Resumen de entrada y diagnóstico del dataset (§12.2). Copia del profiler.
#'
#' ADR-026 (schema 1.1.0): añade el bloque `sample`, que declara la muestra
#' efectivamente modelizada y las exclusiones aplicadas para hacerla comparable.
#' Es la información que impide leer el análisis como si se hubieran modelizado
#' todas las observaciones válidas.
.vm_input_and_diagnosis <- function(profile, sample = NULL) {
  list(
    input_summary = list(
      n = profile$n, n_valid = profile$n_valid,
      exclusions = list(pct_na = profile$pct_na, pct_zeros = profile$pct_zeros,
                        pct_negatives = profile$pct_negatives),
      descriptives = list(min = profile$min, max = profile$max, mean = profile$mean,
                          median = profile$median, sd = profile$sd, cv = profile$cv,
                          skewness = profile$skewness, kurtosis = profile$kurtosis,
                          n_unique = profile$n_unique)
    ),
    sample = if (is.null(sample)) NULL else list(
      n_input              = sample$n_input,
      n_used               = sample$n_used,
      n_excluded_zeros     = sample$n_excluded_zeros,
      n_excluded_negatives = sample$n_excluded_negatives,
      support              = sample$support_label,
      rule                 = sample$rule,
      conditional          = isTRUE(sample$n_excluded_zeros > 0)
    ),
    dataset_diagnosis = list(
      variable_type = profile$variable_type, support = profile$support,
      flags = list(has_zeros = profile$pct_zeros > 0,
                   has_negatives = profile$pct_negatives > 0,
                   looks_like_count = identical(profile$variable_type, "discrete")),
      deferred = list(heavy_tail_evidence = "diferido: requiere Pilar C",
                      possible_multimodal = "diferido: requiere análisis de densidad")
    )
  )
}

#' Metric cards de cabecera (§12.3). 3 activas; la 4.ª (cola) queda diferida.
.vm_metric_cards <- function(motor, assessment) {
  lvl1 <- assessment$recommendation$level1
  if (is.null(lvl1)) return(list())
  top <- assessment$ranking[[1]]
  list(
    list(id = "recommended", order = 1L, label = "Distribución recomendada",
         value = .label_of(motor, lvl1$id), note = NULL,
         icon = "bar-chart-line", tone = "brand"),
    list(id = "confidence", order = 2L, label = "Confianza",
         value = tools::toTitleCase(lvl1$confidence), note = "de la recomendación",
         icon = "shield-check", tone = "neutral"),
    list(id = "global_score", order = 3L, label = "Puntuación global",
         value = .fmt_num(lvl1$composite, 1), note = "sobre 100",
         icon = "speedometer2", tone = "neutral"),
    list(id = "tail_quality", order = 4L, label = "Calidad de cola",
         value = NA_character_, note = "diferido: requiere Pilar C",
         icon = "graph-up-arrow", tone = "muted", status = "deferred")
  )
}

#' Tabla de ranking lista para DT (§12.4). Datos copiados de B4/B3.
.vm_ranking_table <- function(motor, diagnostics, assessment) {
  rows <- lapply(assessment$ranking, function(e) {
    data.frame(
      posicion = e$rank, distribucion = .label_of(motor, e$id),
      puntuacion = round(e$composite, 1),
      ajuste = round(e$pillar_scores$A, 1), parsimonia = round(e$pillar_scores$B, 1),
      parametros = e$n_params,
      aic = round(diagnostics$per_fit[[e$id]]$information$aic, 2),
      estado = if (identical(e$id, assessment$recommendation$level1$id)) "Recomendada" else "Evaluada",
      stringsAsFactors = FALSE)
  })
  excl <- lapply(assessment$excluded, function(e) {
    data.frame(posicion = NA_integer_, distribucion = .label_of(motor, e$id),
               puntuacion = NA_real_, ajuste = NA_real_, parsimonia = NA_real_,
               parametros = NA_integer_, aic = NA_real_,
               estado = sprintf("Descartada: %s", e$reason), stringsAsFactors = FALSE)
  })
  df <- if (length(c(rows, excl)) == 0L) data.frame() else do.call(rbind, c(rows, excl))
  list(
    data = df,
    column_labels = c(posicion = "#", distribucion = "Distribución",
                      puntuacion = "Puntuación", ajuste = "Ajuste",
                      parsimonia = "Parsimonia", parametros = "Parámetros",
                      aic = "AIC", estado = "Estado"),
    align = c(posicion = "right", distribucion = "left", puntuacion = "right",
              ajuste = "right", parsimonia = "right", parametros = "right",
              aic = "right", estado = "left")
  )
}

#' Recomendación para la UI (§12.5). Texto de B5; niveles diferidos marcados.
.vm_recommendation <- function(analysis) {
  txt <- analysis$text_builder$recommendation
  a   <- analysis$assessment
  lvl1 <- a$recommendation$level1
  list(
    level1 = list(
      id = if (is.null(lvl1)) NA_character_ else lvl1$id,
      headline = txt$headline, confidence = txt$confidence,
      main_reason = txt$main_reason, alternatives = txt$alternatives,
      params = if (is.null(lvl1)) NULL else analysis$motor$fits[[lvl1$id]]$params,
      method = if (is.null(lvl1)) NA_character_ else analysis$motor$fits[[lvl1$id]]$method
    ),
    level2_use_case = list(status = "deferred", note = a$deferred$level2_use_case),
    evt_recommendation = list(status = "deferred", note = a$deferred$evt_detection),
    none_good_enough = list(status = "deferred", note = a$deferred$absolute_categories)
  )
}

#' Detalle por distribución (§12.6) y tabla de exportación (§12.10)
#'
#' `cards` son las fichas de texto de los Text Builders (B5): aportan el veredicto
#' ya redactado, de modo que la UI no tenga que componer texto (regla de oro §12).
.vm_fits_and_export <- function(motor, diagnostics, assessment, cards = NULL) {
  card_of <- function(id) {
    if (is.null(cards)) return(NULL)
    c_i <- Filter(function(x) identical(x$id, id), cards)
    if (length(c_i) == 0L) NULL else c_i[[1]]
  }
  fits <- lapply(assessment$ranking, function(e) {
    fit <- motor$fits[[e$id]]
    cd  <- card_of(e$id)
    list(id = e$id, name = fit$label, rank = e$rank, score = e$composite,
         params = fit$params, method = fit$method, n_used = fit$n_used,
         n_params = fit$n_params,
         loglik = fit$logLik,
         verdict = if (is.null(cd)) NA_character_ else cd$verdict,
         vs_recommended = if (is.null(cd)) list() else cd$vs_recommended,
         pillar_scores = e$pillar_scores,
         metrics = diagnostics$per_fit[[e$id]][c("information", "gof")])
  })
  export <- lapply(assessment$ranking, function(e) {
    fit <- motor$fits[[e$id]]; inf <- diagnostics$per_fit[[e$id]]$information
    data.frame(
      distribucion = fit$label, posicion = e$rank,
      puntuacion = round(e$composite, 2), ajuste = round(e$pillar_scores$A, 2),
      parsimonia = round(e$pillar_scores$B, 2), parametros = fit$n_params,
      metodo = fit$method,
      valores = paste(sprintf("%s=%s", names(fit$params),
                              vapply(fit$params, .fmt_num, character(1), digits = 4)),
                      collapse = "; "),
      aic = round(inf$aic, 3), bic = round(inf$bic, 3),
      stringsAsFactors = FALSE)
  })
  list(fits = fits,
       export_table = if (length(export) == 0L) data.frame() else do.call(rbind, export))
}

#' Especificación de gráficos (§12.7): estructura y configuración, sin datos.
.vm_plots_spec <- function(family) {
  specs <- Filter(function(p) p$family %in% c("both", family), DFIT_PLOT_SPECS)
  lapply(specs, function(p) c(p, list(data = NULL)))
}

#' Construye el View Model completo de Tool-02 (§12)
#'
#' Capa de presentación: consume el objeto devuelto por `dist_fit_analyze()` y
#' produce la única estructura que la UI renderiza. No calcula estadística, no
#' altera el ranking y no genera texto nuevo.
#'
#' @param analysis Salida de `dist_fit_analyze()`.
#' @param manifest Lista del `manifest.yml` (nombre y versión). Opcional.
#' @param generated_at Fecha de generación (parametrizable para reproducibilidad).
#' @return Lista con las secciones del §12, más `presentation` (orden y prioridad).
prepare_view_model <- function(analysis, manifest = NULL,
                               generated_at = as.character(Sys.Date())) {
  stopifnot(!is.null(analysis$assessment), !is.null(analysis$text_builder))
  io <- .vm_input_and_diagnosis(analysis$profile, analysis$sample)
  tb <- analysis$text_builder
  fx <- .vm_fits_and_export(analysis$motor, analysis$diagnostics, analysis$assessment,
                            cards = tb$distribution_cards)

  list(
    meta              = .vm_meta(analysis, manifest, generated_at),
    input_summary     = io$input_summary,
    sample            = io$sample,          # ADR-026: muestra común efectiva
    dataset_diagnosis = io$dataset_diagnosis,
    metric_cards      = .vm_metric_cards(analysis$motor, analysis$assessment),
    ranking           = .vm_ranking_table(analysis$motor, analysis$diagnostics,
                                          analysis$assessment),
    recommendation    = .vm_recommendation(analysis),
    fits              = fx$fits,
    plots             = .vm_plots_spec(analysis$assessment$family),
    interpretation    = list(summary = tb$summary, insights = tb$insights,
                             cards = tb$distribution_cards),
    warnings          = lapply(tb$warnings, function(w) list(text = w, notify_type = "warning")),
    export_table      = fx$export_table,
    presentation      = list(
      section_order = c("metric_cards", "plots", "ranking", "interpretation",
                        "warnings", "export_table"),
      icons = c(ranking = "list-ol", interpretation = "info-circle",
                warnings = "exclamation-triangle", export = "download"),
      tones = c(primary = "brand", secondary = "neutral", disabled = "muted")
    )
  )
}


# ============================================================
# 3e. VISUAL ENGINE (B7) — datasets numéricos para los gráficos
# ============================================================
# Único responsable de generar datos para gráficos. Consume EXCLUSIVAMENTE los
# parámetros ya ajustados por el Motor (B2): no reestima, no altera el ranking ni
# la recomendación, no genera texto y no modifica el View Model (devuelve una
# estructura independiente que la UI consume junto al VM).
# Implementación propia (política 2.2); las d/p/q de base R se usan como
# primitivas y se complementan con las fórmulas propias ya validadas.

DFIT_VISUAL_DEFAULTS <- list(
  grid_n         = 512L,   # puntos de la rejilla de evaluación (potencia de 2)
  plotting_a     = 0.5,    # posiciones de trazado (i - a) / n para QQ y PP
  kde_bw_factor  = 0.9,    # regla de Silverman
  kde_iqr_div    = 1.349,  # IQR -> sigma robusto
  kde_bw_exp     = -1 / 5  # n^(-1/5)
)

#' Densidad ajustada de una distribución continua (evaluador; no estima)
.dist_pdf <- function(id, x, p) {
  switch(id,
    exponential = stats::dexp(x, p$rate),
    normal      = stats::dnorm(x, p$mean, p$sd),
    lognormal   = stats::dlnorm(x, p$meanlog, p$sdlog),
    gamma       = stats::dgamma(x, shape = p$shape, scale = p$scale),
    weibull     = stats::dweibull(x, shape = p$shape, scale = p$scale),
    loglogistic = exp(.dloglogistic_log(x, p$shape, p$scale)),
    pareto      = exp(.dpareto_log(x, p$shape, p$scale)),
    burr        = exp(.dburr_log(x, p$shape1, p$shape2, p$scale))
  )
}

#' Función cuantil ajustada (para QQ). Fórmulas propias validadas para
#' loglogística, Pareto (Lomax) y Burr XII.
.dist_quantile <- function(id, prob, p) {
  switch(id,
    exponential = stats::qexp(prob, p$rate),
    normal      = stats::qnorm(prob, p$mean, p$sd),
    lognormal   = stats::qlnorm(prob, p$meanlog, p$sdlog),
    gamma       = stats::qgamma(prob, shape = p$shape, scale = p$scale),
    weibull     = stats::qweibull(prob, shape = p$shape, scale = p$scale),
    loglogistic = p$scale * (prob / (1 - prob))^(1 / p$shape),
    pareto      = p$scale * ((1 - prob)^(-1 / p$shape) - 1),
    burr        = p$scale * ((1 - prob)^(-1 / p$shape2) - 1)^(1 / p$shape1),
    poisson     = stats::qpois(prob, p$lambda),
    negative_binomial = stats::qnbinom(prob, size = p$size, mu = p$mu),
    geometric   = stats::qgeom(prob, p$prob)
  )
}

#' Rejilla de evaluación sobre el rango observado
.visual_grid <- function(x, n_points) seq(min(x), max(x), length.out = n_points)

#' Histograma empírico (regla de Sturges; implementación propia)
.histogram_data <- function(x) {
  n <- length(x)
  k <- max(1L, ceiling(log2(n)) + 1L)
  breaks <- seq(min(x), max(x), length.out = k + 1L)
  idx <- pmin(findInterval(x, breaks, rightmost.closed = TRUE), k)
  counts <- tabulate(idx, nbins = k)
  width <- diff(breaks)
  data.frame(bin_start = breaks[-length(breaks)], bin_end = breaks[-1],
             mid = (breaks[-length(breaks)] + breaks[-1]) / 2,
             count = counts, density = counts / (n * width))
}

#' Función de distribución empírica (ECDF) en los estadísticos de orden
.ecdf_points <- function(x) {
  xs <- sort(x); n <- length(xs)
  data.frame(x = xs, ecdf = seq_len(n) / n)
}

#' Estimación kernel de densidad (gaussiano, ancho de banda de Silverman)
.kde_curve <- function(x, grid, cfg) {
  n <- length(x)
  sigma <- min(stats::sd(x), stats::IQR(x) / cfg$kde_iqr_div)
  if (!is.finite(sigma) || sigma <= 0) sigma <- stats::sd(x)
  h <- cfg$kde_bw_factor * sigma * n^cfg$kde_bw_exp
  y <- vapply(grid, function(g) mean(stats::dnorm((g - x) / h)) / h, numeric(1))
  list(bandwidth = h, curve = data.frame(x = grid, density = y))
}

#' Puntos QQ: cuantiles teóricos frente a estadísticos de orden
.qq_points <- function(x, id, params, a) {
  xs <- sort(x); n <- length(xs)
  prob <- (seq_len(n) - a) / n
  data.frame(theoretical = .dist_quantile(id, prob, params), sample = xs)
}

#' Puntos PP: CDF ajustada frente a probabilidad empírica
.pp_points <- function(x, id, params, a, family) {
  xs <- sort(x); n <- length(xs)
  theo <- if (identical(family, "continuous")) .dist_cdf(id, xs, params)
          else .dist_cdf_discrete(id, xs, params)
  data.frame(empirical = (seq_len(n) - a) / n, theoretical = theo)
}

#' Soporte entero sobre el que se evalúa la PMF ajustada
#'
#' ADR-019. La versión anterior usaba `0:max(grid)`, es decir, un punto por cada
#' entero del rango observado: con importes enteros grandes (max 48.827) genera
#' ~48.828 puntos POR CANDIDATA, y el gráfico resultante bloquea la interfaz. El
#' número de puntos pasa a estar acotado por `grid_n`, adelgazando el soporte de
#' forma uniforme cuando el rango lo excede (la PMF se dibuja como curva, así que
#' el adelgazamiento no altera la lectura del gráfico).
#'
#' @param kmax Valor entero máximo del soporte a representar.
#' @param n_points Nº máximo de puntos (por defecto `grid_n`).
#' @return Vector de enteros no negativos, de longitud <= `n_points`.
.discrete_grid <- function(kmax, n_points = DFIT_VISUAL_DEFAULTS$grid_n) {
  kmax <- max(0L, as.integer(kmax))
  if (kmax + 1L <= n_points) return(0:kmax)
  unique(as.integer(round(seq(0, kmax, length.out = n_points))))
}

#' Curvas de densidad/PMF ajustadas para cada candidata convergente
.fitted_curves <- function(analysis, grid, family) {
  ids <- vapply(analysis$assessment$ranking, function(e) e$id, character(1))
  k <- if (identical(family, "continuous")) NULL else .discrete_grid(max(grid))
  lapply(ids, function(id) {
    fit <- analysis$motor$fits[[id]]
    if (identical(family, "continuous")) {
      list(id = id, label = fit$label,
           curve = data.frame(x = grid, density = .dist_pdf(id, grid, fit$params)))
    } else {
      list(id = id, label = fit$label,
           curve = data.frame(k = k, pmf = .dist_pmf(id, k, fit$params)))
    }
  })
}

#' Datos de QQ y PP de una distribución concreta (B7)
#'
#' Bloque **ligero** del Visual Engine: solo depende de la distribución elegida,
#' de modo que la interfaz pueda cambiar de distribución sin recomputar el
#' histograma, la KDE ni las curvas. Consume únicamente parámetros ya ajustados;
#' no reestima, no modifica el ranking ni la recomendación.
#'
#' @param analysis Salida de `dist_fit_analyze()`.
#' @param data data.frame original (para recuperar la muestra de la variable).
#' @param distribution Id de la distribución a representar. `NULL` (defecto) usa
#'   la recomendada. Un id no evaluado se ignora y se usa la recomendada.
#' @param config Constantes de visualización (`DFIT_VISUAL_DEFAULTS`).
#' @return list(qq_plot, pp_plot), cada uno con `distribution`, `label`,
#'   `is_recommended` y sus puntos.
build_qq_pp_data <- function(analysis, data, distribution = NULL,
                             config = DFIT_VISUAL_DEFAULTS) {
  stopifnot(!is.null(analysis$assessment), !is.null(analysis$sample), is.data.frame(data))
  family <- analysis$assessment$family
  top    <- analysis$assessment$recommendation$level1$id
  ids    <- vapply(analysis$assessment$ranking, function(e) e$id, character(1))
  target <- if (is.null(distribution) || !(distribution %in% ids)) top else distribution
  fit    <- analysis$motor$fits[[target]]
  a      <- config$plotting_a

  # ADR-028: la muestra es la COMÚN del análisis, la misma sobre la que se
  # estimaron los parámetros. Antes se rederivaba aquí con `.prepare_support()`,
  # lo que era correcto por distribución pero mantenía tres copias de la misma
  # decisión. `data` se conserva en la firma por compatibilidad de contrato.
  x_t    <- analysis$sample$x
  is_rec <- identical(target, top)

  list(
    qq_plot = list(status = "ready", distribution = target, label = fit$label,
                   is_recommended = is_rec,
                   points = .qq_points(x_t, target, fit$params, a)),
    pp_plot = list(status = "ready", distribution = target, label = fit$label,
                   is_recommended = is_rec,
                   points = .pp_points(x_t, target, fit$params, a, family),
                   ecdf = .ecdf_points(x_t))
  )
}

#' Genera los datasets numéricos de los gráficos (B7)
#'
#' Consume únicamente los parámetros ajustados por el Motor y la muestra. No
#' reestima, no modifica el ranking ni el View Model.
#'
#' @param analysis Salida de `dist_fit_analyze()`.
#' @param data data.frame original (para recuperar la muestra de la variable).
#' @param config Constantes de visualización (`DFIT_VISUAL_DEFAULTS`).
#' @param distribution Id de la distribución para QQ/PP. `NULL` (defecto) usa la
#'   recomendada; el histograma y las curvas no dependen de este argumento.
#' @return Lista por id de gráfico con sus datos y estado.
build_visual_data <- function(analysis, data, config = DFIT_VISUAL_DEFAULTS,
                              distribution = NULL) {
  stopifnot(!is.null(analysis$assessment), !is.null(analysis$sample), is.data.frame(data))
  family <- analysis$assessment$family
  # ADR-028: histograma, KDE, rejilla y curvas ajustadas se construyen sobre la
  # MISMA muestra que produjo las estimaciones. Antes el histograma y la KDE
  # usaban la muestra completa (incondicional) mientras las curvas eran
  # densidades condicionadas al soporte común: dos normalizaciones distintas
  # superpuestas en el mismo eje, con un desajuste de escala de 1/P(X in soporte).
  x <- analysis$sample$x

  grid <- if (identical(family, "continuous")) {
    .visual_grid(x, config$grid_n)
  } else {
    .discrete_grid(max(x), config$grid_n)   # acotado (ADR-019), antes seq(0, max(x))
  }

  hist_block <- if (identical(family, "continuous")) {
    list(histogram = .histogram_data(x), kde = .kde_curve(x, grid, config),
         curves = .fitted_curves(analysis, grid, family))
  } else {
    # Frecuencias observadas por `tabulate` (vectorizado) en lugar de un vapply
    # sobre 0:max(x): con importes enteros grandes eso eran ~9,8 millones de
    # comparaciones y un data.frame de 48.828 filas (ADR-019). Si el soporte
    # excede la rejilla, se conservan solo los valores observados —a lo sumo n—,
    # que contienen toda la información del diagrama de barras.
    xi   <- as.integer(round(x))
    kmax <- max(xi)
    freq <- tabulate(xi + 1L, nbins = kmax + 1L) / length(xi)
    obs  <- if (kmax + 1L <= config$grid_n) {
      data.frame(k = 0:kmax, freq = freq)
    } else {
      kk <- sort(unique(xi))
      data.frame(k = kk, freq = freq[kk + 1L])
    }
    list(observed = obs, curves = .fitted_curves(analysis, grid, family))
  }
  qp <- build_qq_pp_data(analysis, data, distribution, config)

  list(
    histogram_density = c(list(status = "ready", family = family), hist_block),
    qq_plot     = qp$qq_plot,
    pp_plot     = qp$pp_plot,
    mean_excess = list(status = "deferred", note = "requiere Pilar C (cola)"),
    var_tvar    = list(status = "deferred", note = "requiere Pilar C (cola)")
  )
}


# ============================================================
# 3f. UNCERTAINTY VIEW (B16.1) — payload de la vista de incertidumbre
# ============================================================
# ESTRUCTURA PARALELA, igual que el Visual Engine: NO forma parte del View Model
# y por tanto NO altera `DFIT_SCHEMA_VERSION`, que se mantiene en 1.1.0. La UI la
# consume junto al VM.
#
# NO CALCULA ESTADÍSTICA. Organiza lo que ya produjeron B12 (analítica), B13
# (bootstrap), B14 (validación) y B15 (comparación descriptiva) para que la
# interfaz y la exportación la consuman. No reestima, no recalcula SE, IC,
# Hessiana, réplicas ni huellas, y no altera ranking, recomendación ni AUTO.
#
# PM (OD-15, opción C): PM es un estimador **alternativo** disponible solo aquí.
# No entra en `.motor()`, ni en AUTO, ni en el ranking, ni en la recomendación.
# Cuando el estimador activo es PM, la estimación puntual mostrada es la de PM y
# NO la del análisis principal, y la vía analítica queda desactivada por
# construcción: comparar una analítica de MLE con un bootstrap de PM sería
# comparar estimadores distintos.

#' Etiquetas de estimador para la interfaz.
DFIT_UNCERTAINTY_ESTIMATORS <- c(mle = "MLE (máxima verosimilitud)",
                                 mom = "Momentos (MoM)",
                                 lmom = "L-momentos",
                                 pm = "Percentile Matching (alternativo)")

#' Tabla vacía con las columnas de una tabla de parámetros de incertidumbre.
.dfit_empty_param_table <- function() {
  data.frame(parametro = character(0), estimacion = numeric(0),
             se = numeric(0), ic_inferior = numeric(0), ic_superior = numeric(0),
             stringsAsFactors = FALSE)
}

#' Tabla por parámetro a partir de un bloque de B14 (`analytic` o `bootstrap`).
.dfit_param_table <- function(validation, which = c("analytic", "bootstrap")) {
  which <- match.arg(which)
  ps <- validation$parameters
  if (!is.list(ps) || length(ps) == 0L) return(.dfit_empty_param_table())
  num <- function(v) if (is.null(v) || length(v) != 1L) NA_real_ else as.numeric(v)
  rows <- lapply(ps, function(p) {
    b <- if (is.list(p[[which]])) p[[which]] else list()
    data.frame(parametro = as.character(p$name), estimacion = num(p$estimate),
               se = num(b$se), ic_inferior = num(b$ci_lower),
               ic_superior = num(b$ci_upper), stringsAsFactors = FALSE)
  })
  df <- do.call(rbind, rows); rownames(df) <- NULL; df
}

#' Datos del gráfico de distribución bootstrap de UN parámetro
#'
#' Devuelve un dataset numérico; **no dibuja**. Coherente con la regla del
#' Visual Engine: `calc.R` produce datos, `mod_tool.R` los representa.
#'
#' `theta_hat` es la estimación puntual del **estimador activo**: si el activo es
#' PM, es la de PM, no la del análisis principal.
#'
#' @return list(available, reason, parameter, replicates, theta_hat, ci_lower,
#'   ci_upper, confidence_level, n_replicates) — `replicates` es `NULL` cuando no
#'   procede.
build_bootstrap_plot_data <- function(bootstrap, point_estimate, parameter) {
  out <- list(available = FALSE, reason = NA_character_, parameter = parameter,
              replicates = NULL, theta_hat = NA_real_, ci_lower = NA_real_,
              ci_upper = NA_real_, confidence_level = NA_real_,
              n_replicates = 0L)
  if (is.null(bootstrap) || !is.list(bootstrap) || is.null(bootstrap$replicates)) {
    out$reason <- "no hay réplicas bootstrap disponibles"; return(out)
  }
  M <- bootstrap$replicates
  if (!is.matrix(M) || !(parameter %in% colnames(M)) || nrow(M) < 2L) {
    out$reason <- "no hay réplicas válidas suficientes para representar la distribución"
    return(out)
  }
  th <- if (is.list(point_estimate)) unlist(point_estimate) else point_estimate
  out$replicates <- as.numeric(M[, parameter])
  out$n_replicates <- nrow(M)
  out$theta_hat <- if (!is.null(th) && parameter %in% names(th))
                     unname(th[[parameter]]) else NA_real_
  if (is.matrix(bootstrap$ci) && parameter %in% rownames(bootstrap$ci)) {
    out$ci_lower <- as.numeric(bootstrap$ci[parameter, "lower"])
    out$ci_upper <- as.numeric(bootstrap$ci[parameter, "upper"])
  }
  out$confidence_level <- if (is.null(bootstrap$confidence_level)) NA_real_
                          else bootstrap$confidence_level
  out$available <- TRUE
  out
}

#' Payload de la vista de incertidumbre (B16.1)
#'
#' @param analysis Salida de `dist_fit_analyze()`.
#' @param point_estimate `list(params, estimator, distribution)` del estimador
#'   ACTIVO en la vista (el del análisis, o PM alternativo).
#' @param analytic Bloque de `.mle_uncertainty()` o `NULL`.
#' @param bootstrap Bloque de `.bootstrap_estimator()` o `NULL`.
#' @param manifest Lista del `manifest.yml`. Opcional.
#' @param config Configuración de ejecución.
#' @return Estructura paralela de incertidumbre (ver sección).
build_uncertainty_view <- function(analysis, point_estimate,
                                   analytic = NULL, bootstrap = NULL,
                                   manifest = NULL,
                                   config = dfit_default_config()) {
  est  <- as.character(point_estimate$estimator)[1]
  dist <- as.character(point_estimate$distribution)[1]

  # GUARDA (OD-15 / §2): la vía analítica de B12 solo existe para MLE. Si llega
  # un bloque analítico con un estimador que no lo admite, se descarta aquí en
  # lugar de dejar que B14/B15 monten una comparación entre estimadores
  # distintos. No es una corrección silenciosa: queda en `diagnostics`.
  dropped_analytic <- FALSE
  if (!identical(est, "mle") && !is.null(analytic)) {
    analytic <- NULL; dropped_analytic <- TRUE
  }

  validation <- .validate_estimator(point_estimate, analytic, bootstrap,
                                    analysis$sample, config)
  comparison <- .compare_uncertainty(validation)

  smp <- analysis$sample
  fit <- analysis$motor$fits[[dist]]
  ctx <- list(
    distribution = dist,
    distribution_label = if (is.null(fit$label)) dist else fit$label,
    estimator = est,
    estimator_label = if (est %in% names(DFIT_UNCERTAINTY_ESTIMATORS))
                        unname(DFIT_UNCERTAINTY_ESTIMATORS[[est]]) else est,
    # `meta$method` es el método SOLICITADO ("auto" incluido); `fit$method` es el
    # EFECTIVAMENTE usado en esta distribución, que con AUTO puede ser MoM o
    # L-momentos por caída de `.fit_auto()`. Se publican ambos porque significan
    # cosas distintas y confundirlos etiquetaría mal el ajuste.
    analysis_method_requested = analysis$meta$method,
    analysis_method_effective = fit$method,
    # Alternativo = distinto del método efectivo de la distribución (en v1.1, PM).
    is_alternative_estimator = !identical(est, fit$method),
    n_input = smp$n_input, n_used = smp$n_used,
    support = smp$support_label,
    conditional = validation$sample$conditional,
    conditional_note = validation$sample$conditional_note
  )

  boot_meta <- if (is.list(validation$bootstrap)) validation$bootstrap else list()
  gv <- function(v, d = NA) if (is.null(v)) d else v

  # ---- Identidad de la muestra en el pasaporte ----------------------------
  # NO puede depender de haber ejecutado bootstrap: B12 también huella la
  # muestra, y un resultado analítico sin bootstrap sigue siendo un resultado de
  # incertidumbre que debe identificar sus datos. Se toman los campos que B14 ya
  # propaga en `comparability` —no se recalcula nada ni se crea otro algoritmo—,
  # prefiriendo la vía bootstrap cuando existe, que es la asociada al resultado
  # remuestreado. Con ambas vías presentes y OD-18 verificada, las dos huellas
  # coinciden por construcción, de modo que la preferencia es indiferente.
  cmpv <- if (is.list(validation$comparability)) validation$comparability else list()
  .fp_usable <- function(fp) {
    is.character(fp) && length(fp) == 1L && !is.na(fp) && grepl("^[0-9a-f]{64}$", fp)
  }
  data_id <- if (.fp_usable(cmpv$bootstrap_sample_fingerprint)) {
    list(n_used = smp$n_used, fingerprint = cmpv$bootstrap_sample_fingerprint,
         fingerprint_algo = gv(cmpv$bootstrap_fingerprint_algo, NA_character_),
         fingerprint_status = gv(cmpv$bootstrap_fingerprint_status, NA_character_),
         fingerprint_source = "bootstrap")
  } else if (.fp_usable(cmpv$analytic_sample_fingerprint)) {
    list(n_used = smp$n_used, fingerprint = cmpv$analytic_sample_fingerprint,
         fingerprint_algo = gv(cmpv$analytic_fingerprint_algo, NA_character_),
         fingerprint_status = gv(cmpv$analytic_fingerprint_status, NA_character_),
         fingerprint_source = "analytic")
  } else {
    # Sin ninguna vía calculada todavía no hay resultado de incertidumbre: se
    # declara la ausencia. NO se inventa una huella ni se usa `n_used` como
    # sustituto de identidad.
    list(n_used = smp$n_used, fingerprint = NA_character_,
         fingerprint_algo = NA_character_, fingerprint_status = NA_character_,
         fingerprint_source = NA_character_)
  }

  repro <- list(
    analysis = list(
      distribution = dist, estimator = est,
      uncertainty_method = if (!is.null(bootstrap)) "nonparametric_bootstrap"
                           else if (identical(validation$analytic$status, "complete"))
                             "analytic_mle" else NA_character_,
      B_requested = gv(boot_meta$B_requested), B_success = gv(boot_meta$B_success),
      B_failed = gv(boot_meta$B_failed),
      confidence_level = gv(boot_meta$confidence_level,
                            gv(validation$analytic$confidence_level, NA_real_)),
      seed = gv(boot_meta$seed),
      pm_percentiles = if (identical(est, "pm") && !is.null(bootstrap))
                         bootstrap$pm_percentiles else NULL),
    data = data_id,
    software = list(tool_name = gv(manifest$name, NA_character_),
                    tool_version = gv(manifest$version, NA_character_),
                    schema_version = DFIT_SCHEMA_VERSION)
  )

  diags <- comparison$diagnostics
  if (dropped_analytic) {
    diags <- c(diags, paste("analytic inference discarded: not applicable for",
                            sprintf("estimator '%s'", est)))
  }

  out <- list(
    context = ctx,
    point_estimate = point_estimate$params,
    analytic = list(status = validation$analytic$status,
                    reason = validation$analytic$reason,
                    confidence_level = validation$analytic$confidence_level,
                    table = .dfit_param_table(validation, "analytic")),
    bootstrap = list(status = gv(boot_meta$status, "not_requested"),
                     reason = gv(boot_meta$reason, NA_character_),
                     confidence_level = gv(boot_meta$confidence_level, NA_real_),
                     B_requested = gv(boot_meta$B_requested),
                     B_success = gv(boot_meta$B_success),
                     B_failed = gv(boot_meta$B_failed),
                     success_rate = gv(boot_meta$success_rate, NA_real_),
                     seed = gv(boot_meta$seed), quantile_type = gv(boot_meta$quantile_type),
                     failures = gv(boot_meta$failures, list(counts = integer(0))),
                     parameters = names(validation$parameters),
                     table = .dfit_param_table(validation, "bootstrap")),
    validation = validation,
    comparison = comparison,
    reproducibility = repro,
    diagnostics = diags,
    limitations = validation$limitations
  )
  # NOTA: las réplicas NO viajan en esta estructura. Viven en el resultado de
  # B13 que la sesión conserva, y solo se usan para dibujar (§4 del contrato).
  out$export_table <- .dfit_uncertainty_export(out, comparison)
  out
}

#' Tabla de exportación de incertidumbre: UNA FILA POR PARÁMETRO
#'
#' Grano distinto del export del ranking —una fila por distribución—, de modo que
#' se publica como tabla independiente y `export_table` del View Model **no se
#' toca**. Nunca incluye réplicas individuales.
.dfit_uncertainty_export <- function(uv, comparison) {
  p <- comparison$parameters
  if (!is.data.frame(p) || nrow(p) == 0L) return(data.frame())
  r <- uv$reproducibility
  pmp <- r$analysis$pm_percentiles
  data.frame(
    distribucion = uv$context$distribution_label,
    estimador = uv$context$estimator,
    estimador_alternativo = uv$context$is_alternative_estimator,
    parametro = p$parameter,
    estimacion = p$estimate,
    analitico_disponible = p$analytic_available,
    analitico_se = p$analytic_se,
    analitico_ic_inf = p$analytic_ci_lower,
    analitico_ic_sup = p$analytic_ci_upper,
    analitico_nivel = p$analytic_confidence_level,
    bootstrap_disponible = p$bootstrap_available,
    bootstrap_se = p$bootstrap_se,
    bootstrap_ic_inf = p$bootstrap_ci_lower,
    bootstrap_ic_sup = p$bootstrap_ci_upper,
    bootstrap_nivel = p$bootstrap_confidence_level,
    b_solicitadas = r$analysis$B_requested,
    b_exitosas = r$analysis$B_success,
    b_fallidas = r$analysis$B_failed,
    seed = r$analysis$seed,
    pm_percentiles = if (is.null(pmp)) NA_character_ else paste(pmp, collapse = "/"),
    n_modelizada = r$data$n_used,
    fingerprint = r$data$fingerprint,
    fingerprint_algo = r$data$fingerprint_algo,
    fingerprint_estado = r$data$fingerprint_status,
    herramienta = r$software$tool_name,
    version_herramienta = r$software$tool_version,
    version_schema = r$software$schema_version,
    comparacion_estado = comparison$comparison_status,
    stringsAsFactors = FALSE)
}


# ============================================================
# 4. ORCHESTRATOR + STUBS DE CAPAS — diseño §11
# ============================================================

#' Marcador de capa pendiente (stub limpio)
#'
#' @param layer Nombre de la capa.
#' @return Lista con estado "pending" y el bloque en que se implementará.
.pending <- function(layer) {
  list(status = "pending", layer = layer, block = unname(DFIT_PENDING_LAYERS[layer]))
}

#' Punto de entrada único del motor de Tool-02 (§11.1)
#'
#' Orquesta el pipeline en el orden aprobado. En B1 están implementadas las capas
#' 0 (profiler) y la selección de candidatas; las capas de ajuste, diagnóstico,
#' evaluación, texto y View Model son stubs que se completan en B2-B6. Función
#' pura y sin Shiny (§11.2).
#'
#' @param data data.frame validado.
#' @param variable Nombre de la columna numérica a modelizar.
#' @param mode "auto" | "manual".
#' @param family Forzar familia en modo manual: "continuous" | "discrete" | NULL.
#' @param analysis_depth "standard" | "comprehensive".
#' @param config Lista de configuración de ejecución (`dfit_default_config()`).
#' @return Lista con `profile`, `candidates`, `decision_engine`, las capas
#'   pendientes y `meta`.
dist_fit_analyze <- function(data, variable,
                             mode = c("auto", "manual"),
                             family = NULL,
                             method = c("mle", "mom", "lmom", "auto"),
                             analysis_depth = c("standard", "comprehensive"),
                             config = dfit_default_config()) {
  mode           <- match.arg(mode)
  method         <- match.arg(method)
  analysis_depth <- match.arg(analysis_depth)
  if (!is.data.frame(data)) stop("`data` debe ser un data.frame.", call. = FALSE)
  if (!variable %in% names(data)) {
    stop(sprintf("La variable '%s' no existe en los datos.", variable), call. = FALSE)
  }

  x <- data[[variable]]
  if (!is.numeric(x)) stop(sprintf("La variable '%s' no es numérica.", variable), call. = FALSE)

  # Capa 0: perfilado.
  profile <- profile_dataset(x, variable, config)

  # Enrutado de familia: manual (forzada) o auto (del diagnóstico).
  variable_type <- if (mode == "manual" && !is.null(family)) {
    match.arg(family, c("continuous", "discrete"))
  } else {
    profile$variable_type
  }

  # Selección de candidatas.
  candidates <- select_candidate_distributions(variable_type)

  # Capa 0.5 (ADR-026): muestra común comparable. Punto ÚNICO donde se decide
  # sobre qué observaciones se ajusta el análisis; todas las capas siguientes la
  # consumen sin volver a filtrar.
  x_valid <- x[!is.na(x)]
  sample  <- build_analysis_sample(x_valid, candidates, config)

  # Capa 1: ajuste de las candidatas por el método (default "mle"; "auto",
  # "mom" y "lmom" disponibles, B2.2).
  motor <- .motor(sample, candidates, config, method = method)

  # Capas 2-4: Diagnostics (B3), Assessment (B4) y Text Builders (B5).
  engine      <- decision_engine_spec()
  diagnostics <- .diagnostics(sample, motor, config)
  assessment  <- .assess(diagnostics, motor, engine)
  text        <- .text_builders(profile, candidates, motor, diagnostics, assessment,
                                engine, sample)

  list(
    profile         = profile,
    sample          = sample,
    candidates      = candidates,
    decision_engine = engine,
    motor           = motor,
    diagnostics     = diagnostics,
    assessment      = assessment,
    text_builder    = text,
    view_model      = .pending("view_model"),
    meta = list(
      variable                = variable,
      mode                    = mode,
      analysis_depth          = analysis_depth,
      family                  = variable_type,
      method                  = motor$method,
      decision_engine_version = engine$version,
      block                   = "B2.1"
    )
  )
}
