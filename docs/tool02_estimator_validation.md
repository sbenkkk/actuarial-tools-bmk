# Tool-02 — B14.0: contrato de validación del estimador

> **ESTADO: contrato FROZEN / APPROVED (ADR-037).**
> **B14.1 — IMPLEMENTED / NOT YET APPROVED.**
>
> El motor vive en `R/calc.R` §2c-quinquies (`.validate_estimator()`) y los
> tests en `tests/b14_estimator_validation_tests.R`. **No ejecutado todavía**:
> la aprobación requiere evidencia real de la suite B14 y de la regresión
> completa.
>
> No toca `R/calc.R`, `R/mod_tool.R`, `app.R`, `tests/`, `manifest.yml`,
> `shared/`, Decision Engine, ranking, schema ni `renv`.
> `DFIT_SCHEMA_VERSION` 1.1.0 · `manifest` 1.0.2.

---

## 1. Objetivo

**B14 no calcula inferencia. La consume, la organiza y valida su coherencia.**

B12 produce incertidumbre analítica del MLE. B13 produce réplicas bootstrap y sus
resúmenes. Ambos existen y están cerrados. Lo que falta es una capa que responda,
para un ajuste concreto:

> ¿Qué información de incertidumbre tenemos, de qué fuente, bajo qué
> configuración, y qué se puede y no se puede leer conjuntamente?

Esa pregunta hoy no tiene respuesta única: `fit$inference` (B12) y el objeto
bootstrap (B13) son estructuras separadas, con estados y niveles de confianza
propios, y sin ningún punto donde se compruebe que hablan del mismo ajuste.

**B14 es esa capa.** Su valor no está en producir números nuevos —no produce
ninguno— sino en **hacer explícito lo que hay, lo que falta y por qué**.

## 2. Frontera entre bloques — CONGELADA

| Bloque | Produce | Estado |
|---|---|---|
| **B12** | Información observada, `Σ_u`, `Σ_θ`, SE analíticos, IC Wald en escala transformada | CLOSED / APPROVED |
| **B13** | Réplicas, `SE_boot`, `Bias_boot`, **IC percentil `type = 7`**, contabilidad de fallos, fingerprint | CLOSED / APPROVED |
| **B14** | **Nada nuevo.** Consume, organiza y valida coherencia de B12/B13 | *este documento* |
| **B15** | Comparación y diagnósticos analítico *vs* bootstrap | Pendiente |
| **B16** | Integración: UI, schema, export, configuraciones | Pendiente |
| **B17** | Validación integral y release | Pendiente |

**Regla derivada:** si una cantidad ya la produce B12 o B13, **B14 la consume**.
Un segundo cálculo de la misma magnitud en otro bloque no es redundancia
inofensiva: es una fuente de divergencia silenciosa.

---

## 3. Principio central

**`fit$params` sigue siendo la estimación oficial.** B14 **nunca** la sustituye
por la media bootstrap, por `θ̂ − bias_boot`, por un ajuste analítico ni por
ninguna estimación corregida.

El sesgo bootstrap es **diagnóstico**. **OD-12 permanece OPEN / DEFERRED.**

---

## 4. Objeto conceptual

```r
.validate_estimator(
  point_estimate,        # fit$params + method + distribution
  analytic_inference,    # bloque de B12, o NULL
  bootstrap_inference,   # bloque de B13, o NULL
  sample_meta,           # metadatos de build_analysis_sample() — §11
  config
)
```

**Shiny-free y PURA.** No ejecuta `.estimate()`, `.mle_uncertainty()`,
`.bootstrap_estimator()` ni `.pm_fit()`. Sin RNG, sin E/S, sin estado. Dos
llamadas con las mismas entradas producen salidas `identical()`.

**Recibe resultados ya calculados.** Si un bloque no existe, recibe `NULL`; eso
es información, no un error.

---

## 5. Casos que debe soportar

| # | Estimador | Analítico | Bootstrap | Situación |
|---|---|---|---|---|
| A | MLE | válido | no calculado | Solo analítico |
| B | MLE | inválido / no disponible | válido | Solo bootstrap |
| C | MLE | válido | válido | Ambos |
| D | MLE | inválido | inválido | Sin incertidumbre publicable |
| E | MoM | **no aplicable** | válido | Solo bootstrap |
| F | L-momentos | **no aplicable** | válido | Solo bootstrap |
| G | **PM** | **no aplicable** | válido | Solo bootstrap |

**`no aplicable` no es `fallido`, y la distinción no es cosmética.** Para MoM,
L-momentos y PM la inferencia analítica de B12 **no está definida**: toda su
construcción exige que el score se anule en `θ̂`, y esos estimadores no lo anulan
—PM minimiza `J_PM`, no `ℓ`—. Presentarlo como «fallo» sugeriría un defecto donde
hay una frontera de diseño, e invitaría a alguien a «arreglarlo» más adelante.

En v1.1 **no hay inferencia analítica genérica** para MoM, L-momentos ni PM.

---

## 6. Taxonomía de estados

Una sola variable `valid` esconde información. Se proponen **cuatro ejes
independientes** más un estado global **derivado**, nunca al revés.

### 6.1 Ejes

**`point_estimate.status`** — `available` · `unavailable`

**`analytic.status`**

| Valor | Significado |
|---|---|
| `not_applicable` | El estimador no admite esta vía (MoM, L-mom, PM) |
| `not_requested` | Aplicable pero no se pidió |
| `failed` | Se intentó y no produjo salida válida. Lleva `reason` de B12 |
| `complete` | SE e IC disponibles para todos los parámetros |

**`bootstrap.status`** — se deriva **exclusivamente** de `B_success` y `B_failed`

| Condición | `bootstrap.status` | **Contribución bootstrap** al estado global |
|---|---|---|
| No se ejecutó | `not_requested` | **ninguna** |
| `B_success = 0` | `failed` | **ninguna** |
| `B_success = 1` | **`insufficient`** | **ninguna** |
| `B_success ≥ 2` y `B_failed > 0` | `partial` | **aporta incertidumbre bootstrap** |
| `B_success = B_requested ≥ 2` | `complete` | **aporta incertidumbre bootstrap** |

> **La tercera columna es una CONTRIBUCIÓN, no un estado global.** El bootstrap
> **no determina por sí solo** el estado global: éste depende conjuntamente del
> punto estimado, de `analytic.status`, de `bootstrap.status` y de las
> incompatibilidades (§6.2). Un bootstrap que aporta incertidumbre produce
> `uncertainty_bootstrap` **solo si** el analítico no la aporta; si además
> `analytic.status == "complete"`, el estado global es **`uncertainty_both`**.

**`insufficient` NO es un umbral de calidad y por tanto NO invade OD-11.** Es una
**condición matemática**: con una sola réplica **no existe la desviación típica
muestral** —cero grados de libertad— y no hay distribución bootstrap empírica
suficiente para publicar una medida de incertidumbre. La frontera está en la
definición de las cantidades, no en un juicio sobre su calidad.

**Coherencia con B13, no contradicción.** B13 emite para `B_success = 1`
`status = "partial"` con **`valid = FALSE`**, y para `B_success ≥ 2` con fallos
`status = "partial"` con **`valid = TRUE`**. B14 no cambia esos valores: los
**clasifica** con mayor resolución, separando en `insufficient` y `partial` dos
situaciones que B13 ya distinguía por `valid`. La equivalencia correcta es:

```
bootstrap$valid == TRUE   ⟺   global ∈ { "uncertainty_bootstrap", "uncertainty_both" }
                          ⟺   B_success >= 2        (contrato actual de B13)
```

**`comparability.status`** — `not_applicable` (falta una vía) · `comparable` ·
`limited` (ver §10) · `incompatible` (I3/I4)

### 6.2 Estado global, derivado

`no_point_estimate` · `point_only` · `uncertainty_analytic` ·
`uncertainty_bootstrap` · `uncertainty_both` · `incompatible`

**`point_only` significa: hay estimación puntual y NO hay incertidumbre
publicable POR NINGUNA VÍA.** Requiere que **ambas** contribuciones estén
ausentes.

**Derivación, explícita y única.** El estado global es una función de **todos**
los ejes, nunca de uno solo (I13):

```
si point_estimate no disponible          ->  no_point_estimate
si hay incompatibilidad (I3/I4)          ->  incompatible
en otro caso, con
    a_ok = (analytic.status  == "complete")
    b_ok = (bootstrap.status %in% c("partial", "complete"))   # B_success >= 2

     a_ok  &&  b_ok   ->  uncertainty_both
     a_ok  && !b_ok   ->  uncertainty_analytic
    !a_ok  &&  b_ok   ->  uncertainty_bootstrap
    !a_ok  && !b_ok   ->  point_only
```

### 6.3 Casos, verificados contra la derivación

| # | Escenario | analytic | bootstrap | `a_ok` | `b_ok` | global |
|---|---|---|---|:-:|:-:|---|
| 1 | analítico completo, bootstrap no pedido | `complete` | `not_requested` | ✓ | ✗ | `uncertainty_analytic` |
| 2 | analítico fallido, bootstrap no pedido | `failed` | `not_requested` | ✗ | ✗ | `point_only` |
| 3 | analítico no aplicable / no disponible + bootstrap válido | `not_applicable` o `not_requested` | `partial` o `complete` | ✗ | ✓ | `uncertainty_bootstrap` |
| 4 | ambos completos | `complete` | `complete` | ✓ | ✓ | **`uncertainty_both`** |
| 5 | bootstrap `partial`, `B_failed > 0`, `B_success ≥ 2`, analítico no válido | `failed` / `not_applicable` | `partial` | ✗ | ✓ | `uncertainty_bootstrap` |
| 6 | **bootstrap `insufficient` y analítico NO válido** | `failed` / `not_applicable` | `insufficient` | ✗ | ✗ | **`point_only`** |
| 7 | **bootstrap `insufficient` pero analítico COMPLETO** | `complete` | `insufficient` | ✓ | ✗ | **`uncertainty_analytic`** |
| 8 | `B_success = 0` y analítico no válido | `failed` / `not_applicable` | `failed` | ✗ | ✗ | `point_only` |
| 9 | ninguna vía disponible | `not_applicable` | `not_requested` | ✗ | ✗ | `point_only` |

**El caso 7 es el que hace explícita la corrección: un bootstrap insuficiente NO
elimina una incertidumbre analítica válida.** Los dos ejes son independientes;
que una vía no aporte nada no degrada a la otra. La lectura contraria —«el
bootstrap falló, luego no hay incertidumbre»— sería un error de composición, y es
exactamente lo que la derivación de §6.2 impide.

Simétricamente, el caso 4 muestra por qué la equivalencia de I15 **no** puede
escribirse contra `uncertainty_bootstrap` a secas: ahí `bootstrap$valid == TRUE`
y sin embargo el global es `uncertainty_both`.

**Los casos 2, 6, 8 y 9 comparten `point_only` y son cuatro situaciones
distintas.** Ése es el motivo de los ejes separados: el global dice *qué se puede
publicar*; los ejes dicen *por qué*. Un solo campo no puede hacer ambas cosas.

### 6.4 `partial` no significa «malo»; `insufficient` no es un umbral

Tres estados que conviene no confundir entre sí:

- **Caso 5 — `partial`.** `B_failed > 0` con `B_success ≥ 2`: SE, sesgo e IC
  **existen y son utilizables**. `partial` describe la **ejecución**, no la
  calidad, y el estado global sí es `uncertainty_bootstrap`. **No hay umbral**:
  un `success_rate` bajo no degrada la clasificación.
- **Caso 6 — `insufficient`.** `B_success = 1`. El sesgo **es formalmente
  calculable** (la media de una réplica existe) y el IC percentil es
  **computable pero degenerado a un punto**; el **SE no está definido**. Se
  conservan `bias_available = TRUE` y `ci_degenerate = TRUE` **como información
  técnica**, pero **el estado global es `point_only`**: no se publica
  incertidumbre bootstrap a partir de una sola réplica.
- **Caso 7 — `failed`.** `B_success = 0`: no hay nada.

**La distinción entre 5 y 6 es de naturaleza, no de grado.** En el caso 5 las
cantidades **existen** y podría discutirse su fiabilidad — eso es OD-11. En el
caso 6 la desviación típica muestral **no está definida**, y eso no es materia
de umbral: ninguna política de calidad puede hacer existir un estadístico que
requiere al menos dos observaciones.

Se exponen banderas separadas —`se_available`, `bias_available`,
`ci_degenerate`— para que la información técnica siga disponible aunque el
estado global no autorice a publicarla.

**No se introduce ningún umbral de `success_rate`. OD-11 sigue OPEN / DEFERRED
a B15.**

---

## 7. Contrato por parámetro

```r
parameters[[j]] <- list(
  name     = ,
  estimate = ,                    # de fit$params — SIEMPRE la oficial

  analytic = list(
    available = , valid = , status = , reason = ,
    se = , ci_lower = , ci_upper = , confidence_level = ,
    transform = , support =        # de DFIT_PARAM_TRANSFORM (B12)
  ),

  bootstrap = list(
    calculated = , valid = , status = , reason = ,
    se = , bias = , ci_lower = , ci_upper = , confidence_level = ,
    se_available = , bias_available = , ci_degenerate =
  )
)
```

**Todos los valores se MAPEAN. Ninguno se recalcula.**

**La ausencia se representa explícitamente**: `available = FALSE` + `status` +
`NA` en los numéricos. **Nunca omitiendo el campo** — un campo ausente es
indistinguible de un error de construcción.

`transform` y `support` se propagan porque explican por qué un IC analítico es
**asimétrico** en escala natural: proviene de un Wald en escala `u`
retrotransformado (OD-16). Sin ese dato, la asimetría parece un defecto.

---

## 8. Contrato global de bootstrap

Se consumen y exponen **verbatim**: `B_requested` · `B_success` · `B_failed` ·
`success_rate` · `seed` · `confidence_level` · `quantile_type` ·
`data_fingerprint` · `fingerprint_algo` · `fingerprint_status` ·
`failures$counts` · `failures$examples` · `summaries_conditional_on_success`.

**No se genera** score de calidad, semáforo, ni `HIGH`/`MEDIUM`/`LOW`.

---

## 9. Sesgo

B13 produce `bias = mean(θ*) − θ̂`. **B14 solo lo presenta.**

Sin corrección de sesgo. Sin «estimación ajustada». **Sin MSE.**

### 9.1 `relative_bias` — se propone EXCLUIRLO, y no como OD

Coincido con la preferencia inicial, con dos razones y una consecuencia.

**Primera: inestabilidad cerca de cero.** `bias/θ̂` diverge cuando `θ̂ → 0`, y hay
parámetros del catálogo que legítimamente rondan el cero — `mean` de la Normal,
`meanlog` de la Lognormal —.

**Segunda, y más fuerte: no es invariante para parámetros de localización.**
`meanlog` es una localización en escala logarítmica: cambiar la unidad de los
datos lo desplaza en una constante aditiva, de modo que `bias/meanlog` **depende
de la unidad elegida**. No es una cantidad comparable.

**Consecuencia: esto ya está decidido.** Es el mismo argumento que llevó en
B12.1 a referenciar `mean` a `sd_true` y `meanlog` a `sdlog_true` en lugar de
usar error relativo. Incluir `relative_bias` en B14 **contradiría una decisión
frozen**. Por tanto no se propone como decisión abierta: **se excluye por
coherencia**. Si algún día se quisiera una medida adimensional del sesgo, el
precedente correcto es el de B12.1 —referenciarlo a una escala del propio
modelo—, no dividir por `θ̂`.

---

## 10. MLE analítico + bootstrap: lado a lado, sin juicio

Cuando ambos existen, B14 **los coloca lado a lado y se detiene ahí**.

**No calcula** `SE_boot / SE_analytic`, diferencia relativa de SE, cociente de
amplitudes de IC, diferencias de extremos ni ningún índice de solapamiento.
**No afirma** que coincidan, que discrepen, que uno sea mejor, ni que haya
estabilidad o inestabilidad. Todas ésas son métricas candidatas de **B15**.

B14 deja disponibles los datos que B15 necesitará, y **una sola cosa más**: la
declaración de si son comparables.

### 10.1 Comparabilidad

```r
comparability = list(
  status                 = ,   # not_applicable | comparable | limited | incompatible
  same_confidence_level  = ,
  analytic_level         = ,
  bootstrap_level        = ,
  same_parameter_names   = ,
  same_sample_n          = ,
  sample_identity_verified = ,  # §10.2
  notes                  =
)
```

**Niveles de confianza distintos no invalidan nada.** Cada IC sigue siendo válido
**individualmente** bajo su propio nivel. Lo que no se puede hacer es compararlos
—amplitudes, extremos, diferencias relativas— sin advertencia, porque la
diferencia observada mezclaría el efecto del método con el del nivel.

Por eso `same_confidence_level = FALSE` ⇒ `status = "limited"`, con los dos
niveles expuestos. **B14 no corrige ni recalcula niveles**: no reescala un IC del
90 % al 95 %, aunque sea aritméticamente posible en la vía analítica —y aunque
**no** lo sea en la percentil, que exigiría recalcular cuantiles sobre las
réplicas, es decir, recalcular inferencia—. Esa asimetría entre vías es otra
razón para no armonizar: se compararían objetos construidos de formas distintas.

### 10.2 OD-18 — Identidad de muestra entre vías de inferencia — **RESUELTA**

> **OD-18 — Sample identity across inference paths.**
> Resuelta con la intervención mínima descrita aquí. Alcance: **solo identidad
> de muestra**. No introduce ninguna métrica de acuerdo estadístico — eso es B15.

**Causa original.** `.data_fingerprint()` —SHA-256 sobre el vector serializado—
existía desde B13 pero **solo se invocaba desde `.bootstrap_estimator()`**. El
bloque analítico de B12 no llevaba identidad, de modo que B14 solo podía
comparar `n`, que es **condición necesaria y no suficiente**: dos muestras
distintas del mismo tamaño la satisfacen.

**Solución adoptada: opción (b) en su forma mínima — una sola identidad,
heredada.** No se crea un mecanismo nuevo: `.mle_uncertainty()` invoca **el mismo
helper** que ya usaba B13, de modo que no existen dos implementaciones que puedan
divergir. B12 expone:

```r
analytic$sample <- list(n_used = , fingerprint = , fingerprint_algo = "sha256",
                        fingerprint_status = )
```

Es **metadata**: no interviene en ningún cálculo estadístico de B12 —Hessiana,
transformación, delta, Wald, guardas Cholesky y reglas de estado quedan intactas—.

**Regla de verificación, exacta.** `sample_identity_verified = TRUE` exige las
**once** condiciones, todas:

| # | Condición |
|---|---|
| 1–2 | Existen huella analítica y huella bootstrap |
| 3 | Ambas son **SHA-256 bien formados**: exactamente 64 caracteres `[0-9a-f]` |
| 4–5 | `fingerprint_status == "complete"` en **ambas** vías |
| 6–7 | `fingerprint_algo == "sha256"` en **ambas** vías |
| 8 | Los dos algoritmos **coinciden** |
| 9 | `n_used` es un escalar finito en ambas |
| 10 | `n_used` **coincide** |
| 11 | Las huellas **coinciden exactamente** |

**No basta con que dos cadenas sean iguales.** `"abc" == "abc"` no es evidencia
de nada: sin validez de formato, de estado y de algoritmo, la igualdad no prueba
que ambas vías identifiquen el mismo vector bajo el contrato de B13 — y eso es
exactamente lo que B15 necesita poder dar por supuesto al leer un `TRUE`.

**La igualdad de `n` tampoco basta.** No se admite ningún sustituto de identidad:
ni media, ni sd, ni min/max, ni cuantiles, ni `n` a solas.

**Orden de resolución:** primero validez (1–8), luego tamaño (9–10), luego
igualdad (11). Una huella inutilizable da `not_verifiable` **antes** de mirar
`n`, porque no se puede afirmar «muestras distintas» sin identidades válidas que
comparar.

**`sample_identity_status` distingue por qué no se verifica**, porque «falta
evidencia» y «evidencia de muestras distintas» no son lo mismo:

| Estado | Condición | `comparability$status` |
|---|---|---|
| `verified` | las once condiciones se cumplen | `comparable` / `limited` según nivel |
| `mismatch` | huellas **válidas** y **distintas** | `incompatible` |
| `different_n` | huellas válidas, `n_used` distinto | `incompatible` |
| `not_verifiable` | huella ausente · formato inválido · `fingerprint_status` no `complete` · algoritmo ausente o no SHA-256 · algoritmos distintos entre vías | `limited` |
| `not_applicable` | solo existe una vía | `not_applicable` |

`sample_identity_reason` indica el **motivo concreto**, no solo la categoría.

**La falta o el fallo de identidad degradan `comparability`, NO el estado
global.** Es deliberado y es el punto que evita convertir OD-18 en un problema
mayor del que resuelve: bloquea la **comparación** entre vías —que es lo que
carecería de sentido— pero **cada inferencia sigue siendo utilizable por
separado**. Un `mismatch` no invalida ni el SE analítico ni el IC bootstrap; solo
prohíbe leerlos uno contra otro.

**Lo que esto desbloquea.** B15 puede ahora exigir
`sample_identity_verified = TRUE` como precondición antes de comparar. Sin ella,
una discrepancia sería inatribuible —¿método, o dato?—.

**Lo que OD-18 NO responde:** si los resultados de ambas vías coinciden
estadísticamente. Aquí no hay comparación de SE, diferencia relativa, solapamiento
de IC, puntuación de acuerdo, etiquetas de estabilidad ni umbrales. **B15.**

---

## 11. Muestra modelizada (ADR-026)

```r
sample = list(
  n_input = , n_used = ,
  n_excluded_zeros = , n_excluded_negatives = ,
  support_label = , requires_positive = ,
  conditional = ,          # TRUE si hubo exclusiones
  conditional_note =
)
```

**Origen obligatorio: el objeto de `build_analysis_sample()`.**

> **Trampa concreta a evitar.** `fit$n_excluded` **NO** sirve: desde ADR-026 es
> **vestigial y vale siempre 0** —así está documentado en el propio `calc.R`—,
> porque la exclusión ocurre una sola vez en la capa 0.5 y el ajuste recibe la
> muestra ya restringida. Leerlo daría «0 excluidos» en todos los casos y
> ocultaría precisamente lo que esta sección existe para exponer.

**No se crea una segunda muestra.** Solo se conserva la referencia.

### 11.1 Por qué esto importa más de lo que parece

Si `n_excluded_zeros > 0`, la incertidumbre publicada corresponde a los
parámetros de la **distribución condicional positiva** que se modelizó, **no** a
la distribución completa original con su átomo en cero.

Un actuario que lea «IC de la severidad» sin ese matiz interpretará otra cosa —y
la diferencia es material cuando la frecuencia de siniestro nulo es alta—. El
`conditional_note` debe ser explícito y no una nota al pie.

---

## 12. OD-17

B14 **propaga exactamente** `summaries_conditional_on_success = TRUE` y los
diagnósticos de fallos. No los reinterpreta.

**Copy breve:**

> Los resúmenes bootstrap se calculan sobre las réplicas válidas.

**Copy técnico:**

> Si la probabilidad de éxito de una réplica depende del valor que habría tomado
> el estimador, los resúmenes condicionados a éxito pueden no representar la
> distribución bootstrap no condicionada. La dirección y magnitud de esta
> distorsión dependen del mecanismo de fallo.

**Prohibido afirmar** que siempre estrecha, que siempre ensancha, que siempre
subestima o que siempre sobreestima. **OD-17 sigue OPEN / NON-BLOCKING.**

---

## 13. Interpretación

Dos niveles, ambos **texto, no cálculo**.

### 13.1 Breve

> **Error estándar.** Estima la variabilidad de la estimación: cuánto cabría
> esperar que cambiara si se repitiera el procedimiento sobre otra muestra.
>
> **Intervalo de confianza.** Resume un rango de valores compatibles con la
> incertidumbre del estimador bajo el procedimiento utilizado.
>
> **Sesgo bootstrap.** Compara la media de las estimaciones bootstrap con la
> estimación obtenida en la muestra original. Es un diagnóstico: la estimación
> oficial no se corrige.

### 13.2 Técnico

> **Vía analítica (solo MLE).** Información **observada**
> `J(θ̂) = −∇²ℓ(θ̂)`, invertida para obtener la covarianza y trasladada a escala
> natural por método delta. Es una **aproximación asintótica**. No es la
> información esperada de Fisher `I(θ) = E[J(θ)]`, que es otra cantidad. El IC es
> **Wald construido en la escala transformada** y retrotransformado, por lo que
> resulta **asimétrico** en escala natural para parámetros positivos y para
> probabilidades — es deliberado: respeta el soporte por construcción.
>
> **Vía bootstrap.** Remuestreo **no paramétrico iid** de la muestra de análisis,
> con reestimación completa en cada réplica. No asume normalidad asintótica. El
> IC es **percentil** sobre las réplicas válidas, con `quantile(type = 7)`, de
> modo que un extremo puede ser un valor **interpolado** y no una réplica
> observada; el soporte se conserva por **convexidad** del espacio paramétrico.

### 13.3 Dos confusiones que la interfaz debe evitar

**Frecuentista, no bayesiano.** Un intervalo de confianza **no** es un intervalo
de credibilidad: no dice que el parámetro esté dentro con probabilidad 0,95. La
propiedad es de **cobertura del procedimiento** en repeticiones hipotéticas.
Nunca debe escribirse «hay un 95 % de probabilidad de que el parámetro esté
entre…».

**Incertidumbre de parámetro, no de modelo.** Todo lo anterior es condicional a
la distribución elegida. **No** incorpora la incertidumbre por **selección de
modelo** —que la candidata correcta fuese otra—, que es un problema distinto y
está fuera del alcance de v1.1.

---

## 14. Invariantes

| # | Invariante |
|---|---|
| **I1** | B14 **no cambia** la estimación puntual |
| **I2** | B14 **no recalcula** nada de B12/B13 |
| **I3** | Nombres y orden de parámetros coinciden entre punto / analítico / bootstrap cuando existan |
| **I4** | Si no coinciden ⇒ `incompatible` + `reason`. **Sin reordenación silenciosa** |
| **I5** | Los `confidence_level` se conservan verbatim; **nunca se armonizan** |
| **I6** | `B_requested = B_success + B_failed` |
| **I7** | `nrow(replicates) = B_success` cuando existan réplicas |
| **I8** | `summaries_conditional_on_success` se conserva |
| **I9** | El `data_fingerprint` se conserva |
| **I10** | Los metadatos de muestra se conservan |
| **I11** | **Función pura**: sin RNG, sin E/S, sin estado; dos llamadas iguales ⇒ salidas `identical()` |
| **I12** | **La ausencia se representa explícitamente** (`status` + `NA`), nunca omitiendo el campo |
| **I13** | El estado global es **derivado** de los ejes, nunca al revés: ningún eje se ajusta para encajar en él |
| **I14** | `ci_lower ≤ ci_upper` se conserva **tal como se recibe**; B14 no reordena extremos |
| **I15** | `bootstrap$valid == TRUE` (B13) **si y solo si** `global ∈ {uncertainty_bootstrap, uncertainty_both}`. Bajo el contrato actual de B13, equivalentemente `B_success ≥ 2` |
| **I16** | `sample_identity_verified = TRUE` **solo** si ambas vías aportan una identidad de muestra comparable. En ausencia de huella en el bloque analítico, es `FALSE` (OD-18) |

I11, I13, I15 e I16 se proponen añadir a los diez del encargo. **I11** hace la
capa testeable de forma trivial y descarta de raíz que se cuele una reejecución.
**I13** protege la propiedad que da valor a §6: si alguna vez se «corrigiera» un
eje para que el global cuadrase, la taxonomía dejaría de informar. **I15** ata la
clasificación de B14 al veredicto de B13, de modo que no puedan divergir. **I16**
impide que la verificación de identidad se dé por buena por omisión, que es la
forma en que este tipo de comprobación suele degradarse.

> **CORRECCIÓN de I15 (2026-09-03).** Una versión anterior lo enunciaba como
> `global == "uncertainty_bootstrap" ⟺ bootstrap$valid == TRUE`. **Era una
> equivalencia falsa** y contradecía el propio §6.2: con `analytic = complete` y
> `bootstrap = complete` el global es `uncertainty_both` y sin embargo
> `bootstrap$valid == TRUE`, de modo que el «solo si» no se cumple. El error era
> tratar un eje como si determinase el global — precisamente lo que I13
> prohíbe. La forma corregida enuncia la implicación en el sentido que sí se
> sostiene y contra el **conjunto** de estados globales que incluyen
> contribución bootstrap.

---

## 15. Contrato de salida

```r
validation <- list(
  status         = ,            # §6.2
  estimator      = ,            # "mle" | "mom" | "lmom" | "pm"
  distribution   = ,
  point_estimate = ,            # fit$params, verbatim

  sample         = list(...),   # §11
  analytic       = list(status = , reason = , confidence_level = , ...),
  bootstrap      = list(status = , reason = , ...),   # §8
  parameters     = list(...),   # §7

  comparability  = list(...),   # §10.1
  diagnostics    = list(...),
  limitations    = character()  # §16
)
```

**Estructura conceptual.** **No se modifica el schema.** La ubicación definitiva
dentro del resultado productivo se decide en **B16**, junto con el
`SCHEMA / CONTRACT ISSUE` de `fit$inference` que sigue abierto y diferido.

### 15.1 `limitations`

Vector de textos que el consumidor **debe** poder mostrar. Se propone poblarlo
al menos con: muestra condicional (§11.1) · resúmenes condicionados al éxito
(§12) · niveles no comparables (§10.1) · identidad de muestra no verificada
(§10.2) · sin inferencia analítica para este estimador (§5).

Van en un campo propio y no diluidas en `reason` porque **son limitaciones del
resultado válido**, no motivos de fallo. Mezclarlas haría que un resultado
perfectamente utilizable pareciese defectuoso.

---

## 16. Fuera de alcance

Umbrales de comparación · etiquetas de estabilidad · incertidumbre de selección
de modelo · H4 · bootstrap paramétrico de GoF (ADR-008) · inferencia bayesiana ·
BCa · bootstrap-t · bootstrap dependiente · incertidumbre de VaR/TVaR · **MSE** ·
corrección de sesgo · UI · export · persistencia · integración de schema.

---

## 17. Relación con el material teórico

El curso trata precisión del estimador, distribución del estimador, error
estándar y varianza, intervalos de confianza, aproximación analítica, bootstrap
no paramétrico, sesgo, y `MSE = Var + Bias²`.

**`MSE` queda fuera de B14 en v1.1**, con una precisión que conviene mantener
escrita y **enunciada correctamente**:

```
SE_boot = sd(θ̂*)        es una ESTIMACIÓN BOOTSTRAP de   sqrt( Var(θ̂) )

MSE(θ̂) = Var(θ̂) + Bias(θ̂)²
```

**Por eso `SE_boot` no es el MSE ni contiene el término de sesgo.** Son dos
afirmaciones distintas y ambas importan: `SE_boot` **estima** la raíz de la
varianza —no la iguala—, y aun estimándola perfectamente seguiría sin incluir
`Bias²`.

> **CORRECCIÓN (2026-09-03).** Una redacción anterior decía que `SE_boot` **es**
> «la raíz de la primera componente del MSE». Eso implicaba una **identidad
> exacta** entre `sd(θ̂*)` y `sqrt(Var(θ̂))` que no se sostiene: `sd(θ̂*)` es un
> **estimador** de esa cantidad, con su propio error de Monte Carlo —que decrece
> con `B`— y sujeto además a la condicionalidad de OD-17. La distinción entre
> *estimar* e *igualar* es justamente la que este contrato exige en todas partes.

Tampoco se mezcla **incertidumbre de parámetros** con **selección de modelo**:
son preguntas distintas y v1.1 solo responde la primera.

---

## 18. Cuestiones NO congeladas

| # | Cuestión | Propuesta | Estado |
|---|---|---|---|
| 1 | Valores exactos de la taxonomía (§6) | Los de este documento | Nombres ajustables antes de implementar |
| 2 | `relative_bias` | **Excluir** por coherencia con B12.1 (§9.1) | No es OD: ya decidido |
| 3 | **Identidad de muestra entre vías** (§10.2) | Declarar `FALSE`, no simular | **OD-18 — OPEN / BLOCKS B15 COMPARISON** |
| 4 | Ubicación en el resultado productivo | — | **B16** |
| 5 | Textos definitivos de §13 | Borradores | Redacción final en B16 |

**Se abre una OD nueva: OD-18.** No por un detalle de campos, sino porque
**bloquea la validez de un bloque posterior**: sin identidad de muestra
verificable, la comparación de B15 no puede atribuir una discrepancia al método
en vez de al dato. Las otras cuatro cuestiones sí son expresables dentro de
B14.0 y no requieren OD.

### 18.1 Estado de las OD tras B14.0

| OD | Estado |
|---|---|
| OD-8 | OPEN / DEFERRED **B16** |
| OD-11 | OPEN / DEFERRED **B15** |
| OD-12 | OPEN / DEFERRED |
| OD-14 | OPEN / DEFERRED |
| OD-15 | OPEN / DEFERRED **B16** |
| OD-17 | OPEN / NON-BLOCKING |
| **OD-18** | **OPEN / BLOCKS B15 COMPARISON** — *nueva* |

---

*Actuarial Tools by BMK — B14.0, contrato **FROZEN / APPROVED** (ADR-037). Sin implementación.*
