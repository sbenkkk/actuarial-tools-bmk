# Tool-02 · Distribution Fitting — notas de versión v1.1.0

> **ESTADO: BORRADOR. RELEASE NO CERRADA.**
> `manifest` sigue en **1.0.2**. El bump a 1.1.0 es el **último** paso de B17 y
> solo procede tras completar la validación automática y la aceptación manual
> sin ningún `PRODUCT BUG — BLOCKING`.

---

## Qué añade v1.1.0 respecto a v1.0.2

Una sola capa nueva: **incertidumbre de parámetros**. El flujo de análisis
—perfilado, muestra común, ajuste, diagnósticos, ranking, recomendación,
gráficos, ficha técnica y exportación— **no cambia**.

### 1. Incertidumbre analítica del MLE

Errores estándar e intervalos de confianza derivados de la **matriz de
información observada** `J(θ̂) = −∇²ℓ(θ̂)`, invertida y trasladada a escala
natural por **método delta**.

- Se calcula en la escala computacional en que el problema está bien
  acondicionado, con transformación **declarativa por parámetro** —identidad para
  parámetros libres, logaritmo para positivos, logit para probabilidades—.
- **Cadena de validación estricta** de diez pasos, con Cholesky. Si falla
  cualquiera, se declara el motivo y **no se publica ningún error estándar**.
  Nunca se recurre a pseudoinversa, recorte de autovalores ni regularización.
- Los intervalos se construyen en la escala transformada y se retrotransforman,
  de modo que **respetan el soporte del parámetro**: un `scale` nunca produce un
  extremo negativo. A cambio son **asimétricos** en escala natural.
- Disponible **solo para MLE**. No es una limitación de implementación: la
  construcción exige que el score se anule en `θ̂`, y los demás estimadores no lo
  anulan.

### 2. Bootstrap no paramétrico

Motor genérico de remuestreo **iid con reemplazamiento** sobre la muestra de
análisis, reejecutando **el mismo estimador y la misma configuración** en cada
réplica.

- Cubre **MLE, MoM, L-momentos y Percentile Matching**.
- Produce réplicas, **error estándar**, **sesgo como diagnóstico** e
  **intervalo percentil** (`quantile`, `type = 7`).
- Las réplicas que no producen un ajuste válido **según las mismas reglas
  productivas** se contabilizan como fallidas: no se reparan, no se relajan
  guardas, no se reintentan.
- **Solo se ejecuta bajo demanda.** Nunca al cargar datos, calcular el análisis,
  cambiar de fila del ranking o entrar en la vista.

### 3. Validación y comparación descriptiva

- Una capa que **organiza** lo anterior y valida su coherencia: nombres y orden
  de parámetros, niveles de confianza, e **identidad de la muestra** entre las
  dos vías mediante huella **SHA-256**.
- Cuando ambas vías existen **y corresponden verificablemente a la misma
  muestra**, se presentan lado a lado.

> **La comparación es descriptiva.** No se aplica ningún criterio automático de
> acuerdo ni de estabilidad.

### 4. Vista dedicada de incertidumbre

Una vista interna, accesible desde la pantalla principal y con retorno, que no
recalcula el análisis al navegar. Muestra la distribución seleccionada y el
**estimador efectivamente utilizado** —relevante en modo automático, donde el
método puede diferir por distribución—, las tablas analítica y bootstrap, un
gráfico por parámetro de la distribución bootstrap, la comparación descriptiva
cuando procede, y las limitaciones aplicables.

### 5. Percentile Matching

Estimador por igualación de cuantiles, con objetivo normalizado y tres presets
—10/50/90 por defecto, 10/25/50/75/90 ampliado, 25/50/75 central—. Disponible
como **estimador alternativo dentro de la vista de incertidumbre**, sobre la
distribución seleccionada. **No participa** en la selección automática, el
ranking ni la recomendación.

### 6. Reproducibilidad

Cada ejecución de bootstrap registra su configuración: distribución, estimador,
`B` solicitadas/exitosas/fallidas, nivel de confianza, **semilla**, percentiles
PM cuando aplica, `n` modelizada, **huella SHA-256** de la muestra, y versiones
de herramienta y schema. Los metadatos quedan **congelados con el resultado**:
editar los controles después no los altera.

### 7. Exportación

Nuevo CSV de incertidumbre, **una fila por parámetro**, con estimación,
resultados de ambas vías cuando existan y todos los metadatos de
reproducibilidad. **No incluye las réplicas individuales.** La exportación
existente del ranking **no cambia**.

---

## Lo que v1.1.0 **NO** incluye

Se enumera explícitamente para que no se lea de más en lo anterior:

- **No** hay evaluación automática de estabilidad del estimador.
- **No** hay puntuación de fiabilidad del bootstrap ni umbral de réplicas
  exitosas.
- **No** hay corrección de sesgo, ni intervalos BCa o bootstrap-t.
- **No** se publica MSE.
- **No** hay incertidumbre de **selección de modelo**: toda la incertidumbre
  publicada es condicional a la distribución elegida.
- **No** hay propagación de incertidumbre a VaR, TVaR ni ES.
- **No** hay incertidumbre analítica para MoM, L-momentos ni PM.
- **No** hay `B` personalizado, ni gestor de configuraciones, ni configuraciones
  guardadas, ni importación o restauración de sesiones.
- **No** hay bootstrap paramétrico para calibración de bondad de ajuste.
- **No** hay métodos bayesianos, EVT/POT ni distribuciones nuevas.

---

## Limitaciones metodológicas declaradas

**Muestra condicional (ADR-026).** Para el catálogo continuo positivo se
modeliza la muestra restringida al soporte común. Cuando hay observaciones nulas
excluidas, la incertidumbre corresponde a los parámetros de la **distribución
condicional positiva**, no a la variable original completa con su masa en cero.

**Resúmenes bootstrap condicionados al éxito (OD-17, abierta).** Si la
probabilidad de que una réplica produzca un ajuste válido depende del valor que
habría tomado el estimador, los resúmenes calculados sobre las réplicas válidas
pueden no representar la distribución bootstrap no condicionada. **La dirección
y la magnitud de esa distorsión dependen del mecanismo de fallo y no se
determinan aquí.** El producto publica siempre los contadores y los motivos de
fallo para que la situación sea observable.

**Sin criterio de fiabilidad del bootstrap (OD-11, diferida).** No se establece
ninguna fracción mínima de réplicas exitosas: sería un umbral sin evidencia.

**Aproximación asintótica (vía analítica).** Los intervalos de Wald sobre la
información observada son una aproximación válida para tamaños muestrales
suficientes; su cobertura exacta no está garantizada en muestras pequeñas.

**Incertidumbre de selección de modelo (H4, futura).** Fuera de alcance.

**Pesos de Percentile Matching (OD-14, diferida).** El objetivo usa pesos
uniformes.

---

## Compatibilidad

| Elemento | v1.0.2 | v1.1.0 |
|---|---|---|
| `schema_version` | 1.1.0 | **1.1.0 (sin cambio)** |
| Exportación del ranking | — | **sin cambio** |
| Contrato de interacción (ADR-029) | — | **sin cambio** |
| Ranking, recomendación, AUTO, Decision Engine | — | **sin cambio** |

La capa de incertidumbre es una **estructura paralela**: no se cuelga del
resultado público, de modo que no hay cambio contractual que versionar.

---

## Dependencias

Se añade **`digest`** (0.6.37), usada para la huella SHA-256 de la muestra.
Declarada en `renv.lock`.

---

*Actuarial Tools by BMK — Tool-02 v1.1.0. Borrador de notas de versión.*
