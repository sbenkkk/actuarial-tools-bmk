# Tool-02 — B13: contrato de bootstrap no paramétrico para incertidumbre del estimador

> **ESTADO: CONTRATO CONGELADO (ADR-035) · B13.1 CLOSED / APPROVED (ADR-036).**
>
> El motor está implementado en `R/calc.R` §2c-quater y **validado por ejecución
> real en R 4.4.1**: `tests/b13_bootstrap_tests.R` bloques **A–O PASS** y **15
> suites de regresión PASS**. `renv` inicializado en la raíz; `digest 0.6.37`
> registrado en `renv.lock`.
>
> **Sigue sin implementarse:** la integración pública en `fit$inference`
> —diferida a **B16** junto con el schema futuro—, la UI, y B14/B15/B17. El
> bootstrap es hoy un objeto **standalone**: `manifest` 1.0.2 y
> `DFIT_SCHEMA_VERSION` 1.1.0 sin cambios.
>
> Las decisiones marcadas **FROZEN** están congeladas por el owner. Las marcadas
> **OPEN** no lo están, y se indica si bloquean la implementación.

---

## 1. Objetivo

Cuantificar la incertidumbre de un **estimador**, cualquiera que sea, mediante
**bootstrap no paramétrico iid**, sin depender de normalidad asintótica ni de que
el estimador maximice una verosimilitud.

```
para b = 1, …, B:
    x*⁽ᵇ⁾  = sample(sample$x, size = n, replace = TRUE)
    θ̂⁽ᵇ⁾  = estimator( x*⁽ᵇ⁾ )     ← EL MISMO estimador y la MISMA configuración

{ θ̂⁽¹⁾, …, θ̂⁽ᴮ⁾ }  aproxima la distribución muestral de θ̂ bajo el bootstrap
```

**Por qué importa para Tool-02:** B12 cubre solo el MLE, por una razón
estructural —la información observada exige que el score se anule en θ̂—. **MoM,
L-momentos y Percentile Matching quedan sin ninguna medida de incertidumbre hasta
B13.** PM en particular es hoy un estimador productivo, congelado y validado, del
que no publicamos ni un error estándar.

---

## 2. Distinción crítica: dos bootstraps que **no** deben unificarse

| | **A. Incertidumbre de parámetro (B13)** | **B. Calibración GoF (ADR-008)** |
|---|---|---|
| Pregunta | ¿Cuánto varía **θ̂** si la muestra hubiera sido otra? | ¿Es **extremo** este estadístico GoF bajo el modelo ajustado? |
| Remuestreo | **No paramétrico**: se remuestrean las **observaciones** | Puede exigir **simulación paramétrica** desde el modelo ajustado |
| Hipótesis | Ninguna sobre el modelo: la EDF es el «universo» | **Asume que el modelo ajustado es cierto** |
| Salida | Réplicas de θ̂, SE, sesgo, IC percentil | Distribución nula de un estadístico, p-valor calibrado |
| Uso del ajuste | Se reestima en cada réplica | Se usa como generador |

**FROZEN — dos motores separados.** No comparten estado, semilla, configuración
ni estructura de salida. Fusionarlos produciría un motor que responde a una
pregunta y se lee como si respondiera a la otra. Si algún día conviene compartir
infraestructura, será la de *ejecución de réplicas*, nunca la semántica.

---

## 3. Muestra bootstrap — **P-1, FROZEN**

**B13 remuestrea exclusivamente `sample$x`**, la muestra de análisis común ya
construida por ADR-026. **No** se vuelve al dato original, ni a `x_valid`, ni a
las observaciones excluidas.

```
x*_b = sample(sample$x, size = length(sample$x), replace = TRUE)
```

`n` es constante en todas las réplicas.

**Consecuencia semántica, que debe declararse al usuario:** el bootstrap estima la
incertidumbre del **mismo objeto estadístico** que el ajuste original. Para
severidad continua con ceros excluidos, eso significa que **B13 estima la
incertidumbre de la distribución condicional positiva**, no de la distribución
completa con su átomo en cero. Es la lectura correcta —es lo que se ajustó—, pero
no es la misma pregunta que «cuánta incertidumbre hay sobre la severidad total».
**METHODOLOGICAL LIMITATION declarada, no defecto.**

---

## 4. Alcance de estimadores

El motor ejecuta **exactamente el mismo estimador con exactamente la misma
configuración** que produjo el ajuste original.

| Estimador | Configuración que debe replicarse |
|---|---|
| MLE | distribución |
| MoM | distribución |
| L-momentos | distribución |
| **Percentile Matching** | distribución · **percentiles seleccionados** · objetivo congelado (`s_Q`, pesos uniformes) · preset o configuración manual |

**PM fija el diseño de la interfaz.** Su configuración no se reduce al id de la
distribución: incluye el vector de percentiles. Un motor que recibiera solo
`(id, method)` no podría reproducir PM.

---

## 5. Arquitectura — **OD-10, RESOLVED FOR B13**

**FROZEN.** Motor **Shiny-free**, inicialmente en `R/calc.R`, diseñado como
**motor genérico con estimador inyectado**:

```r
.bootstrap_estimator(x, estimator_fn, B, seed, confidence_level, ...)
```

`estimator_fn` es un **adaptador** construido fuera del motor que:

- toma una muestra bootstrap;
- ejecuta **exactamente** el estimador y la configuración originales;
- devuelve `list(success, params, status, reason)`.

**El motor NO contiene un `switch` que duplique MLE / MoM / L-mom / PM.** Esa es
la decisión de diseño central: evita duplicar lógica, mantiene una sola fuente de
reglas productivas, sirve a los cuatro estimadores sin conocerlos, facilita la
promoción futura a `shared/` —sería un movimiento de fichero, no una
reescritura— y lo deja reutilizable para incertidumbre de VaR/TVaR, donde el
«estimador» sería una función de riesgo sobre θ̂.

**No se promueve a `shared/` todavía**: la regla 4 exige dos o más consumidores y
hoy hay uno.

---

## 6. Contrato de salida — **FROZEN en semántica**

Los nombres exactos pueden ajustarse en implementación; **la semántica no**.

```r
fit$inference$bootstrap <- list(
  method           = "nonparametric_bootstrap",
  status           = ,      # not_requested | complete | partial | failed
  valid            = ,
  reason           = ,

  B_requested      = 1000L,
  B_success        = ,
  B_failed         = ,
  success_rate     = ,      # B_success / B_requested

  seed             = ,
  confidence_level = 0.95,
  quantile_type    = 7L,
  estimator        = ,      # "mle" | "mom" | "lmom" | "pm"
  distribution     = ,
  parameter_names  = ,      # orden canónico de la distribución
  pm_percentiles   = ,      # NULL salvo PM

  replicates       = ,      # matriz B_success x k, dimnames = list(NULL, nombres)
  se               = ,      # §8
  bias             = ,      # §9  (DIAGNÓSTICO)
  ci               = ,      # §7
  failures         = list(counts = c(<motivo> = n, ...), examples = ),

  warnings         = character(0)
)
```

**`replicates` como matriz `B_success × k`, no anidada por parámetro.** Preserva
el **emparejamiento** entre parámetros dentro de cada réplica —imprescindible
para la futura propagación a VaR/TVaR, que necesita θ*ᵦ completo—; el número de
filas **es** `B_success`, sin dos contadores que puedan desincronizarse; y es
trivialmente serializable.

---

## 7. Intervalo de confianza — **P-2, FROZEN**

**Bootstrap percentil**, con el tipo de cuantil **explícito**:

```r
stats::quantile(replicates[, j],
                probs = c(alpha/2, 1 - alpha/2),
                type  = 7,
                names = FALSE)
```

```
CI_j = [ Q*_{α/2} , Q*_{1−α/2} ]
```

Sin BCa, sin studentized, sin bootstrap-t, sin corrección de sesgo.

### 7.1 Por qué se respeta el soporte — argumento corregido

> **CORRECCIÓN metodológica (ADR-035).** Una versión anterior de este contrato
> justificaba el respeto del soporte diciendo que «los extremos del IC son
> valores efectivamente alcanzados por las réplicas». **Es falso con
> `stats::quantile()`**, que con `type = 7` **interpola** entre estadísticos de
> orden: el extremo publicado puede no ser ninguna réplica observada.

El argumento correcto es de **convexidad**. Los espacios paramétricos de Tool-02
son `ℝ`, `(0, ∞)` y `(0, 1)`, **todos intervalos convexos**. Un cuantil de
`type = 7` es una **combinación convexa de dos réplicas válidas**, luego cae en el
segmento que las une y por tanto dentro del mismo intervalo:

- parámetros positivos → el extremo permanece **> 0**;
- probabilidades → el extremo permanece **dentro de (0, 1)**;
- parámetros libres → permanece en **ℝ**.

**No hace falta que el extremo sea una réplica observada; basta con que el soporte
sea convexo y las réplicas válidas estén dentro.** Es el mismo objetivo que
persigue OD-16 en la vía analítica, alcanzado por otro camino y con una
justificación que sí se sostiene.

`quantile_type = 7` se **registra en la salida**: sin él, el intervalo no es
reproducible entre implementaciones.

---

## 8. Error estándar bootstrap — **FROZEN**

```
SE_boot(θⱼ) = sd( θ̂ⱼ*⁽¹⁾, …, θ̂ⱼ*⁽ᴮ_success⁾ )      desviación típica MUESTRAL de R
```

sobre réplicas **válidas**.

**Esto no es el MSE**, y la distinción debe quedar escrita porque hay material
académico previo del proyecto cuya anotación se presta a confusión:

```
MSE(θ̂) = Var(θ̂) + Bias(θ̂)²
```

`sd(replicates)` estima la **desviación típica de la distribución bootstrap del
estimador**. Con precisión: **`SE_boot` es una ESTIMACIÓN bootstrap de
`sqrt(Var(θ̂))`** —la estima, no la iguala: tiene su propio error de Monte Carlo,
que decrece con `B`—. Y como `MSE(θ̂) = Var(θ̂) + Bias(θ̂)²`, **`SE_boot` no es el
MSE ni contiene el término de sesgo**, aun cuando estimara la varianza a la
perfección. **B13 no publica MSE.**

> **CORRECCIÓN de redacción (2026-09-03).** La versión anterior decía «la raíz de
> la primera componente, y solo de la primera», lo que implicaba **identidad
> exacta** entre `sd(θ̂*)` y `sqrt(Var(θ̂))`. **No cambia ninguna decisión
> congelada**: `SE_boot` sigue definido igual y B13 sigue sin publicar MSE.

---

## 9. Sesgo bootstrap — diagnóstico, no corrección — **FROZEN**

```
Bias_boot(θⱼ) = mean( θ̂ⱼ* ) − θ̂ⱼ
```

Se publica como **diagnóstico técnico**. **No se corrige θ̂. No se crea
`theta_hat_corrected = theta_hat − Bias_boot` en B13.** La corrección de sesgo
**aumenta la varianza**, y si el sesgo se estima con ruido puede empeorar el error
cuadrático total; publicarla como estimación alternativa sin esa advertencia
induciría a error. **OD-12 sigue OPEN / DEFERRED.**

---

## 10. Imposibilidad matemática **≠** calidad Monte Carlo

Son dos conceptos distintos y el contrato los mantiene separados. La versión
anterior los mezclaba.

### 10.1 Imposibilidad matemática — **se codifica ahora, FROZEN**

Condiciones bajo las cuales una cantidad **no existe**, con independencia de
cualquier juicio de calidad:

| `B_success` | Qué existe | Qué no existe |
|---|---|---|
| **0** | Nada | **No hay distribución bootstrap empírica.** Sin SE, sin sesgo, sin IC. `valid = FALSE` |
| **1** | `mean(θ*)` existe, luego **`Bias_boot` es formalmente calculable** | **`sd()` muestral no está definida** (cero grados de libertad): sin SE. El IC percentil degenera a un punto |
| **≥ 2** | SE, sesgo e IC son calculables | — |

> **CORRECCIÓN (ADR-035).** La versión anterior afirmaba que con `B_success = 1`
> tampoco había sesgo. **Era incorrecto:** la media de una sola réplica existe, de
> modo que `Bias_boot` es formalmente calculable. Lo que no está definido es la
> **desviación típica muestral**. Que el sesgo así calculado carezca de **utilidad
> práctica** es una cuestión distinta —de calidad, §10.2— y no debe presentarse
> como imposibilidad matemática. Confundir ambas cosas debilita el argumento
> cuando de verdad hace falta.

### 10.2 Calidad estadística / Monte Carlo — **NO se codifica como PASS/FAIL**

Situaciones que **se registran objetivamente** y **no** se convierten todavía en
un veredicto:

- percentiles que coinciden con el mínimo o el máximo de las réplicas;
- pocos valores efectivos en las colas de la distribución bootstrap;
- `success_rate` bajo;
- pocas réplicas;
- IC inestable entre ejecuciones;
- sensibilidad extrema a una sola réplica.

**No se introduce ningún umbral arbitrario.** Nada del tipo «`success_rate < 0,90`
⇒ bootstrap inválido»: sería un número inventado, y ADR-021 ya enseñó lo que
cuesta calibrar un umbral sobre un dataset concreto. **OD-11 permanece OPEN /
DEFERRED**; la política de calidad e interpretación se decidirá con evidencia,
previsiblemente contra la vía analítica en B15.

Se publica un **aviso objetivo** cuando hay fallos —cuántos y por qué motivo—,
sin etiqueta valorativa y sin `High / Medium / Low`.

---

## 11. Réplicas fallidas — **OD-9, RESOLVED FOR B13**

**Principio FROZEN:**

> Una réplica que **no produce un ajuste válido según las mismas reglas
> productivas** que el estimador original se clasifica como **FAILED**.

**Prohibido**, dentro del bucle bootstrap: reparar la réplica · cambiar de método ·
relajar guardas · sustituir parámetros · usar cualquier *fallback* silencioso ·
convertir un fallo en éxito.

**Razón:** relajar las reglas dentro del bucle produciría la distribución
bootstrap de **un estimador que no es el que se usa en producción**, y por tanto
una incertidumbre que no describe al estimador real. El bootstrap debe heredar las
reglas, no negociarlas.

**ADR-027 no se modifica.**

### 11.1 Motivos de fallo que deben registrarse

Con la taxonomía productiva existente, no una nueva:

| Motivo | Origen |
|---|---|
| `optimizer_failure` | El optimizador no alcanzó una solución finita |
| `boundary_guard` | Guarda (A) de ADR-027: óptimo en la frontera numérica |
| `loglik_implausible` | Guarda (B) de ADR-027: verosimilitud no acotada |
| `reject_scale_collapse` | PM: `s_Q = 0`, los cuantiles objetivo colapsan |
| `reject_start` | PM: no se pudo construir un arranque válido |
| `reject_config` | PM: configuración inválida en la réplica |
| `estimator_unavailable` | MoM / L-momentos sin solución válida para esa réplica |
| `degenerate_replica` | Réplica sin variabilidad suficiente para el estimador |
| `nonfinite_params` | Parámetros no finitos |

Se registran **conteos por motivo**, no solo el total: 200 fallos por frontera
numérica y 200 por no convergencia son diagnósticos **distintos**. Y unos pocos
**ejemplos** (índice de réplica y estado parcial) para auditoría, con tope de
tamaño.

> **CORRECCIÓN (ADR-035).** La versión anterior ilustraba OD-9 con «el remuestreo
> cambia la proporción de ceros y Lomax dispara ADR-027». **Ese ejemplo era
> incorrecto para el flujo continuo actual y contradecía P-1**: `sample$x` ya
> excluye los ceros en la capa 0.5 (ADR-026), de modo que ninguna réplica puede
> contener ceros y la guarda (A) sobre Lomax **no puede dispararse por esa vía**.
> Retirado y sustituido por la tabla de motivos reales.

---

## 12. Selección condicionada al éxito — **OD-17, OPEN**

Los resúmenes bootstrap se calculan sobre las réplicas **válidas**:

```
{ θ*_b : success_b = TRUE }
```

Es decir, proceden de `L(θ̂* | success = TRUE)` y **no necesariamente** de la
distribución bootstrap completa `L(θ̂*)`.

**FORMULACIÓN CONGELADA:**

> Si la probabilidad de éxito de una réplica depende del valor que habría tomado
> el estimador, los resúmenes calculados sobre las réplicas válidas pueden no
> representar la distribución bootstrap no condicionada. **La dirección y
> magnitud de esa distorsión dependen del mecanismo de fallo y no se determinan
> en B13.**

Si `P(success | θ̂*)` depende de `θ̂*`, hay **sesgo de selección**. Según el patrón
de fallos, la distorsión puede **estrechar** la distribución, **ensancharla**,
**desplazarla**, **afectar preferentemente a una cola**, o **alterar sesgo, SE e
IC de formas distintas entre sí**.

> **CORRECCIÓN (2026-09-03).** Una versión anterior de este contrato afirmaba
> que el sesgo esperado iba «en la dirección de estrechar los extremos, es decir,
> de subestimar la incertidumbre, que es la peor dirección posible». **Esa
> dirección no estaba justificada y se retira.** El argumento sostiene que la
> distribución condicionada puede diferir de la no condicionada; **no** sostiene
> en qué sentido. Sin conocer `P(success | θ̂*)` no puede deducirse el signo del
> efecto: un mecanismo que falla en la cola estrecharía, pero uno que falla cerca
> del centro —réplicas degeneradas con poca dispersión, por ejemplo— ensancharía.
> `METHODOLOGICAL OVERREACH` en documentación; **sin efecto sobre el código**,
> que nunca dependió de esa dirección.

**FROZEN como consecuencia:** siempre deben almacenarse `B_requested`,
`B_success`, `B_failed`, `success_rate` y los motivos de fallo agrupados. **El
producto nunca debe presentar un IC bootstrap sin acompañarlo internamente de esta
información.**

**No se introduce umbral de `success_rate`** ni se declara automáticamente
inválido un bootstrap por una fracción concreta de fallos. La política de
interpretación se decidirá con evidencia.

**OD-17 — OPEN / DOES NOT BLOCK B13 IMPLEMENTATION.**

---

## 13. Reproducibilidad — **P-3, FROZEN**

Una **única** llamada a `set.seed(seed)` al inicio de la ejecución bootstrap, y a
continuación **B remuestreos secuenciales** con el RNG de R. **No** se deriva una
semilla independiente por réplica en v1.1: solo haría falta para paralelizar, que
no está en el alcance.

Reproducir un resultado exige el mismo `seed`, `B`, `x`, estimador y
configuración, y la misma versión de R/RNG cuando sea relevante. **`seed` se
registra en la salida.**

---

## 14. Memoria — **OD-7, RESOLVED**

**FROZEN: se almacenan todas las réplicas válidas** en una matriz
`B_success × k` de `double`.

```
5000 × 3 × 8 bytes = 120.000 bytes ≈ 117 KiB
```

más el overhead de R. **No es un problema material para Tool-02.** Y B13 actúa
sobre **una distribución seleccionada**, no sobre las siete continuas
simultáneamente.

Por tanto, y explícitamente: **sin streaming, sin reservoir sampling, sin
eliminación temprana, sin compresión, sin límite artificial adicional.**
Optimizar aquí sería resolver un problema que las cifras dicen que no existe.

Las réplicas se conservan porque se necesitan para: SE · sesgo · IC percentil ·
histogramas y densidades de B16 · comparación analítico-*vs*-bootstrap de B15 ·
futura propagación a VaR/TVaR. **P-5 FROZEN.**

Se conservan **internamente**; **no** entran en el export estándar.

---

## 15. `B` y nivel de confianza — decisiones de producto

| Parámetro | Valor |
|---|---|
| `confidence_level` | Defecto **0,95**; configurable; validado como escalar finito **estrictamente en (0,1)**, misma regla que la vía analítica |
| `B` | Defecto **1000**; presets 500 / 1000 / 2000 / 5000; valor libre en modo avanzado |

**`B = 5000` no será defecto sin benchmark de rendimiento**, y no se ejecuta
ahora. Para dimensionar la decisión, **extrapolación y no medición de bootstrap**:
B11.1 midió ≈ 2,4 ms por ajuste de Burr, el más caro del catálogo, lo que daría
≈ 2,4 s con `B = 1000` y ≈ 12 s con `B = 5000`. Doce segundos sin
retroalimentación exigen indicador de progreso — decisión de B16, no de B13.

**No se introduce un `B` mínimo de calidad.** Los únicos mínimos son los
estructurales de §10.1.

---

## 16. Fuera del alcance de B13

Bootstrap paramétrico de GoF (ADR-008) · BCa, bootstrap-t, studentized ·
bootstrap dependiente o por bloques · corrección de sesgo (OD-12) · etiquetas de
estabilidad (OD-11) · MSE como salida · incertidumbre de VaR/TVaR · comparación
analítico-*vs*-bootstrap (B15) · UI (B16) · métodos bayesianos.

---

## 17. Estado de las decisiones

| # | Decisión | Estado |
|---|---|---|
| P-1 | Remuestrear `sample$x` (ADR-026); `n` constante; incertidumbre de la distribución condicional | **FROZEN** |
| P-2 | IC percentil con `stats::quantile(type = 7)`; soporte respetado por **convexidad** | **FROZEN** |
| P-3 | Semilla única al inicio, remuestreos secuenciales | **FROZEN** |
| P-5 | Conservar todas las réplicas válidas, sin tope | **FROZEN** |
| §2 | Dos motores separados (B13 ≠ ADR-008) | **FROZEN** |
| §5 | Motor genérico con estimador inyectado, en `calc.R`, sin `switch` | **FROZEN** (OD-10 RESOLVED FOR B13) |
| §8 | `SE_boot = sd(θ*)`; **no es MSE** | **FROZEN** |
| §9 | Sesgo como diagnóstico; sin corrección | **FROZEN** |
| §10.1 | Mínimos estructurales por imposibilidad matemática | **FROZEN** |
| §10.2 | Calidad Monte Carlo: se registra, no se juzga | **FROZEN** (OD-11 OPEN) |
| §11 | Réplica inválida ⇒ FAILED, sin reparación | **FROZEN** (OD-9 RESOLVED FOR B13) |
| §12 | Contadores y motivos siempre presentes | **FROZEN** (OD-17 OPEN) |
| §18 | Huella de datos | ✅ **RESOLVED** — OD-6 (SHA-256 vía `digest`) |
| — | **Identidad de muestra entre vías de inferencia** | **OD-18 — OPEN / BLOCKS B15 COMPARISON** |

> **OD-18, registrada aquí para trazabilidad (abierta en B14.0, ADR-037).**
> B13 emite `data_fingerprint`; **el bloque analítico de B12 no**. En
> consecuencia no puede verificarse que ambas vías se calcularon sobre el mismo
> vector: solo coincide `n`, condición necesaria y no suficiente. **Mientras no
> sea verificable, B15 no puede realizar la comparación analítico-*vs*-bootstrap**,
> porque una discrepancia sería inatribuible —¿método, o dato?—. No se resuelve
> en B13 ni en B14: toca contratos de bloques *frozen* o la capa de análisis.

---

## 18. Huella de datos — **OD-6, OPEN**

Objetivo: detectar que un bootstrap guardado corresponde a **otros** datos. Es una
**huella de identidad de datos**, **no** un hash resistente a manipulación: no hay
adversario en el modelo de amenazas, solo el riesgo de sustitución accidental.

### 18.1 El requisito decisivo: **sensibilidad al orden**

Antes de comparar alternativas conviene fijar esto, porque **descarta una de
ellas por corrección, no por robustez**.

`sample()` con una semilla fija selecciona **índices**. Si `x` se permuta, los
mismos índices apuntan a valores distintos y **el bootstrap produce réplicas
distintas**. Por tanto, para que la huella cumpla su función —«este bootstrap
corresponde a estos datos»— **debe ser sensible al orden**. Una huella que
declarase «mismos datos» para un vector permutado estaría avalando un resultado
irreproducible.

**La huella de B13 debe ser sensible al orden. FROZEN como requisito.**

### 18.2 Alternativas

| | Enfoque | Sensible al orden | Colisiones | Dependencia | Coste | Riesgo de implementación |
|---|---|---|---|---|---|---|
| **A** | Invariantes numéricos: `n`, `sum`, `sum(x²)`, `min`, `max`, cuantiles | **NO** (son funciones simétricas) | Altas: cualquier permutación colisiona; y dos muestras con los mismos momentos también | Ninguna | Muy bajo | Nulo |
| **B** | `digest::digest(x)` | Sí | Despreciables (SHA/xxHash) | **Nueva, fuera del stack aprobado** | Bajo | Nulo (paquete maduro) |
| **C1** | `serialize()` a fichero temporal + **`tools::md5sum()`** | Sí | Despreciables | **Ninguna que instalar**: `tools` es paquete base | Bajo + E/S | Muy bajo |
| **C2** | Checksum tipo Adler-32 vectorizado sobre `serialize(x, NULL)` | Sí | ~2⁻³² por par con dos acumuladores; mejorable con lanes | Ninguna | Bajo | **Medio**: código de hash escrito a mano |

### 18.3 Análisis

**A queda descartada por corrección, no por debilidad.** `sum`, `min`, `max` y los
cuantiles son **funciones simétricas**: una permutación de `x` da exactamente la
misma huella y sin embargo **un bootstrap distinto** con la misma semilla. Es
precisamente el fallo que la huella debe evitar. Añadido: la aritmética de coma
flotante hace que `sum()` ni siquiera sea *exactamente* invariante bajo
permutación, de modo que A no es fiablemente sensible **ni** fiablemente
insensible al orden — lo peor de ambos mundos.

**B es la solución técnicamente limpia.** Una línea, paquete maduro, colisiones
despreciables. El coste real es de gobernanza: el stack aprobado no lo incluye y
exige autorización expresa. Conviene decir que la regla «sin dependencias nuevas»
existe para **mantener el stack pequeño**, no para obligarnos a escribir nuestro
propio hash — que es justo el tipo de código donde un error pasa inadvertido
durante meses.

**C1 es el punto intermedio honesto.** `tools` es un **paquete base**: viene con
R, no hay nada que instalar y no amplía el stack en el sentido que importa.
`tools::md5sum()` da calidad criptográfica en tres líneas. Su pega es real: exige
un **fichero temporal**, lo que introduce un efecto de E/S en una función que
debería ser pura y puede fallar en entornos de sólo lectura o con `TMPDIR`
restringido. Mitigable con `tryCatch` y degradación explícita, pero es un efecto
lateral que hay que declarar.

**C2 es viable y es el que menos recomiendo.** Un doble acumulador estilo Adler-32
sobre la salida de `serialize()` es determinista, sensible al orden, vectorizable
con `cumsum` y sin dependencias. Pero hay que trocear por bloques con reducción
modular para no desbordar los 2⁵³ de un `double` con muestras grandes, y ese es
exactamente el tipo de detalle que se implementa mal y no da la cara hasta que un
usuario tiene un dataset grande. **Escribir un hash a mano para ahorrar una
dependencia base es un mal cambio.**

### 18.4 OD-6 — **RESOLVED / IMPLEMENTED / VALIDATED**

> **Decisión (owner): `digest` AUTORIZADO. SHA-256 sobre el vector de análisis,
> determinista y sensible al orden.**
>
> **Implementación:** `.data_fingerprint()` en `R/calc.R` §2c-quater, con
> `algo = "sha256"` y `serialize = TRUE` **explícitos** y guarda de dependencia
> sin sustituto.
>
> **Validación real (R 4.4.1):** bloque B de `tests/b13_bootstrap_tests.R`,
> **B.1–B.20 PASS**. Verificados: SHA-256 · 64 caracteres hexadecimales ·
> determinismo · **sensibilidad al orden** · sensibilidad a cambios pequeños ·
> `x` sin ordenar, deduplicar, redondear ni resumir · rechazo auditable de
> entradas inválidas · **`NA` y `NaN` distinguidos en el motivo** · **sin
> fallback a MD5** · propagación exacta al resultado bootstrap · misma
> configuración ⇒ mismo fingerprint y mismas réplicas.
>
> **Infraestructura: RESUELTA.** `renv` inicializado en la raíz, `renv.lock`
> versionado, `.Rprofile` activo. `digest 0.6.37` registrado. `renv::status()`:
> *«No issues found — the project is in a consistent state.»* Ver §18.7.

#### Contexto original del bloqueo (se conserva la traza)

> **OD-6 — RESOLVED FOR B13 en lo metodológico.** El owner autoriza `digest` y se
> adopta **SHA-256 sobre el vector numérico de análisis**, determinista y
> sensible al orden.
>
> **La implementación productiva queda BLOQUEADA por un motivo distinto y
> ajeno a la decisión: `ENVIRONMENT / DEPENDENCY ISSUE`.**
>
> El mecanismo de dependencias **declarado** por el proyecto es **renv**
> —`README` §17 («`renv.lock` — único lockfile de dependencias del proyecto»),
> `.gitignore` con siete entradas `renv/…`, y `.Rprofile` preparado para
> activarlo—. Pero **renv no está inicializado**: no existe la carpeta `renv/`,
> no existe `renv.lock`, y la línea `source("renv/activate.R")` está
> **comentada**.
>
> Consecuencia: **aunque `digest` esté instalado en la máquina del owner, hoy no
> hay forma coherente de declararlo.** Usarlo en este estado produciría
> exactamente la «dependencia fantasma que solo funciona en esta máquina» que el
> encargo prohíbe: el código fallaría en cualquier clon del repositorio sin que
> nada en el proyecto explicara por qué.
>
> **Por tanto `.data_fingerprint()` NO se implementa** y devuelve
> `status = "not_available"` con motivo auditable. **No se sustituye por
> ninguna otra solución** (§18.3 A queda descartada por corrección, no por
> conveniencia). El punto de inserción es único y está documentado en el código.
>
> **Remediación, en este orden:**
> 1. `renv::init()` en la raíz del repositorio;
> 2. `renv::install("digest")`;
> 3. `renv::snapshot()` para fijarlo en `renv.lock`;
> 4. descomentar `source("renv/activate.R")` en `.Rprofile`;
> 5. añadir `digest` al stack declarado del `README`.
>
> Solo entonces el cuerpo de `.data_fingerprint()` puede escribirse como
> `digest::digest(x, algo = "sha256", serialize = TRUE)`.

### 18.5 Semántica acordada del fingerprint (para cuando se desbloquee)

| Cuestión | Respuesta |
|---|---|
| Qué se hashea | El **vector numérico de análisis** `sample$x`, tal cual, sin redondeo ni normalización previa |
| `serialize` | **`TRUE`**. Sobre un vector numérico produce una representación binaria determinista del objeto R completo, incluidos tipo y longitud. Con `serialize = FALSE`, `digest` hashea la representación de texto, que depende de opciones de formato y es una vía innecesaria de fragilidad |
| Algoritmo | **`algo = "sha256"`, explícito.** No se depende del defecto de `digest()`, que es MD5 y podría cambiar entre versiones |
| Formato de salida | Cadena hexadecimal de **64 caracteres** (256 bits) |
| Sensibilidad al orden | **Sí, por construcción**: la serialización preserva el orden de los elementos. Es el requisito decisivo de §18.1 |
| `NA` / `NaN` / `Inf` | **No deben llegar**: `sample$x` es una muestra de análisis válida. Aun así, la función debe **rechazarlos de forma auditable** en lugar de hashearlos, porque un hash de un vector con `NA` sería una identidad válida de un objeto inválido. Nótese además que `NaN` y `NA_real_` tienen representaciones distintas y darían huellas distintas, lo que refuerza que el filtrado debe ser explícito y no implícito |
| Modelo de amenazas | **Identidad práctica de datos, no resistencia a un adversario.** SHA-256 se elige por disponibilidad y ausencia de colisiones accidentales, no por criptografía |

### 18.7 Infraestructura renv — **RESUELTA**

> **`DEPENDENCY / REPRODUCIBILITY ISSUE — RESOLVED.`**
> Nunca fue un defecto estadístico del bootstrap: era una carencia de
> **declaración de dependencias**. Se registra con esa clasificación.

**Estado tras la inicialización (verificado en el repositorio):**

| Elemento | Estado |
|---|---|
| `renv/activate.R` | Presente y versionado |
| `renv.lock` | Presente. **R 4.4.1**, repositorio CRAN, **84 paquetes** |
| `.Rprofile` | **Activo**: `source("renv/activate.R")` sin comentar |
| `renv/.gitignore` | Generado por renv; ignora `library/`, `local/`, `cellar/`, `lock/`, `python/`, `sandbox/`, `staging/` |
| `renv/settings.json` | `snapshot.type: "implicit"`, `vcs.manage.ignores: true` |
| `renv::status()` | *No issues found — the project is in a consistent state* |

**Los 84 paquetes NO son un `DEPENDENCY SNAPSHOT ISSUE`.** Es el cierre
transitivo correcto del stack declarado en el `README`: los quince paquetes de
primer nivel —`shiny`, `bslib`, `ggplot2`, `plotly`, `DT`, `dplyr`, `tidyr`,
`readr`, `glue`, `shinycssloaders`, `bsicons`, `yaml`, `renv`, `digest`,
`systemfonts`— están todos presentes, y el resto son sus dependencias
recursivas. Un lockfile de tres entradas habría sido el resultado *incorrecto*.

**Versiones registradas y una diferencia observada.** `digest 0.6.37`, la misma
que estaba instalada. `renv` quedó registrado como **1.2.4**, mientras que la
inspección previa a la inicialización reportaba **1.1.8**: renv se actualizó a sí
mismo durante `init()`, comportamiento normal de la herramienta. Se deja
constancia por trazabilidad; no afecta a `digest` ni al contrato.

**Requisito operativo, no defecto del producto.** `.Rprofile` solo se carga si R
arranca con **la raíz del repositorio** como directorio de trabajo. Ejecutar con
`cd tools/distribution-fitting && Rscript tests/…` **no activaría renv** y
resolvería `digest` contra la librería global, anulando el propósito del
lockfile. Los scripts resuelven su raíz con `.locate_script()` y funcionan desde
cualquier sitio, de modo que **deben invocarse desde la raíz**.

#### Contexto previo a la inicialización (se conserva la traza)

**Inspección de la raíz `actuarial-tools-bmk/` (2026-09-03):**

| Elemento | Estado |
|---|---|
| `.Rprofile` | Existe. **Tres líneas, las tres comentarios.** La tercera es `# source("renv/activate.R")`. **Ninguna otra lógica**: descomentarla no afecta a nada más |
| `.gitignore` | **Ya correcto**: ignora `renv/library/`, `renv/local/`, `renv/cellar/`, `renv/lock/`, `renv/python/`, `renv/sandbox/`, `renv/staging/`, versionando por tanto `renv.lock` y `renv/activate.R` |
| `README` §17 | Ya declara «`renv.lock` — único lockfile de dependencias del proyecto» y `renv` en el stack |
| `renv/`, `renv.lock`, `DESCRIPTION` | **No existen** |
| Otro sistema de dependencias | **Ninguno**. No hay conflicto |

**Conclusión: la intención estaba declarada y la configuración preparada; solo
falta ejecutar la inicialización.** No hay decisión pendiente, solo una acción.

**No se descomenta `.Rprofile` todavía.** `source("renv/activate.R")` sobre un
fichero inexistente **aborta el arranque de toda sesión R** del repositorio.
Además, `renv::init()` **escribe esa línea por sí mismo**; el cambio manual solo
haría falta si quedara duplicada con la comentada.

**Aviso operativo, no trivial.** `.Rprofile` solo se carga si R **arranca con la
raíz del repositorio como directorio de trabajo**. Las suites se han venido
ejecutando con `cd tools/distribution-fitting && Rscript tests/…`, y en la
carpeta de la herramienta **no hay `.Rprofile`**: en esa forma de invocación
**renv no se activaría** y `digest` se resolvería contra la librería global,
anulando el propósito del lockfile. Los scripts de test resuelven su raíz con
`.locate_script()` y funcionan invocados desde cualquier sitio, de modo que la
recomendación es **ejecutarlos siempre desde la raíz del repositorio**.

### 18.8 Recomendación original (previa a la decisión)

**Orden de preferencia: B > C1 > C2 ≫ A.**

**Recomiendo solicitar autorización para `digest`.** Si no se concede,
**C1 (`tools::md5sum()` sobre `serialize()`)** es el fallback que no requiere
autorización ninguna, con el efecto de E/S declarado en el contrato.

**A no debe adoptarse en ninguna de las dos ramas**, ni siquiera como prefiltro
barato: daría una falsa sensación de verificación en el caso —permutación— que
precisamente hay que detectar.

**OD-6 sigue OPEN.** No bloquea congelar el resto del contrato, **pero sí bloquea
la implementación de la reproducibilidad completa**: sin huella, el registro de
`config` no puede garantizar que el bootstrap guardado corresponde a estos datos.
La decisión es del owner y es de una sola pregunta: **¿se autoriza `digest`?**

---

*Actuarial Tools by BMK — B13, contrato congelado (ADR-035). Sin implementación.*
