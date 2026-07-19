# ============================================================
# Tool: kernel-density
# Archivo: calc.R — núcleo matemático de la herramienta (sin Shiny, regla 7)
# Autor: BMK
# Última actualización: 2026-07-19
# ============================================================
#
# Librería matemática pura de Kernel Density Estimation. Ejecutable con
# source("R/calc.R") desde una consola de R, sin la aplicación: no depende de
# Shiny, plotly ni de los componentes del framework. Las funciones locales de la
# herramienta no llevan prefijo bmk_ (regla 3); los helpers internos usan prefijo
# de punto ".".
#
# Implementación propia (política 2.2): stats::density(), stats::bw.nrd*() y
# stats::quantile() se usan SOLO como referencia de validación, nunca en el
# camino principal (excepción: dnorm/pnorm como evaluación exacta del propio
# kernel gaussiano, y sd/var/IQR/quantile como primitivas estadísticas base).
#
# ORGANIZACIÓN DEL ARCHIVO (bloques):
#   0. Constantes        <- implementado
#   1. Kernels     [2A]  <- implementado
#   2. Bandwidth   [2B]  <- implementado
#   3. Estimation  [2C]  <- implementado
#   4. Diagnostics [2D]  <- implementado
#   5. Assessment  [2E]  <- implementado en este sub-bloque (capa intermedia)
#   6. Text Builders [2E] <- implementado
#   7. Orchestrator [2F] <- implementado en este sub-bloque
#
# CAPAS CONCEPTUALES (aprobado):
#   Mathematical Results -> Structured Diagnostics -> Assessment -> Text Builders
#   El Assessment es un objeto categórico simple (estado de la muestra). Los Text
#   Builders consumen ÚNICAMENTE el Assessment, nunca los resultados crudos, de
#   modo que futuras herramientas reutilicen el mismo mecanismo.


# ============================================================
# 0. CONSTANTES
# ============================================================

# Nombres válidos de kernel: fuente única de verdad para match.arg() (regla 8).
KDE_KERNELS <- c("gaussian", "epanechnikov", "uniform", "triangular", "biweight")

# Constantes numéricas del núcleo matemático (regla 8: sin números mágicos).
KDE_DEFAULTS <- list(
  # --- Bandwidth ---
  # Divisor IQR->sigma robusto. 1.349 = qnorm(.75) - qnorm(.25); es EXACTAMENTE
  # el valor usado por stats::bw.nrd0() y stats::bw.nrd(), lo que permite la
  # validación por igualdad exacta contra ambas.
  iqr_divisor                = 1.349,
  bw_exponent                = -1 / 5,   # n^(-1/5), orden de la regla normal
  bw_factor_silverman        = 0.9,      # Silverman rule of thumb (= bw.nrd0)
  bw_factor_scott            = 1.06,     # Scott 1992           (= bw.nrd)
  bw_factor_normal_reference = 1.06,     # AMISE-óptimo bajo normalidad (NRR, con sd)

  # --- Estimation (rejilla de evaluación) ---
  # grid_n: nº de puntos de la rejilla para dibujar densidad y CDF. 512 = potencia
  #   de 2, misma convención que stats::density(); suficiente para curvas suaves.
  # grid_extend_h: extensión de la rejilla más allá del rango de los datos, en
  #   múltiplos de h. Con 3*h el kernel gaussiano queda cubierto hasta la práctica
  #   totalidad de su masa; para los kernels de soporte compacto solo añade ceros.
  # IMPORTANTE: la rejilla afecta al DIBUJO y a la comprobación cruzada por
  #   acumulación, NO a la precisión del VaR (kde_quantile invierte la CDF
  #   analítica por búsqueda de raíz, con independencia de la rejilla).
  grid_n                     = 512L,
  grid_extend_h              = 3,

  # --- Diagnostics ---
  outlier_iqr_mult           = 1.5,   # regla de Tukey: Q1-1.5*IQR, Q3+1.5*IQR
  bw_near_tol                = 0.10,  # tolerancia (+/-10%) de "próximo" a la banda automática
  n_small                    = 30L,   # umbral de "muestra pequeña" (dato estructurado, no texto)

  # --- Assessment (umbrales de categorización; datos, no texto) ---
  n_moderate                 = 200L,  # n >= n_moderate -> "large"; entre n_small y este -> "moderate"
  skew_moderate              = 0.5,   # |skew| < este -> "symmetric"
  skew_high                  = 1.0,   # |skew| >= este -> "high"
  kurt_light                 = 2.5,   # curtosis < este -> "light"
  kurt_heavy                 = 3.5,   # curtosis > este -> "heavy"
  outlier_prop_many          = 0.05,  # proporción de outliers >= este -> "many"
  var_gap_moderate           = 0.02,  # |gap relativo VaR| < este -> "close"
  var_gap_notable            = 0.10,   # |gap relativo VaR| >= este -> "notable"

  # --- Defaults del pipeline (kde_analyze) ---
  default_kernel             = "gaussian",
  default_bw_method          = "silverman",           # Silverman rule of thumb (= bw.nrd0)
  default_levels             = c(0.95, 0.99, 0.995)    # niveles de VaR por defecto
)

# Versión del motor de cálculo (independiente de manifest.yml, que versiona la
# herramienta). Se expone en el bloque metadata del objeto de salida.
KDE_ENGINE_VERSION <- "1.0.0"

# ------------------------------------------------------------
# DECISIÓN DE ARQUITECTURA CONGELADA (aprobada, no reabrir)
# ------------------------------------------------------------
# 1) La rejilla (make_grid) se usa EXCLUSIVAMENTE para visualización y para
#    validaciones cruzadas. El cálculo del VaR es COMPLETAMENTE independiente de
#    la discretización del dominio: se obtiene invirtiendo la CDF ANALÍTICA
#    (kde_quantile -> uniroot sobre sum de kernel_cdf). Congelado para toda la
#    herramienta.
# 2) La comprobación por acumulación (cumsum de la densidad) es SOLO una
#    validación numérica cuya precisión depende del tamaño de la rejilla. NUNCA
#    sustituye a la CDF analítica en el camino de cálculo.


# ============================================================
# 1. KERNELS  [Sub-bloque 2A]
# ============================================================
#
# Todos los kernels operan sobre el argumento estandarizado u = (x - x_i) / h,
# están normalizados para integrar 1 y son simétricos respecto a 0. Cuatro tienen
# soporte compacto [-1, 1]; el gaussiano tiene soporte en toda la recta real.
#
#   Kernel         K(u)                         Soporte
#   ------------   --------------------------   --------
#   gaussian       (1/sqrt(2*pi)) e^(-u^2/2)     R
#   epanechnikov   (3/4)(1 - u^2)                |u| <= 1
#   uniform        1/2                           |u| <= 1
#   triangular     1 - |u|                       |u| <= 1
#   biweight       (15/16)(1 - u^2)^2            |u| <= 1
#
# Nota docente: el script del Máster parametrizaba el kernel uniforme como
# dunif(u, 0, 2) (asimétrico sobre (0,2)). Aquí se adopta la formulación estándar
# simétrica sobre [-1, 1] (Decisión 1), por rigor y coherencia con la literatura.
#
# VALIDACIÓN FUTURA (no implementada aún): comprobar los momentos de cada kernel,
# como control adicional de correcta normalización y simetría:
#   - Primer momento  mu_1(K) = integral u*K(u) du   = 0     (por simetría).
#   - Segundo momento mu_2(K) = integral u^2*K(u) du  = varianza del kernel:
#       gaussian = 1, epanechnikov = 1/5, uniform = 1/3,
#       triangular = 1/6, biweight = 1/7.

#' Soporte de un kernel
#'
#' Devuelve el intervalo [a, b] fuera del cual el kernel es cero. Helper interno
#' compartido por kernel_k() y kernel_cdf().
#'
#' @section Tipo: Auxiliar (helper interno).
#' @param kernel Nombre del kernel (uno de KDE_KERNELS).
#' @return Vector numérico de longitud 2 con los límites del soporte.
.kernel_support <- function(kernel) {
  kernel <- match.arg(kernel, KDE_KERNELS)
  if (identical(kernel, "gaussian")) c(-Inf, Inf) else c(-1, 1)
}

#' Evalúa el núcleo K(u) de un kernel
#'
#' Función pura y vectorizada. Fuera del soporte compacto devuelve 0.
#'
#' @section Tipo: Auxiliar.
#' @param u Vector numérico ya estandarizado, u = (x - x_i) / h.
#' @param kernel Nombre del kernel (uno de KDE_KERNELS).
#' @return Vector numérico K(u), de la misma longitud que u.
#' @examples
#' kernel_k(0, "gaussian")      # ~0.3989423
#' kernel_k(0, "epanechnikov")  # 0.75
#' kernel_k(c(-2, 0, 2), "uniform")  # 0.0 0.5 0.0
kernel_k <- function(u, kernel) {
  kernel <- match.arg(kernel, KDE_KERNELS)
  inside <- abs(u) <= 1  # solo relevante para los de soporte compacto

  switch(
    kernel,
    gaussian     = stats::dnorm(u),
    epanechnikov = ifelse(inside, 0.75 * (1 - u^2), 0),
    uniform      = ifelse(inside, 0.5, 0),
    triangular   = ifelse(inside, 1 - abs(u), 0),
    biweight     = ifelse(inside, (15 / 16) * (1 - u^2)^2, 0)
  )
}

#' Evalúa la función de distribución del kernel, G(u) = integral_{-inf}^{u} K(t) dt
#'
#' Forma analítica cerrada por kernel (no integración numérica). Es la base de la
#' CDF de la KDE (Decisión 3): F_hat(x) = (1/n) sum_i G((x - x_i)/h). Monótona,
#' con G(-1)=0, G(0)=0.5 y G(1)=1 en los kernels de soporte compacto.
#'
#' @section Tipo: Auxiliar.
#' @param u Vector numérico estandarizado, u = (x - x_i) / h.
#' @param kernel Nombre del kernel (uno de KDE_KERNELS).
#' @return Vector numérico G(u) en [0, 1], de la misma longitud que u.
#' @examples
#' kernel_cdf(0, "epanechnikov")  # 0.5
#' kernel_cdf(c(-1, 0, 1), "triangular")  # 0.0 0.5 1.0
kernel_cdf <- function(u, kernel) {
  kernel <- match.arg(kernel, KDE_KERNELS)

  if (identical(kernel, "gaussian")) {
    return(stats::pnorm(u))
  }

  # Kernels de soporte compacto: fórmula del interior + recorte a [0, 1].
  interior <- switch(
    kernel,
    # ∫ 0.75(1 - t^2) dt = 0.75(u - u^3/3) + 0.5
    epanechnikov = 0.75 * (u - u^3 / 3) + 0.5,
    # ∫ 0.5 dt = (u + 1) / 2
    uniform      = (u + 1) / 2,
    # tramo izq. y der.: 0.5 + u - sign(u) * u^2/2
    triangular   = 0.5 + u - sign(u) * u^2 / 2,
    # ∫ (15/16)(1 - t^2)^2 dt = (15/16)(u - 2u^3/3 + u^5/5 + 8/15)
    biweight     = (15 / 16) * (u - 2 * u^3 / 3 + u^5 / 5 + 8 / 15)
  )

  # Recorte: 0 por debajo del soporte, 1 por encima.
  out <- ifelse(u < -1, 0, ifelse(u > 1, 1, interior))
  out
}


# ============================================================
# 2. BANDWIDTH  [Sub-bloque 2B]
# ============================================================
#
# Selección del ancho de banda h. Tres reglas automáticas del MVP + Manual.
# Nomenclatura definitiva (Decisión 2, Opción A), verificada contra la literatura
# y contra R base:
#
#   Método (UI)              Fórmula                                Equivale a
#   ----------------------   ------------------------------------   ----------------
#   Silverman (Rule of Thumb) 0.9 *min(sd, IQR/1.349) * n^(-1/5)     stats::bw.nrd0
#   Scott                     1.06*min(sd, IQR/1.349) * n^(-1/5)     stats::bw.nrd
#   Normal Reference          1.06* sd               * n^(-1/5)      NRR clásica (sd)
#   Manual                    valor h introducido por el usuario     -
#
# DISEÑO EXTENSIBLE: los métodos automáticos se registran en KDE_BW_METHODS
# (nombre -> función(x) -> h). Añadir un método futuro (Sheather-Jones, UCV/BCV,
# plug-in, ...) consiste ÚNICAMENTE en:
#   1) implementar bw_<metodo>(x);
#   2) añadir una entrada al registro KDE_BW_METHODS.
# No hay que tocar bw_automatic(), bw_resolve() ni kde_analyze(): recorren el
# registro dinámicamente. (Salvedad: un "adaptive bandwidth" produce un h por
# punto, no escalar; requeriría además que kde_density() acepte h vectorial. El
# registro admite su selección, pero esa extensión es más profunda y se abordará
# en su momento.)

#' Exige un mínimo de observaciones para estimar el ancho de banda
#' @section Tipo: Auxiliar (helper interno). Replica el guard de stats::bw.nrd*().
#' @param x Vector numérico.
#' @return invisible(TRUE); lanza error si length(x) < 2.
.bw_require_min <- function(x) {
  if (length(x) < 2L) {
    stop("Se necesitan al menos 2 observaciones para estimar el ancho de banda.")
  }
  invisible(TRUE)
}

#' Ancho de banda de Silverman (Rule of Thumb)  [= stats::bw.nrd0]
#'
#' Escala robusta A = min(sd, IQR/1.349) y constante 0.9. Replica exactamente
#' bw.nrd0, incluida su salvaguarda cuando los cuartiles coinciden (A = 0).
#'
#' @section Tipo: Auxiliar.
#' @param x Vector numérico (sin NA; la limpieza es responsabilidad del llamante).
#' @return Ancho de banda h (numeric escalar, sin nombre).
bw_silverman <- function(x) {
  .bw_require_min(x)
  hi <- stats::sd(x)
  lo <- min(hi, stats::IQR(x) / KDE_DEFAULTS$iqr_divisor)
  if (lo == 0) {
    lo <- if (hi > 0) hi else if (abs(x[1L]) > 0) abs(x[1L]) else 1
  }
  KDE_DEFAULTS$bw_factor_silverman * lo * length(x)^KDE_DEFAULTS$bw_exponent
}

#' Ancho de banda de Scott (1992)  [= stats::bw.nrd]
#'
#' Escala robusta A = min(sd, IQR/1.349) y constante 1.06. Replica exactamente
#' bw.nrd (que NO incluye la salvaguarda de bw.nrd0: con datos constantes da 0).
#'
#' @section Tipo: Auxiliar.
#' @param x Vector numérico (sin NA).
#' @return Ancho de banda h (numeric escalar, sin nombre).
bw_scott <- function(x) {
  .bw_require_min(x)
  r <- stats::quantile(x, c(0.25, 0.75))
  h <- (r[[2L]] - r[[1L]]) / KDE_DEFAULTS$iqr_divisor
  KDE_DEFAULTS$bw_factor_scott *
    min(sqrt(stats::var(x)), h) * length(x)^KDE_DEFAULTS$bw_exponent
}

#' Ancho de banda por Normal Reference Rule (implementación propia)
#'
#' AMISE-óptimo bajo normalidad con kernel gaussiano: 1.06 * sd * n^(-1/5). Usa la
#' desviación típica muestral (no la escala robusta). No coincide con bw.nrd salvo
#' cuando sd <= IQR/1.349.
#'
#' @section Tipo: Auxiliar.
#' @param x Vector numérico (sin NA).
#' @return Ancho de banda h (numeric escalar).
bw_normal_reference <- function(x) {
  .bw_require_min(x)
  KDE_DEFAULTS$bw_factor_normal_reference *
    stats::sd(x) * length(x)^KDE_DEFAULTS$bw_exponent
}

# Registro extensible de métodos de bandwidth. Se define tras las funciones para
# que existan al construir la lista. Cada entrada es una LISTA DE METADATOS, no
# solo la función, para permitir futuras ampliaciones (etiqueta de UI, tipo,
# referencia bibliográfica, y en el futuro flags como differentiable, requires,
# etc.) sin romper el contrato. Campos actuales:
#   - fn        : function(x) -> h              (obligatorio; NULL si no automático)
#   - label     : etiqueta para la UI            (la usará mod_tool.R)
#   - type      : "automatic" | "manual"
#   - reference : cita de la regla
# Para añadir un método futuro (Sheather-Jones, UCV/BCV, plug-in, ...): impleméntalo
# arriba y añade aquí su entrada; bw_automatic()/bw_resolve() lo recogen solos.
KDE_BW_METHODS <- list(
  silverman = list(
    fn = bw_silverman, label = "Silverman (Rule of Thumb)",
    type = "automatic", reference = "Silverman (1986), = bw.nrd0"
  ),
  scott = list(
    fn = bw_scott, label = "Scott",
    type = "automatic", reference = "Scott (1992), = bw.nrd"
  ),
  normal_reference = list(
    fn = bw_normal_reference, label = "Normal Reference",
    type = "automatic", reference = "Normal Reference Rule (sd)"
  )
)

#' Nombres de los métodos automáticos registrados (aquellos con función)
#' @section Tipo: Auxiliar.
#' @return Vector de caracteres con las claves de los métodos automáticos.
.bw_automatic_names <- function() {
  is_auto <- vapply(KDE_BW_METHODS, function(m) identical(m$type, "automatic"),
                    logical(1))
  names(KDE_BW_METHODS)[is_auto]
}

#' Calcula TODOS los anchos de banda automáticos registrados
#'
#' Recorre los métodos automáticos de KDE_BW_METHODS. Se calcula siempre (aunque
#' el método elegido sea Manual), porque el indicador visual de bandwidth y el
#' clasificador under/oversmoothing necesitan las referencias automáticas.
#'
#' @section Tipo: Pública.
#' @param x Vector numérico (sin NA).
#' @return Vector numérico con nombre por método (p. ej. silverman, scott,
#'   normal_reference).
bw_automatic <- function(x) {
  keys <- .bw_automatic_names()
  vapply(keys, function(k) KDE_BW_METHODS[[k]]$fn(x), numeric(1))
}

#' Resuelve el ancho de banda efectivo según el método elegido
#'
#' Despacha por nombre contra el registro; "manual" usa el h del usuario. Devuelve
#' también todos los automáticos, para alimentar el indicador y la clasificación.
#'
#' @section Tipo: Auxiliar.
#' @param x Vector numérico (sin NA).
#' @param method Uno de los nombres de KDE_BW_METHODS, o "manual".
#' @param h_manual Ancho de banda manual (> 0). Obligatorio si method = "manual".
#' @return list(h = numeric, method = character, automatic = named numeric).
bw_resolve <- function(x, method, h_manual = NULL) {
  method <- match.arg(method, c(.bw_automatic_names(), "manual"))
  automatic <- bw_automatic(x)

  if (identical(method, "manual")) {
    if (is.null(h_manual) || !is.finite(h_manual) || h_manual <= 0) {
      stop("El ancho de banda manual debe ser un número positivo.")
    }
    h <- h_manual
  } else {
    h <- unname(automatic[[method]])
  }

  list(h = h, method = method, automatic = automatic)
}


# ============================================================
# 3. ESTIMATION  [Sub-bloque 2C]
# ============================================================
#
# KDE:  f_hat(x) = (1/(n*h)) * sum_i K((x - x_i)/h)                      (Máster)
# CDF:  F_hat(x) = (1/n)     * sum_i G((x - x_i)/h)   con G = kernel_cdf  (Decisión 3)
# VaR KDE = F_hat^{-1}(p) por búsqueda de raíz sobre la CDF ANALÍTICA.
#
# ------------------------------------------------------------
# JUSTIFICACIÓN DEL DOMINIO DE EVALUACIÓN (make_grid)
# ------------------------------------------------------------
# xmin = min(x) - grid_extend_h * h
# xmax = max(x) + grid_extend_h * h
# nº de puntos = grid_n (512)
#
# Justificación matemática:
#  - Cada dato x_i aporta densidad solo dentro de su ventana. Para kernels de
#    SOPORTE COMPACTO, K((x - x_i)/h) = 0 cuando |x - x_i| > h; por tanto la
#    densidad es EXACTAMENTE 0 fuera de [min(x) - h, max(x) + h]. Extender 3*h no
#    pierde masa (solo añade ceros), y da margen visual.
#  - Para el kernel GAUSSIANO (soporte infinito) la densidad nunca es 0, pero
#    decae como una normal: a 3*h del dato más extremo queda ~0.1% de una cola de
#    kernel, y a 4*h ~0.003%. grid_extend_h = 3 captura la práctica totalidad de
#    la masa para el dibujo y para la comprobación por acumulación.
#  - grid_n = 512 (potencia de 2, convención de stats::density) basta para curvas
#    visualmente suaves; más puntos solo mejoran el dibujo y la coincidencia de la
#    validación cruzada, con coste despreciable.
#
# Influencia sobre la precisión del VaR:
#  - NINGUNA en el VaR de producción. kde_quantile() NO integra sobre la rejilla:
#    invierte la CDF analítica F_hat (suma de kernel_cdf) mediante uniroot, con
#    tolerancia numérica propia. Por eso el VaR es independiente de grid_n y de
#    grid_extend_h. La rejilla influye únicamente en (a) el dibujo de las curvas y
#    (b) el grado de coincidencia de la validación cruzada por acumulación
#    (cumsum(densidad)*dx), que converge al VaR analítico al refinar la rejilla.
#  - Nota de sesgo de borde (severidad >= 0): con kernel gaussiano se filtra masa
#    por debajo de 0. Es una limitación conocida (documentada en el README); el
#    recorte del eje a x >= 0 es decisión de presentación en mod_tool.R, no de
#    calc.R, que trabaja sobre el dominio matemáticamente correcto.

#' Construye la rejilla de evaluación de densidad/CDF
#'
#' @section Tipo: Auxiliar.
#' @param x Vector numérico (datos, sin NA).
#' @param h Ancho de banda (> 0).
#' @return Vector numérico de longitud KDE_DEFAULTS$grid_n, creciente, que cubre
#'   [min(x) - k*h, max(x) + k*h] con k = KDE_DEFAULTS$grid_extend_h.
make_grid <- function(x, h) {
  ext <- KDE_DEFAULTS$grid_extend_h * h
  seq(min(x) - ext, max(x) + ext, length.out = KDE_DEFAULTS$grid_n)
}

#' Densidad KDE evaluada en una rejilla
#'
#' f_hat(g) = (1/(n*h)) * sum_i K((g - x_i)/h). Implementación propia (no
#' stats::density). Complejidad O(n * length(grid)); memoria O(n).
#'
#' @section Tipo: Auxiliar.
#' @param x Vector numérico (datos, sin NA).
#' @param grid Puntos donde evaluar la densidad (típicamente make_grid(x, h)).
#' @param h Ancho de banda (> 0).
#' @param kernel Nombre del kernel (uno de KDE_KERNELS).
#' @return Vector numérico de densidades (>= 0), de la longitud de grid.
kde_density <- function(x, grid, h, kernel) {
  kernel <- match.arg(kernel, KDE_KERNELS)
  n <- length(x)
  dens <- vapply(grid, function(g) sum(kernel_k((g - x) / h, kernel)), numeric(1))
  dens / (n * h)
}

#' CDF de la KDE evaluada en una rejilla (suma de CDFs de kernel, Decisión 3)
#'
#' F_hat(g) = (1/n) * sum_i G((g - x_i)/h), con G = kernel_cdf. Monótona por
#' construcción y exacta (no depende de la finura de la rejilla).
#'
#' @section Tipo: Auxiliar.
#' @param x Vector numérico (datos, sin NA).
#' @param grid Puntos donde evaluar la CDF.
#' @param h Ancho de banda (> 0).
#' @param kernel Nombre del kernel.
#' @return Vector numérico en [0, 1], no decreciente, de la longitud de grid.
kde_cdf <- function(x, grid, h, kernel) {
  kernel <- match.arg(kernel, KDE_KERNELS)
  n <- length(x)
  vapply(grid, function(g) sum(kernel_cdf((g - x) / h, kernel)), numeric(1)) / n
}

#' Cuantil (VaR) de la KDE por inversión de la CDF analítica
#'
#' Resuelve F_hat(q) = p para cada p mediante búsqueda de raíz (uniroot) sobre la
#' CDF analítica; independiente de la rejilla. El intervalo de búsqueda se expande
#' hasta enmarcar la raíz, garantizando robustez incluso para p extremos.
#'
#' @section Tipo: Auxiliar.
#' @param x Vector numérico (datos, sin NA).
#' @param h Ancho de banda (> 0).
#' @param kernel Nombre del kernel.
#' @param p Vector de niveles de probabilidad en (0, 1).
#' @return Vector numérico de cuantiles (VaR KDE), de la longitud de p.
kde_quantile <- function(x, h, kernel, p) {
  kernel <- match.arg(kernel, KDE_KERNELS)
  Fhat <- function(q) mean(kernel_cdf((q - x) / h, kernel))

  rng  <- range(x)
  base <- KDE_DEFAULTS$grid_extend_h * h

  invert_one <- function(pp) {
    if (!is.finite(pp) || pp <= 0 || pp >= 1) return(NA_real_)
    lo <- rng[1L] - base
    hi <- rng[2L] + base
    step <- 1L
    while (Fhat(lo) > pp && step <= 60L) { lo <- lo - (2^step) * h; step <- step + 1L }
    step <- 1L
    while (Fhat(hi) < pp && step <= 60L) { hi <- hi + (2^step) * h; step <- step + 1L }
    stats::uniroot(function(q) Fhat(q) - pp, lower = lo, upper = hi,
                   tol = .Machine$double.eps^0.5)$root
  }

  vapply(p, invert_one, numeric(1))
}

#' Cuantil empírico (VaR empírico) de referencia
#'
#' Envoltorio de stats::quantile() para comparar el VaR KDE con el cuantil crudo.
#' Se usa como comparación honesta, no como camino principal.
#'
#' @section Tipo: Auxiliar.
#' @param x Vector numérico (datos, sin NA).
#' @param p Vector de niveles de probabilidad en [0, 1].
#' @return Vector numérico de cuantiles empíricos, sin nombres.
empirical_quantile <- function(x, p) {
  unname(stats::quantile(x, probs = p, names = FALSE))
}


# ============================================================
# 4. DIAGNOSTICS  [Sub-bloque 2D]
# ============================================================
#
# Todas las funciones de este bloque devuelven ÚNICAMENTE datos estructurados
# (numéricos, lógicos o listas). NINGUNA genera texto: la redacción de mensajes,
# recomendaciones y Actuarial Insights es responsabilidad exclusiva de los Text
# Builders (bloque 5). sample_diagnostics() agrega el diagnóstico de la muestra
# en un ÚNICO objeto estructurado.

#' Asimetría por momentos (estimador poblacional / sesgado)
#'
#' g1 = m3 / m2^(3/2), con m_k = (1/n) sum (x - media)^k. Coincide con
#' scipy.stats.skew y con e1071::skewness(type = 1). Normal -> ~0.
#'
#' @section Tipo: Auxiliar.
#' @param x Vector numérico (sin NA).
#' @return Asimetría (numeric escalar); NA si la varianza es 0.
moment_skewness <- function(x) {
  m  <- mean(x)
  m2 <- mean((x - m)^2)
  if (m2 == 0) return(NA_real_)
  mean((x - m)^3) / m2^(3 / 2)
}

#' Curtosis por momentos (bruta, no exceso)
#'
#' g2 = m4 / m2^2. Coincide con scipy.stats.kurtosis(fisher = FALSE) y con
#' e1071::kurtosis(type = 1) + 3. Normal -> ~3 (colas más pesadas si > 3).
#'
#' @section Tipo: Auxiliar.
#' @param x Vector numérico (sin NA).
#' @return Curtosis bruta (numeric escalar); NA si la varianza es 0.
moment_kurtosis <- function(x) {
  m  <- mean(x)
  m2 <- mean((x - m)^2)
  if (m2 == 0) return(NA_real_)
  mean((x - m)^4) / m2^2
}

#' Estadísticos descriptivos de la muestra (objeto estructurado)
#'
#' Solo datos numéricos. El coeficiente de variación es sd/media; NA si media = 0.
#'
#' @section Tipo: Auxiliar.
#' @param x Vector numérico (sin NA).
#' @return list con: n, n_unique, mean, median, sd, cv, skewness, kurtosis,
#'   min, max, range, q25, q75, iqr.
sample_stats <- function(x) {
  m   <- mean(x)
  s   <- stats::sd(x)
  q   <- stats::quantile(x, c(0.25, 0.75), names = FALSE)
  rng <- range(x)
  list(
    n        = length(x),
    n_unique = length(unique(x)),
    mean     = m,
    median   = stats::median(x),
    sd       = s,
    cv       = if (m == 0) NA_real_ else s / m,
    skewness = moment_skewness(x),
    kurtosis = moment_kurtosis(x),
    min      = rng[1L],
    max      = rng[2L],
    range    = rng[2L] - rng[1L],
    q25      = q[1L],
    q75      = q[2L],
    iqr      = q[2L] - q[1L]
  )
}

#' Detección de valores extremos por la regla de Tukey (IQR)
#'
#' Vallas Q1 - k*IQR y Q3 + k*IQR con k = KDE_DEFAULTS$outlier_iqr_mult. Cuartiles
#' por stats::quantile (tipo 7). Solo datos estructurados.
#'
#' @section Tipo: Auxiliar.
#' @param x Vector numérico (sin NA).
#' @return list(count, indices, lower, upper, proportion).
detect_outliers <- function(x) {
  q    <- stats::quantile(x, c(0.25, 0.75), names = FALSE)
  iqr  <- q[2L] - q[1L]
  mult <- KDE_DEFAULTS$outlier_iqr_mult
  lower <- q[1L] - mult * iqr
  upper <- q[2L] + mult * iqr
  idx   <- which(x < lower | x > upper)
  list(
    count      = length(idx),
    indices    = idx,
    lower      = lower,
    upper      = upper,
    proportion = length(idx) / length(x)
  )
}

#' Diagnóstico de la muestra: ÚNICO objeto estructurado
#'
#' Agrega descriptivos y outliers en un solo objeto, más el flag estructurado de
#' muestra pequeña. Es lo que consume mod_tool.R para el panel de diagnóstico
#' previo al cálculo (feature E). Sin texto.
#'
#' @section Tipo: Pública.
#' @param x Vector numérico (sin NA).
#' @return list(stats, outliers, is_small_sample).
sample_diagnostics <- function(x) {
  st <- sample_stats(x)
  list(
    stats           = st,
    outliers        = detect_outliers(x),
    is_small_sample = st$n < KDE_DEFAULTS$n_small
  )
}

#' Clasifica el ancho de banda frente a la banda de métodos automáticos
#'
#' Compara el h efectivo con el rango [min, max] de los anchos automáticos, con
#' tolerancia relativa KDE_DEFAULTS$bw_near_tol. Produce un estado estructurado
#' (under/near/over) y una posición relativa para el indicador visual. Sin texto.
#' Semántica: h por debajo de la banda -> posible undersmoothing; por encima ->
#' posible oversmoothing.
#'
#' @section Tipo: Pública.
#' @param h Ancho de banda efectivo (> 0).
#' @param automatic Vector nombrado de anchos automáticos (salida de bw_automatic).
#' @return list(status, rel_position, band_low, band_high, near_tol, h, automatic).
classify_bandwidth <- function(h, automatic) {
  lo  <- min(automatic)
  hi  <- max(automatic)
  tol <- KDE_DEFAULTS$bw_near_tol
  width <- hi - lo

  status <- if (h < lo * (1 - tol)) {
    "under"
  } else if (h > hi * (1 + tol)) {
    "over"
  } else {
    "near"
  }

  rel_position <- if (width > 0) (h - lo) / width else 0

  list(
    status       = status,
    rel_position = rel_position,
    band_low     = lo,
    band_high    = hi,
    near_tol     = tol,
    h            = h,
    automatic    = automatic
  )
}


# ============================================================
# 5. ASSESSMENT  [Sub-bloque 2E]  — capa intermedia
# ============================================================
#
# Traduce los resultados matemáticos y el diagnóstico estructurado a un objeto
# CATEGÓRICO simple ("estado de la muestra"). No genera texto. Es la única entrada
# de los Text Builders, de modo que el mecanismo sea reutilizable por otras
# herramientas. Campos categóricos + figures (cifras que el texto podrá citar como
# enteros; el formateo de decimales/porcentajes es de la UI, no de calc.R).
#
# Construcción por etapas: con solo el diagnóstico se obtiene el estado de la
# muestra (para el panel previo al cálculo, feature E). Añadiendo la clasificación
# de bandwidth y los VaR se completa con bandwidth_quality, var_gap y
# estimation_quality (para Actuarial Insights, feature G).

#' Construye el Assessment (estado categórico de la muestra)
#'
#' @section Tipo: Pública.
#' @param diagnostics Salida de sample_diagnostics(x).
#' @param bw_class Salida de classify_bandwidth() (opcional; post-cálculo).
#' @param var_kde VaR KDE por nivel (opcional).
#' @param var_empirical VaR empírico por nivel (opcional).
#' @param levels Niveles de VaR asociados a var_kde/var_empirical (opcional).
#' @return list con campos categóricos (sample_size, skewness_level,
#'   skewness_direction, tail_behavior, outlier_level, y si procede
#'   bandwidth_quality, var_gap_level, var_gap_direction, estimation_quality) y
#'   una sublista figures con cifras de apoyo.
build_assessment <- function(diagnostics, bw_class = NULL,
                             var_kde = NULL, var_empirical = NULL, levels = NULL) {
  st <- diagnostics$stats
  ol <- diagnostics$outliers
  d  <- KDE_DEFAULTS

  # --- Estado de la muestra (siempre) ---
  sample_size <- if (st$n < d$n_small) "small" else if (st$n < d$n_moderate) "moderate" else "large"

  sk <- st$skewness
  skewness_level <- if (is.na(sk)) "unknown"
    else if (abs(sk) < d$skew_moderate) "symmetric"
    else if (abs(sk) < d$skew_high) "moderate" else "high"
  skewness_direction <- if (is.na(sk) || abs(sk) < d$skew_moderate) "none"
    else if (sk > 0) "right" else "left"

  ku <- st$kurtosis
  tail_behavior <- if (is.na(ku)) "unknown"
    else if (ku < d$kurt_light) "light"
    else if (ku > d$kurt_heavy) "heavy" else "normal"

  outlier_level <- if (ol$count == 0L) "none"
    else if (ol$proportion >= d$outlier_prop_many) "many" else "few"

  assessment <- list(
    sample_size        = sample_size,
    skewness_level     = skewness_level,
    skewness_direction = skewness_direction,
    tail_behavior      = tail_behavior,
    outlier_level      = outlier_level,
    bandwidth_quality  = NULL,
    var_gap_level      = NULL,
    var_gap_direction  = NULL,
    estimation_quality = NULL,
    figures = list(
      n              = st$n,
      outlier_count  = ol$count,
      skewness       = st$skewness,
      kurtosis       = st$kurtosis,
      cv             = st$cv,
      h              = NULL,
      levels         = NULL,
      var_kde        = NULL,
      var_empirical  = NULL,
      var_rel_gap    = NULL
    )
  )

  # --- Calidad del bandwidth (si hay clasificación) ---
  if (!is.null(bw_class)) {
    assessment$bandwidth_quality <- switch(
      bw_class$status,
      under = "undersmoothing",
      over  = "oversmoothing",
      "balanced"
    )
    assessment$figures$h <- bw_class$h
  }

  # --- Gap VaR KDE vs empírico (si hay VaR) ---
  if (!is.null(var_kde) && !is.null(var_empirical) && !is.null(levels)) {
    rel_gap <- (var_kde - var_empirical) / var_empirical
    top <- length(levels)  # nivel más alto
    g <- rel_gap[top]
    assessment$var_gap_level <- if (abs(g) < d$var_gap_moderate) "close"
      else if (abs(g) < d$var_gap_notable) "moderate" else "notable"
    assessment$var_gap_direction <- if (g >= 0) "above" else "below"
    assessment$figures$levels        <- levels
    assessment$figures$var_kde       <- var_kde
    assessment$figures$var_empirical <- var_empirical
    assessment$figures$var_rel_gap   <- rel_gap
  }

  # --- Calidad global de la estimación (si hay bandwidth) ---
  if (!is.null(assessment$bandwidth_quality)) {
    assessment$estimation_quality <- if (sample_size == "small" || outlier_level == "many") {
      "limited"
    } else if (assessment$bandwidth_quality == "balanced" && sample_size == "large") {
      "good"
    } else {
      "moderate"
    }
  }

  assessment
}


# ============================================================
# 6. TEXT BUILDERS  [Sub-bloque 2E]
# ============================================================
#
# Únicas funciones de calc.R que generan texto. Devuelven SIEMPRE character.
# Consumen EXCLUSIVAMENTE el Assessment (nunca los resultados crudos). La
# conversión a htmltools es responsabilidad de mod_tool.R.
#
# ------------------------------------------------------------
# ESTILO DE REDACCIÓN CONGELADO (toda la plataforma)
# ------------------------------------------------------------
# Lenguaje PRUDENTE. Fórmulas admitidas (equivalentes ES de los términos guía):
#   "podría / podrían indicar", "podría sugerir", "parece coherente con",
#   "conviene considerar" / "considere", "podría beneficiarse de".
# PROHIBIDAS las categóricas: "incorrecto", "erróneo", "mal", "definitivamente",
#   "debe" / "hay que", "seguro".
# Bloques INDEPENDIENTES y CORTOS (Quality / Diagnosis / Recommendation); nunca
# párrafos largos. El texto solo cita cifras ENTERAS (n, nº de outliers); los
# decimales, porcentajes y VaR se muestran formateados en la UI (metric cards,
# tablas), no aquí.

#' Notas del diagnóstico previo al cálculo (feature E)
#'
#' @section Tipo: Auxiliar.
#' @param assessment Salida de build_assessment().
#' @return Vector de character (frases cortas e independientes), posiblemente vacío.
build_diagnostic_notes <- function(assessment) {
  a <- assessment; f <- a$figures; notes <- character(0)

  notes <- c(notes, switch(a$sample_size,
    small    = glue::glue("La muestra es reducida (n = {f$n}); las estimaciones de la cola podrían ser poco estables. Conviene interpretarlas con cautela."),
    moderate = glue::glue("El tamaño muestral (n = {f$n}) es moderado; los resultados parecen razonables, aunque la cola podría beneficiarse de más datos."),
    large    = glue::glue("El tamaño muestral (n = {f$n}) es amplio, lo que favorece una estimación estable.")
  ))

  if (a$skewness_level == "high" && a$skewness_direction == "right") {
    notes <- c(notes, "La marcada asimetría a la derecha parece coherente con datos de severidad.")
  } else if (a$skewness_level == "high") {
    notes <- c(notes, "La muestra presenta una asimetría marcada que podría influir en la forma estimada.")
  } else if (a$skewness_level == "moderate") {
    notes <- c(notes, "La muestra presenta una asimetría moderada.")
  }

  if (a$tail_behavior == "heavy") {
    notes <- c(notes, "La curtosis elevada podría indicar colas más pesadas que la normal; el VaR alto podría ser sensible a ellas.")
  } else if (a$tail_behavior == "light") {
    notes <- c(notes, "Las colas parecen más ligeras que las de una distribución normal.")
  }

  if (a$outlier_level == "many") {
    notes <- c(notes, glue::glue("Se observan {f$outlier_count} valores extremos; conviene comparar Silverman con Scott para evaluar su efecto en la cola."))
  } else if (a$outlier_level == "few") {
    notes <- c(notes, glue::glue("Se detectan {f$outlier_count} posibles valores extremos; su efecto sobre la cola podría ser limitado."))
  }

  notes
}

#' Mensaje dinámico del ancho de banda (feature D)
#'
#' @section Tipo: Pública.
#' @param assessment Salida de build_assessment() con bandwidth_quality.
#' @return character(1).
build_bandwidth_message <- function(assessment) {
  q <- assessment$bandwidth_quality
  if (is.null(q)) {
    return("Ajuste el método o el ancho de banda para observar su efecto sobre la estimación.")
  }
  switch(q,
    undersmoothing = "Ancho de banda reducido respecto a los métodos automáticos. Mayor sensibilidad al ruido; podría producirse undersmoothing.",
    oversmoothing  = "Ancho de banda elevado respecto a los métodos automáticos. Mayor suavizado; la densidad podría ocultar estructura de la cola.",
    "Ancho de banda próximo a los métodos automáticos. La estimación parece equilibrada."
  )
}

#' Actuarial Insights en bloques independientes (feature G)
#'
#' @section Tipo: Pública.
#' @param assessment Salida de build_assessment() completa (post-cálculo).
#' @return list(quality, diagnosis, recommendation), cada uno vector de character.
build_insights <- function(assessment) {
  a <- assessment

  # --- Quality ---
  quality <- character(0)
  if (!is.null(a$estimation_quality)) {
    quality <- c(quality, switch(a$estimation_quality,
      good     = "La estimación parece robusta para el tamaño y la calidad de la muestra.",
      moderate = "La estimación parece razonable, con reservas por el tamaño muestral o los valores extremos.",
      limited  = "La fiabilidad de la estimación podría ser limitada; conviene tratar los resultados como orientativos."
    ))
  }
  if (!is.null(a$bandwidth_quality)) {
    quality <- c(quality, switch(a$bandwidth_quality,
      undersmoothing = "El ancho de banda seleccionado podría estar sobreajustando el ruido.",
      oversmoothing  = "El ancho de banda seleccionado podría estar sobre-suavizando la cola.",
      "El ancho de banda parece próximo a los métodos automáticos."
    ))
  }

  # --- Diagnosis ---
  diagnosis <- character(0)
  if (a$skewness_level %in% c("high", "moderate")) {
    dir <- if (a$skewness_direction == "right") "a la derecha" else "a la izquierda"
    diagnosis <- c(diagnosis, glue::glue("La densidad parece asimétrica {dir}, patrón que podría ser coherente con una variable de severidad."))
  } else if (a$skewness_level == "symmetric") {
    diagnosis <- c(diagnosis, "La densidad parece aproximadamente simétrica.")
  }
  if (a$tail_behavior == "heavy") {
    diagnosis <- c(diagnosis, "La cola parece más pesada que la de una normal; el VaR alto podría ser sensible a ella.")
  }
  if (!is.null(a$var_gap_level)) {
    intensidad <- switch(a$var_gap_level, close = "muy próximo", moderate = "moderadamente", "notablemente")
    sentido <- if (a$var_gap_direction == "above") "por encima" else "por debajo"
    diagnosis <- c(diagnosis, glue::glue("El VaR por kernel parece situarse {intensidad} {sentido} del cuantil empírico, lo que podría reflejar el reparto de la masa de cola por el suavizado."))
  }
  if (a$outlier_level == "many") {
    diagnosis <- c(diagnosis, glue::glue("Los {a$figures$outlier_count} valores extremos podrían influir de forma relevante en la cola derecha."))
  }

  # --- Recommendation ---
  recommendation <- c("Conviene contrastar el resultado con al menos dos métodos de ancho de banda antes de fijar una conclusión.")
  if (!is.null(a$bandwidth_quality)) {
    if (a$bandwidth_quality == "undersmoothing") {
      recommendation <- c(recommendation, "La estimación podría beneficiarse de un ancho de banda algo mayor para reducir el ruido.")
    } else if (a$bandwidth_quality == "oversmoothing") {
      recommendation <- c(recommendation, "La estimación podría beneficiarse de un ancho de banda algo menor para no ocultar la cola.")
    }
  }
  if (a$sample_size == "small" || a$tail_behavior == "heavy") {
    recommendation <- c(recommendation, "Con esta muestra, el VaR extremo podría beneficiarse de datos adicionales o de un contraste con métodos paramétricos.")
  }

  list(quality = quality, diagnosis = diagnosis, recommendation = recommendation)
}


# ============================================================
# 7. ORCHESTRATOR  [Sub-bloque 2F]
# ============================================================
#
# kde_analyze() es EXCLUSIVAMENTE un coordinador: ensambla el pipeline llamando a
# las funciones de los bloques anteriores. NO contiene fórmulas matemáticas ni
# lógica estadística nueva (toda vive en Kernels/Bandwidth/Estimation/Diagnostics/
# Assessment/Text). Su única aritmética es higiene de entrada (descartar valores
# no finitos) y empaquetado del resultado.
#
# ------------------------------------------------------------
# CONTRATO DE SALIDA CONGELADO (API pública del motor)
# ------------------------------------------------------------
# kde_analyze() devuelve SIEMPRE una lista con estos bloques, y solo estos. La UI
# (mod_tool.R) consume EXCLUSIVAMENTE este objeto:
#   $input       : n_input, n_used, n_removed, kernel, method, levels, domain
#   $bandwidth   : h, method, automatic, classification (classify_bandwidth)
#   $estimation  : curve (data.frame x/density/cdf), var (data.frame por nivel)
#   $diagnostics : sample_diagnostics (stats, outliers, is_small_sample)
#   $assessment  : build_assessment (estado categórico + figures)
#   $text        : diagnostic_notes, bandwidth_message, insights(quality/diagnosis/recommendation)
#   $metadata    : tool, tool_version, engine_version, kernel, bandwidth_method,
#                  h, n_used, seed, created_at
#
# Los campos de $metadata garantizan la REPRODUCIBILIDAD del resultado: versión
# del motor y de la herramienta, kernel y método de bandwidth aplicados, semilla
# (cuando la entrada procede de datos generados) y marca temporal. tool_version y
# seed los aporta el llamante (mod_tool.R los conoce; calc.R no lee manifest.yml
# ni fija semillas), y son NULL si no se proporcionan.

#' Ejecuta el pipeline completo de KDE y devuelve el contrato de salida
#'
#' Coordinador puro. No implementa matemática: invoca los bloques y empaqueta.
#'
#' @section Tipo: Pública.
#' @param x Vector numérico de la variable (severidad). Se descartan los valores
#'   no finitos (NA/NaN/Inf) como higiene de entrada.
#' @param kernel Nombre del kernel (uno de KDE_KERNELS).
#' @param method Método de bandwidth (nombre de KDE_BW_METHODS o "manual").
#' @param h_manual Ancho de banda manual (> 0), obligatorio si method = "manual".
#' @param levels Niveles de VaR (probabilidades en (0,1)).
#' @param tool_version Versión de la herramienta (de manifest.yml), solo para
#'   metadata/reproducibilidad. NULL si no se aporta.
#' @param seed Semilla con la que se generó la entrada, solo para
#'   metadata/reproducibilidad. NULL si la entrada no es generada. calc.R no fija
#'   la semilla: únicamente la registra.
#' @return Lista con los bloques del contrato congelado (ver cabecera del bloque).
kde_analyze <- function(x,
                        kernel       = KDE_DEFAULTS$default_kernel,
                        method       = KDE_DEFAULTS$default_bw_method,
                        h_manual     = NULL,
                        levels       = KDE_DEFAULTS$default_levels,
                        tool_version = NULL,
                        seed         = NULL) {
  kernel <- match.arg(kernel, KDE_KERNELS)

  # --- Higiene de entrada (no es estadística: solo descarta no-finitos) ---
  n_input <- length(x)
  x_used  <- x[is.finite(x)]
  n_used  <- length(x_used)
  if (n_used < 2L) {
    stop("Se necesitan al menos 2 observaciones finitas para el análisis KDE.")
  }

  # --- Pipeline (cada paso delega en su bloque) ---
  bw       <- bw_resolve(x_used, method, h_manual)
  grid     <- make_grid(x_used, bw$h)
  density  <- kde_density(x_used, grid, bw$h, kernel)
  cdf      <- kde_cdf(x_used, grid, bw$h, kernel)
  var_kde  <- kde_quantile(x_used, bw$h, kernel, levels)
  var_emp  <- empirical_quantile(x_used, levels)
  diag     <- sample_diagnostics(x_used)
  bw_class <- classify_bandwidth(bw$h, bw$automatic)
  assess   <- build_assessment(diag, bw_class, var_kde, var_emp, levels)
  text     <- list(
    diagnostic_notes  = build_diagnostic_notes(assess),
    bandwidth_message = build_bandwidth_message(assess),
    insights          = build_insights(assess)
  )

  # --- Empaquetado del contrato (sin recomputar nada estadístico) ---
  list(
    input = list(
      n_input   = n_input,
      n_used    = n_used,
      n_removed = n_input - n_used,
      kernel    = kernel,
      method    = bw$method,
      levels    = levels,
      domain    = range(x_used)
    ),
    bandwidth = list(
      h              = bw$h,
      method         = bw$method,
      automatic      = bw$automatic,
      classification = bw_class
    ),
    estimation = list(
      curve = data.frame(x = grid, density = density, cdf = cdf),
      var   = data.frame(
        level         = levels,
        var_kde       = var_kde,
        var_empirical = var_emp,
        rel_gap       = assess$figures$var_rel_gap  # reutiliza el ya calculado en Assessment
      )
    ),
    diagnostics = diag,
    assessment  = assess,
    text        = text,
    metadata = list(
      tool             = "kernel-density",
      tool_version     = tool_version,
      engine_version   = KDE_ENGINE_VERSION,
      kernel           = kernel,
      bandwidth_method = bw$method,
      h                = bw$h,
      n_used           = n_used,
      seed             = seed,
      created_at       = Sys.time()
    )
  )
}

#' Genera datos de ejemplo de severidad (lognormal), con propósito demostrativo
#'
#' Muestra sintética realista para el arranque "cero pantalla vacía" y para
#' demostrar el KDE: severidad lognormal (asimetría positiva, cola derecha con
#' valores extremos naturales). Con semilla fija es reproducible. Genera la misma
#' distribución que el CSV incluido en data/example_data.csv.
#'
#' CONTRATO DEL DATASET (data/example_data.csv):
#'   - claim_id    : character. Identificador de siniestro (CLM00001...). No NA.
#'   - loss_amount : numeric.   Importe de siniestro (severidad). Unidades:
#'                   monetarias (u.m.). Dominio esperado: (0, +Inf). Sin NA.
#' La columna del contrato de datos del proyecto es loss_amount (apartado 7.6).
#'
#' @section Tipo: Pública.
#' @param n Número de observaciones.
#' @param seed Semilla opcional para reproducibilidad.
#' @return data.frame con claim_id (character) y loss_amount (numeric, > 0).
make_example_data <- function(n = 500L, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  # Lognormal de severidad: mediana ~ exp(6) ~ 403, cola derecha marcada.
  loss <- stats::rlnorm(n, meanlog = 6, sdlog = 0.9)
  data.frame(
    claim_id    = sprintf("CLM%05d", seq_len(n)),
    loss_amount = round(loss, 2),
    stringsAsFactors = FALSE
  )
}
