# Tool-02 — Contrato de incertidumbre analítica del MLE (B12)

> **Estado. B12.1 CLOSED / APPROVED · B12.2 CLOSED / APPROVED (ADR-034).**
> Validado en R 4.4.1: suite `b12_uncertainty_tests.R` PASS completa y **14
> suites de regresión PASS**, incluida la revalidación posterior a la corrección
> del diagnóstico de Cholesky (§5.0). Sin regresiones funcionales, sin warnings
> en el camino nominal.
>
> El motor vive en `R/calc.R` §2c-ter; los tests en
> `tests/b12_uncertainty_tests.R`. La política numérica se congeló con la
> evidencia de B12.1 (§7 de `tool02_b12_benchmark.md`) y se recoge en §7.1.
> `DFIT_SCHEMA_VERSION` sigue en 1.1.0 y `manifest` en 1.0.2: `inference` es
> opt-in y no se expone todavía (B16).

---

## 1. Objetivo

Publicar, para un ajuste **MLE convergido**, una medida de incertidumbre de los
parámetros estimados derivada de la curvatura de la log-verosimilitud en el
óptimo — errores estándar y matriz de covarianza —, junto con un diagnóstico
auditable que permita **no publicarla** cuando no sea fiable.

## 2. Alcance

**Dentro:** información observada, covarianza, errores estándar, cadena de
validación estructural, diagnóstico de condicionamiento. Distribuciones con MLE
convergido, continuas y discretas.

**Fuera:**

| Fuera de B12 | Bloque |
|---|---|
| Bootstrap y sus réplicas | B13 |
| Sesgo bootstrap e IC percentil | **B13** (ya implementados) |
| Organización y validación de las salidas de B12/B13 | B14 |
| Comparación analítico *vs* bootstrap | B15 |
| Interfaz y visualización | B16 |
| Intervalos de confianza | B12.2, y solo tras resolver **OD-16** |
| **Percentile Matching** | B13 (bootstrap) |

### 2.1 Por qué PM queda fuera, explícitamente

Un ajuste PM lleva asociada una `logLik` (ADR-032, punto 5), pero es una
**evaluación *ex post*** de la verosimilitud en `θ_PM`. **PM no maximiza esa
verosimilitud** — minimiza `J_PM` —, de modo que `θ_PM` **no es un punto crítico
de `ℓ`**: el score no se anula ahí.

Esto no es un matiz. Toda la construcción de §3 descansa en que `∇ℓ(θ̂) = 0`;
sin esa condición, la inversa de la Hessiana **no es** la covarianza asintótica
del estimador, y la aproximación cuadrática está centrada en un punto que no es
el óptimo. **Reutilizar la maquinaria MLE sobre `θ_PM` produciría un SE con
apariencia de validez y sin contenido.** La incertidumbre de PM se obtiene por
bootstrap en B13, que no necesita esa hipótesis.

---

## 3. Definiciones matemáticas

Sea `ℓ(θ) = Σᵢ log f(xᵢ; θ)` y `θ̂` el MLE.

```
J(θ̂) = −∇²ℓ(θ̂) = ∇²[−ℓ(θ̂)]        MATRIZ DE INFORMACIÓN OBSERVADA
Σ̂    = J(θ̂)⁻¹
SEⱼ  = sqrt( Σ̂[j,j] )
```

### 3.1 Información observada frente a información esperada

**Terminología obligatoria: `J(θ̂)` es la *información observada*.** No debe
llamarse «Fisher Information» a secas. La información esperada de Fisher es

```
I(θ) = E_θ[ J(θ) ]
```

y **no es lo que este motor calcula**. La diferencia importa por tres razones:

1. `J(θ̂)` depende de la muestra concreta; `I(θ)` es una esperanza sobre el modelo.
2. `J(θ̂)` no requiere que el modelo sea correcto para describir la curvatura
   *observada*; `I(θ)` sí presupone el modelo.
3. Cuando el modelo está mal especificado, ambas divergen — y la varianza correcta
   es la sándwich, que **no** está en el alcance de B12.

**Consecuencia práctica para el benchmark:** una fórmula cerrada de la literatura
puede corresponder a (A) la Hessiana observada, (B) la información esperada, o
(C) la covarianza asintótica del MLE. **No son intercambiables.** Cada referencia
de B12.1 declara a cuál de las tres corresponde (`ref_kind`).

---

## 4. Escala de cálculo — OD-5

### 4.1 La política

Sea `u = T(θ)` una transformación **declarativa por parámetro** y
`θ = T⁻¹(u)`. Se calcula

```
f(u)   = −ℓ( T⁻¹(u) )
J_u    = ∇²_u f  evaluada en û = T(θ̂)
Σ_u    = J_u⁻¹
Σ_θ    = G Σ_u Gᵀ          con  G = ∂T⁻¹(u)/∂uᵀ  en û
SEⱼ    = sqrt( Σ_θ[j,j] )
```

Como las transformaciones son **componente a componente**, `G` es **diagonal**:
`G = diag(dθⱼ/duⱼ)`.

### 4.2 Por qué en escala `u` y no en escala natural

El mismo argumento que motivó ADR-014 para la optimización. Con `shape ≈ 1` y
`scale ≈ 1e3`, la Hessiana en escala natural tiene entradas que difieren en seis
órdenes de magnitud: una regla de paso única es simultáneamente demasiado grande
para una coordenada y demasiado pequeña para la otra, y el número de condición se
degrada por razones que **no son estadísticas sino de unidades**. En escala `u`
los parámetros son O(1) y una regla de paso relativa es homogénea.

**No es una aproximación**: el método delta es exacto para la transformación de la
covarianza asintótica, porque `T` es un difeomorfismo componente a componente.

### 4.3 No todos los parámetros son positivos

`log` **no** sirve como transformación universal. Dos contraejemplos reales en el
catálogo actual:

- `mean` (Normal) y `meanlog` (Lognormal) viven en **ℝ**: `log` no está definida.
- `prob` (Geométrica) vive en **(0,1)**: `log` no la acota superiormente y
  admitiría `p̂ > 1`. La transformación correcta es **logit**.

Por eso la tabla es **declarativa por parámetro** y no una regla global.

### 4.4 Tabla propuesta `DFIT_PARAM_TRANSFORM`

Nombres **exactamente** los que devuelven los `.mle_*` de `R/calc.R`, verificados
por inspección del código.

| Distribución | Parámetro | Soporte | `T(θ)` | `T⁻¹(u)` | `dθ/du` |
|---|---|---|---|---|---|
| exponential | `rate` | θ > 0 | `log θ` | `exp u` | `θ` |
| gamma | `shape` | θ > 0 | `log θ` | `exp u` | `θ` |
| gamma | `scale` | θ > 0 | `log θ` | `exp u` | `θ` |
| weibull | `shape` | θ > 0 | `log θ` | `exp u` | `θ` |
| weibull | `scale` | θ > 0 | `log θ` | `exp u` | `θ` |
| lognormal | `meanlog` | θ ∈ ℝ | `θ` | `u` | `1` |
| lognormal | `sdlog` | θ > 0 | `log θ` | `exp u` | `θ` |
| loglogistic | `shape` | θ > 0 | `log θ` | `exp u` | `θ` |
| loglogistic | `scale` | θ > 0 | `log θ` | `exp u` | `θ` |
| pareto (Lomax) | `shape` | θ > 0 | `log θ` | `exp u` | `θ` |
| pareto (Lomax) | `scale` | θ > 0 | `log θ` | `exp u` | `θ` |
| burr | `shape1` | θ > 0 | `log θ` | `exp u` | `θ` |
| burr | `shape2` | θ > 0 | `log θ` | `exp u` | `θ` |
| burr | `scale` | θ > 0 | `log θ` | `exp u` | `θ` |
| normal | `mean` | θ ∈ ℝ | `θ` | `u` | `1` |
| normal | `sd` | θ > 0 | `log θ` | `exp u` | `θ` |
| poisson | `lambda` | θ > 0 | `log θ` | `exp u` | `θ` |
| geometric | `prob` | θ ∈ (0,1) | `log(θ/(1−θ))` | `1/(1+e^{−u})` | `θ(1−θ)` |
| negative_binomial | `size` | θ > 0 | `log θ` | `exp u` | `θ` |
| negative_binomial | `mu` | θ > 0 | `log θ` | `exp u` | `θ` |

**No implementada en producción.** Debe quedar validada por B12.1 antes de entrar
en `calc.R`.

### 4.5 Hallazgo colateral de la inspección: producción es correcta hoy, y por poco

`.mle_optim()` aplica `log()` a **todos** los parámetros de arranque, sin tabla.
Eso sería incorrecto para `mean`, `meanlog` y `prob`. **No lo es** porque
ninguna de esas tres distribuciones llega a `.mle_optim()`: Normal, Lognormal,
Exponencial, Poisson y Geométrica tienen **MLE cerrado**, y Binomial Negativa usa
`optimize()` sobre `size` (positivo) con `mu` fijado a la media muestral. Los
cinco que sí pasan por `.mle_optim()` —Gamma, Weibull, Loglogística, Pareto,
Burr— tienen **todos** sus parámetros positivos.

**No hay bug latente.** Pero la corrección actual depende de una coincidencia
entre dos listas que nadie mantiene explícitamente. La tabla declarativa de §4.4
la vuelve explícita, y ese es un argumento a su favor independiente de B12.

---

## 5. Cadena de validación estructural — OD-4 (parte estructural)

Sobre una matriz candidata `J_u`, en este orden:

| # | Comprobación | Fallo ⇒ `reason` |
|---|---|---|
| 1 | Dimensiones `k × k` correctas | `dimensiones incorrectas` |
| 2 | Todos los elementos finitos | `elementos no finitos` |
| 3 | Simetría numérica | `asimetría por encima de la tolerancia` |
| 4 | Definida positiva, **vía Cholesky** | `no es definida positiva: no puede obtenerse una covarianza analítica fiable a partir de esta matriz` |
| 5 | Invertible | `no invertible` |
| 6 | `Σ_u` finita | `Sigma_u no finita` |
| 7 | Jacobiano delta válido | `jacobiano delta no válido` |
| 8 | `Σ_θ` finita | `Sigma_theta no finita` |
| 9 | `diag(Σ_θ)` estrictamente positiva | `diagonal no estrictamente positiva` |
| 10 | SE naturales finitos y > 0 | `SE no finitos o no positivos` |

Cualquier fallo produce **`valid = FALSE` con motivo auditable** y **ningún SE**.

### 5.0 Los motivos declaran lo que se comprueba, no lo que se sospecha

Un principio que conviene dejar escrito, porque es fácil violarlo sin darse
cuenta: **el `reason` no debe afirmar una causa que la comprobación no
establece.**

El caso concreto (corregido en ADR-034, clasificado como *PRODUCT DIAGNOSTIC COPY
DEFECT*): el fallo de Cholesky en el paso 4 se diagnosticaba como «θ̂ no es un
máximo local estricto de la verosimilitud». Eso es una **inferencia causal** que
el síntoma no sostiene. La misma matriz no definida positiva es compatible con
**identificación débil**, **curvatura prácticamente singular**, **aproximación
numérica insuficiente** o **mal condicionamiento** — situaciones en las que θ̂ sí
puede ser un máximo local. El mensaje correcto se limita a lo comprobado y a su
consecuencia operativa: no puede obtenerse una covarianza analítica fiable a
partir de esa matriz.

### 5.1 Prohibiciones explícitas

- **No** pseudoinversa silenciosa.
- **No** corrección de autovalores.
- **No** sustituir la matriz problemática por una aproximación «más bonita».
- **No** inventar un SE cuando la información observada no es válida.

### 5.2 Evaluaciones inválidas: criterio distinto al del optimizador

En una función **objetivo**, sustituir una evaluación no finita por `1e10` es
correcto: solo comunica «no vayas ahí». En una estimación de **derivada** sería
inadmisible: la penalización inventaría una curvatura enorme y produciría un SE
minúsculo con apariencia de validez.

**Regla:** si cualquier punto del estencil de diferencias no es finito, la entrada
es inválida y la matriz entera se rechaza con motivo. **Nunca se penaliza, nunca
se rellena.**

### 5.3 Coherencia con ADR-027

Si un ajuste MLE fue rechazado por una guarda de ADR-027 —óptimo en la frontera
numérica del espacio paramétrico, o log-verosimilitud implausible— **no puede
producir inferencia analítica válida**. La aproximación cuadrática presupone un
óptimo interior; en la frontera no existe.

---

## 6. Diagnóstico de condicionamiento — sin umbral inventado

Se calcula y se conserva `rcond(J_u)` y, si resulta informativo, los autovalores
extremos. **En B12 esto es un DIAGNÓSTICO CUANTITATIVO, no una regla de rechazo.**

**No** se establece `rcond < 1e-8 ⇒ invalid` ni ninguna variante. **No** se
publican etiquetas `High/Medium/Low`.

**Sí** son motivos objetivos de invalidación: no finita, no definida positiva,
singular o no invertible, covarianza inválida, SE inválidos. Son propiedades
estructurales, no umbrales.

**B15** comparará la inferencia analítica contra bootstrap y podrá aportar la
evidencia que justifique una política de condicionamiento. Antes de eso,
cualquier umbral sería arbitrario — es la lección de ADR-021.

---

## 7. Precisión: no existe «contraste exacto»

La Hessiana por diferencias finitas es una **aproximación**. Su error tiene dos
componentes que se oponen:

```
error ≈  C₁ · h² · |f⁗|        (truncamiento)
       + C₂ · ε · |f| / h²      (redondeo)
```

El mínimo está en `h ~ ε^(1/4)` para segundas derivadas, no en `ε^(1/2)` ni en
`ε^(1/3)`. Por tanto el vocabulario correcto es **referencia analítica, error
numérico, tolerancia, convergencia del esquema y estabilidad frente al paso** —
nunca «coincidencia exacta».

Fijar la tolerancia y la regla de paso **con evidencia** fue el objeto de B12.1.

### 7.1 Política numérica CONGELADA (B12.1)

```
h_j = ε^(1/4) · max(|u_j|, 1)          (config$hessian_step_c)

J_ii = [ f(u+hᵢeᵢ) − 2f(u) + f(u−hᵢeᵢ) ] / hᵢ²
J_ij = [ f(++) − f(+−) − f(−+) + f(−−) ] / (4 hᵢ hⱼ)
```

**Prohibido:** `optim(hessian=TRUE)` · `numDeriv` · Richardson · `ε^(1/3)` ·
pseudoinversa · recorte de autovalores · parche de simetrización · penalización
`1e10` dentro de la Hessiana · `suppressWarnings()` global.

Evidencia (R 4.4.1, 0 warnings): A da mediana de error relativo de Frobenius
**9,8e−08** y p90 **1,4e−06**, frente a **1,9e−05** / **6,2e−04** de `ε^(1/3)` al
mismo coste, y **2,6e−07** / **6,6e−06** de Richardson **al doble de coste**.
`ε^(1/4) = 1,22e−4` cae dentro de la meseta de las cinco familias con referencia.
Asimetría máxima observada = **0**, de modo que la simetrización es innecesaria y
añadirla ocultaría un fallo real si algún día dejara de serlo.

**Por qué Richardson empeora**, aunque cancele el término `O(h²)`: en
`h ≈ ε^(1/4)` el error ya está dominado por el **redondeo**, que la extrapolación
no cancela y **amplifica** al restar dos estimaciones muy próximas. Aplicarla
sobre un paso ya óptimo es contraproducente.

---

## 8. Intervalos de confianza — **OD-16, RESUELTA**

> **CONGELADA (B12.1 / ADR-034).** Se adopta la alternativa (a): **Wald marginal
> en escala transformada con retrotransformación monótona**, nivel configurable
> con defecto 95 %.
>
> ```
> CI_u_j = û_j ± z·SE_u_j        z = qnorm(1 − α/2),  α = 1 − nivel
> CI_θ_j = T_j⁻¹( CI_u_j )
> ```
>
> `identity` → Wald habitual, simétrico. `log` → intervalo estrictamente
> positivo, **asimétrico** en escala natural. `logit` → intervalo estrictamente
> dentro de (0,1). **No se usa `θ̂ ± z·SE_θ` para parámetros positivos o
> probabilidades, y NO se trunca a posteriori a 0 ni a 1.**
>
> Validación del nivel: numérico escalar finito y **estrictamente en (0,1)** —
> el dominio donde `qnorm(1−α/2)` está definido y es finito. No se inventa un
> mínimo arbitrario.

El razonamiento que llevó ahí se conserva a continuación.

**No se implementan IC en B12.1.** Se documenta el problema para B12.2.

`θ̂ ± z·SE` en escala natural **puede producir valores imposibles** para un
parámetro restringido: un `scale` con SE grande daría un extremo inferior
negativo, y un `prob` cercano a 1 daría un extremo superior mayor que 1. Un IC
que sale del espacio paramétrico no es conservador: es incorrecto.

Como ya se dispone de `Σ_u` en la escala transformada, hay una alternativa
coherente: **construir el intervalo en escala `u` y transformarlo de vuelta**,

```
IC_u = [ ûⱼ − z·sqrt(Σ_u[j,j]) ,  ûⱼ + z·sqrt(Σ_u[j,j]) ]
IC_θ = T⁻¹( IC_u )
```

que respeta el soporte por construcción, ya que `T⁻¹` es monótona. Tiene además
el argumento de que la normalidad asintótica suele ser mejor aproximación en la
escala transformada. A cambio, el intervalo es **asimétrico** en escala natural y
no está centrado en `θ̂`, lo que hay que explicar en la interfaz.

**OD-16 — RESUELTA: alternativa (a).** Las descartadas: (b) recorte al soporte
—un intervalo recortado ya no tiene la cobertura nominal y oculta el problema en
vez de resolverlo—; (c) sin recorte, declarando la limitación —publicaría
extremos imposibles—.

---

## 9. Relación con B13 y B15

- **B13 (bootstrap).** Vía independiente y complementaria. Cubre PM, que B12 no
  puede cubrir (§2.1), y no necesita normalidad asintótica.
- **B15 (comparación).** Contrastará SE analíticos contra bootstrap sobre los
  mismos ajustes. Es el bloque que puede aportar evidencia para una política de
  condicionamiento (§6) y para detectar mala especificación.

---

*Actuarial Tools by BMK — B12, contrato metodológico. Sin implementación productiva.*
