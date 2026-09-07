# Tool-02 — B12.1: Numerical Observed-Information Benchmark

> **ESTADO: CLOSED / APPROVED.** Ejecutado por el owner en **R 4.4.1
> (aarch64-apple-darwin20)**: ≈ 6,19 s, **0 warnings**, 100 % de matrices válidas.
> Resultados en §7. Política numérica seleccionada: **esquema A**.
>
> **B12.2 queda DESBLOQUEADO** e implementado en ADR-034.

Artefacto: `experiments/b12_observed_information_benchmark.R`
Contrato metodológico: `docs/tool02_mle_uncertainty.md`

---

## 1. Pregunta experimental

Una sola:

> ¿Qué esquema de diferencias finitas y qué regla de tamaño de paso proporcionan
> una aproximación suficientemente precisa y estable de la **información
> observada** para las parametrizaciones **reales** de Tool-02?

No se trata de estimar el RMSE estadístico del MLE. Se trata de medir el **error
numérico de la Hessiana alrededor de `θ̂`**. Por eso el diseño prioriza
**diversidad de condiciones** sobre número de réplicas Monte Carlo.

## 2. Hipótesis, declaradas antes de medir

| # | Hipótesis | Predicción falsable |
|---|---|---|
| **H1** | El paso óptimo para segundas derivadas por diferencias centrales está en `c ≈ ε^(1/4)`, no en `ε^(1/3)` | El esquema **B** tendrá error mayor que el **A**, por dominancia del redondeo |
| **H2** | El error óptimo es aproximadamente **independiente de `n`** | Truncamiento y redondeo escalan ambos con `n`, así que el `c*` óptimo no debería desplazarse con `n` |
| **H3** | Richardson (**C**) reduce el error, pero a coste 2× | Menor error de Frobenius que A; hay que ver si la mejora justifica el coste |
| **H4** | El paso relativo **en escala `u`** hace la regla insensible a la magnitud de los datos | La estabilidad de `J_u` bajo `x → 1000x` será alta en las familias de escala |
| **H5** | La fórmula cruzada de 4 puntos es simétrica **por construcción** | La asimetría medida será exactamente 0; la simetrización sería innecesaria |
| **H6** | Burr, con `k = 3` y posible curvatura débil, dará el peor `rcond` | Se observará en §7.4 |

**H5 tiene consecuencia de diseño:** si se confirma, la política no debe incluir
un paso de simetrización, porque simetrizar una matriz ya simétrica es ruido de
proceso que oculta un fallo real si algún día deja de serlo.

## 3. Diseño

- **Independiente del optimizador.** Se deriva `f(u) = −ℓ(T⁻¹(u))` alrededor de
  `θ̂`, venga `θ̂` de fórmula cerrada o de `optim()`. **No se usa
  `optim(hessian = TRUE)`** ni se depende de haber pasado por `.mle_optim()`.
  Es el requisito de fondo de B12: cinco familias tienen MLE cerrado.
- **Sin dependencias nuevas.** No `numDeriv`. Diferencias centrales propias.
- **Escala `u`** con la tabla declarativa de `tool02_mle_uncertainty.md` §4.4,
  incluida la **logit** para `prob`.
- `n ∈ {100, 1000, 10000}`; **3 réplicas** por (escenario, `n`) para descartar
  casualidades sin convertirlo en un Monte Carlo.
- Semillas deterministas por `(distribución, escenario, n, réplica)`.
- **`θ̂` en la frontera** (p. ej. `λ̂ = 0`, `p̂ = 1`) ⇒ `u` no finita ⇒ el caso se
  **descarta y se registra**, en lugar de contaminar las métricas: es un MLE
  degenerado, no un fallo del esquema numérico.

## 4. Esquemas comparados

Hessiana por diferencias centrales sobre `f(u)`:

```
diagonal:      [ f(u+hᵢeᵢ) − 2f(u) + f(u−hᵢeᵢ) ] / hᵢ²
fuera de diag: [ f(++) − f(+−) − f(−+) + f(−−) ] / (4 hᵢ hⱼ)
```

Regla de paso, **relativa a la coordenada `u`**:

```
hⱼ = c · max(|uⱼ|, 1)
```

| Esquema | `c` | Valor | Justificación |
|---|---|---|---|
| **A** | `ε^(1/4)` | ≈ 1,22e−4 | Balance teórico truncamiento `~h²f⁗` / redondeo `~ε|f|/h²` para **segundas** derivadas |
| **B** | `ε^(1/3)` | ≈ 6,06e−6 | Óptimo para **primeras** derivadas. Incluido como **contraste**: debería ser peor (H1) |
| **C** | Richardson sobre A | `h` y `h/2` | `J_R = (4·J(h/2) − J(h))/3` cancela el término `O(h²)`. Justificación **analítica**, no de ensayo y error. Coste 2× |

**Por qué el paso es relativo a `u` y no a `θ`:** una escala de severidad de
`1e3` en `θ` es un **desplazamiento aditivo** en `log θ`. La regla en `u` es por
tanto insensible a la magnitud de los datos (H4), cosa que una regla en `θ` no
puede ser.

Además se ejecuta un **barrido de `c` sobre `10^{−9}` … `10^{−2}`** en pasos de
medio orden, para localizar el mínimo empírico y **medir la anchura de la
meseta** (rango de `c` donde el error no supera 10× el mínimo). La anchura importa
tanto como el mínimo: una regla con meseta estrecha es frágil aunque su óptimo sea
bueno.

## 5. Referencias analíticas — derivadas bajo la parametrización de `calc.R`

Todas verificadas por inspección del código, no copiadas de otra parametrización.
Todas son **Hessianas observadas evaluadas en `θ̂`** (`ref_kind = "observed"`), no
covarianzas asintóticas: en estas cinco familias la Hessiana observada se reduce
en `θ̂` a una función de `θ̂` y `n`.

### 5.1 Exponencial — `rate = λ`, `dexp(x, rate)`

`ℓ = n log λ − λΣx`, `ℓ'' = −n/λ²` ⇒ `J_θ = n/λ²`, `Σ_θ = λ²/n`.
En `u = log λ`: `d²(−ℓ)/du² = λΣx`, y en `λ̂ = n/Σx` queda **`J_u = n` exactamente**,
independiente de los datos y del parámetro. Es el caso de control más limpio del
benchmark.

### 5.2 Poisson — `lambda`, `dpois`

`ℓ'' = −Σx/λ²`; en `λ̂ = x̄` ⇒ `J_θ = n/λ`, `Σ_θ = λ/n`. En `u = log λ`:
`J_u = n·λ̂`.

### 5.3 Geométrica — `prob = p`, `dgeom`, soporte {0,1,2,…}

**Inspeccionado, no supuesto:** `.mle_geometric()` usa `p̂ = 1/(1+x̄)` y
`stats::dgeom`, es decir **fallos antes del primer éxito**, no ensayos hasta el
primer éxito. Con esa parametrización `Σx = n(1−p)/p` y

```
ℓ = n log p + Σx·log(1−p)
ℓ'' = −n/p² − Σx/(1−p)²   ⇒   J_θ = n / (p²(1−p))
Σ_θ = p²(1−p)/n
```

En `u = logit p`, con `dθ/du = p(1−p)` y score nulo en `p̂`:
**`J_u = n(1−p̂)`**. Es la única referencia con transformación **logit**, y por
tanto la validación de que la tabla declarativa no es decorativa.

### 5.4 Normal — `(mean, sd)` con `sd` = MLE (divide por `n`), `dnorm`

```
∂²ℓ/∂μ²   = −n/σ²
∂²ℓ/∂μ∂σ  = −2Σ(x−μ)/σ³   →  en μ̂, Σ(x−μ̂) = 0  ⇒  EXACTAMENTE 0
∂²ℓ/∂σ²   = n/σ² − 3Σ(x−μ)²/σ⁴  →  con Σ(x−μ̂)² = nσ̂²  ⇒  −2n/σ̂²
```

`J_θ = diag(n/σ², 2n/σ²)`, `Σ_θ = diag(σ²/n, σ²/(2n))`.

En `u = (μ, log σ)`: **`J_u = diag(n/σ², 2n)`**, de donde
**`Var(log σ̂) ≈ 1/(2n)`**, y el método delta con `G = diag(1, σ)` devuelve
**`Var(σ̂) ≈ σ²/(2n)`**. **Ésta es la validación explícita de OD-5.**

La **off-diagonal es exactamente 0 en el MLE**, así que es también el caso donde
el error relativo no tiene sentido y debe usarse **error absoluto** (§6).

### 5.5 Lognormal — `(meanlog, sdlog)`, `dlnorm`

`log f(x) = log f_N(log x; meanlog, sdlog) − log x`. El término `−log x` **no
depende de los parámetros**, luego la Hessiana es **idéntica** a la Normal
aplicada a `log x`. Mismas expresiones con `σ = sdlog`. Segunda validación de
OD-5, ahora con `meanlog` en escala identidad y datos de magnitud `~1e3`.

### 5.6 Binomial Negativa — **REFERENCIA NO DISPONIBLE**

La información respecto de `size` involucra `E[trigamma(x + size)]`, que **no
tiene forma cerrada elemental** bajo la parametrización `(size, mu)` de
`.mle_negative_binomial()`. **No se inventa una referencia.** Queda como caso sin
verdad analítica; si se desea, puede tratarse como stress en una iteración
posterior.

## 6. Métricas

Sobre los casos con referencia:

- Error de `J_u` **entrada a entrada**, con selección automática: **relativo** si
  `|ref| > 1e−12`, **absoluto** si la referencia es (casi) cero. Nunca un error
  relativo absurdo sobre un cero.
- **Norma relativa de Frobenius** de la matriz completa:
  `‖J_num − J_ref‖_F / ‖J_ref‖_F`. Se documenta que la norma es Frobenius.
- Error relativo máximo de **varianzas** y de **SE** en escala natural.
- Error **absoluto** de la covarianza off-diagonal.
- Éxito de Cholesky · `rcond` · autovalores extremos · asimetría.
- Sensibilidad al paso (barrido de `c`).
- Nº de evaluaciones y tiempo por Hessiana.

## 7. Resultados — **EJECUTADO**

**RUNTIME: R 4.4.1 (aarch64-apple-darwin20). Parse OK. Benchmark completo.
≈ 6,19 s. 0 warnings. 100 % de matrices válidas en los casos con referencia
analítica, para los tres esquemas.**

### 7.1 Exactitud frente a la referencia analítica

| Esquema | % válidos | mediana Fro `J_u` | p90 | mediana err. rel. SE | mediana evals |
|---|--:|--:|--:|--:|--:|
| **A** `ε^(1/4)` | 100 % | **9,796e−08** | **1,423e−06** | **8,313e−08** | **3** |
| B `ε^(1/3)` | 100 % | 1,948e−05 | 6,245e−04 | 1,884e−05 | 3 |
| C Richardson | 100 % | 2,644e−07 | 6,553e−06 | 1,700e−07 | 6 |

Por familia, **A fue igual o mejor** que las alternativas salvo diferencias
puntuales no materiales.

### 7.2 Contraste con las hipótesis

| Hipótesis | Resultado |
|---|---|
| **H1** `ε^(1/4)` mejor que `ε^(1/3)` | **CONFIRMADA.** Dos órdenes de magnitud en la mediana, **440× en el p90**, al mismo coste |
| **H2** óptimo independiente de `n` | **CONFIRMADA.** `c*` estable en las tres escalas de `n` |
| **H3** Richardson mejora | **FALSADA en su parte cuantitativa.** C es **2,7× peor** que A en mediana y 4,6× en p90, con el doble de evaluaciones |
| **H4** paso relativo en `u` insensible a la escala del dato | **CONFIRMADA.** Estabilidad de escala claramente mejor con A |
| **H5** simetría por construcción | **CONFIRMADA.** Asimetría máxima observada = **0** |
| **H6** Burr da el peor `rcond` | **CONFIRMADA.** ≈ 1e−3 a 2e−2 según escenario |

**Por qué falla Richardson, y no es casualidad.** La extrapolación cancela el
término `O(h²)` de **truncamiento**. Pero en `h ≈ ε^(1/4)` el error ya está
dominado por el **redondeo**, que Richardson no cancela — y que además **amplifica**,
porque resta dos estimaciones muy próximas y divide por 3. Aplicar Richardson
sobre un paso ya óptimo empeora el resultado. La hipótesis estaba declarada antes
de medir y el benchmark la falsó: es exactamente para lo que servía.

### 7.3 Sensibilidad al paso

`c*` empírico: Exponencial **1e−4**, Poisson **1e−4**, Geométrica **3,16e−4**,
Normal **1e−4**, Lognormal **3,16e−4**.

**`ε^(1/4) = 1,22e−4` cae dentro de la meseta de buen comportamiento de las cinco
familias.** La constante no se elige por ensayo y error: coincide con el óptimo
teórico **y** con el empírico. En Geométrica y Lognormal el óptimo empírico está
algo por encima, de modo que ahí el esquema opera ligeramente desplazado del
mínimo — lo que justifica una tolerancia de test algo mayor para esas dos.

### 7.4 Stress

Gamma, Weibull, Loglogística, Pareto y Burr: **matrices finitas, Cholesky OK,
`valid = TRUE` en todos los escenarios ejecutados, 0 warnings**. Estabilidad de
paso y de escala **claramente mejor con A que con B**.

**Burr: `rcond` ≈ 1e−3 a 2e−2** según escenario. **No se convierte en regla de
rechazo.** Una información con `rcond` pequeño puede ser estructuralmente válida:
el condicionamiento mide cuán informativa es la curvatura en la peor dirección, no
si la matriz es una covarianza legítima. La relación entre condicionamiento y
fiabilidad práctica se evalúa contra bootstrap en **B15**.

### 7.5 Decisión

**Esquema A**, `h_j = ε^(1/4)·max(|u_j|,1)`, diferencias centrales, **sin
simetrización** (innecesaria por H5), **sin Richardson** (no compensa),
**sin `ε^(1/3)`** (peor precisión). Evaluación no finita del estencil ⇒ matriz
inválida con motivo. `rcond` como diagnóstico sin umbral.

**B12.1 = CLOSED / APPROVED.** Implementado en B12.2 (ADR-034).

## 8. Stress sin verdad analítica

Aplicado a **Gamma, Weibull, Loglogística, Pareto/Lomax y Burr** con las
parametrizaciones exactas de `calc.R`. Aquí **no se inventa una verdad
analítica**; se observa: matriz finita, simetría, definida positiva, `rcond`,
estabilidad frente a `h → 2h`, estabilidad bajo `x → 1000x`, SE **solo como
diagnóstico experimental**, y fallos numéricos.

**`optim` convergido no es prueba de buena información observada.** Son
propiedades distintas: la convergencia dice que el gradiente es pequeño; el
condicionamiento de la Hessiana, que la curvatura es informativa en todas las
direcciones. Burr merece atención especial por posible curvatura débil en `shape2`
(H6), coherente con lo observado en B11.1.

## 9. Warnings

Capturados con `withCallingHandlers`, con contexto (distribución, escenario, `n`,
esquema, punto de código, valor de `u`). **Sin `suppressWarnings()` global.**

Taxonomía obligatoria: `PRODUCT BUG` · `TEST DEFECT` · `EXPERIMENTAL SCRIPT
DEFECT` · `EXPECTED NUMERICAL EXPLORATION` · `ENVIRONMENT WARNING` ·
`METHODOLOGICAL LIMITATION`.

**Matiz importante respecto de B11.1:** allí los avisos venían de la exploración
del optimizador en puntos lejanos, y eran esperables. **Aquí no.** El estencil de
diferencias se evalúa **cerca de `θ̂`**, donde la log-verosimilitud debería ser
perfectamente evaluable. Un aviso en `where = hessiana` **no** puede clasificarse
como `EXPECTED NUMERICAL EXPLORATION` sin justificarlo: es un indicio de que el
paso es demasiado grande o de que `θ̂` está cerca de una frontera.

## 10. Criterio de cierre de B12.1

B12.1 solo podrá cerrarse si la evidencia permite elegir, **con razones**:

1. esquema de Hessiana;
2. regla de paso, con su constante justificada y la anchura de su meseta;
3. simetrización, si procede (H5 sugiere que no);
4. tratamiento de evaluaciones inválidas;
5. validación estructural;
6. diagnóstico de condicionamiento.

**No basta con «la que funciona».** Si ninguna regla resulta suficientemente
robusta —por ejemplo, si la meseta es estrecha o si el óptimo se desplaza con la
familia—, **debe declararse** y B12.2 seguirá bloqueado.

---

*Actuarial Tools by BMK — B12.1, diseño. Sin resultados. Sin implementación productiva.*
