# Tool-02 — B11.1-R2: diagnóstico numérico, preset y normalización

| Campo | Valor |
|---|---|
| **Bloque** | B11.1-R2 — diagnóstico dirigido. **No es implementación de PM** |
| **Estado** | **PASS — OPEN WEIGHTS/PRESET DECISION** |
| **Baseline** | Tool-02 **v1.0.2**, intacto |
| **Fecha** | 2026-09-02 |
| **Entrada** | Resultados de `pm_r_verification.R` ejecutado por el owner en **R 4.4.1** |

---

## 0. Procedencia de cada resultado — LEER ANTES QUE NADA

> **CORRECCIÓN (2026-09-03).** La primera versión de este documento presentaba el
> benchmark de preset «R = 300, seis DGP» sin declarar su runtime, en un contexto
> que invitaba a leerlo como evidencia de R. **No lo es.** `R = 300` designa el
> número de **repeticiones Monte Carlo**, no el lenguaje. Queda corregido aquí y en
> todas las tablas afectadas.

| Sección | Runtime | Script | Estado |
|---|---|---|---|
| §1.1 identidad en el mismo θ | Python/SciPy | inline | evidencia **secundaria** |
| §1.2 `m = k` ⇒ `J_min → 0` | Python/SciPy | inline | evidencia **secundaria** |
| §1.4 error frente a `θ_true` | Python/SciPy | inline | evidencia **secundaria** |
| §2 tolerancias | Python/SciPy | inline | evidencia **secundaria** |
| **§3 preset Burr, 300 repeticiones** | **Python/SciPy** | `experiments/pm_burr_preset.py` | **PENDIENTE de R** |
| **§4 hipótesis de pesos** | **Python/SciPy** | inline | **PENDIENTE de R** |
| §5.1–5.2 `s_IQR` vs `s_Q` | Python/SciPy + **R 4.4.1** | `pm_r_verification.R` T6b | **CONFIRMADO en R** |
| §6 `m_effective` | Python/SciPy + **R 4.4.1** | `pm_r_verification.R` T6b | parcialmente confirmado |

**Lo ejecutado realmente en R 4.4.1** por el owner, con
`Rscript tools/distribution-fitting/experiments/pm_r_verification.R`, fue: T1
(mismo argmin), T2/T3 (escala), T4 (Burr con `R_MC = 100`), T5 (Normal) y T6/T6b
(configuraciones inválidas, IQR = 0 **y modo `spread`**).

**Lo ejecutado en Python/SciPy** son los diagnósticos que explican esos resultados y
el benchmark ampliado de preset con 300 repeticiones y seis DGP. Es **evidencia
experimental secundaria**: sirve para formular y descartar hipótesis, **no sustituye
la validación en R**. El script `experiments/pm_burr_preset_R.R` replica ese
benchmark en R y está pendiente de ejecución.

---

## 1. Burr m=3: por qué `dif_rel_J = 9,05·10⁴`

**No es un bug, y tampoco es un valle plano.** Es un **artefacto de la métrica que
elegí**, y la causa es de una simplicidad incómoda.

### 1.1 La identidad se cumple exactamente

Primero lo que había que descartar. Evaluando `J_A(θ)` y `s²·J_norm(θ)` **en el
mismo θ**:

| Caso | en `θ_A` | en `θ_norm` | en un `θ` arbitrario |
|---|---:|---:|---:|
| burr m=3 | 0,000e+00 | 2,7e−16 | 0,000e+00 |
| burr m=5 | 0,000e+00 | 1,2e−16 | 0,000e+00 |
| pareto m=3 | 0,000e+00 | 0,000e+00 | 0,000e+00 |
| pareto m=2 | 2,2e−16 | 1,3e−16 | 2,0e−16 |

Diferencia relativa **cero o del orden del épsilon de máquina, en cualquier θ**.
**No hay bug de implementación.**

### 1.2 La causa: con `m = k`, el mínimo de `J` es cero

Con `m = k` el sistema está **exactamente determinado**: `k` parámetros pueden
igualar `k` cuantiles empíricos, luego `J_min → 0`. Y entonces
`|J_A − J_norm| / |J_A|` **divide por un número próximo al cero de máquina**:

| Caso | m | k | `J_A(θ_A)` | `J_A(θ_norm)` | dif **absoluta** | dif **relativa** |
|---|--:|--:|---:|---:|---:|---:|
| **burr** | **3** | **3** | **1,24e−08** | 1,74e−01 | 1,74e−01 | **1,40e+07** |
| **pareto** | **2** | **2** | **2,42e−09** | 5,08e−02 | 5,08e−02 | **2,10e+07** |
| **lognormal** | **2** | **2** | **1,21e−10** | 1,09e−01 | 1,09e−01 | **8,98e+08** |
| burr | 5 | 3 | 1,5157e+00 | 1,5158e+00 | 2,8e−05 | 1,9e−05 |
| pareto | 3 | 2 | 7,24e−05 | 7,49e−05 | 2,5e−06 | 3,5e−02 |
| gamma | 3 | 2 | 1,0108e+02 | 1,0111e+02 | 3,3e−02 | 3,3e−04 |

Separación limpia: **`m = k` ⇒ ratio de 10⁷–10⁹. `m > k` ⇒ ratio de 10⁻⁵ a 10⁻²**.

**El `dif_rel_J` que reportó R es una métrica mal diseñada por mí**, no un hallazgo.

> **Clasificación formal: IMPLEMENTATION DEFECT — experimental diagnostic metric.**
> **No** es un problema del estimador. Con `m = k` queda **prohibido** el cociente
> relativo contra un `J ≈ 0`. En su lugar deben usarse: diferencia **absoluta** de
> `J`; `J` evaluada en **ambos** θ; distancia entre parámetros; sensibilidad al
> arranque; y diagnósticos de condicionamiento e identificabilidad.

### 1.3 Y explica también el patrón invertido Python/R

En Python, burr m=3 dio `dif_rel_θ = 0,92` con `dif_rel_J = 2e−3`; en R,
`dif_rel_θ = 0,067` con `dif_rel_J = 9e4`. Parecía una contradicción. No lo es:
ambos miden un cociente cuyo denominador ronda 10⁻⁸ y cuyo valor depende de dónde
pare exactamente cada optimizador. **El cociente no es reproducible entre
implementaciones porque su denominador es ruido numérico.**

### 1.4 Un `J` menor no es una estimación mejor

Sobre 150 réplicas de `burr` con `m = k = 3`:

| | A (sin normalizar) | Normalizada |
|---|---:|---:|
| Error relativo mediano frente a **θ_true** | **0,4142** | **0,4141** |
| `J_A` alcanzada (mediana) | 9,47e−08 | 2,27e−06 |

A alcanza un `J` veinte veces menor **y está exactamente igual de lejos de la
verdad**. Con `m = k`, `J = 0` significa reproducir los cuantiles **muestrales**,
ruido incluido. Es la patología de `m = k`, no una virtud de A.

---

## 2. Tolerancias: la diferencia es NUMERICAL STOPPING SCALE

Prueba controlada sobre burr `m = 3`, 80 réplicas:

| Tolerancia | `J_A(θ_A)` | `J_A(θ_norm)` | dif. relativa de θ |
|---|---:|---:|---:|
| por defecto | 9,586e−08 | 2,362e−06 | 0,0001 |
| `ftol = 1e−15` | 9,157e−08 | 8,321e−07 | 0,0000 |
| `ftol = 1e−15`, `gtol = 1e−12` | **8,979e−08** | **8,979e−08** | **0,0000** |

**Al endurecer las tolerancias ambas convergen al mismo punto, con el mismo valor de
`J` hasta la última cifra.** Es la demostración directa: la discrepancia es
**escala del criterio de parada**, no estimadores distintos.

Con ello queda cerrado el mecanismo que ya se había medido: el gradiente de `J_A`
está inflado por `s²` (medido en Burr: `|∇J_A| / |∇J_norm| = IQR² = 1,52·10⁵`), y
los criterios de parada de L-BFGS-B son **absolutos**.

**Clasificación del problema Burr m=3: NUMERICAL.** No metodológico, no de
implementación del objetivo, no de identificación —aunque la identificación con
`m = k` es mala por separado, §3—.

**No se propone tocar las tolerancias de producción.** La normalización resuelve el
problema en la escala correcta, sin tocar `optim()`.

---

## 3. Preset: P3c vs P3w vs P5 — 300 repeticiones, seis DGP

> **RUNTIME: Python/SciPy** (`experiments/pm_burr_preset.py`). Evidencia secundaria.
> **Pendiente de confirmar en R** con `experiments/pm_burr_preset_R.R`. «300» son
> repeticiones Monte Carlo, no el lenguaje R.

Burr, `n = 1.000`, objetivo normalizado, `w_j = 1`, 300 réplicas por celda.

### 3.1 Fallos catastróficos (`|error relativo| > 1`), sobre 300

**`shape2`:**

| DGP | θ verdadero | P3c | **P3w** | P5 |
|---|---|---:|---:|---:|
| moderada | (2,0 · 1,5 · 500) | 53 | **4** | 5 |
| pesada | (1,2 · 0,8 · 400) | 19 | **0** | 6 |
| shapes suaves | (3,0 · 2,5 · 600) | 101 | **14** | 15 |
| shape2 alto | (2,0 · 4,0 · 500) | 100 | **44** | 46 |
| shape2 bajo | (2,0 · 0,5 · 500) | 2 | **0** | 0 |
| escala ×1000 | (2,0 · 1,5 · 500.000) | 59 | **3** | 6 |
| **total** | | **334** | **65** | **78** |

**`scale`:**

| DGP | P3c | **P3w** | P5 |
|---|---:|---:|---:|
| moderada | 34 | **1** | 2 |
| pesada | 27 | **1** | 11 |
| shapes suaves | 64 | **1** | 2 |
| shape2 alto | 88 | **22** | 27 |
| shape2 bajo | 2 | **0** | 0 |
| escala ×1000 | 41 | **3** | 3 |
| **total** | **256** | **28** | **45** |

**P3w gana o empata en las seis, para los dos parámetros.** Totales sumando
`shape2` y `scale`: **P3c 590 · P3w 93 · P5 123**.

### 3.2 Error mediano y colas del error, `shape2`

| DGP | | P3c | **P3w** | P5 |
|---|---|---:|---:|---:|
| moderada | mediana | 0,3734 | **0,1503** | 0,1700 |
| | p95 | 3,6264 | **0,6018** | 0,6770 |
| pesada | mediana | 0,2604 | **0,1229** | 0,1793 |
| | p95 | 1,1980 | **0,3532** | 0,6088 |
| shapes suaves | mediana | 0,5332 | 0,2389 | **0,2012** |
| | p95 | 1440,08 | **0,9534** | 0,9859 |
| shape2 alto | mediana | 0,5984 | 0,3254 | **0,3177** |
| | p95 | 1352,34 | **3,5512** | 4,0154 |

`rel_RMSE` de `shape2` con P3c alcanza **30.118** en «shapes suaves» y **2.280** en
«shape2 alto»: no es un error grande, es una estimación sin sentido.

### 3.3 Comportamiento estable al cambiar de magnitud

**Aclaración necesaria sobre qué es `escala_x1000`.** Es una **réplica
distribucional reescalada**: se simula de `Burr(2,0; 1,5; 500.000)`. **No** es la
muestra de `moderada` multiplicada por 1.000. Las dos series comparten la ley
teórica reescalada, no los mismos números.

Por tanto este DGP **no es** —y no debe presentarse como— una prueba de
identidad exacta bajo cambio de unidad. Esa invariancia *sample-by-sample* ya
quedó verificada, con igualdad hasta precisión de máquina, en **T2/T3 de
`pm_r_verification.R`**, que sí compara `x` frente a `1000·x` sobre el mismo
vector. Lo que `escala_x1000` aporta es distinto y complementario: que el
comportamiento **agregado** del preset no se degrada al trabajar en otra
magnitud.

Con esa lectura: `shape2` da P3w **0,3005 vs 0,2969** y P5 **0,3420 vs 0,3418**
—diferencias dentro del ruido Monte Carlo—, coherente con la invariancia ya
demostrada en T2/T3.

### 3.4 Conclusión: **P5 NO queda confirmado como default**

La evidencia favorece a **P3w = 10/50/90**, y de forma consistente. Pero
**no propongo congelarlo** por dos razones:

1. Toda esta evidencia es de **Burr**. No se ha medido el efecto de P3w frente a P5
   en las otras seis continuas, donde el benchmark original de B11.1 daba a P5 la
   mejor mediana global (`rel_RMSE` 0,0292 frente a 0,0307 de P3w).
2. La causa del comportamiento —§4— apunta a que la elección de preset y la de
   pesos son **el mismo problema**. Congelar un preset antes de decidir los pesos
   sería congelar el síntoma.

---

## 4. Por qué P5 no mejora a P3w: la hipótesis de los pesos

> **RUNTIME: Python/SciPy.** Evidencia secundaria, pendiente de R.

La hipótesis del owner era que, con pesos uniformes, P5 = {10, 25, 50, 75, 90}
coloca **3 de 5** residuos en la zona central [25, 75] —el 60 %— frente a **1 de 3**
de P3w —el 33 %—, recentralizando el objetivo.

**La probé directamente**, añadiendo configuraciones que separan «número de puntos»
de «cobertura de cola». Burr, 3 DGP, R = 300, error de `shape2`:

| Configuración | m | % central | mediana moderada | mediana pesada | mediana suaves | catastróficos /900 |
|---|--:|--:|---:|---:|---:|---:|
| P3c 25/50/75 | 3 | **100 %** | 0,3649 | 0,2581 | 0,4701 | **145** |
| **P3w 10/50/90** | 3 | 33 % | 0,1557 | **0,1242** | 0,2278 | **26** |
| P5 10/25/50/75/90 | 5 | 60 % | 0,1719 | 0,2146 | 0,2340 | 36 |
| P5t 5/10/50/90/95 | 5 | **20 %** | 0,1927 | 0,3327 | **0,1834** | 47 |
| P4t 10/25/75/90 | 4 | 50 % | 0,2127 | 0,1529 | 0,2661 | 30 |
| P3x 5/50/95 | 3 | 33 % | **0,1349** | 0,2477 | 0,1911 | **11** |

**La hipótesis se sostiene en parte, pero no es monótona.**

A favor: P3c con el 100 % central es catastrófico, y P5 con el 60 % es peor que P3w
con el 33 %. La dilución central es real.

En contra: **P5t, con solo el 20 % central, es peor que P3w** (47 frente a 26), y
notablemente peor en el DGP pesado (0,3327 frente a 0,1242). Ir más hacia la cola
**no** mejora indefinidamente.

**La explicación completa es un compromiso entre dos efectos opuestos:** los
cuantiles extremos aportan la información sobre la cola que `shape2` necesita, pero
son **estadísticamente más ruidosos**, y con cola pesada ese ruido crece. Con pesos
uniformes, la composición del conjunto decide dónde cae el equilibrio.

**Consecuencia: los pesos dejan de ser una cuestión diferible.** Con una ponderación
adecuada —por ejemplo por la varianza asintótica del cuantil muestral,
`p(1−p)/(n·f(q_p)²)`— sería posible **añadir percentiles sin diluir**, y la elección
de preset perdería gran parte de su criticidad.

**No propongo pesos aquí** (§8 del encargo lo prohíbe expresamente y, con razón, no
hay evidencia para hacerlo). Pero **OD-14 queda abierta y es real**, no teórica.

**Cautela:** P3x = 5/50/95 es la mejor de la tabla, y **no lo propongo**. Son 3 DGP y
un solo tamaño muestral: proponerlo sería exactamente el sobreajuste que este
bloque existe para evitar.

---

## 5. OD-13: `s_IQR` frente a `s_Q`

Con `s_Q = max_j q̂(p_j) − min_j q̂(p_j)`, la amplitud de los **objetivos**.

### 5.1 Ambas son válidas como normalizador

| | X | 1000·X | cociente |
|---|---:|---:|---:|
| `s_IQR` | 2.284,52 | 2.284.515,89 | ×1000 |
| `s_Q` | 5.852,95 | 5.852.950,84 | ×1000 |

Ambas escalan exactamente con `c` y **ninguna depende de θ**, luego **ninguna altera
el argmin**. La elección es puramente numérica, como el contrato ya establecía.

### 5.2 Dónde difieren: casos degenerados

| Caso | cfg | `s_IQR` | `s_Q` | m_req | **m_eff** |
|---|---|---:|---:|--:|--:|
| 1. masa puntual (todo = 1000) | P3c | 0,00 | 0,00 | 3 | **1** |
| 1. masa puntual | P5 | 0,00 | 0,00 | 5 | **1** |
| 2. 60 % masa central | P3c | **0,00** | **0,00** | 3 | **1** |
| **2. 60 % masa central** | **P5** | **0,00** | **4.054,84** | 5 | **3** |
| 3. redondeo ×1000 | P3c | 3.000 | 3.000 | 3 | 3 |
| 3. redondeo ×1000 | P5 | 3.000 | 5.000 | 5 | 4 |
| 4. redondeo con moda | P3c | 1.200 | 1.200 | 3 | **2** |
| 4. redondeo con moda | P5 | 1.200 | 4.900 | 5 | 4 |
| 5. continua | P3c | 1.944 | 1.944 | 3 | 3 |
| 5. continua | P5 | 1.944 | 4.941 | 5 | 5 |

**La fila decisiva es la cuarta.** Muestra con el 60 % de la masa en un valor
central, analizada con P5: `s_IQR = 0` — rechazaría por escala degenerada — pero
`m_eff = 3 ≥ k` y `s_Q = 4.054,84 > 0`. **`s_IQR` rechazaría una configuración que
sí tiene información suficiente.**

Y en el caso 1 y en el 2 con P3c, `s_Q = 0` **exactamente cuando `m_eff = 1`**: se
anula justo cuando todos los objetivos colapsan, que es cuando PM está realmente
indeterminado.

**`s_Q` se anula si y solo si todos los cuantiles objetivo coinciden.** Esa
equivalencia es la propiedad que la hace preferible: liga el normalizador a la
condición que hace resoluble el problema, no a una propiedad de la muestra ajena a
la configuración elegida.

### 5.3 Propuesta OD-13 (requiere aprobación)

```
s(x, p) = max_j q_emp(p_j) − min_j q_emp(p_j)
```

sin recurso alternativo: si `s_Q = 0`, se rechaza y se diagnostica (§5.5).

### 5.4 CONFIRMADO EN R — T6b ya se ejecutó

> **CORRECCIÓN (2026-09-03).** La versión anterior afirmaba que faltaba ejecutar el
> modo `spread` en R. **Era incorrecto:** T6b se ejecutó en R 4.4.1 junto con el
> resto de `pm_r_verification.R` y sus resultados estaban disponibles. Se incorporan.

Salida de **R 4.4.1**, `pm_r_verification.R` T6b:

| Caso | cfg | `IQR` | `q_dist` | `spread` (`s_Q`) | modo `iqr` | modo `spread` |
|---|---|---:|:-:|---:|---|---|
| A. degenerada | P3c | 0 | **1/3** | **0** | `scale_degenerate` | `scale_degenerate` |
| A. degenerada | P5 | 0 | **1/5** | **0** | `scale_degenerate` | `scale_degenerate` |
| B. 60 % masa central | P3c | **0** | **1/3** | **0** | `scale_degenerate` | `scale_degenerate` |
| **B. 60 % masa central** | **P5** | **0** | **3/5** | **4.519,23** | **`scale_degenerate`** | **`success`** |
| C. redondeo ×1000 | P3c | 2.000 | 3/3 | 2.000 | `success` | `success` |
| C. redondeo ×1000 | P5 | 2.000 | 4/5 | 5.000 | `success` | `success` |
| D. continua | P3c | 2.431,96 | 3/3 | 2.431,96 | `success` | `success` |
| D. continua | P5 | 2.431,96 | 5/5 | 6.240,95 | `success` | `success` |

**Las cinco propiedades quedan verificadas en R:**

1. `s_Q` depende de la muestra y de la configuración, **nunca de θ** — por construcción.
2. Conserva el argmin — corolario de (1).
3. Es escala-equivariante — C y D muestran que escala con el dato.
4. **Es positiva si y solo si al menos dos cuantiles objetivo difieren.** En R,
   `s_Q = 0` ocurre **exactamente** en las tres filas con `q_dist = 1`.
5. **Evita el rechazo incorrecto.** Fila B/P5: `IQR = 0` haría fallar la
   normalización, pero `q_dist = 3/5 ≥ k` y `s_Q = 4.519,23`; con `spread` el ajuste
   **converge**. `s_IQR` habría rechazado una configuración con información suficiente.

**Y una observación que refuerza la elección.** Con P3c, `s_Q` coincide
**exactamente** con `IQR` en R (2.000 = 2.000; 2.431,96 = 2.431,96), como debe ser:
la amplitud entre los cuantiles 25 y 75 *es* el rango intercuartílico. **`s_Q` no es
una alternativa a `IQR`: es `IQR` generalizado al conjunto de percentiles realmente
utilizado.** Coincide con él en el preset central y se adapta cuando el usuario elige
otro. Eso hace la adopción menos disruptiva de lo que parecía.

### 5.5 Propuesta OD-13 — candidata `s_Q`, **política simple, sin recurso**

> **CORRECCIÓN (2026-09-03, decisión del owner).** La versión anterior proponía
> `IQR(x)` como recurso cuando `m = 1`. **Se retira.** Un segundo normalizador
> introduce una rama con semántica distinta para salvar un caso que ya es
> rechazable, y complica la política sin aportar capacidad. El smoke test de
> `m = 1` asociado se elimina del script de preset en R.

```
s(x, p) = max_j q_emp(p_j) - min_j q_emp(p_j)
```

**Política, completa:**

- si `s_Q` es **finita y > 0** → se usa como normalizador;
- si `s_Q = 0` → la configuración **no aporta dispersión entre los cuantiles
  seleccionados**; se **rechaza con diagnóstico explícito**, sin sustituir el
  normalizador.

**Sin epsilon.** No se introduce ningún umbral numérico arbitrario: la condición es
`s_Q > 0`, y el caso `s_Q = 0` es exactamente aquel en que todos los cuantiles
objetivo coinciden (propiedad 4, verificada en R). Rechazar ahí es la respuesta
correcta, no una limitación.

Nótese que esto cubre también `m = 1`: con un único percentil `s_Q = 0` por
construcción, y el rechazo es el comportamiento deseado —una sola ecuación no
determina `k > 1` parámetros—.

**Recomiendo RESOLVER**, no mantener abierta: la decisión es puramente numérica
—cualquier constante positiva independiente de θ define el mismo estimador—, y la
propiedad decisiva está verificada en R. **Pendiente: aprobación del owner.**

---

## 6. `m_requested` frente a `m_effective`

| Caso | cfg | m_eff | k | Resultado de PM |
|---|---|--:|--:|---|
| 1. masa puntual | P3c / P5 | 1 | 2 | `optimizer_failure` |
| 2. 60 % masa central | P3c | 1 | 2 | `optimizer_failure` |
| 2. 60 % masa central | P5 | 3 | 2 | `optimizer_failure` |
| 3. redondeo ×1000 | P3c | 3 | 2 | success · `sdlog = 0,739` |
| 3. redondeo ×1000 | P5 | 4 | 2 | success · `sdlog = 1,041` |
| 4. redondeo con moda | P3c | **2 = k** | 2 | success · `sdlog = 0,492` |
| 4. redondeo con moda | P5 | 4 | 2 | success · `sdlog = 1,007` |
| 5. continua | P3c / P5 | 3 / 5 | 2 | success · `sdlog ≈ 1,25` |

**Hallazgos:**

1. **`m_eff < k` produce fallo del optimizador**, no un resultado silenciosamente
   erróneo. Es mejor de lo que temía, pero el motivo que se reporta —«el
   optimizador falló»— **no explica la causa real**, que es estructural.
2. **`m_eff = k` es frágil.** Caso 4 con P3c: `m_eff = 2 = k`, converge, y devuelve
   `sdlog = 0,492` frente a `1,007` con P5, sobre la misma muestra. Con datos
   redondeados y una moda, P3c **subestima gravemente** la dispersión.
3. **El redondeo reduce `m_eff` sin anularlo.** Caso 3: `m_eff = 3` con P3c y 4 con
   P5, ambos estimables, pero de nuevo P3c subestima `sdlog` (0,739 frente a 1,041;
   el valor generador es 1,3).

**Propuesta, deliberadamente asimétrica:**

| Condición | Estado | Justificación |
|---|---|---|
| `m_requested < k` | **RECHAZO** | Menos ecuaciones que parámetros: indeterminado por construcción |
| `m_requested ≥ k` | **potencialmente identificable** | Condición **necesaria**, no suficiente |

**`m_effective` se registra como DIAGNÓSTICO, no como regla de suficiencia.**

> **CORRECCIÓN (2026-09-03, decisión del owner).** No se congela la regla
> `m_effective ≥ k → suficiente`. **No es una condición suficiente**, y la propia
> evidencia de esta sección lo muestra: en el caso 2 con P5, `m_eff = 3 > k = 2` y
> aun así PM falla; en el caso 4 con P3c, `m_eff = 2 = k`, converge, y devuelve
> `sdlog = 0,492` frente a `1,007` de P5 sobre la misma muestra — converge hacia un
> valor gravemente sesgado. Tener suficientes valores distintos no garantiza que el
> sistema esté bien condicionado.

> **SEGUNDA CORRECCIÓN (2026-09-03, decisión del owner).** Una versión anterior de
> esta sección proponía además **rechazar cuando `m_eff < k`**. **Se retira
> también.** El argumento es de fondo: percentiles distintos pueden compartir
> valor empírico por **empates o redondeo** y sin embargo **corresponden a
> probabilidades distintas**, de modo que la ecuación asociada **no es
> redundante**. Contar valores empíricos distintos no mide identificabilidad.

**Política, definitiva para v1.1:**

- `m_requested < k` → **RECHAZO** (única regla que gobierna la aceptación);
- `m_requested ≥ k` → potencialmente identificable;
- `m_effective` se **calcula y se expone**, pero **no gobierna** la aceptación en
  ninguno de los dos sentidos;
- cuando haga falta un diagnóstico real de identificabilidad, se hará por
  **sensibilidad / multistart**, no por conteo de valores distintos.

---

## 7. Warnings

> **RESUELTO (2026-09-03).** `pm_warnings_capture.R` ejecutado en **R 4.4.1**.
> Ya no es una conjetura: hay salida real. Se conserva la tabla de origen previsto
> porque se cumplió, y se añade §7.1 con lo medido.

### 7.1 Resultado medido — RESUELTO

**594 avisos, todos con el mismo mensaje: «Se han producido NaNs».**

| Corte | Reparto |
|---|---|
| Por distribución | gamma **445** · normal **149** |
| Por escenario | `T2T3_gam_x1000` **445** · `T5_mu-100` **100** · `T5_mu0` **49** |
| Por punto del código | `objetivo Q(p;theta)` — **594 de 594** |

**Ninguno ocurre fuera del objetivo.** Pero **no todos son de la misma clase**, y
la primera versión de esta sección los agrupó mal:

| Origen | Nº | Clasificación |
|---|--:|---|
| `gamma` — `qgamma` en puntos de prueba del optimizador | **445** | **EXPECTED NUMERICAL EXPLORATION — optimizer trial points** |
| `normal` — `ifelse()` en la reparametrización | **149** | **IMPLEMENTATION DEFECT — experimental reparameterization** |

Los 445 son exploración normal: el optimizador visita puntos donde `Q(p; θ)` no es
finita, la función lo detecta y devuelve la penalización prevista `1e10`.

**Los 149 de la Normal NO lo eran.** No vienen del objetivo estadístico sino de la
reparametrización, que evaluaba `log()` sobre parámetros no positivos aunque
después descartase esa rama:

```r
to_u <- function(th) ifelse(pos, log(th), th)     # evalúa log(mean) aunque lo descarte
```

`ifelse()` evalúa **ambas ramas** sobre el vector completo, así que calcula
`log(-100)` y luego tira el resultado. El aviso es real; la operación, inútil. La
guarda correcta es indexar:

```r
to_u <- function(th) { u <- th; u[pos] <- log(th[pos]); u }
```

**Verificado: la corrección funciona.** `pm_crossfamily_R.R` incorpora esa guarda
por indexación —además de captura local acotada— y en R4, sobre **13.200 ajustes y
22 DGP incluyendo tres de Normal con `μ = 100`, `μ = 0` y `μ = −50`**, registró
**0 avisos `NaN` dentro de `Q(p; θ)`**.

**El problema experimental queda RESUELTO. No se declara ninguna limitación abierta
de PM por estos warnings.**

**Requisito registrado para B11.2.** La implementación productiva de PM **no debe
inundar la consola** con estos avisos: guardas previas cuando sea posible, o
**captura local acotada** únicamente de los avisos conocidos durante `Q(p; θ)`.
**Prohibido `suppressWarnings()` global** — silenciaría también los avisos que sí
señalarían un defecto.

### 7.2 Conjetura previa (se conserva: se cumplió)

Antes de disponer de la salida, acoté **qué operaciones podían generarlos** por
inspección del script:

| Origen previsto | Operación | Clase esperada |
|---|---|---|
| `q_fun$burr` | `(1-p)^(-1/shape2)` con `shape2` pequeño → **overflow** → `Inf`; luego `Inf^(1/shape1)` | **expected numerical exploration** |
| `q_fun$pareto` | `(1-p)^(-1/shape)` → mismo desbordamiento | expected numerical exploration |
| `to_th()` | `exp(u)` con `u` grande durante la exploración → `Inf` | expected numerical exploration |
| `to_u()` | `log(th)` si un arranque fuese ≤ 0 | **implementation**, si apareciese |

Los tres primeros son **exploración normal del optimizador**: la función objetivo
los captura y devuelve la penalización `1e10`. En la réplica Python aparecen como
`RuntimeWarning: overflow encountered in power` en `_q_burr` y `_q_par`, y son
inocuos.

La conjetura era correcta en el mecanismo (desbordamiento durante la exploración,
capturado por la penalización) y **incompleta en el origen**: no anticipé que casi
un cuarto de los avisos los generase `ifelse()` en la reparametrización, no la
función cuantil. §7.1 lo corrige.

---

## 8. Estado de las decisiones

| OD | Estado | Detalle |
|---|---|---|
| **OD-1 (forma del objetivo)** | **RESUELTA** | `J_PM(θ) = (1/s²)·Σ(Q_θ(p_j) − q̂_j)²`. Confirmada en R: identidad exacta, y las discrepancias observadas explicadas y reproducidas como escala del criterio de parada |
| **OD-2 (identificabilidad)** | **RESUELTA solo en su mitad negativa** | `m_requested < k` → REJECT. `m_requested ≥ k` → *potencialmente* identificable. **`m_effective` es solo diagnóstico**: no se congela ni `m_eff ≥ k → identificado` ni `m_eff < k → no identificable` (§6) |
| **OD-3 (compatibilidad)** | **RESUELTA** | 7 continuas + Normal control; ninguna discreta |
| **OD-13 (`s(x)`)** | ✅ **CONGELADA** | `s_Q = max(q̂) − min(q̂)` si es finita y > 0; si `s_Q = 0` → RECHAZO con diagnóstico. **Sin epsilon, sin recurso a `IQR`.** Política v1.1: **mínimo 2 percentiles, también para Exponential** |
| **Preset P3c** | ✅ **DESCARTADO como default** | 602 fallos catastróficos frente a 135/151. Puede conservarse como preset «Central / académico», **no recomendado por defecto** |
| **Preset** | ✅ **CONGELADO** | Default **P3w = 10/50/90**; **P5** como ampliado; **P3c** como «Central / académico», no recomendado (§10.3) |
| **OD-14 (pesos)** | **ABIERTA / DIFERIDA** | §4 demuestra que preset y pesos son el mismo problema. **No son necesarios para liberar PM v1.1** |
| **Warnings** | ✅ **RESUELTOS** | 445 de gamma: EXPECTED NUMERICAL EXPLORATION. 149 de Normal: **IMPLEMENTATION DEFECT — experimental reparameterization**, corregido. **R4: 0 avisos** (§7.1). **No queda ninguna limitación abierta de PM por warnings** |

---

## 9. Limitaciones

1. **§3 y §4 son Python, no R.** Es la limitación principal y la razón de existir de
   `pm_burr_preset_R.R`. §1 y §2 son deterministas y no dependen del motor; §5 está
   confirmada en R.
2. El benchmark del preset es **solo Burr**, `n = 1.000`.
3. ~~Los warnings no se han inspeccionado.~~ **Resuelto en §7.1.**
4. `s_Q` está verificada como **normalizador** (§5.4). La política de rechazo cuando
   `s_Q = 0` no requiere experimento adicional: se sigue de la propiedad 4.
5. P3x = 5/50/95 aparece como la mejor con 3 DGP. **Insuficiente para proponerla.**
6. **El benchmark de preset en Python (§3) NO es pareado.** Su semilla se construye
   como `seed_for(dgp + cfg, rep)`, de modo que cada preset se evaluó sobre una
   muestra Monte Carlo **distinta**. Detectado por el owner al revisar la
   transcripción a R. Clasificación: **IMPLEMENTATION DEFECT — experimental
   benchmark design**; **no afecta a producción**.

   Consecuencia estadística: las estimaciones por preset siguen siendo **insesgadas**
   —cada una es una muestra legítima del mismo DGP—, pero la **comparación** entre
   presets arrastra la varianza de dos sorteos independientes en lugar de la varianza
   de la diferencia, que es menor. La dirección del resultado (P3w mejor que P5) no
   está sesgada, pero su **precisión está sobreestimada** y no admite análisis réplica
   a réplica. Por eso `pm_burr_preset_R.R` se rediseña como **pareado** y pasa a ser
   la evidencia primaria; §3 queda degradada a indicio.
7. **§3.3 no demuestra invariancia de escala.** `escala_x1000` es una réplica
   distribucional reescalada, no la misma muestra × 1.000. La invariancia exacta está
   en T2/T3 de `pm_r_verification.R`. Aclarado en §3.3.

---

## 10. B11.1-R3 (resultados R pareados) y B11.1-R4 (cross-family)

**RUNTIME: R 4.4.1 (aarch64-apple-darwin20). `R_MC = 300`, `n = 1.000`,
normalización `s_Q`, diseño PAREADO.** Estos números **sustituyen** a los de §3,
que eran Python y no pareados.

### 10.1 Preset en Burr, con el diseño corregido

| Métrica | P3c | P3w | P5 |
|---|--:|--:|--:|
| Fallos catastróficos (`shape2` + `scale`) | **602** | **135** | **151** |
| DGP con menor RMSE de `shape2` (de 6) | — | **6** | 0 |
| DGP con menor RMSE de `scale` (de 6) | — | **5** | 1 |
| % réplicas con menor error, `shape2` | — | **51,0 %** | 49,0 % |
| % réplicas con menor error, `scale` | — | **52,1 %** | 47,9 % |

**La lectura correcta, y es la única que debe documentarse:**

> **P3w muestra mayor robustez frente a errores extremos en Burr, pero P5 puede
> ser igual o mejor en el caso típico de muchas réplicas.**

**No se documenta «P3w gana universalmente».** Y conviene entender por qué las dos
mitades de la tabla no se contradicen: ganar el **51 %** de las réplicas y a la vez
tener menor RMSE en **las seis** es la firma de una **distribución de error con
cola**. P3w gana marginalmente más a menudo y **gana mucho más cuando gana**;
las ventajas de P5 son pequeñas. RMSE y conteo de catástrofes pesan la cola; la
proporción pareada, no. Ninguna media global única puede arbitrar esto — de ahí que
el criterio de R4 sea multi-eje.

**Y la corrección del diseño encogió la ventaja de P3w.** Python no pareado daba
**93 vs 123**; R pareado con `s_Q` da **135 vs 151**: la brecha pasa de 30 a 16.
Es exactamente lo anticipado en §9.6 — la precisión del resultado anterior estaba
sobreestimada.

### 10.2 B11.1-R4 — última prueba, diseño

`experiments/pm_crossfamily_R.R`. **Solo P3w vs P5.** Sin P3c, sin pesos, sin
nuevos objetivos, sin nuevas normalizaciones. `s_Q`, pareado, `n = 1.000`,
`R_MC = 300`, **22 DGP**: 7 continuas de v1.1 + Normal como control, con Burr
reducido a control de 2 DGP por estar ya validado. Parámetros documentados en la
cabecera del script y volcados al inicio de la ejecución.

**Escala de referencia del error — decisión metodológica.** `e_j =
|θ̂_j − θ_j| / ref_j`, con `ref_j = |θ_j|` para formas y escalas positivas,
`ref = sd_true` para `mean` de la Normal (hay DGP con `μ = 0` y `μ = −50`) y
**`ref = sdlog_true` para `meanlog` de la Lognormal**. Este último lo añado por
iniciativa propia y conviene justificarlo: `meanlog` es un parámetro de
**localización en escala logarítmica**, de modo que cambiar la unidad de los datos
lo desplaza en una constante aditiva y su «error relativo» **depende de la unidad
elegida** — no es invariante, aunque el valor sea positivo y esté lejos de cero.
Con esta convención, **`e_j > 1` define el fallo catastrófico de forma única para
todos los parámetros**. `bias` y `RMSE` van siempre en unidades del parámetro;
`rel_bias` y `rel_RMSE` solo cuando son interpretables.

**El script informa de los cuatro ejes del criterio:** (A) robustez excluyendo
Burr; (B) precisión típica; (C) DGP donde un preset falla catastróficamente y el
otro no; (D) magnitud de las diferencias segmentada por `k`.

### 10.3 B11.1-R4 — resultados y CIERRE

**RUNTIME: R 4.4.1 (aarch64-apple-darwin20). 22 DGP · 13.200 ajustes · `s_Q` ·
PAREADO · `R_MC = 300` · `n = 1.000`.**

| Familia | Catastróficos P3w / P5 | % réplicas P3w mejor |
|---|:--:|--:|
| Exponencial | 0 / 0 | 41,6 % |
| Gamma | 0 / 0 | 51,0 % |
| Weibull | 0 / 0 | 49,2 % |
| Lognormal | 0 / 0 | **56,5 %** |
| Loglogística | 0 / 0 | 50,9 % |
| **Pareto** | **20 / 28** | **56,0 %** |
| **Burr** (control) | **9 / 40** | 47,6 % |
| Normal (control) | 0 / 0 | 43,9 % |

Convergencia global: **P3w 0,9885 · P5 0,9877**. Precisión típica: diferencias
pequeñas fuera de Pareto y Burr.

**Los cuatro ejes del criterio, respondidos:**

- **(A) ¿P3w conserva la robustez fuera de Burr?** Sí, pero **concentrada**: cinco
  de las seis familias no-Burr dan **cero** fallos catastróficos con ambos presets.
  Toda la diferencia está en **Pareto (20 vs 28)**.
- **(B) ¿P5 mejora la precisión típica?** **No de forma consistente.** P5 gana el
  caso típico más a menudo en Exponencial (58,4 %), Normal (56,1 %), Weibull
  (50,8 %) y Burr (52,4 %); P3w en Lognormal (56,5 %), Pareto (56,0 %), Gamma
  (51,0 %) y Loglogística (50,9 %). **Cuatro a cuatro.**
- **(C) ¿Alguno evita fallos que el otro no?** Solo en las dos familias de cola
  pesada, y siempre a favor de P3w: Pareto 20 vs 28, **Burr 9 vs 40**.
- **(D) ¿Son materialmente pequeñas en familias de 1–2 parámetros?** **Sí.** En las
  familias sin fallos catastróficos las proporciones pareadas se mueven en la banda
  42–57 %, sin patrón, y la convergencia difiere en **0,0008**.

**La lectura honesta.** P3w y P5 son **prácticamente equivalentes** en las familias
sencillas — y en varias P5 gana el caso típico ligeramente más a menudo. La ventaja
de P3w es **específica y valiosa**: reduce el riesgo extremo justo donde el riesgo
extremo importa, en las colas pesadas que dominan el modelado de severidad. Con
diferencias despreciables en el resto y convergencia empatada, ese es el argumento
que decide: **se paga muy poco por una protección concreta.**

**DECISIÓN CONGELADA:** default **P3w = 10/50/90**; **P5** disponible como preset
ampliado; **P3c** disponible como «Central / académico», no recomendado. El texto
exacto de justificación está en §2.1 de `tool02_percentile_matching.md`.

### 10.4 Defecto de reporting en R4 — CORREGIDO

**IMPLEMENTATION DEFECT — experimental reporting only.** El encabezado del bloque A
anunciaba «EXCLUYENDO Burr» y el **total** sí filtraba (`out$family != "burr"`),
pero la **tabla** de «DGP donde un preset falla y el otro no» no aplicaba el filtro,
de modo que aparecían filas de Burr bajo un rótulo que decía excluirlo.

**Corregido en `pm_crossfamily_R.R`:** el criterio C se divide en **C.1** (familias
de decisión, sin Burr) y **C.2** (Burr, etiquetado como control que no participa en
el criterio). **No se reejecuta el benchmark**: el defecto es de presentación, los
CSV y todas las métricas estadísticas son idénticos.

**B11.1 = CLOSED / APPROVED.**

---

*Actuarial Tools by BMK — B11.1-R2/R3/R4. Diagnóstico. Sin implementación productiva.*
