# Tool-02 — Distribution Fitting · Especificación de Diseño (Sprint 0)

| Campo | Valor |
|---|---|
| **Proyecto** | Actuarial Tools by BMK |
| **Herramienta** | Tool-02 — Distribution Fitting |
| **Slug** | `distribution-fitting` |
| **Documento** | `tools/distribution-fitting/tool_02_distribution_fitting_design.md` |
| **Versión** | **1.0 (Sprint 0 — Aprobado)** |
| **Fecha** | Julio 2026 |
| **Estado** | **Approved — Sprint 0 congelado** (ADR-010) |
| **Depende de** | `docs/architecture_v2.md` (Approved, vigente) — prevalece ante cualquier conflicto |
| **Ámbito** | Diseño y arquitectura. Sin código, sin pseudocódigo, sin funciones R, sin pantallas |

**Objetivo del documento.** Diseñar Tool-02 por completo antes de escribir una sola línea de código. Este documento debe ser lo bastante sólido como para que, una vez aprobado y congelado, el desarrollo se realice sin necesidad de tomar ninguna decisión de arquitectura. Hereda íntegramente la arquitectura maestra vigente `architecture_v2.md` (capas, componentes `shared/`, identidad visual, reglas de proyecto, filosofía de coste y validez estadística, checklist de "Tool terminada") y solo especifica lo propio de Tool-02.

**Relación con Tool-01 (KDE).** Tool-01 queda congelada como versión 1.0 y su arquitectura por capas — **Motor → Diagnostics → Assessment → Text Builders → View Model → UI** — es el patrón obligatorio. Tool-02 lo replica sin excepción. La API pública replica la filosofía de `kde_analyze()`: un único punto de entrada que devuelve un objeto de resultado completo, del que se deriva el View Model que consume la UI.

---

## 0. Resumen para decisión (TL;DR)

Antes del detalle, las decisiones de diseño que requieren tu aprobación explícita para congelar:

1. **Alcance = ajuste general de distribuciones (continuas y discretas).** Tool-02 deja de ser solo una herramienta de severidad: soporta familia continua (Gamma, Weibull, Lognormal, Pareto, Exponencial, Burr) y familia discreta (Poisson, Binomial Negativa, Geométrica). Una **fase previa de diagnóstico del dataset** (§3.4, §10) enruta hacia la familia adecuada. Justificación en §3.3.
2. **Conjunto de distribuciones por familia** (§4). La GPD **sale del ranking**: pertenece a EVT (Tool-03) y solo se detecta y se sugiere, sin selección de umbral (§4.4, §7.6).
3. **Criterio de decisión en dos fases** (§7.2): la Fase 1 asigna a cada distribución una **evaluación absoluta** (Excelente / Buena / Aceptable / Pobre / Rechazada); la Fase 2 rankea **solo** las Aceptables o mejores. Así es coherente concluir que ninguna es suficientemente buena.
4. **Recomendación en dos niveles** (§7.7): Nivel 1 = mejor ajuste estadístico; Nivel 2 = adecuación por caso de uso (Pricing / Reserving / Capital) con valoración por estrellas. Se mantiene el nivel de confianza (§7.9).
5. **Criterio externalizado y versionado.** Pesos, umbrales, conflictos, desempates y reglas se llevan a un documento independiente `decision_engine.md` (§7.8). La arquitectura fija el *qué*; el motor de decisión fija el *cuánto*. Se versionan `schema_version` y `decision_engine_version` (§12.11).
6. **Modo AUTO por defecto**; MANUAL solo para usuarios avanzados (§5).

---

## 1. Objetivo funcional

Tool-02 es una herramienta **general de ajuste de distribuciones**: ajusta automáticamente distribuciones paramétricas —continuas o discretas— a una variable numérica y **recomienda cuál utilizar y por qué**, desde un punto de vista estadístico y actuarial.

La herramienta **no es una interfaz para `fitdistrplus`**. Su valor no está en ejecutar un ajuste — eso ya existe — sino en **decidir por el actuario**: qué distribuciones probar, con qué método estimarlas, cómo compararlas de forma coherente, cuál recomendar, con qué nivel de confianza, y para qué uso actuarial es adecuada. El motor de ajuste es una *commodity*; la capa de diagnóstico, criterio e interpretación es el producto.

Formulado como promesa al usuario: *"Sube tus datos, elige la columna, pulsa Calcular. Detecto si la variable es continua o discreta, ajusto las distribuciones adecuadas y te digo cuál usar, cómo de bien ajusta, cómo de estable es y para qué uso actuarial —pricing, reserving o capital— es más recomendable, sin que tengas que saber qué probar."*

---

## 2. Usuarios potenciales y casos de uso

**Usuarios.** Estudiantes de actuariales que aprenden ajuste de distribuciones; actuarios de pricing (severidad de siniestros y frecuencia de recuentos); actuarios de reserving (importes pagados / incurridos); actuarios de capital y Solvencia II (colas, VaR/TVaR); analistas de riesgos que necesitan una distribución paramétrica plausible —continua o discreta— antes de un Monte Carlo.

**Casos de uso.**

- Elegir la severidad para un modelo de coste agregado (frecuencia × severidad).
- Justificar, con criterio reproducible, la distribución elegida ante un revisor o auditor.
- Detectar rápidamente si los datos son *heavy-tailed* y si conviene combinar con Teoría de Valores Extremos (EVT).
- Comparar el ajuste en cola (cuantiles altos 95 / 99 / 99,5 %) frente al ajuste global.
- Docencia: mostrar por qué AIC no basta y cómo se compara realmente el ajuste.

---

## 3. Datos de entrada y variable a modelizar

### 3.1 Entrada

La herramienta acepta **CSV reales con múltiples columnas**, sin exigir un formato preparado. Se apoya en el `mod_data_input` compartido y en `bmk_validate_data()` (arquitectura maestra §7). Ejemplos de columnas presentes en un CSV real: `claim_id`, `paid_loss`, `incurred_loss`, `reserve`, `severity`, `frequency`, `exposure`, etc.

### 3.2 Selección de la variable a modelizar

El usuario elige **una única columna numérica** como "Variable a modelizar". La herramienta:

- Lista automáticamente solo las columnas numéricas del CSV como candidatas.
- Propone por defecto la primera columna numérica plausible (heurística: continua, positiva, con dispersión), de modo que el flujo funcione sin configuración.
- No obliga a renombrar columnas ni a preparar el CSV. El contrato de datos del proyecto (`docs/data_contract.md`) se respeta cuando aplica, pero la selección de variable es libre.

### 3.3 Naturaleza de la variable — alcance general (continua y discreta)

Tool-02 es una herramienta **general de ajuste de distribuciones** y soporta ambos tipos de variable:

- **Continuas y positivas** (severidad, importes, reservas): familia continua del §4.1.
- **Discretas de recuento** (frecuencia de siniestros, nº de reclamaciones): familia discreta del §4.2.

No se mezclan las dos familias en un mismo ranking: **no tiene sentido comparar el AIC de una Poisson con el de una Lognormal**, porque operan sobre soportes y verosimilitudes distintos. La herramienta ajusta y rankea **dentro de la familia** que corresponde a la variable. Qué familia aplica no lo decide el usuario a ciegas: lo determina la **fase previa de diagnóstico del dataset** (§3.4), que clasifica la variable como continua o discreta y lo comunica de forma transparente. En modo MANUAL el usuario avanzado puede forzar la familia.

Esto respeta el principio maestro de *"una aplicación resuelve un único problema"* (arquitectura §1.3): el problema es "ajustar la mejor distribución a esta variable", y la dualidad continua/discreta se resuelve por **enrutado interno**, no por dos modos que el usuario deba entender. La arquitectura por capas sigue siendo única; **no se duplica**.

### 3.4 Diagnóstico previo del dataset (fase de perfilado)

Antes de ajustar ninguna distribución, la herramienta ejecuta una **fase automática de clasificación del problema** (capa 0 en §10). Su objetivo **no** es tomar decisiones ni pre-juzgar el resultado, sino **caracterizar** los datos para (a) enrutar hacia la familia correcta, (b) enriquecer los insights y las recomendaciones posteriores y (c) advertir de situaciones que condicionan el ajuste. Analiza, como mínimo:

| Aspecto | Para qué sirve |
|---|---|
| Continua vs discreta | Enrutar hacia la familia del §4 |
| Presencia y proporción de ceros | Estrategia de ceros (§3.5); compatibilidad de soporte |
| Soporte observado (≥ 0, > 0, ℝ) | Descartar distribuciones incompatibles antes de ajustar |
| Tamaño muestral `n` | Activar/desactivar bootstrap y validación cruzada; modular la confianza |
| Asimetría y curtosis | Anticipar familias plausibles; contexto del insight |
| Evidencia de cola pesada | Disparar el insight de EVT / Tool-03 (§7.6) |
| Posible multimodalidad | Advertir de que ninguna paramétrica unimodal ajustará; sugerir KDE (Tool-01) |

El resultado del perfilado es **descriptivo** y viaja al View Model (`dataset_diagnosis`, §12.2) para alimentar interpretación e insights. Ninguna de estas señales sustituye al ajuste: la recomendación final siempre se basa en distribuciones efectivamente ajustadas y evaluadas.

### 3.5 Tratamiento de ceros y valores no admisibles

Los ceros **nunca se eliminan en silencio**. El perfilado (§3.4) los detecta y cuantifica explícitamente, y la estrategia es consistente:

- **Se reporta siempre** el número y la proporción de ceros (y de negativos y `NA`) en `input_summary` y en la interpretación.
- **Compatibilidad de soporte por distribución.** Una distribución cuyo soporte incluye el cero (la mayoría de las discretas: Poisson, Binomial Negativa, Geométrica; entre las continuas, según parametrización) se ajusta sobre el dato completo. Una distribución estrictamente positiva (Lognormal, Pareto, ciertas parametrizaciones de Gamma/Weibull) **no puede** incluir ceros.
- **Para las estrictamente positivas**, en v1 los ceros se **excluyen de forma explícita y cuantificada** (nunca silenciosa): el View Model registra cuántos se excluyeron y la interpretación lo declara. Si la proporción de ceros es material, se emite el insight *"los datos presentan una masa apreciable en cero; considera un modelo con inflación de ceros (zero-inflated) o una mixtura cuerpo-cero"*, que queda como candidato de v2.
- **Negativos:** incompatibles con todas las distribuciones soportadas; se reportan y excluyen con aviso, y se advierte de que la variable podría no ser una severidad ni un recuento.

Censura y truncamiento quedan fuera de v1 (limitación conocida en el README; candidato de v2).

---

## 4. Distribuciones soportadas (v1)

El conjunto se organiza en **dos familias** según el tipo de variable detectado en el diagnóstico previo (§3.4). Cada familia se ajusta y rankea por separado; **nunca se comparan entre sí** (soportes y verosimilitudes distintos).

### 4.1 Familia continua (variable continua positiva)

Cubre de forma escalonada el espectro de peso de cola, que es la dimensión que de verdad importa en seguros.

| # | Distribución | Parámetros | Peso de cola | Por qué está (justificación actuarial) |
|---|---|---|---|---|
| 1 | **Exponencial** | 1 (tasa) | Ligera | Referencia mínima y benchmark. Un solo parámetro, sin memoria. Ancla la comparación de parsimonia |
| 2 | **Gamma** | 2 (forma, escala) | Ligera-media | Caballo de batalla para severidades moderadas; flexible en asimetría; base de modelos colectivos y GLM de coste |
| 3 | **Weibull** | 2 (forma, escala) | Ligera-media (flexible) | Hazard creciente o decreciente según la forma; captura formas que la Gamma no |
| 4 | **Lognormal** | 2 (μ, σ log) | Media | Estándar de facto en severidad; asimetría positiva natural; interpretación directa en escala logarítmica |
| 5 | **Loglogística (Fisk)** | 2 (forma, escala) | Media-pesada | Cuantiles en forma cerrada (cómodo para VaR); cola más pesada que la Lognormal |
| 6 | **Pareto (Lomax / tipo II)** | 2 (forma, escala) | Pesada | La distribución de cola pesada por excelencia en seguros y reaseguro; capta *large losses* |
| 7 | **Burr (tipo XII)** | 3 (2 forma, 1 escala) | Pesada (muy flexible) | Generaliza Loglogística y Pareto; ajusta cuerpo y cola por separado cuando ninguna de 2 parámetros basta |

### 4.2 Familia discreta (variable de recuento)

| # | Distribución | Parámetros | Sobredispersión | Por qué está |
|---|---|---|---|---|
| 1 | **Poisson** | 1 (λ) | No (media = varianza) | Modelo base de frecuencia; referencia y ancla de parsimonia |
| 2 | **Binomial Negativa** | 2 (tamaño, prob.) | Sí | Frecuencia con sobredispersión (varianza > media), lo habitual en siniestralidad real |
| 3 | **Geométrica** | 1 (prob.) | Sí (caso particular) | Recuentos muy concentrados en valores bajos; caso límite de la Binomial Negativa |

*Ampliable en v2 (familia discreta):* Binomial, Poisson inflada de ceros (ZIP), Binomial Negativa inflada de ceros.

### 4.3 La Normal como control (solo continua)

No se recomienda (una severidad no es Gaussiana), pero se usa internamente como **prueba de control**: si la Normal "gana" a las demás continuas, es señal de que la variable podría no ser una severidad clásica (p. ej. ya está transformada), y la interpretación lo advierte. No ocupa puesto en el ranking de recomendación.

### 4.4 La GPD queda fuera del ranking (pertenece a EVT / Tool-03)

La Generalized Pareto **no compite** en el ranking. Modela *excesos sobre umbral*, no el soporte completo: su verosimilitud no es comparable con la de las distribuciones de cuerpo completo, y ajustarla exige seleccionar un umbral —un problema propio de EVT—. En su lugar, Tool-02 **detecta evidencia de cola pesada** (§7.6) y, cuando la hay, emite el insight: *"Los datos presentan evidencia de comportamiento extremo. Se recomienda un análisis específico mediante Extreme Value Theory (Tool-03)."* Tool-02 **no** implementa selección automática de umbral ni ajuste de GPD.

**Ampliación futura (no v1):** Inverse Gaussian, Gamma Generalizada (GB2), *splicing* cuerpo-cola (mixtura Lognormal-Pareto) y distribuciones discretas adicionales (§4.2).

---

## 5. Métodos de estimación

Dos modos, coherentes con la filosofía de minimizar decisiones del usuario.

### 5.1 Modo AUTO (recomendado, por defecto)

La herramienta selecciona automáticamente el método de estimación más adecuado **por distribución** y **por dataset**, y **explica por qué**. Criterios que pondera:

- **Tamaño muestral.** Con `n` pequeño, MLE puede ser inestable; métodos robustos o de momentos ganan peso.
- **Convergencia.** Si el optimizador de MLE no converge o el Hessiano no es definido positivo (errores estándar no fiables), se degrada a un método alternativo.
- **Estabilidad del ajuste.** Sensibilidad de los parámetros a remuestreo (bootstrap): si MLE produce parámetros muy volátiles, se prefiere un método más estable.
- **Comportamiento observado de los datos.** Indicios de cola muy pesada (p. ej. función de exceso medio creciente) favorecen métodos que estiman bien la cola (L-momentos / PWM para Pareto y Burr en la familia continua).
- **Robustez del método** frente a outliers e influencia de las observaciones extremas.

La decisión de método se registra y se muestra al usuario en la interpretación ("Para la Pareto se ha usado L-momentos en lugar de MLE porque el tamaño muestral es pequeño y MLE resultó inestable"). Nunca es una caja negra.

### 5.2 Modo MANUAL (usuarios avanzados)

Permite fijar el método. Métodos soportados en v1:

| Método | Rol | Cuándo brilla |
|---|---|---|
| **Máxima Verosimilitud (MLE)** | Método principal por defecto | Muestras suficientes, buena convergencia; eficiencia estadística; base para IC de parámetros |
| **Momentos (MoM)** | Alternativa simple y como valor inicial | Muestras pequeñas, arranque del optimizador, distribuciones con momentos cerrados |
| **L-momentos / PWM** | Alternativa robusta para cola | Cola pesada, presencia de extremos, Pareto/Burr; más estable que MLE con pocos datos |

MLE se implementa vía optimización numérica (coherente con la política maestra §2.2 de implementar la lógica estadística manualmente sobre `optim()`). MoM y L-momentos comparten infraestructura de estimación por distribución. Máxima Bondad de Ajuste (MGE/MDE) queda fuera de v1 por complejidad frente a valor marginal; backlog.

Para la **familia discreta** se emplean **MLE y MoM** (L-momentos no aplica a recuentos); la Binomial Negativa usa MLE con MoM como valor inicial. La selección AUTO de método opera igual en ambas familias.

---

## 6. Validación — conjunto de métricas

No basta con AIC / BIC / KS. Se define un conjunto coherente organizado en **cinco pilares**, cada uno con un propósito distinto. La capa Diagnostics computa todas las métricas; la capa Assessment las combina según el criterio de decisión (§7).

### Pilar A — Bondad de ajuste (global)

- **Kolmogorov-Smirnov (KS):** distancia máxima entre CDF empírica y ajustada. Sensible al centro, poco a la cola.
- **Cramér-von Mises (CvM):** distancia cuadrática integrada; usa toda la distribución.
- **Anderson-Darling (AD):** como CvM pero **pondera la cola**; es la métrica de bondad de ajuste más relevante para seguros. Se computa el estadístico y, donde sea defendible, su p-valor por simulación.

### Pilar B — Criterios de información (parsimonia)

- **AIC** y **AICc** (corregido para muestra pequeña — importante con `n` bajo).
- **BIC** (penaliza más la complejidad; útil para no premiar a Burr por tener más parámetros).

### Pilar C — Comportamiento en cola (el pilar diferencial actuarial)

- **AD ponderada a cola superior:** variante de AD que solo pesa el 5–10 % superior.
- **Error en cuantiles altos:** comparación de VaR ajustado vs empírico en 95 / 99 / 99,5 %.
- **Error en TVaR / cola esperada** en esos niveles (relevante para capital y Solvencia II).
- **Desviación en QQ-plot de cola:** magnitud del alejamiento de los puntos extremos respecto a la diagonal.
- **Función de exceso medio (mean excess):** comparación de la forma empírica vs teórica; diagnostica sobre/infra-estimación de la cola.

### Pilar D — Estabilidad y fiabilidad del ajuste

- **Estabilidad de parámetros por bootstrap:** coeficiente de variación de cada parámetro sobre remuestreos. Alta variabilidad = ajuste poco fiable aunque el AIC sea bueno.
- **Convergencia del optimizador:** código de convergencia y definición positiva del Hessiano (errores estándar bien definidos).
- **Amplitud de los intervalos de confianza** de los parámetros.

### Pilar E — Capacidad predictiva (cuando `n` lo permite)

- **Validación cruzada k-fold / holdout:** log-verosimilitud fuera de muestra. Mide si el ajuste generaliza o sobreajusta. Se activa solo con tamaño muestral suficiente; con `n` pequeño se desactiva y se comunica.

### Adaptación por familia (continua vs discreta)

En la **familia discreta**, la bondad de ajuste del Pilar A se evalúa con el **test chi-cuadrado sobre frecuencias observadas vs esperadas** (y comparación de la función de probabilidad), no con KS/AD, que asumen soporte continuo. El Pilar C (cola) se sustituye por el **análisis de sobredispersión** (relación varianza/media) y el ajuste en la cola de recuentos altos. Los Pilares B, D y E se mantienen.

### Criterios actuariales transversales (diagnóstico, no filtro de descarte)

- **Índice de cola.** Se estima el índice de cola empírico (p. ej. vía función de exceso medio o estimadores de cola) como **señal de diagnóstico**, no como criterio de descarte. Sirve para (a) disparar el insight de EVT (§7.6) y (b) contextualizar la interpretación. **No** se descarta ninguna distribución por implicar momentos teóricos infinitos: una cola genuinamente pesada puede tener varianza —o media— infinita, y la varianza muestral siempre es finita, de modo que usarla como prueba en contra sesgaría el criterio justo contra el modelo heavy-tail correcto (ver §7.4).
- **Coherencia de cuantiles extremos.** El error del VaR/TVaR ajustado frente a la evidencia empírica en cuantiles altos alimenta el Pilar C (fidelidad de cola) como métrica **continua**, nunca como veto binario. Un desajuste severo degrada la evaluación absoluta de esa distribución (§7.2), pero la decisión la toma el criterio de dos fases, no una regla aislada.

### Principio de validez estadística (congelado)

La arquitectura exige que los procedimientos utilizados para calcular p-valores o evaluar la significación estadística sean **válidos para distribuciones con parámetros estimados** cuando corresponda —por ejemplo, calibración por bootstrap paramétrico o simulación, en lugar de valores críticos tabulados que asumen parámetros conocidos, como ocurriría al aplicar KS o Cramér-von Mises sobre parámetros ajustados con la misma muestra—. La **elección concreta del procedimiento pertenece al motor matemático** (capas Motor y Diagnostics), **no al criterio de decisión** (§7) ni al View Model (§12). Este requisito queda **congelado**; su implementación se decide en desarrollo. La calibración por simulación es intensiva en cómputo y es precisamente uno de los análisis que justifican tiempos de ejecución mayores y que se gradúan mediante los perfiles de profundidad (§14.2).

---

## 7. Criterio de decisión (obligatorio — se congela antes del desarrollo)

Define **cómo decide la herramienta**. Es filosofía y criterio, no fórmulas. Los **valores concretos** (pesos, umbrales, orden de desempate, reglas) **no viven aquí**: residen en `decision_engine.md` (§7.8). Esta separación permite recalibrar el criterio sin tocar la arquitectura.

### 7.1 Qué significa "mejor distribución"

La mejor distribución **no es la de menor AIC**. Es la que, **dentro de su familia** (§4) y **superando primero un umbral absoluto de calidad**, ofrece el mejor equilibrio entre ajuste global (Pilar A), fidelidad de cola / recuentos altos (Pilar C), estabilidad y fiabilidad (Pilar D) y parsimonia (Pilar B).

### 7.2 Criterio en dos fases

El criterio se estructura en dos fases sucesivas. Esto resuelve la tensión entre evaluar en absoluto (para poder decir "ninguna es buena") y comparar en relativo (para rankear): **primero se evalúa en absoluto, después se rankea solo lo que ha pasado el corte.**

**Fase 1 — Evaluación absoluta (por distribución, independiente de las demás).**
Cada distribución ajustada recibe una **categoría absoluta** a partir de umbrales fijos sobre sus métricas (bondad de ajuste, cola, estabilidad, convergencia). La categoría **no depende** de qué otras distribuciones se hayan probado:

| Categoría | Significado |
|---|---|
| **Excelente** | Ajuste muy bueno en todos los pilares relevantes; apta sin reservas |
| **Buena** | Ajuste sólido con debilidades menores |
| **Aceptable** | Ajuste suficiente; usable con cautela |
| **Pobre** | Ajuste deficiente; no apta para recomendación |
| **Rechazada** | Incumple mínimos de admisibilidad (§7.4); queda fuera |

**Fase 2 — Ranking comparativo (solo entre admisibles).**
Únicamente las distribuciones **Aceptable o superior** compiten. Entre ellas se calcula el ranking por score compuesto (pesos en `decision_engine.md`) y se elige el Nivel 1 de la recomendación (§7.7). Las categorías Pobre y Rechazada **no participan** en la recomendación, pero se muestran en la tabla con su categoría y motivo.

Consecuencia clave: si **ninguna** distribución alcanza al menos "Aceptable", la Fase 2 queda vacía y la herramienta concluye de forma coherente que **ninguna distribución es suficientemente buena** (§7.6). Al basarse el corte en umbrales absolutos y no en una escala relativa, esta conclusión es lógicamente consistente.

### 7.3 Cómo se combinan las métricas en la Fase 2

Entre las admisibles, el score es una **media ponderada de los pilares**; las ponderaciones **no son iguales** (cola y estabilidad pesan más que un AIC marginalmente mejor). Los pesos exactos están en `decision_engine.md`. La ponderación **no** cambia la recomendación de uso: la adecuación por caso de uso se calcula aparte (§7.7, Nivel 2), lo que **elimina la necesidad del antiguo "perfil de ponderación"** elegido por el usuario y su ambigüedad.

### 7.4 Mínimos de admisibilidad (cuándo una distribución es "Rechazada")

Con independencia del AIC, una distribución es **Rechazada** si:

- **No convergió** o el Hessiano no es definido positivo (errores estándar no fiables).
- **Parámetros inestables:** coeficiente de variación por bootstrap por encima del umbral (en `decision_engine.md`).
- **Falla dura de bondad de ajuste:** estadístico de GoF peor que el mínimo admisible (rechazo claro del ajuste).
- **Soporte incompatible:** ajustada sobre datos fuera de su dominio (valores ≤ 0 en una estrictamente positiva; no enteros en una discreta).

**Ya no se rechaza** una distribución por implicar momentos teóricos infinitos (ver §6, criterios transversales): esa señal es diagnóstica, no descalificadora. Esto evita penalizar sistemáticamente el modelo *heavy-tail* correcto.

### 7.5 Resolución de empates (Fase 2)

Cuando dos admisibles quedan a distancia despreciable en score, el orden de desempate es fijo y vive en `decision_engine.md`. Filosofía del orden: **parsimonia → estabilidad → fidelidad de cola → preferencia por la distribución más estándar y defendible ante un revisor.** El desempate aplicado se hace explícito en la interpretación.

### 7.6 Detección de cola pesada y derivación a EVT (Tool-03)

Tool-02 **no** ajusta GPD ni selecciona umbral (§4.4). En su lugar, a partir del diagnóstico (§3.4) y del Pilar C, evalúa **evidencia de comportamiento extremo** (índice de cola, forma de la función de exceso medio, desajuste sistemático de la cola por parte de la mejor candidata). Si la evidencia supera el umbral (en `decision_engine.md`), emite el insight:

> *"Los datos presentan evidencia de comportamiento extremo. Se recomienda un análisis específico mediante Extreme Value Theory (Tool-03)."*

Este insight es **independiente** de la recomendación: puede acompañar incluso a un buen ajuste, señalando que la cola merece análisis dedicado. Es también parte de la conclusión "ninguna suficientemente buena" cuando el fallo se concentra en la cola.

### 7.7 Recomendación en dos niveles

La salida ya **no** es una única recomendación. Tiene dos niveles complementarios:

**Nivel 1 — Mejor ajuste estadístico.** La distribución ganadora de la Fase 2, con sus parámetros, método, categoría absoluta y **nivel de confianza** (§7.9). Responde a "¿cuál describe mejor estos datos?".

**Nivel 2 — Adecuación por caso de uso.** Para las distribuciones admisibles se calcula una **valoración por estrellas** en cada uso actuarial, porque la mejor estadísticamente no siempre es la más adecuada para un fin concreto:

| Distribución | Pricing | Reserving | Capital |
|---|---|---|---|
| *(ejemplo)* Lognormal | ★★★★★ | ★★★★★ | ★★★★☆ |
| *(ejemplo)* Pareto | ★★★☆☆ | ★★★☆☆ | ★★★★★ |

La valoración por uso deriva de qué pilares importan a cada fin (Capital ← fidelidad de cola + estabilidad; Pricing ← ajuste central + parsimonia; Reserving ← ajuste global + coherencia de cuantiles). El mapa uso → pilares vive en `decision_engine.md`. Así, una distribución puede ser el mejor ajuste global y, a la vez, no ser la más recomendable para capital.

### 7.8 Separación de responsabilidades: `decision_engine.md`

Toda la **parametrización del criterio** se externaliza a un documento independiente, `decision_engine.md`, que contiene **exclusivamente**: pesos por pilar, umbrales de las categorías absolutas y de admisibilidad, umbral de detección de EVT, reglas de conflicto entre insights, orden de desempate y el mapa uso → pilares del Nivel 2. Se **versiona** (`decision_engine_version`, §12.11).

Motivo: el criterio actuarial es la parte que se recalibra con la experiencia; aislarlo permite ajustarlo y auditarlo **sin reabrir la arquitectura**, y garantiza que toda recomendación sea reproducible sabiendo con qué versión del motor se generó. La arquitectura fija el *qué*; `decision_engine.md` fija el *cuánto*. El Assessment lee estos valores como configuración; nunca se codifican en `calc.R` (regla maestra 8: sin números mágicos). *En este Sprint solo se define la separación; el contenido calibrado se aborda en un paso posterior, contra datasets de distribución conocida.*

### 7.9 Nivel de confianza de la recomendación

El Nivel 1 lleva siempre un **nivel de confianza — Alta / Media / Baja**, derivado de forma determinista de: la **categoría absoluta** de la ganadora (una "Excelente" da más confianza que una "Aceptable"), la **separación** frente a la segunda admisible, y la **estabilidad** del ajuste (Pilar D). Al basarse la separación en un score que solo se calcula entre admisibles ya cualificadas en absoluto, el indicador es estable y no arbitrario. Se muestra siempre con una frase que lo justifica ("Confianza Media: la Lognormal es 'Buena' y gana, pero la Gamma queda muy cerca y la cola está ajustada al límite").

---

## 8. Ranking automático

El ranking es la traducción visible del criterio de dos fases (§7.2), **no** una ordenación por AIC.

**Principios:**

- Se rankea **solo dentro de la familia** detectada (§4) y **solo entre distribuciones Aceptable o superior** (Fase 2), ordenando por score compuesto.
- Las distribuciones **Pobre** y **Rechazada** se muestran igualmente, agrupadas al final, con su **categoría absoluta** y el motivo — nunca se ocultan: el usuario debe ver por qué una candidata con buen AIC no se recomienda.
- Es **legible por un usuario no experto**: cada fila lleva la categoría absoluta y un veredicto en lenguaje claro, no solo números.
- Muestra el **desglose por pilar** para que se entienda *por qué* una gana.

**Columnas del ranking (contrato de presentación):**

| Columna | Contenido |
|---|---|
| Posición | 1, 2, 3 … (solo admisibles) / — (Pobre/Rechazada) |
| Distribución | Nombre legible |
| Categoría | Excelente / Buena / Aceptable / Pobre / Rechazada (Fase 1) |
| Score | 0–100 (solo admisibles; Fase 2) |
| Ajuste global | Grado o etiqueta — resumen Pilar A |
| Cola / recuentos altos | Grado o etiqueta — resumen Pilar C |
| Estabilidad | Grado o etiqueta — resumen Pilar D |
| Parámetros | Nº de parámetros (parsimonia) |
| Veredicto | Frase corta ("Recomendada", "Alternativa sólida", "Buen cuerpo, cola floja", "Rechazada: no converge") |

Sobre el ranking se destaca por separado la **recomendación en dos niveles** (§7.7): el mejor ajuste estadístico (Nivel 1, con confianza) y la matriz de adecuación por uso (Nivel 2, estrellas por Pricing / Reserving / Capital). Si la Fase 2 está vacía, en lugar del ganador se muestra el mensaje de "ninguna suficientemente buena" y las alternativas sugeridas (KDE / Tool-01, EVT / Tool-03).

---

## 9. Interpretación actuarial (diseño conceptual)

Es el **principal valor diferencial** de la herramienta. **No se usa IA.** Las conclusiones se generan mediante **reglas deterministas** en la capa Text Builders, a partir de los números producidos por Diagnostics y de los veredictos de Assessment. Aquí se diseña el **sistema**, no las reglas concretas.

### 9.1 Naturaleza del sistema

Un **catálogo de reglas** determinista. Cada regla tiene la forma *condición sobre métricas/veredictos → afirmación en lenguaje natural*. Los Text Builders evalúan el catálogo y **componen** un texto coherente (sin contradicciones, sin repetición) que se muestra en la caja de interpretación (`bmk_interpretation_box`). Mismos datos → mismo texto, siempre (reproducibilidad total, auditable).

### 9.2 Dimensiones (familias de afirmaciones)

El sistema cubre, como mínimo, estas dimensiones. Los ejemplos son ilustrativos del *tipo* de afirmación, no las reglas:

- **Perfil del dataset (del diagnóstico §3.4):** "variable continua positiva", "variable de recuento (discreta)", "presencia de una masa apreciable en cero", "posible multimodalidad: considera un enfoque no paramétrico (Tool-01)".
- **Calidad de ajuste global:** "excelente ajuste global", "ajuste global aceptable", "el ajuste global es pobre".
- **Fidelidad de cola / recuentos altos:** "buena representación de la cola", "ligera infraestimación de los cuantiles altos", "la cola está sobreestimada", "sobredispersión bien captada" (discreta).
- **Sesgo en cuantiles concretos:** "infraestima el VaR 99,5 %", "coherente con el VaR empírico".
- **Estabilidad / fiabilidad:** "parámetros estables", "parámetros poco estables", "convergencia deficiente", "errores estándar no fiables".
- **Evidencia de comportamiento extremo (EVT):** "los datos presentan evidencia de comportamiento extremo; se recomienda un análisis mediante Extreme Value Theory (Tool-03)".
- **Recomendación de dos niveles:** Nivel 1 "mejor ajuste estadístico: <dist> (confianza <nivel>)"; Nivel 2 "más adecuada para capital: <dist>; para pricing: <dist>".
- **Categoría y competencia:** "ninguna distribución alcanza el mínimo de calidad: considera KDE (Tool-01) o EVT (Tool-03)", "<dist> rechazada por no convergencia".
- **Avisos de datos:** "se han excluido N valores no positivos (M ceros, K negativos), reportados explícitamente", "la variable parece un recuento y se ha ajustado con la familia discreta".

### 9.3 Principios de composición

- **Jerarquía:** primero el veredicto global (qué se recomienda y con qué confianza), después el detalle (global, cola, estabilidad), después la idoneidad de uso, por último avisos.
- **No genérico:** el texto es específico del dataset y de la distribución ganadora, con números reales incrustados (arquitectura §11.1: la caja de interpretación no puede ser genérica ni copiada de otra herramienta).
- **Sin contradicciones:** las reglas se agrupan de forma que dos afirmaciones incompatibles no coexisten (una capa de resolución de conflictos entre reglas forma parte del diseño de Text Builders).
- **Honestidad:** si el ajuste es malo, el texto lo dice; nunca maquilla un mal resultado.

---

## 10. Arquitectura por capas

Se mantiene la arquitectura de Tool-01 y de la maestra vigente (`architecture_v2.md`). La única adición es una **capa 0 de diagnóstico del dataset (Profiler)** que precede al Motor: es lógica pura sin Shiny, no altera la cadena congelada Motor → … → UI ni la regla de que la UI solo consume el View Model, y su justificación técnica es sólida — el alcance general continua/discreta exige clasificar el problema antes de elegir qué familia ajustar. No se propone ningún otro cambio.

```
        DATOS (CSV → mod_data_input → bmk_validate_data)
                          │
                          ▼
   ┌─────────────────────────────────────────────────────┐
   │ 0. DATASET DIAGNOSIS / PROFILER  (calc.R, sin Shiny) │
   │    Clasifica el problema: continua/discreta, ceros,  │
   │    soporte, n, asimetría, cola pesada, multimodal.   │
   │    Salida DESCRIPTIVA; enruta la familia, no decide  │
   │    la distribución ganadora.                         │
   ├─────────────────────────────────────────────────────┤
   │ 1. MOTOR MATEMÁTICO          (calc.R, sin Shiny)     │
   │    Estima las distribuciones de la familia enrutada  │
   │    por el método elegido; parámetros, logLik, ajuste.│
   ├─────────────────────────────────────────────────────┤
   │ 2. DIAGNOSTICS               (calc.R, sin Shiny)     │
   │    Métricas de los pilares por ajuste (adaptadas a   │
   │    continua/discreta): GoF, IC, cola, estabilidad,   │
   │    predicción y señal de cola pesada.                │
   ├─────────────────────────────────────────────────────┤
   │ 3. ASSESSMENT                (calc.R, sin Shiny)     │
   │    Criterio §7: Fase 1 (categoría absoluta) → Fase 2 │
   │    (ranking entre admisibles) → recomendación de dos │
   │    niveles + confianza + detección EVT. Parametrizado│
   │    por decision_engine.md (versión registrada).      │
   ├─────────────────────────────────────────────────────┤
   │ 4. TEXT BUILDERS             (calc.R, sin Shiny)     │
   │    Reglas deterministas → strings de interpretación. │
   ├─────────────────────────────────────────────────────┤
   │ 5. VIEW MODEL                (calc.R, sin Shiny)     │
   │    Ensambla todo en estructura fija y versionada     │
   │    (schema_version). Única cosa que la UI consume.   │
   └─────────────────────────────────────────────────────┘
                          │  (contrato View Model)
                          ▼
   ┌─────────────────────────────────────────────────────┐
   │ 6. UI  (mod_distribution_fitting.R, Shiny)          │
   │    Consume SOLO el View Model. Nunca llama al motor. │
   └─────────────────────────────────────────────────────┘
```

**Reglas de frontera (heredadas, innegociables):**

- Las capas 0–5 residen en `calc.R` (o `shared/actuarial/` si algo se promueve) y **no dependen de Shiny**: ejecutables por `source()` sin Shiny cargado (arquitectura regla 7). Esto las hace auditables, testeables y migrables a Python en Fase 3.
- La **UI (capa 6) solo consume el View Model**. Nunca accede al Profiler, Motor, Diagnostics o Assessment directamente. Esta es la regla que garantiza que la interfaz sea intercambiable y que la lógica sea reutilizable en Internal Model Studio.
- El **Assessment** lee su parametrización de `decision_engine.md` como configuración versionada; ningún peso ni umbral se codifica en `calc.R` (regla maestra 8).
- `app.R` es orquestación pura (regla 6): carga `shared/`, monta `mod_distribution_fitting` y arranca. Cero cálculo.
- Sin CSS/HTML fuera de `shared/` (regla 16); toda la presentación usa los componentes `bmk_*` existentes.

---

## 11. API pública

Sigue **exactamente** la filosofía de `kde_analyze()`: **un único punto de entrada** que orquesta las capas 0–5 y devuelve un objeto de resultado completo. No se implementa aquí; se define el contrato.

### 11.1 Punto de entrada único

**`dist_fit_analyze(...)`** — recibe el dataset, la variable a modelizar y la configuración; ejecuta Profiler → Motor → Diagnostics → Assessment → Text Builders → View Model; devuelve el **objeto de resultado** del que se deriva el View Model. La UI llama a esta función (dentro de un `reactive`) y a nada más del motor.

**Entradas (contrato conceptual):**

| Argumento | Significado | Defecto |
|---|---|---|
| `data` | `data.frame` validado (del contrato de `mod_data_input`) | — (obligatorio) |
| `variable` | Nombre de la columna numérica a modelizar | — (obligatorio) |
| `mode` | `"auto"` \| `"manual"` | `"auto"` |
| `family` | Forzar familia (solo `manual`): `"continuous"` \| `"discrete"` | AUTO (del diagnóstico §3.4) |
| `distributions` | Subconjunto a probar (solo `manual`); en `auto`, todas las de la familia detectada | todas (familia) |
| `method` | Método de estimación (solo `manual`): `"mle"` \| `"mom"` \| `"lmom"` | AUTO decide |
| `analysis_depth` | Perfil de profundidad del análisis (§14.2): `"standard"` \| `"comprehensive"` | `"standard"` |
| `tail_levels` | Niveles de cuantil de cola a evaluar | `c(0.95, 0.99, 0.995)` |
| `config` | Lista de constantes de ejecución (nº bootstrap, k-folds, semilla…). La parametrización del criterio la aporta `decision_engine.md` | defaults nombrados |

**Salida:** un único objeto (lista estructurada) que **es o contiene** el View Model completo (§12). Igual que `kde_analyze()`, todo lo que la UI necesita sale de esta única llamada; la UI no vuelve a calcular nada.

### 11.2 Principios de la API (heredados de `kde_analyze()`)

- **Una llamada, un resultado completo.** Sin llamadas intermedias desde la UI.
- **Determinista y pura:** mismas entradas → misma salida (con semilla fijada para bootstrap/CV).
- **Sin efectos secundarios ni dependencia de Shiny.** Ejecutable en consola para tests y auditoría.
- **Constantes nombradas, sin números mágicos** (regla 8): todos los umbrales viven en `config` o en constantes documentadas.
- **Documentada en roxygen** (regla 9): título, `@param`, `@return`.

### 11.3 Funciones internas (no públicas, una por capa)

Orientación de diseño, no contrato externo: una función orquestadora por capa (`.profiler` (diagnóstico §3.4), `.motor`/estimación por distribución, `.diagnostics`, `.assessment`, `.text_builders`, `.build_view_model`), invocadas en orden por `dist_fit_analyze()`. Cada una recibe la salida de la anterior. Esto mantiene cada capa testeable de forma aislada.

---

## 12. View Model (contrato completo)

El View Model es la **única** estructura que la UI consume. Se define aquí por completo para que la UI se pueda construir sin decisiones. Es una lista anidada, estable, con estas secciones:

### 12.1 `meta` — metadatos de la ejecución
Nombre y versión de la herramienta (de `manifest.yml`), fecha, variable modelizada, familia detectada (continua/discreta), modo (`auto`/`manual`), semilla usada, **perfil de profundidad** (`analysis_depth`, §14.2), y **versionado explícito**: `schema_version` (versión del contrato del View Model) y `decision_engine_version` (versión de `decision_engine.md` con la que se produjo la recomendación). El perfil de profundidad forma parte de la tupla de reproducibilidad. Justificación en §12.11.

### 12.2 `input_summary` y `dataset_diagnosis` — datos y perfilado
`input_summary`: `n` efectivo y el **desglose explícito de exclusiones** (ceros, negativos, `NA`) con recuento y proporción — nunca silencioso —, más estadísticos descriptivos (media, mediana, desviación, asimetría, curtosis, mín, máx, cuantiles clave).
`dataset_diagnosis` (del Profiler §3.4): clasificación continua/discreta, soporte observado, señal de posible cola pesada, señal de posible multimodalidad, y flags derivados (`has_zeros`, `looks_like_count`, `heavy_tail_evidence`, `possible_multimodal`). Es descriptivo y alimenta interpretación e insights.

### 12.3 `metric_cards` — 3–4 KPIs para la cabecera
Contrato fijo para las metric cards del layout maestro. Propuesta:

| Card | Contenido |
|---|---|
| 1 | Distribución recomendada (nombre) |
| 2 | Nivel de confianza (Alta / Media / Baja) |
| 3 | Ajuste global de la ganadora (grado / score) |
| 4 | Calidad de cola de la ganadora (grado) |

### 12.4 `ranking` — tabla de ranking
Lista con las columnas de §8: posición (solo admisibles), distribución, **categoría absoluta** (Fase 1), score (Fase 2, solo admisibles), grados por pilar, nº parámetros, veredicto y estado (`recommended` / `admissible` / `poor` / `rejected` + motivo). Es la fuente de la tabla `DT`.

### 12.5 `recommendation` — recomendación de dos niveles
**Nivel 1 (mejor ajuste estadístico):** distribución ganadora, parámetros con intervalos de confianza, método usado y **por qué** (texto AUTO), categoría absoluta, nivel de confianza + justificación, desempate aplicado si lo hubo.
**Nivel 2 (adecuación por uso):** matriz de valoración por estrellas por caso de uso (Pricing / Reserving / Capital) para las distribuciones admisibles.
Incluye además `evt_recommendation` (booleano + texto) cuando hay evidencia de cola pesada (§7.6), y `none_good_enough` (booleano + alternativas sugeridas) cuando la Fase 2 queda vacía.

### 12.6 `fits` — detalle por distribución
Para cada distribución: parámetros, método, métricas crudas de los pilares, scores por pilar, **categoría absoluta** y estado (`recommended` / `admissible` / `poor` / `rejected` + motivo). Alimenta vistas de detalle y exportación.

### 12.7 `plots` — especificación de datos de los gráficos
Datos ya preparados (no objetos gráficos: eso es UI) para cada visual. Gráficos previstos:

| Gráfico | Propósito |
|---|---|
| Histograma + densidades ajustadas | Ajuste global visual del cuerpo |
| QQ-plot (ganadora, con zoom de cola) | Desviación en cuantiles, especialmente extremos |
| PP-plot | Ajuste de la CDF |
| Función de exceso medio (empírica vs ajustada) | Diagnóstico de cola / EVT |
| Comparativa de VaR/TVaR por nivel | Ajuste en cuantiles actuariales clave |

La UI aplica `theme_bmk_ggplot()` / `bmk_plotly_layout()`; el View Model solo aporta los datos.

### 12.8 `interpretation` — texto de la caja de interpretación
Strings ya compuestos por Text Builders, agrupados por dimensión (§9.2), listos para `bmk_interpretation_box`. La UI no genera texto.

### 12.9 `warnings` — avisos al usuario
Mensajes para `bmk_notify()` / caja de avisos: exclusiones explícitas (ceros/negativos/`NA`), variable tratada como discreta, evidencia de cola pesada (sugerencia EVT/Tool-03), posible multimodalidad (sugerencia KDE/Tool-01), ninguna distribución suficientemente buena, método degradado, `n` insuficiente para validación cruzada, etc.

### 12.10 `export_table` — datos de exportación CSV
`data.frame` plano listo para `mod_export_csv`: una fila por distribución con parámetros, métricas clave por pilar, categoría absoluta, score y veredicto. Es lo que el usuario descarga.

### 12.11 Justificación del versionado (`schema_version`, `decision_engine_version`)
Dos versiones distintas por dos motivos distintos. `schema_version` versiona el **contrato del View Model**: cuando Internal Model Studio (Fase 4) consuma el View Model de 40 herramientas, necesita saber contra qué forma programa; un cambio de estructura incrementa esta versión sin ambigüedad. `decision_engine_version` versiona el **criterio actuarial** (`decision_engine.md`): dos calibraciones distintas de pesos/umbrales pueden dar recomendaciones distintas sobre los mismos datos, de modo que registrar con qué versión se generó una recomendación es condición de **reproducibilidad y auditabilidad** ante un revisor. Separarlas evita confundir un cambio de presentación con un cambio de criterio.

**Regla de oro:** si la UI necesita un dato, ese dato está en el View Model. Si no está, se añade al View Model, **nunca** se calcula en la UI.

---

## 13. Plan de implementación (bloques independientes)

Desarrollo dividido en bloques pequeños, cada uno implementable y validable de forma aislada. El orden respeta las dependencias entre capas. Cada bloque indica objetivo, entregables y criterio de validación. Todo el bloque de motor (B1–B6) es `calc.R` sin Shiny y validable en consola antes de tocar la UI.

### B0 — Andamiaje desde la plantilla
- **Objetivo:** clonar `tool-00-template` a `tools/distribution-fitting/`, dejar la app arrancando en vacío.
- **Entregables:** carpeta con `app.R`, `R/mod_tool.R`, `R/calc.R`, `manifest.yml`, `README.md`, `data/example_data.csv`.
- **Validación:** la app arranca, muestra header/footer con nombre y versión de `manifest.yml`, sin errores ni warnings en consola.

### B1 — Profiler + Motor de estimación (Capas 0 y 1)
- **Objetivo:** implementar el diagnóstico del dataset (§3.4) —continua/discreta, ceros, soporte, `n`, asimetría, señales de cola pesada/multimodal— y el motor de estimación por MLE de ambas familias (continua §4.1 y discreta §4.2), devolviendo parámetros y logLik. El Profiler enruta la familia.
- **Entregables:** Profiler y funciones de estimación en `calc.R`, sin Shiny; datos de ejemplo continuo y de recuento.
- **Validación:** el Profiler clasifica correctamente datasets continuos y discretos y detecta ceros; parámetros verificados contra un caso conocido (paper / script previo / `fitdistrplus` como contraste), dentro de tolerancia.

### B2 — Métodos de estimación adicionales + AUTO de método (Capa 1)
- **Objetivo:** añadir MoM (continua y discreta) y L-momentos (continua); implementar la selección AUTO de método por distribución/dataset y su justificación textual.
- **Entregables:** métodos adicionales y lógica de selección con motivo registrado.
- **Validación:** en datasets diseñados (muestra pequeña, cola pesada, sobredispersión, no convergencia forzada) AUTO elige el método esperado y lo explica.

### B3 — Diagnostics: métricas por pilar (Capa 2)
- **Objetivo:** calcular las métricas (§6) por ajuste, **adaptadas a la familia** (KS/AD/CvM y cola para continua; chi-cuadrado y sobredispersión para discreta), más el índice de cola como señal diagnóstica.
- **Entregables:** módulo de diagnóstico en `calc.R`; bootstrap y k-fold parametrizados por `config`.
- **Validación:** cada métrica verificada contra referencia conocida; estabilidad reproducible con semilla fija; degradación correcta cuando `n` es insuficiente (Pilar E desactivado).

### B4 — Assessment: criterio de dos fases + `decision_engine.md` (Capa 3)
- **Objetivo:** Fase 1 (categoría absoluta), Fase 2 (ranking entre admisibles), recomendación de dos niveles (§7.7), confianza, detección EVT y mínimos de admisibilidad (§7.4). Crear `decision_engine.md` con pesos/umbrales/conflictos/desempates/mapa uso→pilares y leerlos como configuración versionada.
- **Entregables:** motor de decisión determinista parametrizado por `decision_engine.md` (con `decision_engine_version`).
- **Validación:** casos que fuerzan cada rama: rechazo por no convergencia, empate por parsimonia, "ninguna alcanza Aceptable" → Fase 2 vacía, confianza Alta/Media/Baja, insight EVT disparado. Resultado esperado en cada uno.

### B5 — Text Builders: interpretación determinista (Capa 4)
- **Objetivo:** catálogo de reglas condición→afirmación y composición sin contradicciones (§9).
- **Entregables:** generador de texto en `calc.R` con reglas documentadas.
- **Validación:** mismos datos → mismo texto; cobertura de todas las dimensiones §9.2; ausencia de afirmaciones contradictorias en una batería de escenarios.

### B6 — View Model + API pública (Capas 5 y 11)
- **Objetivo:** ensamblar el View Model completo (§12) —incluidos `schema_version`, `decision_engine_version`, `dataset_diagnosis` y la recomendación de dos niveles— y exponer `dist_fit_analyze()`.
- **Entregables:** constructor del View Model y función pública documentada en roxygen.
- **Validación:** `dist_fit_analyze()` ejecutable en consola sin Shiny; el View Model contiene todas las secciones §12 y ambas versiones; contrato estable frente a datasets continuos y discretos.

### B7 — UI: módulo Shiny sobre el View Model (Capa 6)
- **Objetivo:** `mod_distribution_fitting` consumiendo solo el View Model: sidebar (variable, modo, calcular), panel de diagnóstico del dataset, metric cards, gráficos, ranking `DT` con categorías, recomendación de dos niveles (Nivel 1 + estrellas por uso), insight EVT, interpretación y exportación.
- **Entregables:** `mod_tool.R` con namespacing correcto; solo componentes `bmk_*`.
- **Validación:** flujo extremo a extremo con "generar ejemplo" + "calcular" sin tocar inputs; sin CSS/HTML fuera de `shared/`; no se rompe en 1366×768; la UI nunca llama al motor.

### B8 — Modo MANUAL + robustez de datos
- **Objetivo:** selección manual de familia/distribuciones/método; tratamiento explícito de ceros y negativos (§3.5), enrutado discreto/continuo, límites de datos (§7.5 maestra).
- **Entregables:** controles avanzados y avisos vía `bmk_notify()`.
- **Validación:** casos límite (columna de recuentos, ceros/negativos, CSV al límite) producen avisos claros y exclusiones cuantificadas, nunca errores crípticos ni silenciosos.

### B9 — Cierre: checklist "Tool terminada" + publicación
- **Objetivo:** cumplir íntegramente la checklist maestra §11.
- **Entregables:** `README.md` (qué hace, familias y columnas soportadas, limitaciones: sin censura/truncamiento, sin selección de umbral EVT, sin modelos zero-inflated en v1), `manifest.yml` completo, verificación manual contra caso conocido, despliegue y captura/GIF.
- **Validación:** los 4 bloques de la checklist §11 (funcional, visual, técnico, publicación) superados sin cumplimiento parcial.

**Nota de gestión (regla 17):** toda idea surgida durante el desarrollo va al backlog, no a Tool-02 en curso (splicing, distribuciones extra, censura/truncamiento, zero-inflated, EVT).

---

## 14. Filosofía de coste computacional, profundidad y transparencia

*(Principio de plataforma — aplicable a Tool-02 y a toda herramienta futura: Tool-03 EVT, Tool-04 Aggregate Models, Tool-05 Pricing, Internal Model Studio, ORSA Platform. Su sede natural es la arquitectura maestra; ver la nota de gobernanza §14.5.)*

### 14.1 Sustitución de la promesa de "resultado en menos de un minuto"

La plataforma **ha retirado** el objetivo arquitectónico de "resultado en menos de un minuto" (promovido ya a la maestra `architecture_v2.md` §1.7 y registrado en ADR-007). Estas herramientas se utilizan en proyectos actuariales reales, no compiten con calculadoras online, y es aceptable que un análisis tarde varios minutos cuando ello aporta mayor robustez y confianza. La prioridad de la plataforma es, en este orden:

1. Calidad del análisis.
2. Robustez estadística.
3. Reproducibilidad.
4. Confianza en las recomendaciones.

El **tiempo de ejecución es una consecuencia del problema analizado, no un objetivo de diseño**. Esto **no** legitima la lentitud: la velocidad se persigue en la implementación, sin sacrificar rigor (§14.4).

### 14.2 Profundidad del análisis controlada por el usuario (no degradación automática)

La plataforma **rechaza** desactivar o reducir análisis de forma automática en función del tamaño del dataset. La degradación silenciosa por tamaño es un riesgo de reproducibilidad y de auditoría: haría que el rigor del resultado dependiera del volumen de datos sin que el usuario lo supiera, y que dos datasets recibieran distinto tratamiento sin control ni registro.

En su lugar, la profundidad es una **decisión explícita del usuario**, expresada como un **conjunto pequeño, fijo y enumerado de perfiles de profundidad**, cada uno una **configuración congelada y documentada** (qué validaciones se ejecutan y con qué presupuesto de remuestreo):

| Perfil | Orientado a | Qué ejecuta (filosofía) |
|---|---|---|
| **Standard** (defecto) | La mayoría de usuarios y el uso diario | Ajuste, bondad de ajuste, cola, criterios de información y estabilidad / validación cruzada con presupuesto de remuestreo moderado |
| **Comprehensive** | Estudios exhaustivos, informes técnicos, revisión actuarial | Todas las validaciones disponibles con presupuesto de remuestreo completo (bootstrap y validación cruzada extensos, calibración de p-valores por simulación) |

Decisiones de diseño sobre los perfiles:

- **Enumerados, no un control continuo.** Un deslizador de "intensidad" sería irreproducible y difícil de documentar. Un conjunto fijo y nombrado es auditable: dado el perfil, se sabe exactamente qué se ejecutó.
- **`Standard` es el defecto**, para que un usuario nuevo nunca dispare por accidente un análisis de varios minutos sin buscarlo.
- **La profundidad cambia *amplitud* y *precisión Monte Carlo*, nunca *validez*.** Una métrica que se ejecuta se ejecuta siempre de forma correcta; menos remuestreos significan mayor error de Monte Carlo (intervalos más anchos), no un estadístico inválido. Cada perfil respeta los **suelos mínimos de remuestreo** por debajo de los cuales una cantidad dejaría de ser significativa; esos suelos y presupuestos se parametrizan en `decision_engine.md` / `config`, nunca se codifican.
- **El perfil aplicado es parte de la tupla de reproducibilidad** y viaja en `meta.analysis_depth` (§12.1) junto a la semilla, `schema_version` y `decision_engine_version`. Misma tupla → mismo resultado.
- **Vocabulario común a toda la plataforma.** Todas las herramientas exponen el mismo conjunto de perfiles, de modo que Internal Model Studio u ORSA puedan solicitar una profundidad coherente a una batería de herramientas.

*(Ampliable en el futuro con un tercer perfil ligero de iteración —"Quick"— si se detecta necesidad real; se mantiene fuera de v1 para no multiplicar configuraciones que documentar y validar.)*

### 14.3 Transparencia del progreso

Cuando un análisis dure varios minutos, el usuario debe **comprender siempre qué está haciendo la herramienta**. Filosofía:

- **El progreso se deriva de la propia arquitectura por capas.** El pipeline (Profiler → Motor → Diagnostics → Assessment → Text Builders → View Model) es una secuencia ordenada y conocida de fases con nombre; las fases del progreso **son** esas capas, más las subfases con conteo conocido dentro de Diagnostics. No hay invención ad-hoc: la misma enumeración que estructura `calc.R` estructura el progreso y, después, el informe. Esto lo hace **reutilizable por toda herramienta** que comparta la arquitectura.
- **Secuencia de fases comunicada al usuario (ejemplo):** lectura y validación de datos → diagnóstico inicial del dataset → ajuste de distribuciones → validaciones de bondad de ajuste → bootstrap de estabilidad → validación cruzada → construcción del motor de decisión → generación de la interpretación e informe.
- **Honestidad por encima de estética.** Donde una fase tiene un número de iteraciones conocido (ajustes: *k* de *N*; bootstrap: *r* de *R*; folds: *f* de *F*), se informa por **conteo real**. Donde no lo tiene, se informa **estado** (en curso / hecho). **Nunca** se muestran porcentajes fabricados ni ETAs inventadas que impliquen una precisión inexistente.
- **El progreso es un canal lateral puro:** observa el cálculo, nunca lo altera. Consistente con la pureza de `calc.R` y con el determinismo del resultado.
- **Interrumpibilidad como principio** (no como implementación): un análisis largo debería poder cancelarse sin corromper el estado; al ser las capas puras y ordenadas, cancelar solo descarta trabajo parcial.

### 14.4 Optimizar ≠ degradar (principio explícito)

La arquitectura distingue de forma explícita dos palancas que **no** deben confundirse:

| | Optimizar la implementación | Reducir el contenido del análisis |
|---|---|---|
| Qué cambia | *Cómo de rápido* se calcula | *Qué* se calcula |
| Ejemplos | Paralelización, vectorización, gradientes/Hessianos analíticos, mejores valores iniciales, cacheo de cantidades intermedias, C++ donde se justifique | Menos remuestreos, omitir pilares, tests más gruesos, submuestreo del dataset |
| ¿Permitido? | **Sí, siempre, y fomentado.** No altera el resultado estadístico | **No de forma automática.** Solo (a) por elección explícita de perfil de profundidad (§14.2) o (b) con justificación estadística sólida y documentada |

Este principio impide que, en el futuro, alguien "optimice" una herramienta **degradando en silencio** su rigor. La velocidad se gana en la implementación; la calidad no se sacrifica por defecto.

### 14.5 Nota de gobernanza (sede del principio) — completada

Los principios §14.1–§14.4 y el de §6 (validez estadística) **no son específicos de Tool-02**: son filosofía de plataforma. Por ello se han **promovido a la arquitectura maestra** (`architecture_v2.md` §1.7 y §1.8) y **registrado en `docs/decisions_log.md`** (ADR-007 coste computacional, ADR-008 validez estadística, ADR-009 versionado), conforme al procedimiento de versionado maestro §15.6. La plataforma habla ahora con una única filosofía y las herramientas futuras (Tool-03/04/05, Internal Model Studio, ORSA) la heredan automáticamente. Este paso de gobernanza queda **completado**.

---

## 15. Decisiones aprobadas en el cierre del Sprint 0

Las siguientes decisiones quedan **aprobadas y congeladas** (versión 1.0, estado *Approved*). Su registro formal está en `docs/decisions_log.md` (ADR indicados):

1. **Alcance general continua + discreta** con enrutado por diagnóstico del dataset (§3.3–§3.4), sin duplicar arquitectura. *(ADR-001, ADR-005)*
2. **Conjuntos de distribuciones por familia** (§4) y **GPD fuera del ranking**, tratada solo como detección + derivación a EVT / Tool-03 (§4.4, §7.6). *(ADR-002)*
3. **Criterio de decisión en dos fases** (evaluación absoluta → ranking entre admisibles) (§7.2), con eliminación de la regla de momentos infinitos (§7.4). *(ADR-004)*
4. **Recomendación de dos niveles** (mejor ajuste estadístico + adecuación por uso con estrellas) y nivel de confianza (§7.7, §7.9). *(ADR-006)*
5. **Separación del criterio en `decision_engine.md`** versionado, y **versionado** de `schema_version` y `decision_engine_version` (§7.8, §12.11). *(ADR-003, ADR-009)*
6. **Métodos de estimación v1:** MLE + MoM (ambas familias) y L-momentos (continua) (§5.2). *(ADR-001)*
7. **Filosofía de coste computacional** (§14): retirada de la promesa de "<1 min", prioridad calidad > tiempo, profundidad controlada por el usuario (Standard / Comprehensive), transparencia de progreso derivada de las capas, y principio explícito optimizar ≠ degradar. *(ADR-007)*
8. **Principio de validez estadística** con parámetros estimados (§6). *(ADR-008)*

Los puntos 7 y 8, por ser filosofía de plataforma, se han promovido a la arquitectura maestra `architecture_v2.md` (§14.5). Este documento y `decision_engine.md` quedan **congelados en versión 1.0 (Approved)** y el desarrollo B0–B9 puede comenzar. Todo cambio posterior requiere un ADR (regla maestra 20).

---

*Actuarial Tools by BMK — Tool-02 Distribution Fitting — Especificación de Diseño (Sprint 0) — Estado: **Approved**. Subordinada a `docs/architecture_v2.md`.*
