# Tool-02 — Contrato de estimación e incertidumbre (v1.1.0)

| Campo | Valor |
|---|---|
| **Bloque** | B10 — metodología y contrato. **Solo diseño** |
| **ADR** | ADR-030 |
| **Estado** | Propuesta. **Nada implementado.** Tool-02 permanece en v1.0.2 |
| **Baseline** | v1.0.2, funcionalmente intacto (ADR-026 · 027 · 028 · 029) |
| **Fecha** | 2026-08-30 |

---

## 1. Modelo conceptual

Cuatro niveles, deliberadamente separados:

```
  distribución / modelo            ¿qué familia?              (ranking, ADR-029)
            ↓
  método de estimación             ¿cómo estimo θ?            MLE · MoM · L-mom · PM
            ↓
  theta_hat                        estimación puntual         fit$params  (v1.0.2)
            ↓
  método de incertidumbre          ¿cuánto me fío de θ̂?       analítico · bootstrap
            ↓
  SE · varianza · sesgo · IC · distribución del estimador     fit$inference (NUEVO)
```

La separación no es estética. Cada nivel tiene un modo de fallo propio y debe poder
fallar sin arrastrar a los demás: una distribución puede ajustarse y su incertidumbre
no ser calculable; un método analítico puede no ser válido y el bootstrap sí.

### 1.1 Dos incertidumbres que no deben confundirse

| | Pregunta | Estado en el proyecto |
|---|---|---|
| **Incertidumbre de modelo** | ¿Es Lognormal la distribución correcta? | **H4, abierta.** El ΔAIC de ADR-021 la aproxima mal. **Fuera del alcance de v1.1** |
| **Incertidumbre de parámetro** | Dado que uso Lognormal, ¿cuánto varía `sdlog`? | **Objeto de v1.1** |

Una `sdlog` con un intervalo estrechísimo no dice **nada** sobre si la Lognormal era
la familia adecuada. La interfaz no debe permitir esa lectura.

### 1.2 Dos bootstraps que no deben unificarse

| | Este contrato (v1.1) | ADR-008 (diferido) |
|---|---|---|
| Tipo | **No paramétrico iid** | **Paramétrico** |
| Remuestrea | La muestra observada, con reemplazamiento | Simula de la distribución ajustada |
| Mide | Variabilidad del estimador | Distribución nula de un estadístico GoF |
| Responde | ¿Cuánto varía θ̂? | ¿Qué p-valor tiene este KS con parámetros estimados? |

**No comparten API ni semántica.** Un futuro `bootstrap_parametric()` para GoF debe
ser una función distinta, con nombre distinto, aunque comparta primitivas.

---

## 2. Terminología

| Término | Definición operativa |
|---|---|
| `theta_hat` | Estimación puntual, `fit$params`. Lista nombrada; nombres y cardinalidad varían por distribución |
| `theta_star_b` | Estimación de la réplica bootstrap *b* |
| `bootstrap_se` | `sd(theta_star)` |
| `bootstrap_variance` | `var(theta_star)` |
| `bootstrap_bias` | `mean(theta_star) - theta_hat` |
| `MSE` | `Var + Bias²`. **No se publica en v1.1** (§8.3) |
| Inferencia analítica | Basada en la **matriz de información observada**, `Sigma = J(theta_hat)^-1` |
| `H(theta_hat)` | Hessiana de la **NEGATIVE** log-verosimilitud en el óptimo |
| `available` | El método es aplicable en principio a esta distribución/estimador |
| `valid` | El método se ha ejecutado **y** ha superado sus diagnósticos |
| `computed` | El usuario lo ha solicitado y se ha ejecutado |

### 2.1 Convención de signo — heredada del material académico

El optimizador **minimiza** `NLL(θ) = -log L(θ)`. Por tanto:

```
optim$value  =  NLL(theta_hat)
L(theta_hat) =  exp(-optim$value)          <- NO exp(+optim$value)
```

Consecuencia directa, y por eso importa: la Hessiana que devuelve `optim(hessian = TRUE)`
es la de la **NLL**, es decir, la **matriz de información observada** `J(theta_hat)`.
La covarianza asintótica es su inversa **sin cambio de signo**:

```
Cov(theta_hat)  ≈  J(theta_hat)^-1
```

**Precisión terminológica (corrección B10).** Conviene no llamar "Fisher" a esta
matriz sin cualificar:

```
J(theta_hat) = -∇² l(theta_hat) = ∇²[ -l(theta_hat) ]      <- información OBSERVADA
                                                              (evaluada sobre los datos)

I(theta)     = E[ J(theta) ]                                <- información ESPERADA de Fisher
                                                              (esperanza teórica)
```

Lo que devuelve `optim(hessian = TRUE)` en el óptimo es `J(theta_hat)`, la
**observada**. `I(theta)` requiere una esperanza analítica que solo existe en forma
cerrada para algunas familias. Ambas son asintóticamente equivalentes bajo
condiciones de regularidad, pero **no son la misma cantidad** y B12 usará la
observada.

Un error de signo aquí produce varianzas negativas. El contrato exige verificar
positividad de la diagonal (§4.3) precisamente como red frente a ese error.

---

## 3. Contrato de datos

### 3.1 Dónde vive la inferencia

`fit$params` **conserva su significado actual** —estimaciones puntuales— y no se
toca. La inferencia se añade en una capa separada.

Se evaluaron tres alternativas:

| Alternativa | Valoración |
|---|---|
| **A. Enriquecer `fit$params`** con listas por parámetro | **Rechazada.** Rompe todo consumidor actual: `.vm_fits_and_export` construye la cadena `valores` con `names(fit$params)` y `vapply(fit$params, .fmt_num, ...)`; `output$tabla_parametros` itera igual. Convertir cada parámetro en lista rompe ambos |
| **B. `fit$inference` como capa hermana** | **Recomendada.** Aditiva, no rompe nada, separa estimación de incertidumbre igual que el modelo conceptual |
| **C. Objeto `inference` fuera del `fit`, indexado por id** | Viable y con ventaja en serialización, pero **rompe la localidad**: hoy todo lo de una distribución está en su `fit`. Añade una indirección sin beneficio claro |

**Se propone B**, con una excepción justificada: las réplicas **no** se almacenan por
parámetro (§3.3).

### 3.2 Estructura propuesta

```r
fit$inference <- list(
  status  = "not_requested",   # not_requested | partial | complete | failed
  sample  = list(n = , fingerprint = ),          # §6
  config  = list(...),                           # §6.1 — configuración reproducible

  parameters = list(
    shape = list(
      name = "shape", estimate = 1.8130, estimation_method = "mle",
      support = "positive", transformation = "log",     # §4.4

      analytical = list(
        available = TRUE, valid = TRUE, method = "observed_information",
        variance = , se = , ci_level = 0.95, ci_lower = , ci_upper = ,
        diagnostics = list(hessian_finite = , symmetric = , condition_number = ,
                           invertible = , diag_positive = , at_boundary = ,
                           reason_if_invalid = NA_character_)
      ),

      bootstrap = list(
        available = TRUE, computed = TRUE, type = "nonparametric_iid",
        B_requested = 1000L, B_success = , B_failed = , success_rate = ,
        seed = , mean = , variance = , se = , bias = ,
        ci_level = 0.95, ci_method = "percentile", ci_lower = , ci_upper = ,
        diagnostics = list(failure_counts = c(...), reason_if_invalid = NA_character_)
      )
    ),
    scale = list( ... )
  ),

  replicates = <matriz B x k>,                    # §3.3
  warnings   = character(0),
  errors     = character(0)
)
```

### 3.3 Réplicas: matriz, no listas anidadas

Almacenarlas dentro de cada parámetro duplicaría `B × k` valores y rompería la
correlación entre parámetros. Se propone **una única matriz `B × k`**, filas =
réplicas válidas, columnas = parámetros, con `dimnames`.

Cuatro razones, todas verificables:

1. **Memoria.** B=5000, k=3 → una matriz de 15.000 doubles (≈120 KB). Anidada por
   parámetro, la misma información se replica y se fragmenta.
2. **Correlación preservada.** La fila *b* es un vector θ*ᵦ **conjunto**. Si se
   descompone por parámetro se pierde el emparejamiento, y con él la posibilidad de
   §7 (propagación a medidas de riesgo), que necesita θ*ᵦ completo.
3. **Serialización.** Una matriz numérica es trivialmente exportable.
4. **Trazabilidad.** El número de filas **es** `B_success`: no hay dos contadores que
   puedan desincronizarse.

Las réplicas **se conservan internamente** y **no** entran en el export estándar
(§8.4). Se anota además una decisión abierta sobre el tope de memoria (§9, OD-7).

### 3.4 Compatibilidad hacia atrás

- `fit$params`, `fit$logLik`, `fit$converged`, `fit$method`: **sin cambio**.
- `.vm_fits_and_export`: añade `inference` al `fits` del View Model. Aditivo.
- `export_table`: **sin cambio** en v1.1 salvo las columnas de §8.4, que se añaden al
  final.
- `schema_version`: 1.1.0 → **1.2.0**, cambio **aditivo** — **cuando `inference` se
  exponga**. **NO en B12.2:** allí `inference` es **opt-in** (`.fit_one(..., inference = TRUE)`),
  `dist_fit_analyze()` no lo activa y ningún consumidor lo produce, de modo que el
  contrato serializado productivo no cambia y **no procede el bump**. Se hará en B16,
  cuando el View Model y el export lo publiquen. Anunciar antes un campo que nadie
  emite sería una promesa vacía en el schema.
- `decision_engine_version`: **sin cambio**. La incertidumbre de parámetro no
  interviene en el criterio de recomendación.

---

## 4. Contrato de inferencia analítica

### 4.1 Alcance

Solo **MLE**. Para MoM, L-momentos y PM **no se inventan fórmulas analíticas
genéricas**: su incertidumbre se obtiene por bootstrap. Existen resultados
asintóticos para MoM y L-momentos, pero son específicos por distribución y su
derivación no está en el alcance de v1.1.

### 4.2 Formulación

```
H(theta_hat) = ∇²[ -l(theta) ] |_(theta = theta_hat)       (k x k, información observada)
Sigma_hat    = H(theta_hat)^-1
SE_j         = sqrt( Sigma_hat[j, j] )
IC_j         = theta_hat_j ± z_(1-alpha/2) · SE_j          (en la escala adecuada, §4.4)
```

Multiparamétrico desde el diseño: `k ≥ 1`, matriz completa, no derivadas por separado.

### 4.3 Cadena de validación — publicar solo lo fiable

Cada comprobación debe poder fallar de forma **declarada**:

| # | Comprobación | Si falla |
|---|---|---|
| 1 | Óptimo válido (`converged`, guardas ADR-027 superadas) | `available = FALSE` |
| 2 | Todos los elementos de `H` finitos | `valid = FALSE`, `reason = "hessian_nonfinite"` |
| 3 | `H` simétrica dentro de tolerancia numérica | `valid = FALSE`, `reason = "hessian_asymmetric"` |
| 4 | `H` invertible | `valid = FALSE`, `reason = "hessian_singular"` |
| 5 | Número de condición aceptable | `valid = FALSE`, `reason = "ill_conditioned"` — **umbral abierto, OD-4** |
| 6 | `diag(Sigma) > 0` | `valid = FALSE`, `reason = "negative_variance"` |
| 7 | Parámetro no en la frontera del espacio | `valid = FALSE`, `reason = "boundary"` |

**Regla dura:** si cualquiera falla, **no se publica SE ni IC**. La interfaz declara
que la inferencia analítica no está disponible, indica el motivo y ofrece bootstrap.
Un SE engañoso es peor que ningún SE — es el mismo principio de ADR-008 y §1.8 de la
arquitectura.

### 4.4 Parámetros restringidos

Un IC de Wald sobre un parámetro positivo puede cruzar el cero y producir un
intervalo imposible. El contrato prevé por parámetro:

```
support                 # "positive" | "unit_interval" | "real"
transformation          # log | logit | identity
inverse_transformation
```

El procedimiento previsto —construir el IC en la escala transformada y devolverlo con
la inversa— **no se congela aquí**: qué transformación aplica a cada parámetro de cada
distribución es **OD-5**.

**Nota importante (redactada con precisión, corrección B10).** Esto afecta **solo** a
la inferencia analítica. Sobre el bootstrap percentil cabe afirmar lo siguiente, y
**solo** lo siguiente:

> Si las réplicas almacenadas son **exclusivamente estimaciones válidas dentro del
> espacio paramétrico** —que es lo que garantizan las guardas de ADR-027 al descartar
> las réplicas degeneradas—, entonces el intervalo percentil construido con sus
> cuantiles queda **dentro del rango de esas réplicas válidas** y, por tanto, respeta
> ese espacio paramétrico.

Es una propiedad **condicionada al filtrado de réplicas**, no una garantía universal
de todo bootstrap. Un bootstrap que conservara réplicas inválidas, o un método de IC
distinto del percentil —BCa aplica una corrección que puede desplazar los extremos
fuera del rango observado—, no la hereda.

### 4.5 Casos con solución conocida — banco de validación

| Distribución | Parámetro | SE conocido (de la información esperada `I(theta)`) |
|---|---|---|
| Normal | `mean` (σ conocida) | `SE = σ/√n` |
| Normal | `sd` | `SE = σ/√(2n)` |
| Poisson | `lambda` | `SE = √(λ/n)` |
| Exponencial | `rate` | `SE = λ/√n` |

Las cuatro tienen forma cerrada y sirven de contraste exacto contra la Hessiana
numérica (B12). La Normal y la Exponencial están en el catálogo actual; la Poisson
está en la familia discreta.

---

## 5. Contrato de bootstrap

### 5.1 Algoritmo

```
Dada la muestra común X = analysis$sample$x, de tamaño n:
  fijar semilla
  para b = 1..B:
      X*_b       <- sample(X, n, replace = TRUE)
      theta*_b   <- .estimate(id, X*_b, method)     # MISMO estimador, MISMA config
      aplicar las guardas de ADR-027
      registrar éxito o clasificar el fallo
  agregar sobre las réplicas válidas
```

### 5.2 Reglas derivadas, no elegidas

**(a) Se remuestrea de `analysis$sample$x`, no de la columna original.** ADR-026
define la muestra común como propiedad del **análisis**. Volver a ejecutar la capa 0.5
sobre cada réplica haría variar `n` entre réplicas y destruiría la comparabilidad.

**(b) Genérico respecto al estimador.** Una sola función que recibe el id de la
distribución y el método, y llama a `.estimate()`. **Prohibido** el patrón
`bootstrap_gamma_mle()`, `bootstrap_weibull_mle()`. El despachador ya existe y ya
resuelve las cuatro combinaciones.

**(c) Las guardas de ADR-027 se aplican a cada réplica.** No son un obstáculo: son
la fuente natural de la taxonomía de fallos. Una réplica cuyo `scale` cae en el rango
subnormal **debe** contarse como fallo, no colarse en el agregado.

### 5.3 Taxonomía de estados por réplica

| Estado | Origen en el código actual |
|---|---|
| `success` | `converged = TRUE` y guardas superadas |
| `optimizer_failure` | `.mle_optim` sin solución finita, o `convergence != 0` |
| `guard_failure_boundary` | Guarda A de ADR-027: parámetro subnormal |
| `guard_failure_implausible` | Guarda B de ADR-027: `mean(log f)` sobre la cota |
| `invalid_parameters` | `.estimate()` devuelve `NULL`: el método no procede con esa réplica (p. ej. Pareto MoM con CV²≤1) |
| `support_failure` | La réplica deja menos de `n_params + 1` observaciones utilizables |
| `nonfinite_result` | `logLik` o parámetros no finitos |

Se propone **desdoblar `guard_failure`** en sus dos guardas: son diagnósticos
distintos —una es numérica, la otra estadística— y distinguirlas es informativo.

**Las réplicas fallidas nunca se ignoran en silencio.** Se conservan
`B_requested`, `B_success`, `B_failed`, `success_rate` y el recuento por estado.

### 5.4 Configuración

| Parámetro | Decisión |
|---|---|
| `B` por defecto | **1000** |
| Presets | 500 · 1000 · 2000 · 5000 |
| `B` personalizado | Sí, en configuración avanzada |
| Ejecución | **Bajo demanda**, nunca automática |
| Alcance | **La distribución seleccionada en el ranking**, no necesariamente la recomendada |
| Simultáneo para todas | **No** en v1.1 |
| `ci_level` | Por defecto 0,95; **cualquier valor** en (0,1) con validación estricta |
| Método de IC | **Percentil**. BCa, studentized y bootstrap-t quedan fuera de v1.1 |

**5000 no se fija como valor por defecto.** B17 medirá antes de decidir.

### 5.5 Sin umbrales de fiabilidad

**No se define** ningún umbral del tipo `success_rate < 0,90 → no fiable`, ni
etiquetas *Alta/Media/Baja estabilidad*. Serían invenciones sin evidencia. Hasta que
B17 aporte datos: **métricas objetivas y avisos justificables**. Es la misma lección
de ADR-021, donde unos umbrales fijados por intuición sobre una magnitud sin escala
estable produjeron una confianza inservible.

---

## 6. Contrato de reproducibilidad

**Una semilla por sí sola no garantiza reproducibilidad.** El mismo `seed = 42817`
produce resultados distintos si cambia el dato, la distribución, el estimador, `B` o
la versión del algoritmo.

### 6.1 Configuración reproducible

```r
list(
  name = "Validación Burr agosto",
  seed = 42817L, B = 5000L, ci_level = 0.95,
  uncertainty_method = "bootstrap",
  distribution = "burr", estimation_method = "pm",
  estimation_config = list(percentiles = c(0.25, 0.50, 0.75)),
  variable = "Cost_claims_year",
  sample_fingerprint = "sha256:...",     # §6.2
  n_used = 919L,
  tool_version = "1.1.0", schema_version = "1.2.0",
  rng_kind = "Mersenne-Twister",         # `RNGkind()`, por si cambia el default de R
  created_at = "2026-.."
)
```

### 6.2 Huella de la muestra

Se propone `sha256` sobre la **muestra común ordenada**, serializada con precisión
completa, más `n`. Ordenar la hace invariante al orden de las filas del CSV —dos
ficheros con las mismas observaciones en distinto orden son el mismo análisis— y
sensible a cualquier cambio de valor o de tamaño. Requiere `digest` o equivalente:
**dependencia nueva, OD-6**.

### 6.3 Persistencia — la arquitectura restringe las opciones

Dos restricciones duras del proyecto:

- **Regla 7:** `calc.R` no puede depender de Shiny. El *contrato* puede vivir en
  `calc.R`; el *almacenamiento* no.
- **Fase 1 del roadmap:** despliegue manual en shinyapps.io, sin autenticación ni
  persistencia. El almacenamiento de esa plataforma es **efímero**: se pierde al
  reiniciar la instancia.

| Opción | Viabilidad hoy | Valoración |
|---|---|---|
| **Estado de sesión** | Inmediata | Se pierde al cerrar. Suficiente para comparar dos configuraciones en una sesión |
| **Exportar/importar fichero** | Inmediata, reutiliza `mod_export_csv` | **Portable, versionable, adjuntable a un informe.** Encaja con "CSV como único formato de exportación" si se usa una fila por configuración |
| **`localStorage` del navegador** | Requiere JS | Choca con la regla 16 (nada de HTML/CSS/JS suelto) y con la promesa de privacidad |
| **Servidor autenticado** | **No disponible** | Fase 4 del roadmap |

**Recomendación:** sesión + exportar/importar. **OD-8**, requiere tu aprobación.

---

## 7. Extensibilidad futura (no v1.1)

Las réplicas se conservan porque habilitan, sin recalcular:

```
theta*_b  ->  VaR(theta*_b)  ->  distribución de VaR
          ->  TVaR(theta*_b) ->  distribución de TVaR
          ->  P(X > x | theta*_b)
```

Por eso la matriz `B × k` preserva el emparejamiento entre parámetros (§3.3): sin él,
esta evolución es imposible. **No se implementa en v1.1**, pero el contrato no la
bloquea.

---

## 8. Interfaz y exportación (solo contrato)

### 8.1 Vista principal

| Parámetro | Estimación | SE | IC 95 % |
|---|---|---|---|

Para MLE con analítica válida. Si no lo es: se declara el motivo y se ofrece bootstrap.

### 8.2 Panel avanzado, bajo demanda

Método de incertidumbre (`Automático · Analítico · Bootstrap · Comparar`) · `B` ·
nivel de confianza · configuración reproducible · botón **Calcular incertidumbre**.

### 8.3 Resultados avanzados

SE y sesgo bootstrap, IC, `B_success / B_requested`, recuento de fallos por estado,
avisos y comparación analítico *vs* bootstrap. **MSE no se muestra.** Visualización
futura por parámetro: histograma de θ*, θ̂ marcado, límites del IC y, si existe,
la aproximación analítica superpuesta.

**ADR-029 se mantiene:** la leyenda de Plotly controla únicamente visibilidad.

### 8.4 Exportación

Columnas previstas: `distribucion`, `parametro`, `estimacion`,
`metodo_estimacion`, `metodo_incertidumbre`, `se`, `varianza`, `sesgo`, `ci_level`,
`ci_lower`, `ci_upper`, `B_requested`, `B_success`, `seed`, `sample_fingerprint`.
Las réplicas **no** entran en el export estándar; podrá existir un export avanzado.

### 8.5 DGP sintético

El θ verdadero puede usarse **en tests** para evaluar sesgo, cobertura y recuperación.
**En datos reales θ es desconocido**: la interfaz nunca debe presentar métricas que lo
requieran como si estuviera disponible.

---

## 9. OPEN DECISIONS

Ninguna se ha decidido. Ninguna bloquea B10; las marcadas bloquean su bloque.

| ID | Cuestión | Alternativas | Recomendación técnica | Bloquea |
|---|---|---|---|---|
| ~~OD-1~~ | Función objetivo de PM | — | **RESUELTA — verificada en R 4.4.1 (ADR-031, B11.1-R4):** **Normalized Quantile SSE**, `J = Σ(Q_θ(p_j)−q̂_j)² / s_Q²`. La normalización es **numérica**, no un estimador distinto: difiere por una constante positiva independiente de θ, luego mismo argmin (comprobado a precisión de máquina) | ~~B11~~ |
| ~~OD-13~~ | Elección de `s(x)` y caso `IQR = 0` | — | **RESUELTA en B11.1-R4 (ADR-031):** `s_Q = max(q̂) − min(q̂)`, si es **finita y > 0**. Si `s_Q = 0` → **REJECT** con diagnóstico de colapso de los cuantiles objetivo. **Sin epsilon, sin fallback `IQR`.** Mínimo de producto: **2 percentiles**, también en Exponencial | ~~B11.2~~ |
| ~~OD-2~~ | Política de identificabilidad de PM (m vs k) | — | **RESUELTA en política básica (ADR-031, B11.1-R4):** `m_requested < k` → REJECT; `m_requested ≥ k` → potencialmente identificable. **`m_effective` es solo diagnóstico**: no se congela suficiencia basada en él (los empates y el redondeo hacen que valores empíricos iguales sigan correspondiendo a probabilidades distintas) | ~~B11~~ |
| ~~Preset~~ | Configuración de percentiles por defecto | — | **RESUELTA en B11.1-R4 (ADR-031):** default **10/50/90**; **10/25/50/75/90** como ampliado; **25/50/75** como «Central / académico», **no** default | ~~B11.2~~ |
| **OD-14** | Pesos `w_j` del objetivo PM | (a) uniformes; (b) por varianza asintótica del cuantil muestral | **OPEN / DEFERRED.** Todo B11.1 usó `w_j = 1`. Preset y pesos son el mismo problema, pero **los pesos no son necesarios para liberar PM v1.1** | — (no bloquea) |
| **OD-17** | Selección condicionada al éxito en bootstrap | — | **OPEN / NON-BLOCKING.** Los resúmenes proceden de `L(θ̂*\|success)`, no necesariamente de `L(θ̂*)`. **La dirección y magnitud de la distorsión dependen del mecanismo de fallo y no se determinan en B13.** Mitigación: contadores y motivos siempre presentes | — (no bloquea) |
| **OD-18** | **Identidad de muestra entre vías de inferencia** | (a) huella también en el bloque analítico de B12; (b) identidad común del análisis **aguas arriba**, heredada por ambas vías; (c) equivalente contractual | **OPEN.** B13 lleva `data_fingerprint`; **B12 no**. B14 solo puede comprobar `n` —necesaria, no suficiente— y declara `sample_identity_verified = FALSE`. Sin identidad verificable, **una discrepancia en B15 sería inatribuible (¿método o dato?)**. (b) resuelve la clase, (a) solo el caso | **BLOCKS B15 COMPARISON** |
| ~~OD-3~~ | Compatibilidad de PM por distribución | — | **RESUELTA en B11.1 (ADR-031):** 7 continuas + Normal control; ninguna discreta. Gamma y Burr se mantienen | ~~B11~~ |
| ~~OD-4~~ | Umbral de condicionamiento de la Hessiana | — | **RESUELTA para B12 (ADR-033/034):** cadena estructural de 10 pasos con Cholesky; **`rcond` se publica como diagnóstico y NO invalida**; sin umbral y sin etiquetas. Motivos objetivos de invalidación: no finita, no PD, singular, covarianza inválida, SE inválidos. Una posible regla por condicionamiento se revisará en **B15** con evidencia de bootstrap | ~~B12~~ |
| ~~OD-5~~ | Transformación por parámetro | — | **RESUELTA (ADR-033/034):** cálculo en escala `u` y traslado por **método delta**; tabla **declarativa por parámetro** `DFIT_PARAM_TRANSFORM` (`identity` / `log` / **`logit`** para `prob`). Validada en B12.2 contra `Var(log σ̂) ≈ 1/(2n)` → `Var(σ̂) ≈ σ²/(2n)` | ~~B12~~ |
| ~~OD-16~~ | Política de intervalos de confianza | — | **RESUELTA (ADR-034):** **Wald marginal en escala transformada con retrotransformación monótona**, nivel configurable, defecto 95 %. `log` → IC estrictamente positivo y asimétrico; `logit` → IC dentro de (0,1). **No `θ̂ ± z·SE_θ` para parámetros restringidos; no se trunca a posteriori** | ~~B12.2~~ |
| **OD-6** | Dependencia para el hash | (a) `digest`; (b) `openssl`; (c) huella propia sin dependencias | (a) o (c). El stack aprobado **no incluye ninguna**: exige tu autorización expresa | **B13** |
| **OD-7** | Tope de memoria de las réplicas | (a) sin tope; (b) tope de B; (c) descartar réplicas al cambiar de distribución | (c) + medir en B17. B=5000, k=3 son ~120 KB: probablemente no hay problema, pero conviene medirlo | B13 |
| **OD-8** | Persistencia de configuraciones | §6.3 | Sesión + exportar/importar | **B16** |
| **OD-9** | Resolución para la guarda B en bootstrap | (a) la del **original**; (b) recalcular por réplica | **(a)**. El remuestreo no crea valores nuevos, así que `unique(X*) ⊆ unique(X)` y la resolución por réplica solo puede ser **mayor**, aflojando la guarda de forma inconsistente entre réplicas. La resolución es propiedad del **dato**, no de la réplica | **B13** |
| **OD-10** | Dónde vive el motor de bootstrap | (a) `calc.R` de Tool-02; (b) `shared/actuarial/` desde el inicio | **(a)**. La regla 4 exige **2 o más consumidores** y hoy hay uno. Pero el catálogo prevé `bootstrap-mse/`: diseñar la API **como si fuera a promoverse** (sin estado, sin Shiny, argumentos explícitos) y promover cuando exista el segundo consumidor | B13 |
| **OD-11** | Umbrales de fiabilidad y etiquetas de estabilidad | (a) definir ahora; (b) diferir a B17 | **(b)**, explícito en §5.5 | B17 |
| **OD-12** | ¿Corrección de sesgo? | (a) publicar solo el sesgo; (b) ofrecer `theta_hat - bias` | **(a)** en v1.1. La corrección de sesgo **aumenta la varianza** y su conveniencia depende del caso; publicarla como estimación alternativa sin esa advertencia induce a error | B14 |

---

## 10. Plan B11–B17

| Bloque | Alcance | Entra si |
|---|---|---|
| **B11.1** | ✅ **CLOSED / APPROVED.** Benchmark metodológico de PM, verificado en R 4.4.1. Ver `tool02_pm_benchmark.md` §16 | — |
| **B11.2** | Percentile Matching: registro `DFIT_PM`, entrada en `.estimate()`, validación de configuración, tests | ✅ **Desbloqueado.** OD-1/2/3/13 resueltas y preset congelado |
| **B12** | Incertidumbre analítica MLE: Hessiana, covarianza, SE, IC, cadena de validación de §4.3 | OD-4, OD-5 resueltas |
| **B13** | Motor de bootstrap genérico, taxonomía de fallos, huella de muestra | OD-6, OD-9, OD-10 resueltas |
| **B14** | **Capa de validación del estimador: CONSUME y ORGANIZA las salidas de B12 y B13.** **NO recalcula** SE, sesgo ni IC percentil — B13 ya los produce (ver §10.2) | B13 cerrado |
| **B15** | Comparación analítico *vs* bootstrap y su diagnóstico | B12 y B14 cerrados |
| **B16** | UI, visualización y UX de reproducibilidad | OD-8 resuelta |
| **B17** | Validación integral, regresión, rendimiento, release v1.1.0 | Todo lo anterior |

### 10.2 Reparto de responsabilidades — CONGELADO

> **CORRECCIÓN (2026-09-03).** La tabla de §10 describía B14 como el bloque que
> «calcularía SE, varianza, sesgo e IC percentil». **Es incorrecto desde el
> cierre de B13.1:** ese bloque **ya los calcula**. Mantener aquella descripción
> habría llevado a **duplicar cálculos** en B14, con dos implementaciones de la
> misma cantidad y el riesgo de que divergieran.

| Bloque | Responsabilidad | Estado |
|---|---|---|
| **B12** | **Inferencia analítica MLE.** Información observada, `Σ_u`, `Σ_θ`, SE analíticos, IC Wald en escala transformada | CLOSED / APPROVED |
| **B13** | **Motor bootstrap no paramétrico Y SUS RESÚMENES.** Réplicas, `SE_boot`, `Bias_boot`, **IC percentil `type = 7`**, contabilidad de fallos, fingerprint | CLOSED / APPROVED |
| **B14** | **Capa de validación del estimador.** **CONSUME y ORGANIZA** lo que producen B12 y B13; **no recalcula nada** | Pendiente |
| **B15** | Comparación y diagnósticos analítico *vs* bootstrap | Pendiente |
| **B16** | Integración: UI, schema, export | Pendiente |

**Regla derivada:** si una cantidad ya la produce B12 o B13, **B14 la consume**.
Un segundo cálculo de la misma magnitud en otro bloque no es redundancia
inofensiva: es una fuente de divergencia silenciosa.

### 10.1 Contrato de tests

**A. Percentile Matching (B11).** Recuperación de parámetros en DGP sintéticos con
`n` grande; número variable de percentiles; los **tres presets congelados**
(10/50/90 default, 10/25/50/75/90 ampliado, 25/50/75 central); percentiles
personalizados, inválidos, repetidos y en configuraciones no identificables;
**rechazo con menos de 2 percentiles**; **rechazo cuando `s_Q = 0`** con el
diagnóstico de colapso de cuantiles objetivo; **rechazo cuando
`m_requested < k`**; parámetros restringidos; fallo del optimizador; invarianza de
escala donde la formulación la garantice; y **ausencia de avisos en consola** en
los DGP que los producían (Normal con `μ ≤ 0`, Gamma reescalada).

**B. Analítica MLE (B12).** Contraste **exacto** contra las formas cerradas de §4.5.
Y los fallos declarados: Hessiana singular, no finita, mal condicionada, parámetro en
frontera. Cada uno debe producir `valid = FALSE` con su `reason`, **nunca** un SE.

**C. Bootstrap (B13).** Reproducibilidad con semilla; identidad de resultado con
la misma configuración completa; cambio de semilla ⇒ réplicas distintas; coherencia
`B_requested = B_success + B_failed`; fallos parciales provocados
deliberadamente; sesgo y SE contra referencia independiente; IC percentil contenido
en el espacio paramétrico; **y que el remuestreo respeta ADR-026** (n constante, sin
re-derivar la capa 0.5).

**D. Analítico vs bootstrap (B15).** En DGP sintéticos con `n` grande,
`SE_analítico ≈ SE_bootstrap` dentro de tolerancia estadística. **No se exige
igualdad exacta**: son estimadores distintos de la misma cantidad.

**E. Regresión (B17).** Los 15 scripts de v1.0.2 pasan sin modificación: muestra común
(ADR-026), regresión de `Cost_claims_year`, guardas de ADR-027, ranking y
recomendación, contrato de interacción de ADR-029.

**F. Rendimiento (B17).** Benchmark con `B` = 500, 1000, 2000, 5000 sobre
distribuciones de coste dispar, incluyendo **Burr** (3 parámetros, numéricamente
costosa) y comparándola con Lognormal (forma cerrada). **Ninguna decisión de
rendimiento antes de medir.**

---

*Actuarial Tools by BMK — B10. Contrato propuesto, sin implementación. Baseline v1.0.2 intacto.*
