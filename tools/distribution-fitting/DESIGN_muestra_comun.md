# Tool-02 — Diseño de corrección H2 / H1 / H3

| Campo | Valor |
|---|---|
| **Objeto** | Muestra común comparable (H2), defensa del optimizador (H1), coherencia del Visual Engine (H3) |
| **Estado** | **DISEÑO. Nada implementado.** Ningún fichero de código, test, ADR ni documentación modificado |
| **Origen** | `INCIDENT_2026-08-09_pareto_ceros.md` |
| **Caso de regresión** | `Cost_claims_year` (95.554 válidas · 77.876 ceros · 17.678 positivas) |
| **Requiere** | ADR-026, ADR-027, ADR-028 aprobados antes de tocar código |

---

## Parte I — H2: muestra común

### 1. Punto arquitectónico correcto

**Una nueva etapa 0.5 entre la selección de candidatas y el Motor, dentro de `dist_fit_analyze()`.**

Hoy el filtrado ocurre **dentro** del Motor, una vez por distribución (`.fit_one` → `.prepare_support`). Eso es lo que hace estructuralmente imposible la comparabilidad: cada ajuste decide su propia muestra y ninguna capa superior conoce esa decisión.

La corrección invierte la dependencia: **la muestra se decide una vez, antes de ajustar nada, y se impone a todas las capas.**

```
Profiler (capa 0)
      ↓
select_candidate_distributions()          ← determina QUÉ candidatas compiten
      ↓
build_analysis_sample()   ← NUEVA (capa 0.5)   ← determina SOBRE QUÉ compiten
      ↓
Motor → Diagnostics → Assessment → Text Builders → ViewModel → Visual Engine
```

**Por qué ahí y no antes.** La muestra común no puede fijarse en el Profiler: depende del **conjunto de candidatas**, que a su vez depende de la familia detectada o forzada. El Profiler no conoce las candidatas. Colocarla después de `select_candidate_distributions()` es el primer punto del pipeline donde existe toda la información necesaria.

**Por qué ahí y no dentro del Motor.** Si la construyera el Motor, Diagnostics y el Visual Engine tendrían que volver a derivarla o recibirla por un canal implícito. Situada antes, viaja como dato explícito en el objeto de análisis.

### 2. La regla: intersección de soportes

No es una regla *ad hoc* para los ceros. Es una definición general:

> **La muestra común es la restricción de la muestra válida al soporte que comparten todas las candidatas que van a competir en el ranking.**

Formalmente, la intersección $\bigcap_i \mathrm{sop}(F_i)$ sobre las candidatas seleccionadas. Operativamente, con el catálogo v1:

| Familia | Candidatas | Intersección | Efecto |
|---|---|---|---|
| **Continua** | exponencial, gamma, weibull, lognormal, loglogística, pareto, burr | $(0,\infty)$ — porque 5 de las 7 exigen $x>0$ | **Se excluyen ceros y negativos para todas** |
| **Discreta** | poisson, binomial negativa, geométrica | $\{0,1,2,\dots\}$ — las 3 admiten el 0 | **Sin cambio**: se conservan los ceros |

Esto es exactamente la decisión metodológica que has fijado, pero derivada de una regla, no escrita a mano. Si mañana entra una distribución que admita el cero en toda la familia continua (una Tweedie, una zero-inflated), la regla se recalcula sola.

**El control (Normal) se ajusta sobre la muestra común, no sobre la suya.** Su función es compararse con las candidatas (`control_check` en `.assess`); si vive en otra muestra, la comparación es inválida. Hoy lo es: la Normal se ajusta sobre 95.554 y se compara con una lognormal ajustada sobre 17.678. **Es una instancia latente de H2 que esta corrección cierra de paso.**

### 3. Contrato de la nueva función

```r
#' Muestra común del análisis (capa 0.5)
#'
#' Restringe la muestra válida al soporte compartido por TODAS las candidatas
#' que competirán en el ranking, de modo que verosimilitudes, criterios de
#' información y estadísticos de bondad de ajuste sean comparables entre sí
#' (requisito de la comparación por AIC: exige datos idénticos).
build_analysis_sample <- function(v, candidates, config = dfit_default_config())
```

Devuelve:

| Campo | Contenido |
|---|---|
| `x` | Vector de la muestra común |
| `n_input` | Observaciones válidas de entrada (no NA) |
| `n_used` | `length(x)` |
| `n_excluded_zeros` | Ceros excluidos |
| `n_excluded_negatives` | Negativos excluidos |
| `requires_positive` | `TRUE`/`FALSE`: la intersección exige $x>0$ |
| `support_label` | `"(0, ∞)"` / `"[0, ∞)"` / `"{0,1,2,…}"` |
| `rule` | Texto trazable: *"soporte común a las 7 candidatas continuas"* |
| `resolution` | δ = menor salto entre valores distintos (lo usa la guarda H1, §7) |

**Guarda de suficiencia.** Si tras el filtrado `n_used < config$min_obs_analysis`, el análisis se detiene con un mensaje explícito (*"tras excluir 77.876 ceros quedan N observaciones, insuficientes para estimar las candidatas"*). El valor propuesto es **5**, y no es arbitrario: la candidata con más parámetros es Burr (3), y `.fit_one` ya exige `n ≥ n_params + 1 = 4`; 5 es el menor entero que deja estimables las siete. Va a `dfit_default_config()`, no al código (regla 8).

### 4. Capas que la consumen — demostración

| Capa | Hoy | Después | Por qué es obligatorio |
|---|---|---|---|
| **Motor** `.motor` / `.fit_one` | Recibe `x_valid` (95.554) y cada ajuste filtra por su cuenta | Recibe `sample$x` (17.678) ya filtrado. `.fit_one` **deja de llamar** a `.prepare_support` | Es donde nace la divergencia de muestras. Si no cambia aquí, no cambia nada |
| **Diagnostics** `.diagnostics` | Recibe `x_valid` y **vuelve a filtrar** por distribución para calcular GoF | Recibe `sample$x` y lo usa tal cual | GoF y AIC deben venir de la misma muestra que produjo el `logLik`. Hoy lo son *dentro* de cada ajuste, pero no *entre* ajustes |
| **Assessment** `.assess` | Normaliza min-máx métricas de muestras distintas | Sin cambio de código: recibe métricas ya homogéneas | **Es el consumidor que hoy comete el error**, pero no es donde hay que arreglarlo. Corregido el origen, `.assess` pasa a ser correcto sin tocarlo. *Ver nota abajo* |
| **Text Builders** `.build_warnings` / `.text_builders` | Emite un aviso de exclusión **por distribución** (5 avisos) y anuncia `profile$n_valid` = 95.554 | Un **único** aviso global cuantificado y un `summary` que declara la muestra efectiva | Requisito tuyo: *"no debe parecer que había 95.554 severidades"* |
| **View Model** `.vm_input_and_diagnosis` | Expone `input_summary` con `n`, `n_valid`, `pct_zeros` — y **nadie lo renderiza** | Añade el bloque `sample` (muestra efectiva y exclusiones) | Contrato de integración; lo consumirá la UI y, en el futuro, Internal Model Studio |
| **Visual Engine** `build_visual_data` / `build_qq_pp_data` | Histograma y KDE sobre `x` completo; QQ/PP con `.prepare_support` por distribución | Ambos sobre `analysis$sample$x` | **Es H3.** Ver Parte III |

**Nota sobre `.assess`.** Con la muestra común, `.assess` queda matemáticamente correcto sin modificarlo, pero pierde su red de seguridad: seguiría normalizando alegremente métricas heterogéneas si alguna vez volvieran a serlo. Propongo **una aserción defensiva de 3 líneas** —comprobar que todos los `n_used` de las convergentes coinciden y, si no, detener con error interno— como test vivo del invariante. Es lo único que tocaría de esa capa.

### 5. Sin copias de la lógica de filtrado — confirmación

Hoy `.prepare_support()` (`calc.R:258`) se invoca en **tres** sitios: `.fit_one` (575), `.diagnostics` (798) y `build_qq_pp_data` (1701). Tres invocaciones de la misma función pura, coherentes entre sí por casualidad, no por construcción.

Después:

- **`.prepare_support()` sigue existiendo, sin cambios, y se invoca EXACTAMENTE UNA VEZ**, desde `build_analysis_sample()`.
- **`DFIT_REQUIRES_POSITIVE` sigue siendo la fuente única** de qué soporte exige cada distribución. No se duplica ni se sustituye: pasa de ser consultada por cada ajuste a ser el **insumo del cálculo de la intersección**. Su papel es más importante, no menor.
- Las otras dos invocaciones **se eliminan**, no se reemplazan por lógica equivalente.

Verificación mecánica propuesta como parte de la aceptación: `grep -c "prepare_support(" R/calc.R` debe devolver **2** (la definición y la única llamada).

### 6. Tests congelados que cambian legítimamente

Revisé los datasets de los 8 ficheros de test. El impacto es **notablemente pequeño**, porque solo dos usan datos continuos con ceros:

| Dataset | Ficheros | ¿Cambia? |
|---|---|---|
| `xc` (12 continuos, **sin ceros**) | b2, b2_2, b3, b4, b5, b6, b7 | **No.** La muestra común coincide con la actual |
| `xd` (15 recuentos, **con ceros**) | b2, b2_2, b3, b4, b5, b6, b7 | **No.** Familia discreta: la intersección conserva el 0 |
| `example_data.csv` `loss_amount` (60 obs, sin ceros) | b8, import_csv, acceptance | **No** |
| `xz = c(0, 120.3, …)` (**continuo con un cero**) | b2 §6, b5 §5 | **Sí** |

**Cambian exactamente dos aserciones:**

**(a) `tests/b2_unit_tests.R:140-143`**

```r
check(fz$lognormal$n_excluded$zeros == 1L && fz$lognormal$n_used == 5L, ...)
check(fz$exponential$n_excluded$zeros == 0L && fz$exponential$n_used == 6L, ...)
```

La segunda es precisamente la que codifica el comportamiento defectuoso. Pasa a:

```r
# La exclusión de ceros ya no es por distribución: es global (ADR-026).
check(res_z$sample$n_excluded_zeros == 1L && res_z$sample$n_used == 5L, ...)
check(all(vapply(fz, function(f) f$n_used, numeric(1)) == 5L),
      "muestra común: las 7 candidatas usan las mismas 5 observaciones")
```

**Justificación del cambio de contrato** (regla: no se adapta un test sin demostrar que el contrato cambió legítimamente): el contrato antiguo — *"cada distribución excluye según su soporte"* — es exactamente el que produce H2. ADR-026 lo sustituye por *"todas las candidatas comparten muestra"*. El test se alinea con el contrato nuevo; no se relaja para hacerlo pasar.

**(b) `tests/b5_unit_tests.R:125`**

```r
check(has_text(tz$warnings, "cero"), ...)
```

Probablemente **sobrevive sin tocarse** (el aviso global seguirá conteniendo "cero"), pero el texto exacto cambia. Marcado para verificación, no para modificación preventiva.

**Estructura preservada deliberadamente.** `fit$n_excluded` se **mantiene** en el contrato (con valores 0, porque la muestra llega ya filtrada). Eso evita romper `b2_unit_tests.R:73` (comprobación de estructura) y `b5_unit_tests.R:87-88` (motor sintético). Es una decisión consciente de minimizar el radio de impacto; el campo queda marcado como vestigial en el ADR.

### 7. Tests nuevos — `tests/b2_muestra_comun.R`

Dataset sintético con masa en cero, proporción parecida a la real (80 % ceros), determinista:

```r
set.seed(20260809)
xz <- c(rep(0, 800), round(rlnorm(200, meanlog = 5.7, sdlog = 1.3), 2))
```

| # | Test | Aserción |
|---|---|---|
| **N1** | **Mismo `n_used` en las 7** | `length(unique(vapply(fits, function(f) f$n_used, numeric(1)))) == 1L` y `== 200L` |
| **N2** | **Ceros excluidos cuantificados** | `sample$n_excluded_zeros == 800L`; `sample$n_input == 1000L`; `sample$n_used == 200L`; `sample$requires_positive == TRUE` |
| **N3** | **Comunicación al usuario** | `warnings` contiene **un solo** aviso de ceros, con el número 800, y el `summary` menciona 200 —no 1.000— como muestra modelizada |
| **N4** | **AIC/BIC comparables** | Todos los `information$aic` son finitos y su rango es < 10⁵; `n` usado en `.information_criteria` idéntico para las 7 |
| **N5** | **Pareto finita y no degenerada** | `params$scale > .Machine$double.xmin`; `logLik < 0`; `abs(aic)` del mismo orden que el de lognormal (ratio < 2) |
| **N6** | **Familia discreta intacta** | Con `xd`, `sample$n_used == length(xd)` y `n_excluded_zeros == 0L`: la regla **no** toca recuentos |
| **N7** | **Visual Engine coherente** (H3) | `sum(histogram$density × ancho) ≈ 1`; el `n` del histograma = `sample$n_used`; `nrow(qq_plot$points) == sample$n_used` |
| **N8** | **Invariante del Assessment** | Todas las convergentes comparten `n_used` (aserción defensiva de §4) |
| **N9** | **Una sola llamada al filtro** | `length(grep("prepare_support(", readLines("R/calc.R"), fixed = TRUE)) == 2L` |

**Regresión con el dataset real — `tests/regresion_cost_claims.R`.** Fichero reducido y versionado en `data/samples/` (~5.000 filas conservando la proporción 81,5 % / 18,5 %). Aserciones contra el contrafactual ya calculado, con tolerancia relativa 5 % para absorber el submuestreo:

| Magnitud | Esperado (dataset completo) |
|---|---|
| `sample$n_used` | 17.678 (proporcional en el reducido) |
| `sample$n_excluded_zeros` | 77.876 (íd.) |
| Pareto `shape` | ≈ **1,8130** |
| Pareto `scale` | ≈ **657,99** |
| Pareto `logLik` | ≈ **−131.625,91** |
| Pareto AIC | ≈ **263.255,82** |
| Recomendada | **lognormal** |
| Score lognormal / loglogística / pareto / burr | ≈ **95,4 / 89,7 / 84,3 / 83,3** |
| Pilar B: máximo y mínimo | **100 y 0** (rango completo, no comprimido a 0,8) |

La última fila es la que demuestra que H2 está resuelto: hoy la parsimonia de las cinco sanas vale 0,8; después debe recuperar todo el rango.

---

## Parte II — H1: defensa del optimizador

Dos guardas independientes. Ninguna es una constante inventada para este caso.

### Guarda A — frontera numérica del espacio paramétrico *(obligatoria)*

En `.mle_optim()`, tras la optimización:

```r
if (any(!is.finite(par)) || any(par < .Machine$double.xmin)) {
  converged <- FALSE
  reason    <- "óptimo en la frontera numérica del espacio paramétrico"
}
```

**Justificación.** `.Machine$double.xmin` = 2,225·10⁻³⁰⁸ es el menor doble **normalizado**. Por debajo se entra en el rango subnormal, donde la mantisa pierde bits progresivamente hasta quedarse sin dígitos significativos. Un parámetro estimado ahí **no tiene ninguna cifra válida**. No es un umbral elegido: es una constante del estándar IEEE-754 que R expone.

El caso real: `scale = 4,94·10⁻³²⁴` < 2,225·10⁻³⁰⁸. **Dispara.**

**Coste y riesgo.** Nulo. Ninguna estimación legítima de escala o forma vive en el rango subnormal; si lo hiciera, el ajuste sería inutilizable de todos modos.

### Guarda B — verosimilitud no acotada, por resolución del dato *(recomendada)*

Aplicada en `.fit_one` tras estimar, usando `sample$resolution`:

$$\text{si}\quad \frac{\ell}{n} > -\log\delta + K \quad\Rightarrow\quad \text{converged} = \texttt{FALSE}$$

**Justificación estadística.** Si los datos se registran con resolución δ (aquí, céntimos: δ = 0,01), la verosimilitud correcta es la discretizada: $P(X\in[x\pm\delta/2])\approx f(x)\,\delta \le 1$, de donde

$$\log f(x) \le -\log\delta \quad\Longrightarrow\quad \overline{\log f} \le -\log\delta$$

Un ajuste que la supera está reclamando **más masa de probabilidad de la que existe**. Es el argumento clásico por el que la verosimilitud de una mixtura normal diverge cuando una componente colapsa sobre una observación.

**Propiedad clave: equivarianza de escala.** Si se multiplican los datos por $c$, entonces $\log f$ se desplaza en $-\log c$ y $-\log\delta$ también. **Ambos lados se mueven igual.** La guarda no puede ajustarse a un dataset concreto: es la misma condición en cualquier unidad.

**Calibración sobre los ficheros existentes** (réplica en Python; requiere reverificación en R):

| Fichero | δ | Cota $-\log\delta$ | Peor $\overline{\log f}$ | Margen |
|---|---:|---:|---:|---:|
| `continua_bimodal` | 0,03 | 3,51 | −9,09 | 12,60 |
| `continua_pareto_cola_pesada` | 0,03 | 3,51 | −9,19 | 12,70 |
| `limite_grande_20k` | 0,01 | 4,61 | −9,02 | 13,62 |
| `limite_casi_constante` | 0,0001 | 9,21 | **+3,25** | **5,97** |
| `limite_enteros_grandes` | 1 | 0,00 | −10,09 | 10,09 |
| `limite_muestra_pequena` | 4,34 | −1,47 | −8,68 | 7,21 |
| **`Cost_claims_year` (Pareto)** | **0,01** | **4,61** | **+599,72** | **−595,12** ⚠ |

Margen mínimo legítimo ≈ **6 nats**; la violación patológica es de **595 nats**. Cuatro órdenes de magnitud de separación.

Obsérvese `limite_casi_constante`: es el caso donde una densidad alta es **legítima**, y la guarda no se dispara precisamente porque su δ minúsculo eleva la cota. Es la equivarianza funcionando.

**Sobre K.** La desigualdad es exacta solo si $f$ es constante dentro de la celda; con curvatura el supremo real puede excederla ligeramente. Propongo **K = log(10) ≈ 2,303** (un orden de magnitud de holgura en densidad), declarado en `dfit_default_config()` con esta justificación. Con K = 0 la guarda seguiría siendo correcta en los 12 ficheros; K solo compra margen. **Decide tú**: puedo dejarlo en 0 y evitar la constante.

**Riesgo residual declarado.** Un dataset continuo con muy pocos valores distintos y rango estrecho podría acercarse a la cota. Por eso propongo B como **recomendada** y no como única defensa: A es exacta y suficiente para el caso conocido; B es la red model-agnóstica que cubre una divergencia que se detuviera *antes* del subnormal (p. ej. por agotar `maxit`).

**Casos borde de δ.** Con menos de 2 valores distintos, δ es indefinido → la guarda B se omite y solo actúa A. Se documenta, no se inventa un valor.

### Qué NO propongo

- **No** acotar `optim` con `lower`/`upper`: introduciría cotas arbitrarias en el espacio paramétrico y contradiría la razón de ser de ADR-014.
- **No** tocar `.mle_pareto()`: sus valores iniciales y su fórmula son correctos.
- **No** rechazar por `logLik > 0`: es scale-dependiente y produciría falsos positivos legítimos.

---

## Parte III — H3: Visual Engine

Cambio mínimo, casi mecánico una vez existe la muestra común.

**`build_visual_data()`** (`calc.R:1735-1739`): en lugar de

```r
x <- data[[analysis$meta$variable]]; x <- x[!is.na(x)]
```

usar `analysis$sample$x`. Histograma, KDE, rejilla y curvas ajustadas pasan a vivir en la misma muestra sobre la que se estimaron las densidades. Desaparece la mezcla incondicional/condicionada y el factor P(X>0) = 0,185 deja de faltar, porque deja de haber dos escalas.

**`build_qq_pp_data()`** (`calc.R:1699-1701`): elimina su llamada a `.prepare_support` y usa `analysis$sample$x`. Ya era correcta *por distribución*; ahora es además idéntica para todas.

**Firma.** Ambas conservan el argumento `data` para no romper `mod_tool.R` ni `b7_unit_tests.R`; queda como vestigial (solo validación) y así se declara en ADR-028.

**Fuera de alcance, registrado como UX v1.1:** eje X aplastado por los extremos (18 clases de Sturges sobre un rango de 260.853, con el 99,93 % en la primera). Requiere eje logarítmico, truncamiento por cuantil o zoom. **No se toca ahora.**

---

## Parte IV — Impacto y gobierno

### Ficheros afectados

| Fichero | Cambio | Alcance |
|---|---|---|
| `R/calc.R` | `build_analysis_sample()` nueva; `.fit_one` y `.diagnostics` dejan de filtrar; `.motor` cambia de firma interna; `.mle_optim` + guardas; `.build_warnings` global; `.text_builders` summary; `.vm_input_and_diagnosis` bloque `sample`; `dist_fit_analyze` orquesta; Visual Engine sobre `sample$x` | ~120 líneas netas |
| `R/mod_tool.R` | Ninguno funcional. *Opcional*: renderizar el bloque `sample` (H5) | 0 o ~15 líneas |
| `manifest.yml` | `version: 1.0.0 → 1.0.1` | 1 línea |
| `tests/b2_unit_tests.R` | 2 aserciones (§6) | ADR-026 |
| `tests/b5_unit_tests.R` | Verificar 1 aserción | probablemente 0 |
| `tests/b2_muestra_comun.R` | **Nuevo** (N1–N9) | — |
| `tests/regresion_cost_claims.R` | **Nuevo** | — |
| `data/samples/real_cost_claims_reducido.csv` | **Nuevo** (~5.000 filas) | — |
| `docs/decisions_log.md` | ADR-026/027/028 | gobierno |
| `README.md`, `RELEASE_AUDIT.md` | Muestra común y guardas | documentación |
| `ACCEPTANCE_MANUAL.md` | T-05 cambia de contrato | ver abajo |

### Versionado

- **`schema_version` 1.0.0 → 1.1.0.** El View Model gana el bloque `sample`. Cambio **aditivo**: ningún consumidor existente se rompe.
- **`decision_engine_version` 0.2 → sin cambio.** No se altera ningún peso, umbral ni regla de desempate. Se corrige **sobre qué datos** opera el criterio, no el criterio. Es exactamente la distinción que `decision_engine.md` §3 documenta.

### Impacto sobre el protocolo de aceptación

**T-05 cambia de contrato.** Hoy espera *"la exponencial conserva los ceros; la ficha muestra distinto nº de observaciones usadas según la distribución"*. Después debe esperar lo contrario: **mismo `n_used` para las siete** y **un solo aviso global** de exclusión. Es la prueba que codificaba el comportamiento defectuoso. Se actualizará tras aprobar ADR-026, y el protocolo se repite entero (criterio de cierre de baseline).

### ADRs propuestos — texto para tu aprobación, **no registrados**

**ADR-026 — Muestra común comparable en el análisis continuo.**
*Contexto:* AIC/BIC y estadísticos GoF se comparaban entre ajustes construidos sobre muestras distintas (95.554 vs 17.678 en `Cost_claims_year`), lo que invalida la comparación y, combinado con la degeneración de Lomax, distorsionó el ranking completo.
*Decisión:* la muestra del análisis se restringe una sola vez, antes del Motor, al soporte común a todas las candidatas del ranking. En la familia continua v1 eso implica excluir ceros y negativos globalmente; en la discreta no cambia nada. El control (Normal) se ajusta sobre la misma muestra.
*Consecuencias:* Tool-02 modeliza explícitamente **severidad condicionada a coste positivo**. `fit$n_excluded` queda vestigial. `schema_version` → 1.1.0. Dos aserciones de b2 cambian.

**ADR-027 — Guardas de convergencia del optimizador MLE.**
*Contexto:* con átomo en cero, la verosimilitud de Lomax no está acotada; el optimizador devolvió `converged = TRUE` con `scale = 4,94·10⁻³²⁴` y `logLik = +5,7·10⁷`.
*Decisión:* (A) rechazar como no convergente todo óptimo con algún parámetro por debajo de `.Machine$double.xmin`; (B) rechazar todo ajuste cuya log-verosimilitud media supere la cota por resolución del dato $-\log\delta$.
*Consecuencias:* los ajustes degenerados pasan a `excluded` con motivo visible en lugar de contaminar la normalización.

**ADR-028 — Coherencia de muestra en el Visual Engine.**
*Contexto:* histograma y KDE se construían sobre la muestra incondicional y se superponían a densidades condicionadas, con un desajuste de escala de ×8,05.
*Decisión:* todos los elementos gráficos consumen `analysis$sample$x`.
*Consecuencias:* `data` queda vestigial en la firma de las funciones del Visual Engine.

---

## Parte V — Orden de ejecución propuesto

1. Aprobar ADR-026/027/028 y registrarlos en `docs/decisions_log.md`.
2. **H2**: `build_analysis_sample()` + Motor + Diagnostics + aserción defensiva en `.assess`.
3. **H1**: guardas A y B.
4. **H3**: Visual Engine.
5. Text Builders y View Model (aviso global, summary, bloque `sample`).
6. Tests nuevos N1–N9 + regresión real; actualizar las 2 aserciones de b2.
7. Batería completa: debe volver a **0 `[FALLA]`**, 0 `[ERROR-VERIF]`.
8. Actualizar T-05 del protocolo y **repetir la aceptación manual completa**.

### Criterio de aceptación de la corrección

1. `grep -c "prepare_support("` en `calc.R` = **2**.
2. Los 7 ajustes continuos comparten `n_used` en todo dataset con ceros.
3. `Cost_claims_year` reproduce el contrafactual dentro del 5 %.
4. Pareto: `scale ≈ 658`, `logLik ≈ −131.626`, AIC ≈ **263.256** — finito y del mismo orden que el resto.
5. Pilar B recupera rango completo (máx 100, mín 0).
6. Ningún test previo cambia salvo las 2 aserciones autorizadas por ADR-026.

**No se toca ADR-021 ni la confianza.** Con datos comparables, ΔAIC pasará de −114.873.666 a **−1.767,70** (ya calculado): sigue negativo y la confianza sigue siendo "baja". Eso es el defecto conceptual H4, que se evaluará después y por separado, tal como has indicado.

---

*Actuarial Tools by BMK — Diseño. Pendiente de aprobación. Sin código modificado.*
