# Tool-02 — Informe de diagnóstico

| Campo | Valor |
|---|---|
| **Incidencia** | AIC de Pareto/Lomax ≈ −1,15·10⁸ y ΔAIC ≈ −1,15·10⁸ con dataset real |
| **Fecha** | 2026-08-09 |
| **Estado** | **Diagnóstico. Sin corrección aplicada.** Ningún fichero de código, test, ADR ni documentación gobernada ha sido modificado |
| **Dataset** | `Motor vehicle insurance data_minus_10000_rows.csv`, variable `Cost_claims_year` |
| **Método de reproducción** | Réplica independiente del motor en Python/NumPy/SciPy (no puedo ejecutar R). Todos los valores publicados coinciden **al céntimo** con los de la interfaz, lo que valida la réplica |

---

## 1. Resumen ejecutivo

**Sí, existe un error matemático.** He encontrado **tres defectos distintos**, más una limitación de diseño y un problema de comunicación. No son el mismo problema con tres caras: tienen causas independientes y admiten correcciones independientes.

| # | Hallazgo | Clase |
|---|---|---|
| **H1** | La verosimilitud de Pareto/Lomax **no está acotada** cuando los datos tienen un átomo en cero. El motor no lo detecta y publica como "MLE" el valor donde el `double` se queda sin exponente | **BUG** |
| **H2** | El ranking compara AIC/BIC y estadísticos de bondad de ajuste calculados sobre **muestras distintas** (95.554 vs 17.678 observaciones). Esa comparación es inválida por definición | **BUG** |
| **H3** | El gráfico principal superpone un histograma **incondicional** (con los ceros) sobre curvas de densidad **condicionadas** a x > 0, sin el factor P(X>0). Las alturas no son comparables | **BUG** |
| **H4** | El ΔAIC sale negativo siempre que la recomendación por compuesto no coincide con la mejor por AIC. Es el diseño vigente de ADR-021, no un fallo de código | **LIMITACIÓN METODOLÓGICA** |
| **H5** | La interpretación anuncia "95.554 observaciones válidas" mientras 5 de las 7 candidatas usan 17.678. El aviso existe, pero como notificación flotante transitoria | **UX** |

**Lo que NO es un bug**, y lo demuestro numéricamente en §4 y §8: que Lognormal gane a Burr teniendo Burr mejor AIC; la reparametrización logarítmica del optimizador; la coherencia entre densidad, CDF y cuantil de la Lomax; la muestra usada por QQ y PP; y el aplastamiento del histograma contra cero.

**El valor de −114.873.666,02 que ves en pantalla es aritmética correcta sobre una entrada corrupta.** Lo reproduzco exactamente en §6.

---

## 2. Reproducción

### 2.1 El dataset

| Magnitud | Valor |
|---|---|
| Filas en el CSV | 95.554 |
| Observaciones válidas (no NA) | **95.554** (0 no parseables) |
| Valores = 0 | **77.876** (81,499 %) |
| Valores > 0 | **17.678** (18,501 %) |
| Valores < 0 | 0 |
| Máximo | 260.853,24 |
| Media (todas) | 150,374 |
| Media (positivas) | 812,811 |
| Mediana (positivas) | 287,18 |
| **Cociente n₀ / n₊** | **4,40525** ← reténlo: es la constante que gobierna H1 |

### 2.2 Muestra que usa cada distribución

Fijada por `DFIT_REQUIRES_POSITIVE` (`calc.R:244`) y aplicada en `.prepare_support()` (`calc.R:258`).

| Distribución | ¿Exige x > 0? | n usada |
|---|---|---|
| Gamma, Weibull, Lognormal, Loglogística, Burr | **Sí** | **17.678** |
| **Exponencial** | No (admite 0) | **95.554** |
| **Pareto (Lomax)** | No (admite 0) | **95.554** |
| Normal (control) | No | 95.554 |

### 2.3 Réplica numérica completa

Ajuste MLE replicando `.mle_optim()` (reparametrización logarítmica, L-BFGS-B, `maxit = 500`, penalización 1e10) y `.gof_continuous()` / `.information_criteria()`.

| Distribución | n | conv. | logLik | AIC | BIC | KS | CvM | AD |
|---|---:|:---:|---:|---:|---:|---:|---:|---:|
| exponential | 95.554 | ✔ | −574.578,40 | **1.149.158,79** | 1.149.168,26 | 0,8150 | 18.606,40 | 1.675.358,40 |
| gamma | 17.678 | ✔ | −134.554,89 | **269.113,79** | 269.129,35 | 0,1377 | 110,49 | 669,25 |
| weibull | 17.678 | ✔ | −133.198,74 | **266.401,48** | 266.417,04 | 0,1516 | 51,96 | 409,31 |
| **lognormal** | 17.678 | ✔ | −130.804,35 | **261.612,69** | 261.628,25 | 0,0761 | 32,70 | 225,60 |
| loglogistic | 17.678 | ✔ | −131.296,88 | **262.597,77** | 262.613,33 | 0,0908 | 36,59 | 252,70 |
| **pareto** | 95.554 | ✔ | **+57.306.028,66** | **−114.612.053,32** | −114.612.034,39 | 0,8150 | 17.443,86 | 1.748.514,14 |
| burr | 17.678 | ✔ | −129.919,50 | **259.845,00** | 259.868,34 | 0,1208 | 93,31 | 483,69 |
| normal (control) | 95.554 | ✔ | −831.595,17 | 1.663.194,33 | — | 0,4589 | 6.366,18 | 29.900,17 |

**Los siete AIC coinciden con los de tu pantalla hasta el céntimo**, incluido el −114.612.053,32 de Pareto. La réplica es fiel.

---

## 3. Pareto / Lomax — Auditoría 2

### 3.1 Recorrido completo

**Parametrización.** Lomax (Pareto tipo II) con soporte x ≥ 0:

$$f(x)=\frac{\alpha\lambda^{\alpha}}{(x+\lambda)^{\alpha+1}},\qquad F(x)=1-\Big(\tfrac{\lambda}{x+\lambda}\Big)^{\alpha},\qquad Q(p)=\lambda\big[(1-p)^{-1/\alpha}-1\big]$$

**Coherencia interna: correcta.** Verifiqué que $\frac{d}{dx}F(x)=f(x)$ y que $Q$ es la inversa exacta de $F$. Los tres evaluadores usan el mismo convenio (shape = α, scale = λ) sin cruzarlos:

- `.dpareto_log` (`calc.R:309`) → `log(shape) + shape*log(scale) - (shape+1)*log(x + scale)`
- `.dist_cdf` (`calc.R:642`) → `1 - (p$scale/(x + p$scale))^p$shape`
- `.dist_quantile` (`calc.R:1584`) → `p$scale * ((1-prob)^(-1/p$shape) - 1)`

**Punto 14 de tu lista descartado: no hay inconsistencia shape/scale.**

**Restricciones y transformación.** Ambos parámetros son estrictamente positivos. `.mle_optim` (`calc.R:284`) optimiza sobre θ = log(param) y evalúa `negloglik(exp(theta))`.

**Punto 6 de tu lista descartado: no falta ningún jacobiano, ni sobra.** El cambio es de *variable de optimización*, no de *variable aleatoria*. Se evalúa la verosimilitud original en exp(θ); el argmax es invariante bajo reparametrización biyectiva. Incluir un jacobiano aquí sería precisamente el error.

**Fórmula del AIC.** `.information_criteria` (`calc.R:666`) → `aic <- -2*loglik + 2*k`. Con k = 2 y logLik = +57.306.028,66:

$$\text{AIC} = -2(57{,}306{,}028{.}66) + 4 = -114{,}612{,}053{.}32 \;\checkmark$$

**Punto 10 descartado: logLik y AIC son perfectamente coherentes entre sí.** El problema está aguas arriba, en logLik.

### 3.2 Los parámetros estimados

```
shape (α) = 0.00720555
scale (λ) = 4.94e-324          <-- el menor subnormal representable en IEEE-754 doble
```

λ no es "pequeño": es **el suelo del sistema de punto flotante**. Ese es el hallazgo.

### 3.3 Demostración: la verosimilitud no está acotada

Sea n₀ el número de ceros y n₊ el de positivos. Desarrollando la log-verosimilitud y separando los ceros (para los que log(xᵢ+λ) = log λ):

$$\ell(\alpha,\lambda)=n\log\alpha+\underbrace{(\alpha n_+ - n_0)}_{\text{coeficiente}}\log\lambda-(\alpha+1)\!\!\sum_{x_i>0}\!\log(x_i+\lambda)$$

Cuando λ → 0⁺, log λ → −∞. Por tanto:

$$\boxed{\;\ell\to+\infty \iff \alpha n_+ - n_0 < 0 \iff \alpha < \frac{n_0}{n_+}=4{,}40525\;}$$

Con α̂ = 0,00720555 el coeficiente vale **−77.748,6**. La verosimilitud **diverge**. No existe MLE.

Comprobación numérica sobre este dataset, evaluando la fórmula analítica a α fijo:

| λ | logLik | AIC |
|---|---:|---:|
| 1e−3 | −36.091,49 | 72.186,97 |
| 1e−10 | 1.217.068,32 | −2.434.132,65 |
| 1e−100 | 17.329.121,59 | −34.658.239,18 |
| 1e−300 | 53.133.684,41 | −106.267.364,81 |
| **4,94e−324** | **57.306.028,66** | **−114.612.053,32** |

La última fila **es exactamente lo que devuelve el optimizador y exactamente lo que muestra la interfaz**. Queda probado que el número que ves no es un óptimo: es el último valor representable de una sucesión divergente.

### 3.4 Por qué el optimizador se detiene ahí y dice "convergió"

θ = log λ. Para θ < −745, `exp(θ)` desborda a 0, `log(0)` = −Inf, `.dpareto_log` produce `NaN`, la suma no es finita y `safe()` devuelve la penalización 1e10. Es decir, la función objetivo tiene un **acantilado vertical** en θ ≈ −744,44. L-BFGS-B se para justo en el borde, no encuentra dirección de descenso admisible y devuelve `convergence = 0`. `.mle_optim` traduce eso a `converged = TRUE`.

El guard existente —`if (... || fit$value >= 1e10) converged = FALSE`— solo protege contra la penalización *positiva*. **No hay ninguna comprobación por el lado negativo**, que es justo donde ocurre la divergencia.

### 3.5 Descartes explícitos de tu lista

| Pregunta | Respuesta |
|---|---|
| 8. ¿Signo de logLik? | Positivo (+57M). Legítimo en variables continuas, pero aquí es síntoma |
| 11. ¿Overflow/underflow? | **Underflow silencioso** en λ. No genera `Inf` ni `NaN` en el resultado final: produce un número finito y plausible en apariencia. Por eso pasa desapercibido |
| 12. ¿Densidad > 1? | f(0) = α/λ ≈ **1,4·10³²¹**. Una densidad puede superar 1 sin problema, pero 10³²¹ es la firma de una masa puntual degenerada |
| 13. ¿Densidad normalizada? | Sí, ∫f = 1 para todo (α, λ) > 0. El modelo es válido; lo que falla es que el **supremo** de la verosimilitud está en la frontera λ = 0, que no pertenece al espacio paramétrico |

### 3.6 Contraprueba

Ajustando la **misma Lomax** solo sobre las 17.678 observaciones positivas:

```
shape = 1.8130    scale = 657.99    logLik = -131,625.91    AIC = 263,255.82
```

Perfectamente sana y competitiva. **La degeneración la causan íntegramente los 77.876 ceros**, no la implementación de la Lomax. Sin átomo en cero (n₀ = 0) el coeficiente es α·n > 0 y ℓ → −∞ cuando λ → 0: la verosimilitud está acotada y el MLE existe.

### 3.7 Conclusión

**BUG confirmado, de omisión.** Las fórmulas de la Lomax son correctas. Lo que falta es la detección de una verosimilitud no acotada. Es un caso conocido en estimación paramétrica —el mismo fenómeno que hace explotar la verosimilitud de una mixtura de normales cuando una componente colapsa sobre una observación— y aquí lo dispara la mezcla frecuencia/severidad del dato real.

---

## 4. Pilar A y ranking — Auditoría 3

### 4.1 Qué métricas intervienen realmente

En `.assess()` (`calc.R:926-927`):

```r
a_metrics <- if (family == "continuous") c("ks", "cvm", "ad") else c("chisq")
b_metrics <- c("aic", "aicc", "bic")
```

**El pilar A (columna "Ajuste") NO contiene AIC.** Solo KS, CvM y AD. El AIC vive íntegramente en el pilar B ("Parsimonia"). Cada métrica se normaliza min-máx entre las convergentes con `.norm_lower_better` (100 = mejor, 0 = peor), se promedia por pilar, y se combina con 0,7 / 0,3.

### 4.2 Reconstrucción numérica

| Distribución | norm(KS) | norm(CvM) | norm(AD) | **A** | **B** | **0,7A+0,3B** | UI |
|---|---:|---:|---:|---:|---:|---:|---:|
| lognormal | 100,00 | 100,00 | 100,00 | **100,0** | 0,8 | **70,2** | 70,2 ✔ |
| loglogistic | 98,01 | 99,98 | 100,00 | **99,3** | 0,8 | **69,8** | 69,8 ✔ |
| burr | 93,94 | 99,67 | 99,99 | **97,9** | 0,8 | **68,7** | 68,7 ✔ |
| gamma | 91,66 | 99,58 | 99,97 | **97,1** | 0,8 | **68,2** | 68,2 ✔ |
| weibull | 89,78 | 99,90 | 99,99 | **96,6** | 0,8 | **67,8** | 67,8 ✔ |
| pareto | 0,00 | 6,26 | 0,00 | **2,1** | 100,0 | **31,5** | 31,5 ✔ |
| exponential | 0,00 | 0,00 | 4,18 | **1,4** | 0,0 | **1,0** | 1,0 ✔ |

Reconstrucción exacta de los siete valores. **El motor de decisión ejecuta lo que su especificación dice.**

### 4.3 Lognormal vs Burr

Burr tiene mejor AIC (259.845,00 < 261.612,69) pero peor "Ajuste" (97,9 < 100,0). **Es correcto por diseño**, y se ve en las métricas crudas:

| | KS ↓ | CvM ↓ | AD ↓ |
|---|---:|---:|---:|
| lognormal | **0,0761** | **32,70** | **225,60** |
| burr | 0,1208 | 93,31 | 483,69 |

Lognormal gana en las **tres** distancias de bondad de ajuste. Burr gana en verosimilitud, pero eso alimenta el pilar B, que pesa 0,3 y —crucialmente— **está anulado**: la Pareto degenerada fija el extremo de la escala min-máx en −114.612.053, de modo que todas las candidatas sanas quedan comprimidas en 0,76–0,77. La normalización las vuelve indistinguibles.

**Consecuencia: en esta ejecución el ranking es 100 % pilar A. El pilar B ha dejado de discriminar.** No es una peculiaridad estética: cambia el resultado.

### 4.4 Contrafactual — las 7 sobre la misma muestra (17.678 positivos)

| # | Distribución | Ajuste | Parsimonia | Score | AIC |
|---:|---|---:|---:|---:|---:|
| 1 | lognormal | 99,5 | 85,8 | **95,4** | 261.612,69 |
| 2 | loglogistic | 94,8 | 77,8 | 89,7 | 262.597,77 |
| 3 | **pareto** | 89,3 | 72,5 | **84,3** | 263.255,82 |
| 4 | burr | 76,2 | **100,0** | 83,3 | 259.845,00 |
| 5 | weibull | 74,7 | 47,2 | 66,4 | 266.401,48 |
| 6 | gamma | 66,2 | 25,3 | 53,9 | 269.113,79 |
| 7 | exponential | 0,0 | 0,0 | 0,0 | 272.260,81 |

Compárese con lo que muestra la aplicación: la parsimonia recupera su rango completo (0–100 en vez de 0–0,8), la Pareto pasa de un absurdo 6.º puesto con score 31,5 a un razonable **3.er puesto con 84,3**, y Burr sube de 68,7 a 83,3. El orden 1-2 no cambia, pero **el resto del ranking sí**, y las puntuaciones dejan de estar comprimidas.

### 4.5 Conclusión

El pilar A es **COMPORTAMIENTO CORRECTO**: reconstruido exactamente, y la aparente paradoja Lognormal/Burr está explicada y es la esperada por diseño.

El problema real que aflora aquí es **H2**: KS, CvM, AD, AIC, AICc y BIC de la Exponencial y la Pareto se calculan sobre 95.554 observaciones y se normalizan **junto a** los de las otras cinco, calculados sobre 17.678. Un estadístico KS sobre una muestra con 81,5 % de ceros comparado con uno sobre la severidad condicionada no mide lo mismo. La comparación de AIC exige, por definición, **datos idénticos**. Este defecto existiría aunque H1 no existiera; lo que hace H1 es volverlo catastrófico.

---

## 5. ΔAIC y confianza — Auditoría 4

### 5.1 Cómo se identifica "la siguiente candidata"

`calc.R:975-977`:

```r
aic_top   <- unname(aic[top$id])
aic_rest  <- aic[setdiff(conv_ids, top$id)]
delta_aic <- if (length(aic_rest) == 0L) NA_real_ else min(aic_rest) - aic_top
```

Tres precisiones sobre tus preguntas:

- **No** se ordena previamente por AIC ni se toma la 2.ª del ranking compuesto. Se toma el **mínimo AIC entre todas las demás convergentes**, sea cual sea su puesto.
- `top` sí procede del **ranking compuesto**.
- Por tanto se mezclan dos criterios: se recomienda por compuesto y se mide la confianza por AIC.

### 5.2 Reconstrucción

```
AIC(top = lognormal)         =        261.612,69
min(AIC del resto) = pareto  =   −114.612.053,32
ΔAIC = −114.612.053,32 − 261.612,69 = −114.873.666,01
```

La interfaz muestra **−114.873.666,02**. Diferencia de un céntimo por redondeo del AIC de Pareto. **Reproducción exacta.**

`confidence` = "baja" porque ΔAIC < 2. Correcto según los umbrales de `decision_engine.md` §4.

### 5.3 Interpretación del signo negativo

Un ΔAIC negativo significa, literalmente, *"la recomendada no es la mejor por AIC"*. Y eso **no lo provoca solo Pareto**. En el contrafactual con muestra común:

```
top = lognormal (261.612,69),  mejor AIC = burr (259.845,00)
ΔAIC = −1.767,70  ->  confianza "baja"
```

Sigue siendo negativo. Es **estructural**: siempre que el pilar A (peso 0,7) y el AIC señalen candidatas distintas —lo habitual con datos reales—, ΔAIC será negativo y la confianza colapsará a "baja".

### 5.4 Conclusión

Respondiendo a tus cuatro opciones:

- ¿Consecuencia lógica del diseño actual? **Sí.**
- ¿Bug de ordenación? **No.** El código hace exactamente lo que ADR-021 especifica.
- ¿Bug provocado por Pareto? **Solo la magnitud**, no el signo.
- ¿Defecto conceptual del criterio? **Sí**, y ADR-021 ya lo admitía en su propio texto: *"Si la recomendada no es la mejor por AIC, ΔAIC es negativo y la confianza cae a baja"*. Lo que no se anticipó es que ese caso sería el **normal**, no el excepcional.

Clasificación: **LIMITACIÓN METODOLÓGICA**, no BUG. La cifra absurda es un daño colateral de H1.

---

## 6. Visualización — Auditoría 5

### 6.1 Lo que es correcto

**QQ y PP: correctos.** `build_qq_pp_data` (`calc.R:1687`) reconstruye la muestra con `.prepare_support(x, DFIT_REQUIRES_POSITIVE[[target]])`, es decir, **la muestra que esa distribución usó realmente**. Para Lognormal son las 17.678 positivas. La desviación fuerte en la cola es información legítima: con máximo 260.853 y mediana 287, la Lognormal se queda corta en el extremo. **Eso es el gráfico haciendo su trabajo.**

**El aplastamiento contra cero es aritmética correcta.** `.histogram_data` usa la regla de Sturges: k = ⌈log₂(95.554)⌉ + 1 = **18 clases** sobre [0, 260.853], anchura 14.492.

| Clase | Rango | Frecuencia |
|---|---|---:|
| 0 | [0 – 14.492] | 95.488 (**99,93 %**) |
| 1 | [14.492 – 28.984] | 51 |
| 2 | [28.984 – 43.476] | 9 |
| 3–17 | resto | 6 |

Sturges está pensada para distribuciones aproximadamente simétricas; con asimetría extrema y n grande produce muy pocas clases y demasiado anchas. Cálculo correcto, lectura inútil.

### 6.2 Lo que NO es correcto — H3

Y esto sí es un defecto de cálculo, no de estética:

- `build_visual_data` (`calc.R:1737-1739`) construye el histograma y la KDE con **`x` completo**: `x <- data[[variable]]; x <- x[!is.na(x)]`. Son las 95.554 observaciones, ceros incluidos. El histograma integra a 1 sobre el soporte **incondicional**.
- `.fitted_curves` dibuja las densidades ajustadas de Lognormal, Gamma, Weibull, Loglogística y Burr, que integran a 1 sobre el soporte **condicionado a x > 0**.

Superponerlas sin más es comparar $\hat f(x\mid X>0)$ con $\hat f_{\text{emp}}(x)$. Para que fueran comparables, la curva ajustada tendría que ir multiplicada por P(X>0) = 0,185.

Medido sobre este dataset:

```
altura máxima curva Lognormal        = 5,551e−04
densidad del histograma en la clase 0 = 6,896e−05
ratio ≈ 8,05x        (el factor 1/P(X>0) = 5,405 explica la mayor parte;
                      el resto viene de promediar sobre una clase de 14.492 de ancho)
```

**La curva ajustada está sistemáticamente sobredimensionada respecto al histograma.** Un usuario que compare visualmente el ajuste está leyendo dos escalas distintas sin saberlo.

### 6.3 Clasificación

| Aspecto | Clase |
|---|---|
| QQ/PP sobre la muestra correcta | **COMPORTAMIENTO CORRECTO** |
| Desviación en la cola del QQ | **COMPORTAMIENTO CORRECTO** (información real) |
| Histograma aplastado por Sturges | **UX / limitación** — pide eje logarítmico, truncamiento por cuantil o zoom |
| **Histograma incondicional vs curvas condicionadas** | **BUG (H3)** |

---

## 7. Clasificación final

| ID | Hallazgo | Clasificación |
|---|---|---|
| **H1** | Verosimilitud no acotada de Lomax con átomo en cero; sin guarda; "MLE" espurio en el subnormal mínimo | **BUG** |
| **H2** | AIC / AICc / BIC / KS / CvM / AD comparados y normalizados entre muestras distintas (95.554 vs 17.678) | **BUG** |
| **H3** | Histograma y KDE incondicionales superpuestos a densidades condicionadas, sin factor P(X>0) | **BUG** |
| **H4** | ΔAIC estructuralmente negativo cuando el compuesto no coincide con el mejor AIC | **LIMITACIÓN METODOLÓGICA** |
| **H5** | "95.554 observaciones válidas" en la interpretación frente a 17.678 realmente usadas; aviso solo como toast transitorio | **UX** |
| H6 | Pilar A sin AIC → Lognormal vence a Burr | **COMPORTAMIENTO CORRECTO** |
| H7 | Reparametrización log sin jacobiano | **COMPORTAMIENTO CORRECTO** |
| H8 | Coherencia pdf / cdf / cuantil de Lomax | **COMPORTAMIENTO CORRECTO** |
| H9 | QQ/PP sobre la muestra efectiva de cada distribución | **COMPORTAMIENTO CORRECTO** |
| H10 | Histograma aplastado (Sturges + rango extremo) | **UX** |

### Nota actuarial sobre los ceros

`Cost_claims_year = 0` significa **póliza sin siniestro**, no siniestro de coste nulo. El dataset completo mezcla **frecuencia** (¿hubo siniestro?) y **severidad** (¿cuánto costó?). Modelizar severidad exige condicionar a X > 0, que es lo que hacen —por accidente de su soporte, no por decisión declarada— cinco de las siete candidatas.

Ese condicionamiento **no está declarado en ninguna parte**: es un efecto lateral de `DFIT_REQUIRES_POSITIVE`. La Exponencial y la Pareto, al admitir el cero, terminan modelizando una magnitud distinta (la pérdida agregada por póliza, con masa en 0) y compitiendo en el mismo ranking. **Ese es el origen conceptual común de H1 y H2.**

---

## 8. Ficheros y funciones implicados

| Fichero | Función | Líneas | Responsabilidad |
|---|---|---|---|
| `R/calc.R` | `DFIT_REQUIRES_POSITIVE` | 244–249 | Define qué distribuciones admiten 0. **Origen de H2** |
| `R/calc.R` | `.prepare_support()` | 258–271 | Recorta la muestra por distribución. Correcta en sí |
| `R/calc.R` | `.mle_optim()` | 284–299 | Optimizador. **Sede de H1**: guarda solo por el lado +1e10 |
| `R/calc.R` | `.dpareto_log()` | 309–312 | Log-densidad Lomax. **Correcta**; diverge en λ→0 con ceros |
| `R/calc.R` | `.mle_pareto()` | 363–368 | Arranque (shape 2, scale = media). No causa el problema |
| `R/calc.R` | `.fit_one()` | 568–606 | Registra `n_used` y `n_excluded`. No compara entre ajustes |
| `R/calc.R` | `.information_criteria()` | 666–675 | AIC/AICc/BIC. Fórmula correcta |
| `R/calc.R` | `.diagnostics()` | 787–811 | Coherente **dentro** de cada ajuste; no controla la comparabilidad **entre** ajustes |
| `R/calc.R` | `.norm_lower_better()` | 879–886 | Min-máx. **Amplificador de H1**: un valor absurdo aplana el resto |
| `R/calc.R` | `.assess()` | 905–1028 | Pilares, ranking, ΔAIC. **Sede de H2 y H4** |
| `R/calc.R` | `build_visual_data()` | 1725–1768 | Usa `x` completo para histograma y KDE. **Sede de H3** |
| `R/calc.R` | `.histogram_data()` | 1596–1607 | Sturges. Correcto; **H10** |
| `R/calc.R` | `build_qq_pp_data()` | 1687–1713 | Muestra correcta por distribución. **Sin defecto** |
| `R/calc.R` | `.build_warnings()` | 1239–1265 | Genera el aviso de exclusión de ceros. **H5** (canal transitorio) |
| `R/calc.R` | `.text_builders()` | 1280–1305 | Emite "N observaciones válidas" con `profile$n_valid`. **H5** |
| `decision_engine.md` | §4 | — | Umbrales ΔAIC. **H4** |

---

## 9. Propuesta de corrección mínima — SOLO PROPUESTA

Nada de lo siguiente está implementado.

### H1 — Verosimilitud no acotada

**Mínima (defensiva, ~6 líneas, sin tocar el criterio).** En `.mle_optim`, marcar `converged = FALSE` si el óptimo se alcanza en la frontera numérica del espacio paramétrico: si algún `exp(par)` cae por debajo de un umbral (p. ej. `.Machine$double.xmin`) o si la log-verosimilitud por observación supera una cota razonable. El ajuste pasaría a `excluded` con motivo *"verosimilitud no acotada: el óptimo está en la frontera del espacio paramétrico"*, y desaparecería del ranking en lugar de envenenarlo.

**Alternativa estructural (preferible actuarialmente, mayor alcance).** Declarar Tool-02 como herramienta de **severidad condicionada**: excluir los ceros para *todas* las candidatas, dejándolo explícito en la interfaz. Resuelve H1 y H2 de un golpe, pero es un cambio de contrato y exige ADR.

*Mi recomendación: la defensiva ahora para desbloquear la baseline; la estructural discutida como decisión de v1.1.*

### H2 — Comparación entre muestras distintas

**Mínima.** En `.assess`, antes de normalizar, verificar que todas las convergentes comparten `n_used`. Si no, agruparlas por `n_used` y rankear solo dentro del grupo mayoritario, marcando el resto como *"no comparable: ajustada sobre una muestra distinta (n = …)"*. No cambia ninguna fórmula: solo impide una comparación inválida.

### H3 — Escala del gráfico

**Mínima.** En `build_visual_data`, calcular el histograma y la KDE sobre la **misma muestra que usan las curvas dibujadas** (las positivas, si las candidatas del ranking son estrictamente positivas). Es un cambio de una línea en la selección de `x`, y es lo coherente con lo que ya hace `build_qq_pp_data`.

### H4 — Confianza

**No corregir ahora.** Requiere reabrir ADR-021 y probablemente esperar al pilar D. Documentar en el ADR de v1.1.

### H5 — Comunicación

**Mínima.** Renderizar el bloque `input_summary` del View Model —que **ya existe y no se muestra en ninguna parte**— con n, n_valid, % de ceros y % de negativos, más una línea que declare la muestra efectiva por familia de soporte. Cero cálculo nuevo: solo exponer lo ya calculado.

---

## 10. Tests de regresión propuestos

Si apruebas alguna corrección, estos son los tests que la blindarían. **No implementados.**

### Para H1

1. **`b2_pareto_atomo_cero`** — Muestra sintética con n₀/n₊ ≈ 4,4. Aserción: el ajuste Pareto **no** sale con `converged = TRUE` y `logLik > 0`. Si se aplica la corrección defensiva, debe aparecer en `excluded` con el motivo esperado.
2. **`b2_pareto_sin_ceros_ok`** — No regresión: sobre las 17.678 positivas, `shape ≈ 1,8130`, `scale ≈ 657,99`, `logLik ≈ −131.625,91` (tolerancia 1e−3 relativa). Garantiza que la guarda no rompe el caso sano.
3. **`b2_frontera_umbral`** — Test analítico del umbral: con α fijo, comprobar que el signo de `α·n₊ − n₀` predice la divergencia. Documenta la matemática dentro de la batería.

### Para H2

4. **`b4_muestras_heterogeneas`** — Dataset con ceros. Aserción: no se normaliza en el mismo grupo ninguna pareja de candidatas con `n_used` distinto.
5. **`b4_ranking_muestra_comun`** — Sobre las positivas, reproducir el contrafactual de §4.4: pilar B con rango completo (máximo 100, mínimo 0), no comprimido.

### Para H3

6. **`b7_histograma_misma_muestra`** — Aserción: `sum(histogram$density * ancho) ≈ 1` **y** `length(x)` del histograma = `n_used` de las candidatas dibujadas.
7. **`b7_escala_curva_vs_histograma`** — El máximo de la curva ajustada y el máximo de la KDE deben estar en el mismo orden de magnitud (ratio < 2, no 8).

### Para H5

8. **`b6_input_summary_expuesto`** — El View Model expone `input_summary` con `pct_zeros` correcto, y el smoke test comprueba que se renderiza.

### Regresión general

9. **`acceptance_dataset_real`** — Fichero reducido (~5.000 filas con la misma proporción de ceros) como caso permanente de la batería. **Este dataset ha encontrado tres defectos que 24 ficheros sintéticos no encontraron.** Merece quedarse.

---

*Actuarial Tools by BMK — Informe de diagnóstico. Sin código modificado.*
