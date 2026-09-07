# Tool-02 — B11.1: benchmark metodológico de Percentile Matching

| Campo | Valor |
|---|---|
| **Bloque** | B11.1 — benchmark. **No es la implementación productiva de PM** |
| **Objetivo** | Resolver experimentalmente **OD-1** del contrato B10 |
| **Baseline** | Tool-02 **v1.0.2**, funcionalmente intacto |
| **Estado** | **PASS — OD-1 RESOLVED** (recomendación técnica; requiere aprobación, §12) |
| **Fecha** | 2026-08-31 |
| **Artefactos** | `experiments/`, `experiments/results/*.csv` |

---

## 0. Advertencia sobre el motor de ejecución

**El benchmark se ha ejecutado en Python (NumPy/SciPy), no en R.** No dispongo de R
en este entorno. La decisión es deliberada y está documentada aquí porque afecta a
cómo debe leerse la evidencia:

- Las **parametrizaciones son las de `R/calc.R`**, replicadas función a función
  (§2). No se ha inventado ninguna alternativa.
- El **optimizador es L-BFGS-B con reparametrización logarítmica y `maxit = 500`**,
  el mismo esquema de `.mle_optim()`.
- Los **cuantiles empíricos** usan interpolación lineal, equivalente a
  `stats::quantile(type = 7)`, el valor por defecto de R.
- Esta réplica ya se validó en ADR-026/027: reprodujo los AIC de R **al céntimo** y
  los parámetros a 5–6 cifras significativas.

Se entrega además `experiments/pm_objective_benchmark.R`, transcripción del
experimento a R. **No ha sido ejecutada por mí y debe considerarse no verificada**
hasta que la ejecutes. Su función es auditoría y reproducibilidad en el lenguaje del
proyecto, no sustituir la evidencia de este informe.

---

## 1. Diseño experimental

| Elemento | Valor |
|---|---|
| Semilla maestra | `20260830` |
| Semillas por celda | FNV-1a determinista sobre `(dgp, n, repetición)`. **Añadir un escenario no desplaza los demás** |
| **R (repeticiones Monte Carlo)** | **300** |
| Tamaños muestrales | 100 · 1.000 · 10.000 |
| DGPs | 19 (§3) |
| Configuraciones de percentiles | 4 (§4) |
| Objetivos | 5 (§5) |
| Pesos | **Uniformes `w_j = 1`** en todo el experimento |
| Celdas | 2.190 filas en el CSV principal |
| Fits ejecutados | ≈ 396.000 |
| Tiempo total | ≈ 13 min, en tramos |

### 1.1 Pilot y elección de R

Pilot obligatorio previo: 3 distribuciones (exponencial, lognormal, Burr) × 2 tamaños
(100, 10.000) × 5 objetivos × 30 repeticiones. **1,6 s totales, 1,76 ms por fit,
convergencia 100 %.** Ningún error de diseño.

**R = 300** por tres razones:

1. **Precisión Monte Carlo.** El error estándar del sesgo estimado es
   `sd(θ̂)/√300 ≈ sd/17,3`, es decir, ruido MC del orden del **5,8 %** de la
   desviación típica del estimador. Suficiente para ordenar formulaciones que
   difieran más de ~10 %, y suficiente para **detectar que no difieren**, que es lo
   que ha ocurrido.
2. **Tasa de convergencia.** Con R = 300, una tasa real de 0,95 tiene error estándar
   de 1,3 puntos porcentuales. Las diferencias observadas entre objetivos (0,9843
   frente a 0,9998) son **más de diez veces ese error**: no son ruido.
3. **Coste.** ≈ 13 min. Con R = 500 serían ≈ 22 min sin ganancia decisiva, porque el
   criterio de §22 no se dirime por diferencias finas de RMSE.

**Limitación asumida:** con R = 300 **no** puedo declarar significativa una diferencia
de RMSE del 3 %. Y precisamente las diferencias de exactitud entre objetivos son de
ese orden. La decisión de OD-1 **no se apoya en exactitud** (§11).

### 1.2 Política de arranque

Idéntica para los cinco objetivos en cada dataset: **los valores iniciales que ya usa
`calc.R` para MLE** (MoM para Gamma, aproximación de Justus para Weibull, momentos
logarítmicos para Lognormal, `shape=1 / scale=mediana` para Loglogística,
`shape=2 / scale=media` para Pareto, `c=1 / k=1 / scale=mediana` para Burr).

Ningún objetivo recibe ventaja de arranque. En el experimento de identificabilidad
(§9) se perturban con multiplicadores {0,25 · 0,5 · 1 · 2 · 4}.

### 1.3 Optimización y restricciones

Los parámetros estrictamente positivos se optimizan sobre `log(θ)`; `meanlog` de la
Lognormal y `mean` de la Normal, sobre escala natural. Es el esquema de ADR-014.

**Esta transformación es del problema de optimización y no debe confundirse con la
transformación para IC analíticos de B12**, que es un problema distinto.

Criterio de éxito de un fit, replicando las guardas de ADR-027: estado del
optimizador `0`, parámetros finitos, ningún parámetro positivo por debajo de
`.Machine$double.xmin`, y objetivo finito.

---

## 2. Parametrizaciones (idénticas a `R/calc.R`)

| id | Parámetros | k | Soporte X | Soporte θ | Q(p; θ) |
|---|---|---:|---|---|---|
| `exponential` | `rate` | 1 | x ≥ 0 | rate > 0 | `-log(1-p)/rate` |
| `gamma` | `shape`, `scale` | 2 | x > 0 | ambos > 0 | `qgamma` (numérica) |
| `weibull` | `shape`, `scale` | 2 | x > 0 | ambos > 0 | `scale·(-log(1-p))^(1/shape)` |
| `lognormal` | `meanlog`, `sdlog` | 2 | x > 0 | meanlog ∈ ℝ, sdlog > 0 | `exp(meanlog + sdlog·z_p)` |
| `loglogistic` | `shape`, `scale` | 2 | x > 0 | ambos > 0 | `scale·(p/(1-p))^(1/shape)` |
| `pareto` (Lomax) | `shape`, `scale` | 2 | x ≥ 0 | ambos > 0 | `scale·((1-p)^(-1/shape) − 1)` |
| `burr` (XII) | `shape1`, `shape2`, `scale` | 3 | x > 0 | los tres > 0 | `scale·((1-p)^(-1/shape2) − 1)^(1/shape1)` |
| `normal` (control) | `mean`, `sd` | 2 | x ∈ ℝ | mean ∈ ℝ, sd > 0 | `qnorm` |

Loglogística, Lomax y Burr están implementadas manualmente en `calc.R`; sus `Q` y `F`
se han replicado exactamente desde `.dist_quantile()` y `.dist_cdf()`.

---

## 3. DGPs (19 escenarios, todos con θ verdadero documentado)

| Distribución | Etiqueta | θ verdadero |
|---|---|---|
| Exponencial | `exp_m100` / `exp_m1000` | rate 0,01 / 0,001 (**mismo modelo, escala ×10**) |
| Gamma | `gam_moderada` / `gam_asimetrica` / `gam_casi_sim` | (2, 500) / (0,6, 1500) / (5, 200) |
| Weibull | `wei_moderada` / `wei_hazard_dec` / `wei_ligera` | (1,5, 600) / (0,7, 500) / (2,5, 800) |
| Lognormal | `lnorm_moderada` / `lnorm_asim` / `lnorm_pesada` | (7, 0,6) / (7, 1,3) / (5, 2,0) |
| Loglogística | `llog_moderada` / `llog_pesada` | (3, 300) / (1,5, 300) — la segunda con **varianza infinita** |
| Pareto | `par_var_finita` / `par_pesada` | (3,5, 700) / (1,8, 600) — la segunda con varianza infinita |
| Burr | `burr_moderada` / `burr_pesada` | (2, 1,5, 500) / (1,2, 0,8, 400) |
| Normal | `norm_positiva` / `norm_estandar` | (100, 15) / (0, 1) — **la segunda con cuantiles negativos** |

`norm_estandar` no es decorativo: es el escenario que discrimina qué objetivos son
universalmente aplicables (§7).

---

## 4. Configuraciones de percentiles

| Clave | Percentiles | Comentario |
|---|---|---|
| `Pmk` | k=1: {50} · k=2: {25, 75} · k=3: {25, 50, 75} | m = k, mínimo estructural |
| **`P3c`** | **{25, 50, 75}** | **Preset del contrato** |
| `P3w` | {10, 50, 90} | Mismo m, mayor amplitud |
| `P5` | {10, 25, 50, 75, 90} | m > k, multi-cuantil |

---

## 5. Objetivos comparados

Con `q̂_j` = cuantil empírico de orden `p_j`, `Q_θ` y `F_θ` teóricos y `w_j = 1`:

| Clave | Nombre | `J(θ)` | Origen |
|---|---|---|---|
| **A** | Absoluto en cuantiles | `Σ (Q_θ(p_j) − q̂_j)²` | Familia A del encargo. Es la del material académico |
| **B** | Relativo, denominador **local** | `Σ ((Q_θ(p_j) − q̂_j) / q̂_j)²` | Familia B, con `scale_j = q̂_j` |
| **Bg** | Relativo, denominador **global** | `Σ ((Q_θ(p_j) − q̂_j) / IQR(x))²` | **Variante declarada** (§5.1) |
| **C** | Logarítmico | `Σ (log Q_θ(p_j) − log q̂_j)²` | Familia C. Exige `q̂_j > 0` y `Q_θ > 0` |
| **D** | Espacio de probabilidad | `Σ (F_θ(q̂_j) − p_j)²` | Familia D |

### 5.1 Justificación de la variante Bg

La familia B exige elegir `scale_j`, y el encargo obliga a justificarlo y a **no
ocultar los problemas cuando `q̂_j` se acerca a cero**. La elección natural
—`scale_j = q̂_j`— tiene un fallo estructural: **el denominador es un cuantil que
puede ser cero o negativo**. Con la Normal estándar, `q̂` en `p = 0,50` es la mediana
muestral, que ronda cero: el término se dispara sin declararlo.

`Bg` sustituye el denominador local por uno **global y robusto**, el rango
intercuartílico de la muestra. Conserva lo que se busca en B —adimensionalidad e
invariancia de escala— y elimina la división por una cantidad que puede anularse.

**Se declara explícitamente como variante propia, no como una de las cuatro familias
solicitadas.** B se ha ejecutado igualmente, y su fragilidad se documenta en §7.

---

## 6. Exactitud: los cinco objetivos empatan

Comparación **pareada**, restringida a las celdas donde los cinco objetivos convergen
al 100 % y producen `rel_RMSE` finito (79 celdas), excluyendo Burr con preset central
por ser patológico para todos (§10):

| Objetivo | rel_RMSE mediana | p75 | p90 | Veces el mejor |
|---|---:|---:|---:|---:|
| A | 0,0433 | 0,1070 | 0,1827 | 12 |
| B | 0,0426 | 0,0983 | 0,1660 | 16 |
| Bg | 0,0433 | 0,1070 | 0,1827 | 8 |
| C | 0,0426 | 0,0984 | 0,1665 | 19 |
| **D** | **0,0420** | 0,1055 | 0,1713 | **24** |

Rango entre el mejor y el peor: **3,1 %**. El ruido Monte Carlo con R = 300 es del
orden del 5,8 %. **La diferencia de exactitud no es estadísticamente distinguible.**

Sesgo relativo mediano: 0,0019–0,0022 para los cinco. Ninguno está sesgado.

**Conclusión parcial: la exactitud no decide OD-1.** Lo hace la robustez, que es
exactamente lo que exige §22 del encargo.

Evolución por tamaño muestral (mediana de `rel_RMSE`, celdas convergentes):

| Objetivo | n=100 | n=1.000 | n=10.000 |
|---|---:|---:|---:|
| A | 0,1146 | 0,0357 | 0,0114 |
| B | 0,1358 | 0,0420 | 0,0136 |
| Bg | 0,1384 | 0,0441 | 0,0144 |
| C | 0,1298 | 0,0423 | 0,0137 |
| D | 0,1243 | 0,0400 | 0,0126 |

El error decrece como `n^(-1/2)` en los cinco casos, lo que confirma que las
formulaciones son consistentes. **Advertencia de lectura:** esta tabla está calculada
solo sobre celdas convergentes y por tanto **favorece a A**, cuyos fallos quedan
excluidos. La tabla pareada de arriba es la comparación honesta.

---

## 7. Aplicabilidad: el criterio que elimina C

| Escenario | A | B | Bg | C | D |
|---|:-:|:-:|:-:|:-:|:-:|
| `norm_positiva` (media 100) | ✔ | ✔ | ✔ | ✔ | ✔ |
| `norm_estandar` (media 0) | ✔ | ✔ (frágil) | ✔ | **✘ 300/300 fallos** | ✔ |

**C no es aplicable cuando algún cuantil empírico es ≤ 0.** Con la Normal estándar,
`q̂(0,25) < 0` y el logaritmo no está definido: **24 celdas marcadas
`NOT APPLICABLE`**, la totalidad de las de ese DGP.

Lo relevante no es que falle con la Normal —eso era previsible—, sino **de qué
depende que falle**: no de la familia, sino de **dónde caen los datos**. La misma
Normal con media 100 funciona sin problema. Una formulación cuya aplicabilidad
depende del dato concreto obliga a comprobarla en tiempo de ejecución y a explicar al
usuario por qué el método deja de estar disponible al cambiar de variable.

**Fragilidad oculta de B.** En `norm_estandar`, B **no** declara fallo: la mediana
muestral rara vez es exactamente cero, así que el denominador es diminuto pero no
nulo. El resultado es un objetivo mal escalado que degrada la estimación sin avisar:

| Objetivo | RMSE de `mean` | RMSE de `sd` |
|---|---:|---:|
| A | 0,0356 | 0,0357 |
| **B** | **0,0420 (+18 %)** | 0,0365 |
| Bg | 0,0356 | 0,0357 |
| D | 0,0360 | 0,0357 |

B es peor que Bg en un 18 % para el parámetro de localización, **y falla en
silencio**. Es el peor modo de fallo posible.

---

## 8. Invariancia de escala: el criterio que elimina A

Experimento dedicado (`pm_scale_invariance.py`): mismo dataset ajustado sobre `X` y
sobre `1000·X`, R = 200, n = 1.000, configuración `P3c`. Se comprueba la equivarianza
esperada según la parametrización real: escala directa ×1000, `rate` de la
exponencial **÷1000** (escala inversa), `meanlog` **+ log 1000**, `sdlog` y parámetros
de forma invariantes.

**Resultado analítico.** Bajo `X' = cX` con `θ'` equivariante: `J_B`, `J_Bg`, `J_C` y
`J_D` son **exactamente invariantes**; `J_A` se multiplica por `c²`. El argmin no
cambia —escalar el objetivo por una constante no mueve el mínimo—, así que **A es
matemáticamente equivariante**. Pero las tolerancias de parada de L-BFGS-B son
absolutas: al multiplicar el objetivo por 10⁶, el criterio de parada se alcanza en un
punto distinto.

**Resultado empírico** (desviación relativa máxima respecto a la equivarianza):

| Distribución | A | B | Bg | C | D |
|---|---:|---:|---:|---:|---:|
| exponencial | 9,1e−10 | 6,9e−10 | 1,7e−10 | 2,5e−09 | 2,1e−09 |
| gamma | 3,0e−08 | 4,4e−08 | 3,9e−08 | 5,9e−08 | 7,7e−08 |
| weibull | 3,9e−09 | 1,3e−09 | 1,7e−09 | 4,2e−08 | 4,0e−08 |
| lognormal | 6,9e−10 | 8,8e−10 | 1,1e−09 | 1,2e−09 | 4,5e−09 |
| loglogística | 1,5e−09 | 1,9e−09 | 1,2e−09 | 6,7e−09 | 1,4e−08 |

Los parámetros coinciden. **La diferencia aparece en la convergencia:**

| Escenario | A en `X` | A en `1000·X` | B/Bg/C/D en ambos |
|---|---:|---:|---:|
| exponencial | 0,960 | 0,955 | **1,000** |
| gamma | 0,995 | 1,000 | 1,000 |
| weibull | 0,995 | 0,985 | 1,000 |
| loglogística | 0,985 | 0,995 | 1,000 |
| **burr** | 0,990 | **0,745** | **1,000** |

**Burr pierde 24,5 puntos de convergencia solo por cambiar de unidad.** Y el mismo
patrón está en el benchmark principal: A converge peor en `exp_m1000` que en
`exp_m100` (0,773 frente a 0,853 con `Pmk`), que son el mismo modelo a distinta
escala.

**Veredicto: A es SCALE-SENSITIVE en términos numéricos.** Con importes monetarios
—euros frente a miles de euros— es una desventaja de primer orden. B, Bg, C y D son
**SCALE-INVARIANT**.

---

## 9. Identificabilidad efectiva y sensibilidad al arranque

`pm_identifiability.py`: 5 arranques por dataset (multiplicadores 0,25 · 0,5 · 1 ·
2 · 4), 40 datasets, n = 1.000, 6 DGPs, 3 configuraciones. Se mide la **dispersión
mediana de θ entre arranques**.

| Escenarios con dispersión > 5 % | A | Bg | C | D |
|---|---:|---:|---:|---:|
| de 18 | **0** | 2 | **0** | **4** |
| dispersión máxima | 0,0000 | 1,0000 | 0,0003 | **3,0059** |

- **A y C son perfectamente robustos** al arranque.
- **Bg falla en 2 escenarios**, ambos `burr` con preset `P3c` — la configuración que
  es patológica para todos los objetivos (§10). No es un fallo del objetivo.
- **D falla en 4**, incluidos `lnorm_asim` en **las tres** configuraciones y
  `gam_moderada` con `P3c`. Escenarios normales, no patológicos.

### 9.1 Mecanismo del fallo de D: saturación

`J_D` está acotado por `m`, porque cada término `(F_θ(q̂_j) − p_j)²` vive en [0,1].
Cuando θ se aleja, `F_θ(q̂_j)` satura en 0 o en 1 y **el objetivo se aplana**:

| `meanlog` probado | `F_θ(q̂)` en 25/50/75 | `J_D` | `J_C` |
|---:|---|---:|---:|
| 1,75 | (0,99964 · 0,99997 · 1,00000) | **0,874** | 83,70 |
| 3,50 | (0,97891 · 0,99654 · 0,99969) | 0,840 | 37,43 |
| 5,25 | (0,75354 · 0,91222 · 0,98087) | 0,477 | 9,53 |
| **7,00** (verdadero) | (0,25447 · 0,50334 · 0,76604) | **0,00029** | 0,0049 |
| 8,75 | (0,02239 · 0,09048 · 0,26753) | 0,452 | 8,86 |

Con `meanlog = 1,75` —la mediana ajustada es ~140 veces menor que la real— `J_D` vale
0,874 sobre un máximo de 3, con gradiente casi nulo. El optimizador se queda cerca del
arranque. `J_C`, en cambio, vale 83,7 y conserva pendiente.

**Es una propiedad estructural del espacio de probabilidad, no un fallo del script.**
Clasificación: **METHODOLOGICAL**.

**Matiz honesto sobre el diseño.** El multiplicador se aplica sobre el parámetro en su
escala natural, así que su severidad **no es homogénea entre parametrizaciones**: para
`meanlog`, ×0,25 desplaza la mediana un factor 140, mucho más agresivo que ×0,25 sobre
un `shape`. Por eso el caso lognormal exagera el problema de D. Pero
`gam_moderada` con `P3c` —donde ×0,25 es una perturbación de factor 4, comparable al
resto— también falla con D y no con A, Bg ni C. **La sensibilidad de D es real incluso
en la comparación equitativa.**

---

## 10. Burr y el preset 25/50/75 — CONTRACT CONFLICT

Burr, `n = 1.000`, `burr_moderada`, `rel_RMSE` por parámetro:

| Config | Parámetro | A | B | Bg | C | D |
|---|---|---:|---:|---:|---:|---:|
| **P3c** (25/50/75) | shape1 | 0,139 | 0,139 | 0,138 | 0,139 | 0,139 |
| **P3c** | **shape2** | **362,9** | **5.976,5** | **356,6** | **867,6** | **3.324,4** |
| **P3c** | **scale** | **24,7** | **127,2** | **25,4** | **41,5** | **86,7** |
| P3w (10/50/90) | shape1 | 0,070 | 0,070 | 0,070 | 0,070 | 0,070 |
| P3w | shape2 | **0,327** | 0,327 | 0,327 | 0,327 | 0,327 |
| P3w | scale | **0,231** | 0,231 | 0,231 | 0,231 | 0,232 |
| P5 (10/25/50/75/90) | shape2 | 0,346 | 0,322 | 0,346 | 0,326 | 0,318 |

**Con 25/50/75, el parámetro `shape2` de Burr es inestimable**: error relativo entre
357 y 5.976 según el objetivo. Con 10/50/90 —**el mismo m = k = 3**— el error cae a
0,33. Mejora de **tres órdenes de magnitud**.

**El problema no es `m = k`. Es la estrechez del conjunto.** `shape2` gobierna el
decaimiento de la cola; tres cuantiles centrales entre el 25 % y el 75 % apenas
contienen información sobre ella, y `shape2` y `scale` se compensan mutuamente
dejando el objetivo casi plano. Es también lo que explica el único fallo de arranque
de Bg (§9): en esa configuración hay un valle plano y cualquier método puede terminar
en puntos distintos.

Añadir percentiles ayuda mucho:

| DGP | Objetivo | m=k (P3c) | m>k (P5) | Factor de mejora |
|---|---|---:|---:|---:|
| burr_moderada | A | 3,298 | 0,241 | **13,7×** |
| burr_moderada | D | 1,664 | 0,224 | 7,4× |
| burr_pesada | B | 4,245 | 0,180 | **23,6×** |
| burr_pesada | C | 3,764 | 0,181 | 20,7× |

**Respuesta a "¿m > k mejora o empeora?": mejora, y mucho, cuando el conjunto es
estrecho.** No se ha observado ningún caso en que empeore.

### 10.1 Conflicto con el contrato de producto

El contrato B10 congeló **25/50/75 como preset**. La evidencia dice que ese preset,
aplicado a **Burr**, produce estimaciones inservibles de dos de sus tres parámetros —
con **cualquiera** de los cinco objetivos.

Encaja con el **caso B** de §21 del encargo: *funciona como ejemplo didáctico pero
tiene limitaciones importantes*. Para las seis familias de k ≤ 2 el preset es
razonable: 0,0360 de `rel_RMSE` mediana frente a 0,0307 de 10/50/90, una diferencia
modesta.

**Me detengo aquí, como exige el encargo. No modifico el preset.** Tres opciones,
para que decidas:

1. **Mantener 25/50/75 como preset global** y que la interfaz **advierta** cuando la
   distribución seleccionada tenga k = 3, sugiriendo ampliar el conjunto.
2. **Preset dependiente de k**: {25, 50, 75} para k ≤ 2 y {10, 25, 50, 75, 90} para
   k = 3. Contradice el "preset único" del contrato.
3. **Cambiar el preset global a 10/25/50/75/90.** Es el mejor en `rel_RMSE` mediana
   (0,0292 frente a 0,0360), funciona para todo k, y sigue siendo interpretable.

**Mi recomendación técnica es la 3**, con la 1 como mínimo aceptable. Pero es una
decisión de producto y **no la tomo yo**.

---

## 11. Decisión sobre OD-1

Criterios de §22, todos con evidencia:

| Criterio | A | B | **Bg** | C | D |
|---|:-:|:-:|:-:|:-:|:-:|
| Convergencia media | 0,9843 | 0,9996 | **0,9998** | 0,9449 | 0,9997 |
| Celdas con conv < 1 (de 438) | **335** | 20 | **10** | 39 | 18 |
| Invariancia de escala | **NO** | sí | **sí** | sí | sí |
| Aplicable con cuantiles ≤ 0 | sí | frágil, **falla en silencio** | **sí** | **NO** | sí |
| Robustez al arranque (fallos/18) | 0 | — | 2 (solo config patológica) | 0 | **4** |
| rel_RMSE mediana (pareada) | 0,0433 | 0,0426 | 0,0433 | 0,0426 | 0,0420 |
| Coste medio (ms/fit) | 1,80 | 1,31 | 1,53 | 1,29 | **0,88** |

> **CORRECCIÓN B11.1-R (2026-09-01) — leer antes que la tabla anterior.**
> `IQR(x)` no depende de `theta`, luego `J_Bg = J_A / IQR^2` y **`argmin J_Bg = argmin J_A`**.
> **A y Bg son el mismo estimador**, no dos métodos que compiten. Verificado a
> precisión de máquina (2·10⁻¹⁶). Las filas `A` y `Bg` de la tabla superior son, por
> tanto, **dos implementaciones de un único estimador**: sus `rel_RMSE` idénticos
> hasta la cuarta cifra (0,0433 · 0,1070 · 0,1827) eran la firma de esa identidad, y
> no se interpretaron así en su momento. Las diferencias de **convergencia** entre
> ambas filas son reales pero **numéricas**, no estadísticas: la tolerancia de
> gradiente proyectado de L-BFGS-B es absoluta y `|grad J_A| / |grad J_Bg| = IQR²`
> (medido: 1,52·10⁵ en Burr). La formulación adoptada se denomina **Normalized
> Quantile SSE** y la normalización se justifica como **acondicionamiento numérico**,
> no como definición estadística distinta.

**Eliminaciones, cada una por un motivo distinto y demostrado:**

- **A — no es un estimador eliminado: es el estimador elegido.** Lo que se descarta es
  su **implementación sin normalizar**, por acondicionamiento: 335 celdas con
  convergencia incompleta frente a 10, y Burr pierde 24,5 puntos de convergencia al
  cambiar de unidad. En una herramienta que trabaja con importes monetarios, la forma
  no normalizada es inutilizable — pero el estimador subyacente es el correcto.
- **C — eliminada por aplicabilidad dependiente del dato.** Falla por completo con la
  Normal estándar (300/300). Que su disponibilidad dependa de dónde caigan los datos
  y no de la familia elegida es un mal contrato de cara al usuario.
- **D — eliminada por saturación del objetivo.** Es la más rápida y la más exacta en
  mediana, pero su objetivo acotado se aplana lejos del óptimo y depende del
  arranque en escenarios normales. Un estimador que a veces devuelve el punto de
  partida disfrazado de solución es inaceptable **aunque en promedio sea el mejor**.
- **B — eliminada por fragilidad silenciosa.** Divide por un cuantil que puede
  aproximarse a cero, y cuando ocurre **no lo declara**: degrada la estimación un 18 %
  sin aviso.

**Ganadora: el estimador de mínimos cuadrados en espacio de cuantiles, en su forma
normalizada (`Normalized Quantile SSE`).**

```
J_Bg(theta) = SUM_j [ ( Q_theta(p_j) - q_emp(p_j) ) / IQR(x) ]^2      w_j = 1
```

Es la única sin un modo de fallo descalificatorio: **mejor convergencia del conjunto**
(10 celdas imperfectas de 438), **exactamente invariante de escala**, **aplicable a
todas las distribuciones incluida la Normal con cuantiles negativos**, robusta al
arranque salvo en la configuración patológica de Burr, y con exactitud
estadísticamente indistinguible de la mejor. Su coste (1,53 ms) es un 74 % superior al
de D, irrelevante frente al bootstrap de B13.

**Honestidad sobre esta elección.** En su redacción original, esta sección presentaba
`Bg` como una quinta formulación que vencía a las otras cuatro. **Era un error de
razonamiento, corregido arriba:** `Bg` es `A` reescalada por una constante positiva
independiente de `theta`, luego el mismo estimador. La conclusión práctica —usar la
forma normalizada— **no cambia**; su justificación sí, y pasa a ser mucho más simple:
se elimina B, C y D como estimadores genuinamente distintos, y de la única familia
superviviente se adopta la implementación mejor acondicionada.

**Verificación en R pendiente.** `experiments/pm_r_verification.R` debe confirmar con
`optim()` que ambas formas alcanzan el mismo argmin donde este está bien determinado.

**Una regla común es suficiente.** No hay evidencia que justifique objetivos
específicos por familia: Bg es el mejor o está empatado en las ocho. Se prefiere la
regla única, como indica §22.

### 11.1 Qué queda abierto

Los **pesos `w_j` siguen abiertos**. Todo el experimento usa `w_j = 1` por diseño
(§6 del encargo). No hay evidencia de que ninguna familia exija ponderación para ser
coherente: con pesos uniformes, Bg converge en el 99,98 % de las celdas. La
ponderación por varianza asintótica del cuantil muestral puede evaluarse en una
iteración posterior, sin bloquear B11.2.

---

## 12. Rendimiento

Coste por ajuste, n = 1.000, configuración de 5 percentiles:

| Distribución | A | B | Bg | C | D |
|---|---:|---:|---:|---:|---:|
| exponencial | 0,47 | 0,44 | 0,39 | 0,31 | 0,32 |
| gamma | 2,51 | 1,99 | 2,32 | 1,94 | 1,20 |
| weibull | 0,78 | 0,66 | 0,66 | 0,68 | 0,45 |
| lognormal | 2,26 | 1,23 | 1,84 | 1,04 | 0,79 |
| loglogística | 1,19 | 1,04 | 1,09 | 0,79 | 0,58 |
| pareto | 2,53 | 1,50 | 1,48 | 1,51 | 1,09 |
| burr | 2,49 | 2,08 | 2,42 | 2,00 | 1,22 |
| normal | 2,18 | 1,54 | 2,04 | 2,02 | 1,38 |
| **media** | **1,80** | **1,31** | **1,53** | **1,29** | **0,88** |

**Ninguna formulación es computacionalmente desproporcionada.** Todas por debajo de
3 ms.

**Gamma no debe excluirse por coste.** Su `qgamma` numérica la sitúa en 2,32 ms con
Bg, frente a 0,66 de Weibull: un factor 3,5, no un orden de magnitud. Confirma lo que
el encargo anticipaba: excluirla habría sido una decisión de rendimiento disfrazada
de metodología.

Extrapolación a B13: un bootstrap de B = 1.000 sobre Burr con Bg costaría ≈ **2,4 s**.
Aceptable bajo demanda. **No sustituye a B17.**

---

## 13. OD-2 y OD-3

### OD-2 — validado empíricamente

Los 18 casos deterministas de `pm_contract_tests.py` se comportan como exige §3 del
encargo:

| Caso | Resultado | Motivo |
|---|---|---|
| p = 0 · p = 1 · p < 0 · p > 1 | **REJECT** | fuera del intervalo abierto (0,1) |
| NA · NaN · Inf | **REJECT** | percentil no finito o ausente |
| Duplicados | **REJECT** | restricción redundante |
| Vector vacío | **REJECT** | conjunto vacío |
| m < k (m=1,k=2 y m=2,k=3) | **REJECT** | sistema estructuralmente insuficiente |
| m = k · preset · m > k | **ACCEPT** | — |
| Muy próximos (0,50 y 0,505) | **WARN** | separación mínima 0,0050 |
| Extremos con n = 100 | **WARN** | menos de 5 observaciones en la cola |
| Extremos con n = 10.000 | **ACCEPT** | — |

**`m ≥ k` es necesaria pero no suficiente, y el benchmark lo demuestra:** Burr con
`P3c` cumple `m = k = 3`, converge, y sin embargo `shape2` no queda identificado. La
distinción del contrato entre *potentially identifiable* y *effectively identified*
no es teórica.

**Umbrales.** Los que aparecen arriba (0,01 de separación; 5 observaciones en cola)
son los que he usado **para ejecutar los tests**, no una propuesta congelada. El
benchmark aporta un dato útil —Burr con `P3c` falla y con `P3w` no, siendo ambos
m = k = 3—, pero **no basta para fijar un umbral general de "muy próximo"**. Se
mantienen como WARNING sin umbral congelado, conforme al encargo.

### OD-3 — confirmada

PM se habilita para las **7 continuas** y la **Normal de control**; **no** para
Poisson, Binomial Negativa ni Geométrica. Ninguna continua ha mostrado un problema
estructural que justifique excluirla:

- **Gamma**: incluida. Su coste es 3,5× el de Weibull, no descalificatorio.
- **Burr**: incluida. Su dificultad es **de configuración de percentiles**, no de
  familia: con `P3w` o `P5` se comporta correctamente.
- **Normal**: incluida como control, y ha sido decisiva para eliminar C.

---

## 14. Limitaciones

1. **Motor de ejecución.** Python, no R (§0). La transcripción a R no está verificada.
2. **R = 300.** Diferencias de RMSE inferiores al ~6 % no son distinguibles. Por eso
   OD-1 no se decide por exactitud.
3. **Pesos uniformes.** Por diseño. Los resultados **no** dicen nada sobre pesos
   óptimos.
4. **Perturbación de arranque no homogénea** entre parametrizaciones (§9.1). Puede
   exagerar el problema de D en la Lognormal; el caso Gamma lo confirma igualmente.
5. **19 DGPs**, no un muestreo exhaustivo del espacio de parámetros.
6. **Sin comparación con MLE/MoM/L-momentos.** El encargo la declaraba opcional y
   habría desviado el foco.
7. **Escala probada con un solo factor** (c = 1000).
8. **Sin análisis de perturbación de los cuantiles empíricos**: la sensibilidad al
   arranque cubrió la parte del §16 que resultó discriminante.

---

## 15. Clasificación de incidencias

| Incidencia | Clase |
|---|---|
| A pierde convergencia al reescalar los datos | **METHODOLOGICAL / NUMERICAL** |
| C no aplicable con cuantiles ≤ 0 | **METHODOLOGICAL** |
| B con denominador cercano a cero degrada sin avisar | **METHODOLOGICAL** |
| D satura y depende del arranque | **METHODOLOGICAL** |
| Burr con 25/50/75 no identifica `shape2` | **METHODOLOGICAL** (configuración) |
| Equivarianza mal especificada para `rate` en mi script de escala | **IMPLEMENTATION** — bug propio, detectado y corregido antes de concluir |
| Coste de Gamma 3,5× el de Weibull | **PERFORMANCE**, no descalificatorio |
| Semilla dependiente del preset ⇒ Monte Carlo **no pareado** (§16.2) | **IMPLEMENTATION** — defecto de diseño experimental; sin efecto en producción |
| `ifelse()` evaluando `log()` sobre parámetros no positivos (§16.3) | **IMPLEMENTATION** — reparametrización experimental; corregido por indexación |
| Tabla «excluyendo Burr» que no filtraba Burr (§16.4) | **IMPLEMENTATION** — solo reporting experimental |

**Ninguna incidencia es un bug de Tool-02.** El código productivo no se ha ejecutado
ni modificado en este bloque.

---

## 16. CIERRE DE B11.1 — verificación en R y decisiones congeladas

> **Este documento recoge el benchmark inicial, ejecutado en Python (§0).** Las
> conclusiones que sobrevivieron a la verificación en R están aquí. **Donde §1–§15
> discrepen de §16, prevalece §16.**

### 16.1 Estado final

| Decisión | Estado | Contenido congelado |
|---|---|---|
| **OD-1** — forma del objetivo | **RESOLVED** | `J_PM(θ) = Σ_j [Q_θ(p_j) − q̂_j]² / s_Q²`, **Normalized Quantile SSE**, `w_j = 1` |
| **OD-2** — identificabilidad | **RESOLVED** en política básica | `m_requested < k` → REJECT. `m_effective` **solo diagnóstico** |
| **OD-3** — compatibilidad | **RESOLVED** | 7 continuas + Normal como control; ninguna discreta |
| **OD-13** — normalizador | **RESOLVED** | `s_Q = max(q̂) − min(q̂)`, finita y > 0; si `s_Q = 0` → REJECT. Sin epsilon, sin fallback `IQR`. Mínimo 2 percentiles |
| **Preset** | **RESOLVED** | Default **10/50/90**; ampliado 10/25/50/75/90; central 25/50/75 no recomendado |
| **OD-14** — pesos | **OPEN / DEFERRED** | No necesarios para liberar PM v1.1 |

**B11.1 = CLOSED / APPROVED.**

### 16.2 Corrección de fondo: la variante «Bg» no era un objetivo distinto

`IQR(x)` —y `s_Q`— son **constantes respecto de θ**, luego `J_norm(θ) = J_A(θ)/s²`
y **el argmin es idéntico**. Verificado en R a precisión de máquina. Lo que §5.1 y
§6 presentaban como una familia de objetivos rival es una **normalización
numérica**: no cambia el estimador, cambia la **escala del criterio de parada** de
`optim()`, cuyas tolerancias son absolutas. Ese es el motivo real de las diferencias
de convergencia observadas, y por eso se adopta.

Consecuencia sobre §6: que A y Bg dieran `rel_RMSE` idéntico a cuatro decimales no
era un empate entre métodos, era **la firma de la identidad**.

### 16.3 Evidencia definitiva del preset — R 4.4.1, 22 DGP, diseño PAREADO

El benchmark de §10 usaba **semillas dependientes del preset**, de modo que cada
preset se evaluaba sobre una **muestra distinta**: insesgado por preset, pero con la
comparación inflada en varianza. `pm_crossfamily_R.R` lo rehace **pareado**
—misma muestra para ambos presets— con `s_Q`, `R_MC = 300`, `n = 1.000` y 13.200
ajustes.

| Familia | Catastróficos P3w / P5 | % réplicas P3w mejor |
|---|:--:|--:|
| Exponencial | 0 / 0 | 41,6 % |
| Gamma | 0 / 0 | 51,0 % |
| Weibull | 0 / 0 | 49,2 % |
| Lognormal | 0 / 0 | 56,5 % |
| Loglogística | 0 / 0 | 50,9 % |
| **Pareto** | **20 / 28** | 56,0 % |
| **Burr** (control) | **9 / 40** | 47,6 % |
| Normal (control) | 0 / 0 | 43,9 % |

Convergencia global **P3w 0,9885 · P5 0,9877**.

**Lectura.** Cinco de las seis familias no-Burr dan **cero** fallos catastróficos con
ambos presets; el reparto del caso típico es **cuatro familias a cuatro**. P3w y P5
son **prácticamente equivalentes** en las familias sencillas. La ventaja de P3w es
**específica**: robustez de cola en **Pareto y Burr**. **Está prohibido escribir «P3w
gana universalmente» o «P3w es siempre más preciso».**

Lo que sí queda cerrado sin ambigüedad es el **descarte de 25/50/75 como default**:
602 fallos catastróficos en Burr frente a 135 de P3w. Confirma el CONTRACT CONFLICT
anticipado en §10 y §10.1.

### 16.4 Defectos experimentales detectados y corregidos

| Defecto | Detectado por | Efecto | Estado |
|---|---|---|---|
| Métrica relativa de `J` con `m = k` (divide por ruido) | Análisis del anómalo `9,05e4` | Métrica sin sentido; explicaba el patrón invertido Python/R | Retirada |
| Semilla dependiente del preset ⇒ no pareado | **Owner** | Comparación inflada en varianza | Rediseñado |
| `ifelse()` evaluando `log()` sobre no positivos | Captura de warnings | 149 avisos espurios | Indexación |
| Tabla «excluyendo Burr» sin filtrar Burr | **Owner** | Solo presentación; CSV idénticos | Dividida en C.1 / C.2 |

**Ninguno afecta a producción.** El código productivo no se ha ejecutado ni
modificado en ningún bloque de B11.1.

### 16.5 Warnings

594 avisos, todos «Se han producido NaNs» y todos dentro de `Q(p; θ)`: **445 de
gamma = EXPECTED NUMERICAL EXPLORATION**; **149 de Normal = IMPLEMENTATION DEFECT**
(§16.4). Tras la corrección, R4 registró **0 avisos** sobre 13.200 ajustes.
**Requisito para B11.2:** guardas previas o captura local acotada; **prohibido
`suppressWarnings()` global**.

### 16.6 Limitaciones que se mantienen

De §14 siguen vigentes las 2 a 8. **La 1 queda superada**: las conclusiones que
sostienen las decisiones están verificadas en **R 4.4.1**. Se añade:

9. El benchmark cross-family cubre **22 DGP** con `n = 1.000` fijo. **No se ha
   explorado el efecto del tamaño muestral** sobre la elección de preset.

---

*Actuarial Tools by BMK — B11.1 CLOSED / APPROVED. Sin implementación productiva.*
