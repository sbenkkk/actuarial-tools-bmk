# Tool-02 — Percentile Matching (contrato de diseño)

| Campo | Valor |
|---|---|
| **Bloque** | B10 — diseño · **B11.1 — OD-1/2/3 resueltas por benchmark** |
| **ADR** | ADR-030 (diseño) · **ADR-031 (decisión)** |
| **Estado** | **Nada implementado.** Tool-02 permanece en v1.0.2 |
| **Depende de** | `docs/tool02_inference_contract.md` · `docs/tool02_pm_benchmark.md` |

> **Actualización B11.1 (2026-08-31).** Las tres decisiones abiertas de este documento
> —OD-1 (función objetivo), OD-2 (identificabilidad) y OD-3 (compatibilidad)— quedan
> **resueltas con evidencia** y registradas en **ADR-031**. El detalle experimental está
> en `docs/tool02_pm_benchmark.md`. Las secciones §4, §5 y §6 de este documento
> conservan su redacción original —planteaban las preguntas— y se cierran con las
> resoluciones de §9, añadida al final. **Un punto queda abierto y bloquea el cierre:
> el preset 25/50/75 entra en conflicto con la evidencia para Burr (§9.4).**

---

## 1. Por qué PM entra en v1.1

El material académico del proyecto (*Estimación de Parámetros*, UC3M, §2) enumera
**tres enfoques** de estimación puntual:

> *"Matching: Moments y Percentile. Frecuentistas: Maximum Likelihood. Bayesianos: Posterior Mean."*

Tool-02 v1.0.2 implementa MLE y MoM del primer grupo, **omite Percentile Matching**
y añade L-momentos, que no aparece en el material. La auditoría de trazabilidad
académica ya lo registró como el hueco más claro entre lo implementado y las fuentes
del proyecto.

Y hay una razón funcional, no solo de trazabilidad. El mismo documento explica el
papel de PM:

> *"el método de los momentos a veces no se puede calcular. Como los percentiles muestrales siempre existen, una alternativa de estimación es usar el método del Percentile Matching"*

> *"el método PM no se puede calcular para distribuciones discretas y siempre se puede para distribuciones continuas. Además, el método PM es más robusto a atípicos"*

Eso describe exactamente el hueco de v1.0.2. Con `continua_gamma.csv`, MoM descarta
Pareto (exige CV²>1) y L-momentos descarta **seis de siete** candidatas, dejando el
ranking con una sola fila. PM cubriría las siete continuas y sería, además, el método
robusto a atípicos que una severidad con cola pesada pide.

**Contexto que conviene no olvidar.** *Loss Models* —§10.4.1, incluido en el material
del proyecto— advierte que MoM y PM *"tend to give poor results"* frente a MLE. Eso no
invalida PM: define su papel. **PM es un método de contraste y una alternativa robusta,
no el estimador por defecto.** De ahí que no entre en AUTO.

---

## 2. Decisiones CONGELADAS

| # | Decisión |
|---|---|
| 1 | PM es método de **primera clase**, seleccionable por el usuario junto a MLE, MoM y L-momentos |
| 2 | **Solo distribuciones continuas.** Ver §6 |
| 3 | **NO entra en AUTO.** `.fit_auto` conserva exactamente su política actual: MLE-first con caída a MoM y luego L-momentos |
| 4 | Preset por defecto: **10 % / 50 % / 90 %** (P3w). **Sustituye a 25/50/75.** Ver §2.1 |
| 5 | El preset es un **punto de partida interpretable**, explícitamente **no** una combinación óptima universal. Debe declararse así en la interfaz |
| 6 | El usuario puede modificar **cuántos** percentiles usa y **cuáles**, con **mínimo 2** |
| 7 | La aplicación **valida** la configuración antes de estimar |
| 8 | La formulación admite **m percentiles para k parámetros**, incluido m > k |
| 9 | Normalización **`s_Q = max(q̂) − min(q̂)`**, congelada en B11.1-R4. Ver §10 |

### 2.1 Preset: los tres que se ofrecen — CONGELADO en B11.1-R4

| Etiqueta | Percentiles | Papel |
|---|---|---|
| **Recomendado** | **10 / 50 / 90** | **Default** |
| Ampliado | 10 / 25 / 50 / 75 / 90 | Alternativa disponible |
| Central / académico | 25 / 50 / 75 | Disponible, **no recomendado por defecto** |

**Justificación (texto exacto, no ampliable):**

> P3w = 10/50/90 ofrece el mejor compromiso general entre precisión típica,
> convergencia, simplicidad y robustez frente a errores extremos.
>
> P3w y P5 son **prácticamente equivalentes en muchas familias sencillas**. La
> ventaja de P3w está principalmente en la **robustez de cola** en Pareto y Burr.
> P5 permanece disponible como preset ampliado.

**Está prohibido escribir «P3w gana universalmente» o «P3w es siempre más
preciso».** El benchmark cross-family (22 DGP, 13.200 ajustes, R 4.4.1) lo
desmiente: P5 gana el caso típico más a menudo en Exponencial (58,4 %), Normal
(56,1 %), Weibull (50,8 %) y Burr (52,4 %).

**El cambio de default respecto de 25/50/75 está justificado por evidencia**, no
por preferencia. Las dos advertencias que motivaban la reserva sobre 25/50/75
—poca información de cola, y sistema exactamente determinado con `k = 3`— se
midieron y se confirmaron: en Burr, P3c produce **602** fallos catastróficos frente
a **135** de P3w. 25/50/75 se conserva como preset etiquetado, no como default.

---

## 3. Punto de integración

El despachador actual ya resuelve el problema sin tocar nada más:

```r
.estimate <- function(id, x, method) {
  reg <- switch(method, mle = DFIT_MLE, mom = DFIT_MOM, lmom = DFIT_LMOM, NULL)
  ...
}
```

B11 añade un cuarto registro `DFIT_PM` y una entrada `pm = DFIT_PM` en el `switch`.
Todo lo demás —`.fit_one`, guardas de ADR-027, Diagnostics, Assessment, ranking,
View Model, export— funciona sin modificación, porque PM devolverá la misma estructura
`list(params, logLik, converged, message)` y `.dist_loglik()` calculará la
verosimilitud sobre los parámetros de PM igual que hace hoy con MoM y L-momentos.

**Esa recomputación de `logLik` no es un detalle menor: es lo que mantiene AIC y BIC
comparables entre métodos.** El ranking sigue funcionando exactamente igual.

El registro también determina la disponibilidad: una distribución **ausente** de
`DFIT_PM` producirá el mensaje *"método 'pm' no disponible para 'X'"*, mecanismo ya
existente y ya probado en `b2_2_unit_tests.R`.

---

## 4. Formulación general — PENDIENTE (OD-1)

Forma general propuesta, con **todo lo discutible marcado como abierto**:

```
theta_PM  =  argmin_theta  J(theta)

J(theta)  =  SUM_{j=1..m}  w_j · d( q_hat_j , Q(p_j ; theta) )
```

donde `q_hat_j` es el cuantil empírico de orden `p_j`, `Q(·;θ)` la función cuantil
ajustada, `w_j` un peso y `d(·,·)` una discrepancia.

El material del proyecto la implementa así, con m = k, `w_j = 1` y error cuadrático
absoluto en espacio de cuantiles:

```r
dif <- function(param){
  r1 <- (qgamma(0.1, param[1], param[2]) - quantile(x, 0.1))^2
  r2 <- (qgamma(0.8, param[1], param[2]) - quantile(x, 0.8))^2
  return(r1 + r2)
}
PM <- optim(c(2,1), dif, method = "L-BFGS-B", lower = c(0,0))
```

Es un punto de partida legítimo, pero **no se congela**, y estas son las razones:

### OD-1 — Decisiones que B11 debe resolver con análisis y tests

| Cuestión | Alternativas | Por qué importa |
|---|---|---|
| **Espacio del error** | (a) cuantiles: `q̂ − Q(p;θ)`; (b) probabilidades: `p − F(q̂;θ)` | En severidad, el cuantil del 75 % puede valer 10³ y el del 25 % 10¹. En espacio de cuantiles el percentil alto **domina** la suma por pura magnitud. En espacio de probabilidades todos los términos están acotados en [0,1] |
| **Escala del error** | (a) absoluto; (b) relativo `(q̂−Q)/q̂`; (c) logarítmico `log q̂ − log Q` | Consecuencia directa de lo anterior. El error relativo o logarítmico hace la función objetivo **invariante de escala**, propiedad muy deseable con importes monetarios |
| **Forma de la discrepancia** | (a) cuadrática; (b) absoluta | La cuadrática es diferenciable y estándar; la absoluta es más robusta a un cuantil empírico ruidoso |
| **Pesos `w_j`** | (a) uniformes; (b) por varianza asintótica del cuantil muestral `p(1−p)/(n·f(q_p)²)`; (c) definidos por el usuario | (b) es la elección con fundamento —pondera cada percentil por su precisión— pero requiere estimar la densidad en el cuantil, lo que introduce su propia incertidumbre |
| **Política para m > k** | (a) mínimos cuadrados sobre el sistema sobredeterminado; (b) exigir m = k | (a) usa toda la información y es el caso general; (b) es lo que hace el material académico |
| **Optimizador y arranque** | Reutilizar `.mle_optim` (log-reparametrizado, L-BFGS-B) o uno propio | `.mle_optim` ya resuelve la reparametrización y trae las guardas de ADR-027. Reutilizarlo es lo coherente, pero su firma asume una **negative log-likelihood**; hay que decidir si se generaliza a "función objetivo" o se escribe un gemelo |
| **Definición del cuantil empírico** | `type` de `stats::quantile()` | R ofrece nueve. *Loss Models* usa una interpolación concreta. La elección cambia el resultado con `n` pequeño |
| **Tratamiento por distribución** | Genérico vs casos con solución cerrada | Exponencial y Lognormal admiten PM analítico con m = k. ¿Merece la pena el caso especial? |

**Mi recomendación técnica, no congelada:** error **relativo o logarítmico en espacio
de cuantiles**, cuadrático, pesos uniformes, mínimos cuadrados para m > k. Razón: hace
la función objetivo invariante de escala —crítico con importes— sin introducir la
estimación de densidad que exigen los pesos óptimos. **Debe validarse en B11 con
recuperación de parámetros sobre DGP sintéticos antes de fijarse.**

---

## 5. Validación de la configuración — PENDIENTE (OD-2)

**No se inventan reglas del tipo "mínimo k percentiles porque sí".** El contrato debe
distinguir situaciones que son conceptualmente distintas:

| Situación | Naturaleza | Tratamiento previsto |
|---|---|---|
| `p_j` fuera de (0,1) | **Inválido** | Rechazo con mensaje |
| `p_j` repetidos | **Degenerado** | Aporta cero información nueva: la restricción está duplicada |
| **m < k** | **No identificable** | Menos ecuaciones que incógnitas: el sistema tiene infinitas soluciones. Rechazo justificado matemáticamente, no por convención |
| **m = k** | Exactamente determinado | Válido; sin grados de libertad para detectar mal ajuste |
| **m > k** | Sobredeterminado | Válido; requiere la política de OD-1 |
| `p_j` muy juntos (p. ej. 0,50 y 0,51) | **Poco informativo** | Los cuantiles son casi el mismo dato. **Aviso, no rechazo** |
| `p_j` extremos con `n` pequeño | **Numéricamente frágil** | `quantile(x, 0.99)` con n=8 es casi el máximo muestral. **Aviso** |
| Óptimo en la frontera | **Fallo del optimizador** | Guarda A de ADR-027, ya existente |

La distinción **rechazo** / **aviso** es deliberada: solo se rechaza lo que es
matemáticamente imposible o degenerado. Lo meramente inconveniente se advierte y se
deja decidir al usuario.

`m < k` **no** es una convención: con menos restricciones que parámetros el problema
está genuinamente indeterminado. Esa es la única regla de cardinalidad que este
documento considera justificada, y aun así B11 debe confirmarla por distribución
—puede haber casos con restricciones adicionales de soporte que cambien el recuento—.

---

## 6. Compatibilidad por distribución — PENDIENTE (OD-3)

### 6.1 Discretas: excluidas

El material lo dice sin ambigüedad: *"el método PM no se puede calcular para
distribuciones discretas"*. La razón es que la función cuantil de una distribución
discreta es **escalonada**: `Q(p;θ)` es constante a trozos en θ, la función objetivo
resulta plana con discontinuidades, y no hay gradiente que seguir. Los optimizadores
basados en gradiente —`.mle_optim` usa L-BFGS-B— fallan o se quedan en el punto de
arranque.

**Decisión congelada:** PM **no** se habilita para Poisson, Binomial Negativa ni
Geométrica. La familia discreta conserva MLE y MoM.

### 6.2 Continuas: previsión, a confirmar en B11

| Distribución | k | Q(p;θ) | Previsión |
|---|---|---|---|
| Exponencial | 1 | `-log(1-p)/λ`, cerrada | Directo |
| Lognormal | 2 | `exp(μ + σ·z_p)`, cerrada | Directo |
| Loglogística | 2 | `α·(p/(1-p))^(1/β)`, cerrada | Directo |
| Pareto (Lomax) | 2 | `λ·((1-p)^(-1/α) − 1)`, cerrada | Directo |
| Burr XII | 3 | `λ·((1-p)^(-1/k) − 1)^(1/c)`, cerrada | Directo, pero m ≥ 3 y probable fragilidad numérica |
| Weibull | 2 | `λ·(-log(1-p))^(1/k)`, cerrada | Directo |
| Gamma | 2 | **Sin forma cerrada**: `qgamma()` es numérica | Funciona, pero cada evaluación de `J` invoca `qgamma` m veces. **Coste a medir** |
| Normal (control) | 2 | `qnorm()` | Aplicable; el control mantiene el método de las candidatas |

`.dist_quantile()` **ya implementa las ocho** y está verificado contra sus CDF. PM no
necesita ninguna función cuantil nueva.

**A confirmar en B11:** si la Gamma resulta demasiado lenta, y si Burr converge de
forma estable con m = 3 o exige m > 3.

---

## 7. Interacción con el resto del contrato

| Elemento | Efecto |
|---|---|
| **ADR-026** (muestra común) | PM se estima sobre `analysis$sample$x`, como todos los métodos. Sin excepción |
| **ADR-027** (guardas) | Se aplican íntegras. Un PM con parámetro subnormal se rechaza igual que un MLE |
| **AUTO** | **Sin cambios.** PM no participa |
| **Ranking** | Sin cambios: `logLik` se recalcula sobre los parámetros de PM, luego AIC y BIC siguen siendo comparables |
| **Bootstrap** (B13) | PM es uno de los cuatro estimadores que el motor genérico debe soportar. `estimation_config` guardará los percentiles usados, imprescindible para la reproducibilidad |
| **Incertidumbre analítica** | **No aplica.** PM obtiene su incertidumbre por bootstrap. No se inventan fórmulas analíticas genéricas |

---

## 8. Plan de tests de B11

Recuperación de parámetros sobre DGP sintéticos con `n` grande, por distribución
—si PM no recupera θ verdadero con n = 10.000, la formulación está mal—. Comparación
de la función objetivo entre las alternativas de OD-1, con criterio de decisión
**medido**, no elegido. Preset 25/50/75 frente a configuraciones personalizadas.
Percentiles inválidos, repetidos, m < k, m = k, m > k, muy juntos y extremos con `n`
pequeño. Invarianza de escala **si** la formulación elegida la garantiza —es la prueba
que discrimina entre error absoluto y relativo—. Fallo del optimizador y frontera.
Indisponibilidad correcta en la familia discreta. Y regresión: MLE, MoM, L-momentos y
el ranking **no cambian** al añadir PM.

---

*Actuarial Tools by BMK — B10. Contrato de diseño de Percentile Matching. Sin implementación.*


---

## 9. Resoluciones de B11.1 (ADR-031)

### 9.1 OD-1 — RESUELTA: Normalized Quantile SSE

> **Corrección de B11.1-R (2026-09-01).** La redacción original de esta sección
> presentaba `Bg` como una **quinta formulación que superaba a A**. Era incorrecto.

`s(x)` no depende de `theta`, luego

```
J_Bg(theta) = J_A(theta) / s(x)^2        =>        argmin J_Bg  ==  argmin J_A
```

**A y Bg son el MISMO estimador.** Verificado a precisión de máquina: el cociente
`J_A / J_Bg` reproduce `IQR^2` con desviación relativa de **2·10⁻¹⁶** en Lognormal,
Gamma y Burr. La formulación adoptada es, por tanto:

```
J_PM(theta) = (1 / s(x)^2) * SUM_j [ Q_theta(p_j) - q_emp(p_j) ]^2      w_j = 1
```

denominada **Normalized Quantile Sum of Squared Errors**. La normalización es
**numérica, no estadística**: hace el objetivo adimensional y lleva el gradiente a
escala O(1) —medido en Burr: `|grad J_A| / |grad J_Bg| = IQR² = 1,52·10⁵`—, lo que
importa porque la tolerancia de gradiente proyectado de `optim(method = "L-BFGS-B")`
es **absoluta**. Mismo estimador, mejor acondicionamiento.

**Una pista que estaba a la vista y se leyó mal.** A y Bg dieron `rel_RMSE`
**idénticos hasta la cuarta cifra** (0,0433 · 0,1070 · 0,1827). Esa coincidencia
exacta era la firma de la identidad algebraica, no un empate entre métodos.

Quedan eliminadas las **tres formulaciones genuinamente distintas**:

| Familia | Motivo de eliminación | Dato |
|---|---|---|
| **B** relativa local | Divide por un cuantil que puede anularse y **falla en silencio** | Normal estándar: RMSE de `mean` un **18 % peor**, sin declarar problema |
| **C** logarítmica | Aplicabilidad dependiente **del dato**, no de la familia | **300/300 fallos** con la Normal estándar; la misma Normal centrada en 100 funciona |
| **D** probabilidad | Objetivo acotado que **satura**: sin gradiente lejos del óptimo | Falla el test de arranques en **4 de 18** escenarios, incluidos casos no patológicos |

**A no queda eliminada como estimador**: es el estimador elegido. Lo que se descarta
es su implementación **sin normalizar**, por acondicionamiento numérico (335 celdas
con convergencia incompleta frente a 10).

**Pendiente de verificación en R.** `experiments/pm_r_verification.R` (T1) debe
confirmar que `theta_A ≈ theta_normalizado` con `optim()`. En Python coinciden con
desviación ≤ 6·10⁻⁴ salvo en Pareto (0,61) y Burr con m = 3 (0,92), donde **`J`
difiere en 3·10⁻⁵ y 2·10⁻³**: valle plano, no argmin distinto. Con Burr y m = 5 la
discrepancia baja a 10⁻⁴.

**Pesos: siguen abiertos.** El experimento usó `w_j = 1` por diseño y no permite
concluir nada sobre ponderación. No bloquea B11.2.

### 9.2 OD-2 — RESUELTA

`m < k` → **REJECT**. `m >= k` → *potentially identifiable*, sujeto a validación
efectiva. `p <= 0`, `p >= 1`, no finitos y duplicados → **REJECT**. Muy próximos o
extremos con muestra pequeña → **WARNING**, sin umbral congelado. Los 18 casos
deterministas se comportan como exige el contrato.

**La distinción entre identificable *en potencia* y *en efecto* no era teórica:**
Burr con 25/50/75 cumple `m = k = 3`, converge sin incidencias y aun así deja
`shape2` sin identificar. Es la prueba de que `m >= k` es necesaria y no suficiente.

### 9.3 OD-3 — RESUELTA

PM para las **7 continuas** y la **Normal de control**. **No** para las discretas.

- **Gamma se mantiene.** 2,32 ms por ajuste frente a 0,66 ms de Weibull: factor 3,5,
  cuestión de rendimiento y no de metodología, tal como advertía el encargo.
- **Burr se mantiene.** Su dificultad es de **configuración de percentiles**, no de
  familia: con 10/50/90 o con 10/25/50/75/90 se comporta correctamente.
- **La Normal fue decisiva.** Su inclusión como control es lo que reveló que la
  formulación logarítmica no es universalmente aplicable.

### 9.4 CONTRACT CONFLICT — el preset 25/50/75 con Burr

**Pendiente de decisión del owner. No modificado.**

Con `k = 3`, el preset produce `rel_RMSE` de **357 a 5.976** en `shape2` y de **24 a
127** en `scale`, con **las cinco** formulaciones. Con 10/50/90 —mismo `m = k = 3`—
el error de `shape2` baja a **0,33**.

La causa es la **estrechez** del conjunto: `shape2` gobierna el decaimiento de la
cola y tres cuantiles entre el 25 % y el 75 % no la informan; `shape2` y `scale` se
compensan y el objetivo queda casi plano.

Para las seis familias de `k <= 2` el preset es razonable (0,0360 frente a 0,0307 de
10/50/90). Corresponde al **caso B**: válido como ejemplo didáctico, con limitaciones
importantes. Las tres opciones y la recomendación están en
`docs/tool02_pm_benchmark.md` §10.1.

---

*Resoluciones de B11.1 — ADR-031. Sin implementación productiva.*


---

## 10. OD-13 — elección de `s(x)` y el caso IQR = 0

> **ESTADO: RESUELTA.** Esta sección conserva el análisis que llevó a la decisión.
> **La formulación vigente está en §11.** Donde §10.2 y §11 discrepen, **prevalece
> §11**.

**Naturaleza del problema: numérica, no estadística.** Cualquier `s(x) > 0`
independiente de `theta` define el **mismo estimador**. Lo único que se exige de
`s(x)` es que esté **garantizada positiva y finita** siempre que PM sea resoluble.

### 10.1 Evidencia

Cuatro muestras de 400 observaciones, ajuste Lognormal:

| Caso | IQR | sd | MAD | `q` distintos con 25/50/75 | con 10/25/50/75/90 |
|---|---:|---:|---:|:-:|:-:|
| A. degenerada (todo = 1000) | 0 | 0 | 0 | **1 de 3** | **1 de 5** |
| B. 60 % de la masa en un valor central | **0** | 1.943 | 0 | **1 de 3** | 3 de 5 |
| C. redondeo a múltiplos de 1000 | 1.000 | 7.145 | 1.000 | 2 de 3 | 4 de 5 |
| D. continua sin empates | 2.633 | 4.540 | 908 | 3 de 3 | 5 de 5 |

Y el comportamiento del ajuste:

| Caso | 25/50/75 | 10/25/50/75/90 |
|---|---|---|
| A | `optimizer_failure` | `optimizer_failure` |
| B | **`success` con `sdlog ≈ 0`** | `success`, estimación sana |
| C, D | `success` | `success` |

**El hallazgo es que `IQR = 0` no es el diagnóstico correcto.** En el caso B la
muestra **sí** tiene información (sd = 1.943, rango = 10.397), pero con 25/50/75
**los tres cuantiles objetivo colapsan en el mismo número**: PM queda indeterminado
y devuelve un parámetro en la frontera **declarando éxito**. Con 10/25/50/75/90,
sobre la misma muestra, los objetivos vuelven a ser distintos y la estimación es
correcta.

Es decir: `IQR = 0` no es ni necesario ni suficiente. Lo determinante es si los
**cuantiles objetivo** `q̂(p_j)` son distintos entre sí.

### 10.2 Propuesta (requiere aprobación)

**Diagnóstico —recomiendo congelarlo, la evidencia lo sostiene—.** Antes de estimar,
comprobar cuántos valores **distintos** hay entre los `q̂(p_j)`. Si son menos que
`k`, PM está indeterminado: **REJECT** con motivo explícito, con independencia del
valor de `IQR`. Esto cubre A y B, y distingue *muestra degenerada* de *conjunto de
percentiles inadecuado para esta muestra* —en B, el remedio no es rechazar la
muestra sino sugerir otros percentiles—.

**Normalizador — ABIERTO.** Tres opciones:

| Opción | Ventaja | Inconveniente |
|---|---|---|
| **(a) `s(x) = max(q̂) − min(q̂)`** (amplitud de los objetivos) | Positiva **exactamente** cuando el diagnóstico anterior pasa. Escala con la magnitud real de los residuos, que es lo que se quiere acondicionar | Indefinida con `m = 1` (exponencial con un solo percentil) |
| **(b) `s(x) = IQR(x)`, con cascada IQR → sd → MAD → fallo** | Familiar, robusta | La cascada es arbitraria; `IQR` puede ser cero con muestras informativas (caso B) |
| **(c) `s(x) = sd(x)`** | Nunca cero salvo degeneración total | No robusta a atípicos, justo lo que PM pretende evitar |

**Recomendación: (a).** Ata el normalizador a la condición que hace resoluble el
problema, en lugar de a una propiedad de la muestra que puede anularse con muestras
perfectamente informativas.

**Impacto:** ninguno sobre el estimador —el argmin no cambia—; solo sobre el
acondicionamiento y sobre qué casos se rechazan de forma explícita en vez de
devolver un parámetro degenerado.

---

## 11. OD-13 — ✅ CONGELADA (B11.1-R4)

**Verificada en R 4.4.1** (T6b de `pm_r_verification.R`). Se adopta la opción (a),
**sin el recurso a `IQR` que se proponía en §10.2**: se retiró por decisión del
owner —un segundo normalizador introduce una rama con semántica distinta para
salvar un caso que ya es legítimamente rechazable—.

**Formulación definitiva del estimador PM de la v1.1:**

```
s_Q(x, p) = max_j q̂(p_j) − min_j q̂(p_j)

J_PM(θ) = Σ_j [ Q_θ(p_j) − q̂(p_j) ]² / s_Q²        si s_Q es finita y s_Q > 0

θ̂_PM = argmin_θ J_PM(θ)
```

**Requisitos y política de rechazo:**

| Condición | Comportamiento |
|---|---|
| `s_Q` finita y `> 0` | Se estima |
| `s_Q = 0` | **REJECT** con diagnóstico explícito de **colapso de los cuantiles objetivo** |
| `m_requested < k` | **REJECT** |

**NO epsilon. NO recurso a `IQR`.** Mínimo de producto v1.1: **al menos 2
percentiles seleccionados**, también para Exponencial — con ello el caso `m = 1` no
se diseña y no requiere tratamiento especial.

**`m_effective` se conserva únicamente como DIAGNÓSTICO.** No se congela ninguna
regla de suficiencia de identificabilidad basada solo en `m_effective`, en ninguno
de los dos sentidos: percentiles distintos pueden compartir valor empírico por
empates o redondeo y aun así **corresponden a probabilidades distintas**, de modo
que la ecuación asociada no es redundante.

**Propiedades que sostienen la elección** (todas verificadas en R): independiente
de θ —luego conserva el argmin—; adimensional; escala-equivariante; **generaliza el
IQR**, ya que para 25/50/75 se cumple `s_Q = Q75 − Q25 = IQR` exactamente; y
resuelve el caso B de §10.1, donde `IQR = 0` pero los objetivos de P5 no colapsan y
el ajuste sí es informativo.

> **Corrección respecto de §10.2.** Aquella proponía además rechazar cuando el
> número de `q̂` distintos fuese menor que `k`. **Se retira**, por el argumento de
> empates anterior. La única regla de rechazo por identificabilidad es
> `m_requested < k`.

---

*B11.1 CERRADO — verificado en R 4.4.1. Sin implementación productiva.*
