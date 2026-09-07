# Tool-02 — Decision Engine (criterio actuarial parametrizado)

| Campo | Valor |
|---|---|
| **Proyecto** | Actuarial Tools by BMK |
| **Herramienta** | Tool-02 — Distribution Fitting |
| **Documento** | `tools/distribution-fitting/decision_engine.md` |
| **decision_engine_version** | **0.2** (ADR-021: la confianza pasa a basarse en ΔAIC; incorpora también ADR-019 y ADR-020) |
| **Estado** | **Vigente y validado.** Calibración de los pesos A/B, orden de desempate, umbrales de confianza por ΔAIC, umbral de clasificación discreta y suelos del chi-cuadrado (§4). Sigue siendo **provisional** mientras el pilar D (estabilidad por bootstrap) esté diferido |
| **Depende de** | `tool_02_distribution_fitting_design.md` (§7) y `architecture_v2.md` (vigente) |

---

## 1. Propósito y separación de responsabilidades

Este documento contiene **exclusivamente la parametrización del criterio de decisión** de Tool-02.

La arquitectura de la herramienta (`tool_02_distribution_fitting_design.md`) y la maestra de plataforma (`architecture_v2.md`) fijan el **qué**: el criterio de dos fases, la recomendación de dos niveles, los pilares de validación, el flujo por capas y los principios de plataforma (coste computacional, validez estadística, versionado). Este documento fija el **cuánto**: los valores concretos que la capa Assessment consume como configuración.

Aislar el criterio tiene tres motivos:

1. **Recalibración sin reabrir la arquitectura.** El criterio actuarial se afina con la experiencia; cambiar un peso o un umbral no debe obligar a tocar —ni recongelar— el documento de arquitectura.
2. **Reproducibilidad y auditabilidad.** Toda recomendación viaja con la `decision_engine_version` que la produjo (`meta.decision_engine_version` del View Model), de modo que un revisor puede reconstruir exactamente con qué criterio se generó.
3. **Sin números mágicos** (regla maestra 8). El Assessment lee estos valores como configuración; nunca se codifican en `calc.R`.

---

## 2. Contenido (estructura; valores a calibrar en un paso posterior)

Este documento definirá, y **solo** esto:

1. **Pesos por pilar** del score compuesto de la Fase 2 (A global, B parsimonia, C cola / recuentos altos, D estabilidad, E capacidad predictiva).
2. **Umbrales de las categorías absolutas** de la Fase 1 —Excelente / Buena / Aceptable / Pobre / Rechazada—, por métrica y **por familia** (continua y discreta).
3. **Umbrales de admisibilidad** (§7.4 de la arquitectura): CV máximo de bootstrap, mínimo de bondad de ajuste, criterios de convergencia y de compatibilidad de soporte.
4. **Umbral de detección de cola pesada** que dispara la derivación a EVT / Tool-03 (§7.6).
5. **Reglas de conflicto** entre insights de los Text Builders: qué afirmación prevalece cuando dos podrían coexistir.
6. **Orden de desempate** de la Fase 2 (§7.5): parsimonia → estabilidad → fidelidad de cola → preferencia por la distribución más estándar.
7. **Mapa uso → pilares** para la valoración por estrellas del Nivel 2 (Pricing / Reserving / Capital).

*Este Sprint define únicamente la separación de responsabilidades y la estructura anterior. Los valores calibrados se abordan en un paso posterior, contra datasets de distribución conocida (calibración empírica, no por intuición).*

---

## 3. Versionado

`decision_engine_version` sigue semver de tres componentes. Todo cambio de un valor que pueda alterar una recomendación incrementa la versión y se registra en `docs/decisions_log.md` **antes** de aplicarse (procedimiento maestro §15). El valor vigente viaja siempre en `meta.decision_engine_version` del View Model (§12.1 y §12.11 de la arquitectura).

Distinción importante frente a `schema_version`: `schema_version` versiona la **forma** del View Model (contrato de integración con la UI e Internal Model Studio); `decision_engine_version` versiona el **criterio** (los valores de este documento). Un cambio en uno no implica un cambio en el otro.

---

## 4. Valores calibrados (B4 — inicial, provisional)

Valores que consume la capa Assessment (implementados en `decision_engine_spec()` de `calc.R`). Son **provisionales** y se afinarán cuando existan los pilares C/D y los p-valores.

**Pesos por pilar (Fase 2).** Solo A y B están activos en B4; C, D y E se definen con peso 0 hasta que existan sus métricas.

| Pilar | Peso | Estado |
|---|---|---|
| A — bondad de ajuste | 0.7 | activo |
| B — parsimonia (AIC/AICc/BIC) | 0.3 | activo |
| C — cola · D — estabilidad · E — predictiva | 0 | inactivo (métricas pendientes) |

**Orden de desempate (§7.5).** `parsimonia → AIC → id`. La estabilidad (D) y la fidelidad de cola (C) se insertarán en el orden cuando existan esos pilares.

**Umbrales de confianza (por ΔAIC, ADR-021).** Se mide el **ΔAIC entre la candidata recomendada y la mejor de las restantes**: Alta ≥ 10 · Media ≥ 2 · Baja en otro caso (criterio de Burnham & Anderson, 2002). Si la recomendada no es la mejor por AIC, ΔAIC es negativo y la confianza cae a baja. Además, si la recomendada no es la mejor ni por AIC ni por el pilar A, la confianza no puede superar "media".

*Por qué ΔAIC y no la separación del compuesto.* Hasta v0.1 la confianza se leía de la diferencia de puntuación compuesta entre la 1.ª y la 2.ª, con umbrales 20/8. Esa puntuación procede de una normalización min-máx cuya escala la fija **la peor candidata**, de modo que la separación no es comparable entre datasets: una candidata muy mala estira el rango y comprime las diferencias entre las buenas. Ningún par de umbrales fijos puede funcionar sobre una magnitud sin escala estable. El ΔAIC sí la tiene. La separación del compuesto se conserva en `composite_separation` como dato descriptivo.

**Provisionalidad.** Sigue siendo una calibración provisional: por diseño (§7.9) la confianza corresponde al **pilar D (estabilidad por bootstrap)**, aún diferido. ΔAIC es una aproximación mejor fundada que la anterior, no la definitiva.

**Esperanza mínima del chi-cuadrado discreto (ADR-019).** Las categorías se agrupan hasta alcanzar una esperanza de **5** por celda; si con ese suelo no quedan grados de libertad (muestras pequeñas) se recurre al suelo relajado de **1** (regla de Cochran), dejándolo documentado en `gof_note`. Si tampoco así hay al menos 2 celdas y 1 grado de libertad, el estadístico se devuelve como `NA` explícito, no como `NaN`.

**Umbral de clasificación discreta (ADR-020).** `discrete_max_unique = 50`: una variable entera y no negativa con más de 50 valores distintos se trata como **continua**. Es el refinamiento previsto por §3.3, antes desactivado (`Inf`). Evita que una severidad en euros redondeada a entero se modelice con Poisson o binomial negativa. La familia sigue siendo forzable a mano.

**Bandas de presentación de los Text Builders (B5).** Clasifican un score de pilar (0–100) al redactar fortalezas y limitaciones: fuerte ≥ 75 · débil ≤ 25 · intermedio en otro caso. Son reglas de **texto**, no de decisión: no alteran el ranking ni la recomendación.

**Pendiente (bloques posteriores):** umbrales de categorías absolutas (Fase 1, requieren p-valores), mínimos de admisibilidad por inestabilidad (Pilar D), umbral de EVT (Pilar C), reglas de conflicto de insights (B5) y mapa uso → pilares del Nivel 2 (Pilares C/D).

---

*Actuarial Tools by BMK — Tool-02 Decision Engine v0.2 (ADR-019/020/021: chi-cuadrado con agrupación de categorías, umbral de clasificación discreta y confianza por ΔAIC). Subordinado a `tool_02_distribution_fitting_design.md` y `architecture_v2.md`.*
