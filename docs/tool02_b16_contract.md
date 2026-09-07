# Tool-02 — B16.0: contrato de UI, integración, reproducibilidad y exportación

> **ESTADO: PROPUESTA PARA REVISIÓN. NADA IMPLEMENTADO.**
> Sin código de producción. B16.1 no ha comenzado.

---

## 1. Arquitectura actual (auditada, no supuesta)

### 1.1 Ficheros reales

**El repositorio NO tiene `visual_engine.R`, `export.R` ni ningún fichero de
schema.** Todo vive en dos ficheros:

| Fichero | Líneas | Contenido |
|---|--:|---|
| `R/calc.R` | 4.117 | Capas 0 a 5 completas: profiler, muestra común, motor, PM, B12, B13, B14, B15, diagnostics, decision engine, assessment, text builders, **View Model**, **Visual Engine**, orquestador |
| `R/mod_tool.R` | 901 | Módulo Shiny: UI + server. Sin estadística |
| `app.R` | 37 | Arranque |

El Visual Engine (§3e) y el schema (`DFIT_SCHEMA_VERSION`) son **secciones de
`calc.R`**, no ficheros. La exportación se delega en el módulo compartido
`shared/modules/mod_export_csv.R`.

### 1.2 UI

`bslib::layout_sidebar` con un panel principal **lineal**: métricas → gráfico
plotly → ranking DT → QQ/PP → ficha técnica → comparación → interpretación →
botón de exportación. **No hay `navset`, ni pestañas, ni modales de contenido.**

### 1.3 Estado reactivo

| Reactivo | Tipo | Nota |
|---|---|---|
| `datos()` | módulo | CSV cargado |
| `variable_sel()` | `reactive` | columna elegida |
| **`analysis()`** | **`eventReactive(input$calcular)`** | **única llamada a `dist_fit_analyze()`**; nada se recalcula sin pulsar el botón |
| `view_model()` | `reactive` | `prepare_view_model(analysis)` |
| `visual_data()` | `reactive` | `build_visual_data(analysis, datos)` — **estructura independiente del VM** |
| **`selected_id()`** | **`reactiveVal`** | estado de exploración (ADR-029). Se reinicia a la recomendada al recalcular |

### 1.4 Exportación

```r
mod_export_csv_server("exportar",
                      data = reactive(view_model()$export_table),
                      filename = base_nombre)
```

El módulo compartido escribe **un `data.frame` verbatim** a CSV. `export_table`
tiene **una fila por distribución del ranking**. `mod_export_csv_ui` **ya se
instancia dos veces** en la herramienta (plantilla y resultados).

### 1.5 Schema y versionado

`DFIT_SCHEMA_VERSION <- "1.1.0"`, expuesto en `view_model$meta$schema_version`.
`manifest.yml`: `version: 1.0.2`, `status: draft`.

**Hallazgo aprovechable:** `.vm_meta()` ya declara

```r
seed = NA_integer_,   # sin remuestreo todavía: aplicará con bootstrap/CV
```

Es un hueco previsto para exactamente este bloque.

### 1.6 Capas de incertidumbre disponibles

`.mle_uncertainty(fit, x, confidence_level, config)` · `.bootstrap_estimator(x,
estimator_fn, B, seed, confidence_level, theta_hat, …)` ·
`.bootstrap_adapter_fit(id, method, family, resolution, config)` ·
`.bootstrap_adapter_pm(id, percentiles, config)` · `.validate_estimator(...)` ·
`.compare_uncertainty(validation)`.

`analysis$sample` aporta `x`, `n_used`, `resolution`, `support_label`,
`n_excluded_zeros/negatives`; `analysis$candidates$family` aporta la familia.
Todo lo que B16 necesita está disponible **sin recalcular nada**.

---

## 2. Flujo UX propuesto

### 2.1 Navegación: `bslib::navset_hidden`

**Mecanismo mínimo y robusto, sin dependencias nuevas.** El panel principal
actual se envuelve en:

```
navset_hidden(id = "vista",
  nav_panel_hidden("analisis",       <panel actual, sin tocar>),
  nav_panel_hidden("incertidumbre",  <vista dedicada>))
```

Entrada: `bslib::nav_select("vista", "incertidumbre")` desde el CTA.
Salida: `nav_select("vista", "analisis")` desde «← Volver al análisis».

**Por qué ésta y no otras.** `renderUI` que sustituya el panel destruiría y
recrearía plotly y DT en cada ida y vuelta. `conditionalPanel` exige que el
estado viva en JS. Un modal contradice el requisito. `navset_hidden` mantiene
ambos paneles en el DOM y es de `bslib`, ya en el stack.

**Cautela a mitigar:** los outputs de un panel oculto se **suspenden**; al
volver, se re-renderizan. `analysis()` es `eventReactive`, de modo que **no se
recalcula estadística** —el contrato §2 se cumple—, pero sí habría un
re-dibujado de ~1–2 s. Mitigación: `outputOptions(output, "grafico_ajuste",
suspendWhenHidden = FALSE)` para los tres gráficos y las dos tablas pesadas.

### 2.2 CTA en la pantalla principal

Tarjeta al final del panel, antes de la exportación:

> **Incertidumbre de parámetros**
> Evalúa la precisión de los parámetros estimados.
> `[ Explorar incertidumbre → ]`

Deshabilitada mientras no exista `analysis()`.

### 2.3 Vista dedicada

```
← Volver al análisis
INCERTIDUMBRE DE PARÁMETROS
Analizando: Lognormal · MLE          ← selección del ranking (ADR-029)
Muestra modelizada: n = 1.234 · soporte (0, Inf) · 200 ceros excluidos

[1] Incertidumbre analítica          ← inmediata si B12 la da
[2] Incertidumbre bootstrap          ← solo bajo demanda
[3] Comparación descriptiva          ← solo si B15 = available
▸ Reproducibilidad y detalles técnicos
```

### 2.4 Estados vacíos y de error

| Situación | Qué se muestra |
|---|---|
| Sin análisis | CTA deshabilitado |
| MLE con B12 `complete` | Tabla analítica inmediata |
| MLE con B12 `failed`/`not_available` | Explicación breve + `reason` de B12 en detalles técnicos + oferta de bootstrap. **No se fabrica SE/CI** |
| MoM / L-mom | «La incertidumbre analítica no está disponible para este estimador en v1.1. Puedes calcularla por bootstrap.» |
| Bootstrap no ejecutado | «No se ha calculado bootstrap para esta selección.» + botón |
| Bootstrap con `B_success = 0` | «Ninguna réplica produjo un ajuste válido», con motivos agrupados |
| Bootstrap con `B_success = 1` | Sin SE; se declara que una sola réplica no permite publicar incertidumbre |
| B15 `not_comparable` | Las dos tablas por separado + nota de que no se ha verificado que correspondan a la misma muestra. **Nunca lado a lado como comparación válida** |

---

## 3. Contrato de estado reactivo

### 3.1 Qué se calcula automáticamente y qué no

| Elemento | Cuándo |
|---|---|
| `analysis()` | Solo al pulsar «Calcular» (**sin cambios**) |
| Incertidumbre **analítica** | Al entrar en la vista, para la distribución seleccionada. Coste ≈ 9 evaluaciones de log-verosimilitud: despreciable |
| **Bootstrap** | **Solo** al pulsar `[ Calcular incertidumbre bootstrap ]` |
| B14 / B15 | Derivados; se recalculan cuando cambia cualquiera de sus entradas. Son organización, no inferencia |

**Prohibido disparar bootstrap** al cargar la app, al seleccionar distribución,
al clicar el ranking, al entrar en la vista, al cambiar la leyenda o al entrar
en comparación.

### 3.2 Identidad del resultado bootstrap — **opción A**

**Se conserva un único resultado bootstrap** en un `reactiveVal`, junto a la
clave de configuración con la que se produjo:

```
key = list(distribution, estimator, sample_fingerprint, B,
           confidence_level, seed, pm_percentiles)
```

Se muestra **si y solo si** `identical(key_guardada, key_actual)`. Si no,
«No se ha calculado bootstrap para esta selección.»

**Por qué A y no un cache.** El escenario del encargo —Lognormal → bootstrap →
volver → Gamma → volver— se resuelve con una comparación de igualdad. Un cache
keyed añadiría gestión de tamaño, desalojo e invalidación para ahorrar una
reejecución de 2–12 s que el usuario ha pedido explícitamente. Coherente con la
regla del proyecto: simplicidad sobre complejidad.

**`sample_fingerprint` en la clave, no `n`.** Es la lección de OD-18: dos
muestras distintas con el mismo `n` no son la misma muestra. Se lee de
`analysis$sample` mediante el helper existente, sin recalcular nada nuevo.

**`seed` en la clave: decisión que conviene confirmar.** Incluirla significa que
editar el campo oculta el resultado anterior hasta reejecutar. Es una regla
única, sin excepciones, y **hace imposible mostrar un resultado cuya semilla no
coincida con la que se ve en pantalla** — precisamente la inconsistencia
silenciosa que el proyecto viene evitando. El coste es que un cambio accidental
del campo obliga a recalcular. La alternativa —dejar `seed` fuera de la clave y
mostrar siempre la semilla congelada del resultado— evita ese coste a cambio de
permitir que campo y resultado discrepen en pantalla. **Recomiendo incluirla.**

### 3.3 Invalidación

El resultado bootstrap deja de mostrarse —sin borrarse retroactivamente ni
alterar sus metadatos— cuando cambia: la distribución seleccionada, el
estimador, el análisis (nuevo `Calcular`, que cambia el fingerprint), `B`, el
nivel de confianza, la semilla o la configuración PM.

---

## 4. Contrato de reproducibilidad

### 4.1 Ciclo de vida de la semilla

1. Al entrar en la vista, si no hay semilla, la app propone una válida.
2. El usuario puede editarla. `[ Generar otra ]` propone otra.
3. Al ejecutar, la semilla se **congela dentro del resultado** junto al resto de
   la clave.
4. Editar el campo después **no altera** los metadatos del resultado ya
   producido; solo deja de considerarse vigente (§3.2).

**Límites que ya impone B13** (`.validate_bootstrap_seed`): escalar numérico,
finito, entero. La UI debe validar contra eso, no inventar otros.
`.validate_bootstrap_B`: escalar finito entero ≥ 1 — pero en v1.1 **B se elige
de una lista cerrada** (500 / 1000 / 2000 / 5000, defecto 1000), sin valor
libre.

### 4.2 Pasaporte

| Bloque | Campos | Origen |
|---|---|---|
| Análisis | `distribution`, `estimator`, `uncertainty_method`, `B_requested`, `B_success`, `B_failed`, `confidence_level`, `seed`, `pm_percentiles` | B13/B14 verbatim |
| Datos | `n_used`, `data_fingerprint`, `fingerprint_algo`, `fingerprint_status` | B13/B14 verbatim |
| Software | `tool_name`, `tool_version`, `schema_version` | `manifest` + `DFIT_SCHEMA_VERSION` |

Se presenta dentro de `▸ Reproducibilidad y detalles técnicos`.

**Fuera de v1.1:** biblioteca de configuraciones, «Mis configuraciones»,
persistencia, importar/restaurar sesiones, duplicar configuraciones, gestor de
configuraciones. La reproducibilidad de v1.1 es **registrar, mostrar y
exportar**.

---

## 5. Contrato visual

### 5.1 Tablas

Tres tablas `DT`, con la misma estética que las existentes:

- **Analítica**: parámetro · estimación · SE · IC · nivel.
- **Bootstrap**: parámetro · estimación · SE · IC · nivel, más el bloque de
  réplicas solicitadas / exitosas / fallidas.
- **Comparación** (solo con B15 `available`): las seis columnas de
  `.compare_uncertainty()$parameters`, **sin ninguna columna derivada**.

### 5.2 Gráfico de distribución bootstrap

Uno por parámetro, con `plotly` —ya en el stack y ya usado—, construido sobre
`bootstrap$replicates[, j]`:

- histograma o densidad de las réplicas válidas;
- línea vertical de la **estimación puntual oficial**;
- dos líneas o banda para los extremos del IC percentil;
- título con el nombre del parámetro y el nivel de confianza.

**Overlay analítico opcional y descriptivo:** cuando B12 esté disponible, una
marca de los extremos del IC analítico, visualmente distinguible y etiquetada.
**Sin puntuación de acuerdo, sin solapamiento cuantificado, sin semáforo, sin
clasificación, sin interpretación automática.**

**Coherencia con el Visual Engine (§3e de `calc.R`):** los datos del gráfico
deben producirse en `calc.R` —una función que transforma réplicas en un dataset
numérico— y `mod_tool.R` limitarse a dibujarlos. Es la regla vigente: el módulo
no calcula.

### 5.3 Diagnósticos

Se muestran los textos que **ya producen** B14 y B15 (`diagnostics`,
`limitations`), sin reescribirlos ni añadir juicios. Incluye la advertencia
neutral de OD-17 cuando corresponda.

### 5.4 Responsive

`bslib::layout_columns` con las mismas proporciones que la ficha técnica actual;
una columna en pantallas estrechas.

---

## 6. Resultado público y schema

### 6.1 Propuesta: **estructura paralela, schema intacto**

Hay precedente en el propio proyecto. El Visual Engine **no forma parte del View
Model**: `build_visual_data()` devuelve «una estructura independiente que la UI
consume junto al VM». B16 debe seguir ese patrón:

```
prepare_view_model(analysis)      →  view_model            (schema 1.1.0)
build_visual_data(analysis, data) →  visual_data           (paralelo)
build_uncertainty_view(...)       →  uncertainty_data      (paralelo, NUEVO)
```

**Consecuencia: `DFIT_SCHEMA_VERSION` se mantiene en 1.1.0.** No hay campo nuevo
en el resultado público, luego no hay cambio de schema que versionar. Si en
cambio se colgara `view_model$uncertainty`, por la convención del propio
proyecto —ADR-026 añadió el bloque `sample` y llevó el schema a 1.1.0— tocaría
**1.2.0**, en contra del objetivo declarado de release.

La única excepción razonable es `meta$seed`, que **ya existe** como
`NA_integer_` con un comentario que anticipa este uso: rellenarlo es ocupar un
hueco previsto, no ampliar el contrato.

### 6.2 Estructura de `uncertainty_data`

```
uncertainty_data = list(
  selection   = list(distribution, distribution_label, estimator, n_used,
                     support, conditional, conditional_note),
  analytic    = list(status, reason, confidence_level, parameters = <df>),
  bootstrap   = list(status, reason, confidence_level, B_requested, B_success,
                     B_failed, success_rate, seed, quantile_type,
                     failures, parameters = <df>, plots = <por parámetro>),
  comparison  = <salida de .compare_uncertainty(): status + tabla>,
  reproducibility = list(analysis = , data = , software = ),
  diagnostics = character(), limitations = character()
)
```

**Obligatorios:** `selection`, `reproducibility$data`, `reproducibility$software`.
**Opcionales:** `analytic` (`NULL` si no aplica), `bootstrap` (`NULL` mientras no
se ejecute), `comparison` (`NULL` si no hay dos vías).

**Las réplicas NO viajan en esta estructura**; permanecen en el resultado de B13
guardado en el `reactiveVal` de sesión, y solo se usan para dibujar.

---

## 7. Contrato de exportación

### 7.1 Mecanismo: **tercera instancia del módulo existente**

`mod_export_csv_ui/server` ya se instancia dos veces. Una tercera, dentro de la
vista de incertidumbre, con su propio `data.frame` plano y su propio nombre de
fichero. **No se crea una familia nueva de formatos y no se toca el módulo
compartido.**

### 7.2 Por qué no extender `export_table`

`export_table` tiene **una fila por distribución del ranking**. La incertidumbre
tiene **una fila por parámetro de una sola distribución**. Son granos distintos;
mezclarlos obligaría a rellenar con `NA` o a duplicar filas, y rompería el
significado actual de una exportación que ya está validada.

### 7.3 Contenido

Una fila por parámetro, con las columnas de identificación repetidas —formato
plano, apto para Excel:

```
distribucion · estimador · parametro · estimacion ·
se_analitico · ic_analitico_inf · ic_analitico_sup · nivel_analitico ·
se_bootstrap · ic_bootstrap_inf · ic_bootstrap_sup · nivel_bootstrap ·
b_solicitadas · b_exitosas · b_fallidas · seed ·
n_modelizada · fingerprint · herramienta · version_herramienta · version_schema
```

Más una columna `limitaciones` con los textos de B14/B15 concatenados.

**No se exportan por defecto las réplicas individuales.**

---

## 8. Recomendación de versionado

**Opción B: `manifest` permanece en 1.0.2 durante B16; el bump a 1.1.0 lo hace
B17.**

Razones: el proyecto ya versiona **estado validado**, no estado implementado
—1.0.2 se fijó tras validar las correcciones de ADR-029, no al escribirlas—; el
`manifest` es la fuente de la versión mostrada en la interfaz, de modo que
anunciar 1.1.0 antes de la validación integral mostraría al usuario una versión
que aún no existe; y B17 es explícitamente el bloque de validación integral y
release.

`DFIT_SCHEMA_VERSION` se mantiene en **1.1.0** por §6.1.

---

## 9. Ficheros que cambiarían en B16.1

| Fichero | Cambio |
|---|---|
| `R/calc.R` | Nueva sección **3f**: `build_uncertainty_view()` y el dataset del gráfico bootstrap. Rellenar `meta$seed`. **Sin tocar** B12–B15 ni ninguna capa estadística |
| `R/mod_tool.R` | `navset_hidden`, CTA, vista dedicada, controles, `reactiveVal` del bootstrap, tercera instancia de exportación |
| `tests/b16_ui_tests.R` | Nuevo |
| `docs/decisions_log.md` | ADR-039 |
| `docs/tool02_b16_contract.md` | Este documento |

**No cambian:** `app.R`, `manifest.yml` (hasta B17), `decision_engine.md`,
`shared/`, `renv`, ni las suites B11.2–B15.

---

## 10. Plan de pruebas

**Unitarias (`calc.R`)** — `build_uncertainty_view()` con las siete
combinaciones de estado de B14/B15; dataset del gráfico coherente con
`replicates`; ausencia de réplicas en la estructura; pasaporte completo;
`meta$seed` poblado solo tras ejecutar.

**Reactivas (`testServer`)** — el bootstrap **no** se dispara al entrar en la
vista, al cambiar de fila del ranking ni al navegar; sí al pulsar el botón;
cambiar de distribución **oculta** el resultado anterior; el resultado
reaparece al volver a la selección original solo si la clave coincide;
`analysis()` **no** se reevalúa al navegar; la semilla congelada no cambia al
editar el campo.

**Exportación / schema** — el CSV de incertidumbre contiene una fila por
parámetro y ninguna réplica; `export_table` **intacta**;
`schema_version == "1.1.0"`.

**UX manual** — protocolo corto en la línea del `ACCEPTANCE_MANUAL` existente.

**Regresión** — las 18 suites actuales.

---

## 11. Riesgos y bloqueos reales

### R1 — **CONTRACT INCONSISTENCY · BLOQUEANTE**

**PM no puede ser hoy «el estimador utilizado».**

- `MOD_METHOD_CHOICES` ofrece `mle`, `auto`, `mom`, `lmom`. **No incluye PM.**
- `dist_fit_analyze(method = match.arg(c("mle","mom","lmom","auto")))` **no
  acepta `"pm"`**.
- `.motor()` **rechaza explícitamente** `method = "pm"` con `stop()` — guarda
  deliberada de B11.2, porque comparar por AIC un ajuste PM con uno MLE exige
  una decisión que B11.1 no tomó.
- **OD-15** (exposición de PM en la interfaz y su relación con el ranking) sigue
  **OPEN / DEFERRED TO B16**.

El §11 del encargo asume que PM puede ser el estimador de un análisis; hoy no
puede serlo. **Requiere decisión antes de B16.1.** Tres caminos:

| | Camino | Consecuencia |
|---|---|---|
| **(a)** | PM entra en el selector y en `.motor()` | PM entra en ranking y AIC: **reabre lo que B11.2 cerró**. Requiere resolver OD-15 con criterio propio de comparación. Alcance grande |
| **(b)** | PM queda fuera de la vista de incertidumbre en v1.1 | Se retira §11. Coste: PM sigue sin ninguna medida de incertidumbre, que era su carencia declarada |
| **(c)** | **PM como estimador alternativo DENTRO de la vista** | En la vista, sobre la distribución **ya seleccionada**, se ofrece «estimar también por Percentile Matching» con su preset. Se llama a `.pm_fit()` y se bootstrapea con `.bootstrap_adapter_pm()`. **PM no entra en `.motor()`, ni en el ranking, ni en AUTO, ni en la recomendación.** OD-15 se resuelve en su mitad mínima |

**Recomiendo (c).** Es la única que satisface §11 sin reabrir B11.2 ni tocar el
Decision Engine, y encaja con lo que ya está construido: `.bootstrap_adapter_pm()`
existe y está validado. Pero **es una decisión del owner**, no mía.

### R2 — ENVIRONMENT WARNING

Los outputs de un `nav_panel` oculto se suspenden y se re-renderizan al volver.
No recalcula estadística —`analysis()` es `eventReactive`— pero sí redibuja
(~1–2 s medidos en el protocolo de aceptación). Mitigación conocida:
`suspendWhenHidden = FALSE` en los outputs pesados.

### R3 — METHODOLOGICAL LIMITATION

Con `B = 5000` sobre Burr, la extrapolación del coste por ajuste medido en
B11.1 da ≈ 12 s sin retroalimentación. Mitigación: `bmk_loading` ya existe y se
usa; además `B = 1000` es el defecto.

### R4 — CONTRACT INCONSISTENCY · menor

`.vm_meta()` fija `seed = NA_integer_` incondicionalmente. Rellenarlo requiere
que `prepare_view_model()` reciba la semilla, o dejarlo en `NA` y publicarla
solo en `uncertainty_data`. **Recomiendo lo segundo**: menos superficie tocada y
el `view_model` no depende de un estado que puede no existir.

### R5 — Documental

Los ficheros `visual_engine.R`, `export.R` y `schema*` mencionados en el encargo
**no existen**. Ningún riesgo técnico, pero el plan de B16.1 debe escribirse
contra la estructura real.

**Ningún PRODUCT BUG, TEST DEFECT ni EXPERIMENTAL ISSUE detectado.**

---

## 12. Fuera de alcance — confirmado

`B` personalizado · configuraciones guardadas · gestor de configuraciones ·
restaurar/importar · métricas automáticas de acuerdo · etiquetas de estabilidad
o calidad · umbrales · MSE · corrección de sesgo · BCa · bootstrap-t · bootstrap
paramétrico para incertidumbre de parámetros · GoF bootstrap (ADR-008) ·
incertidumbre analítica para MoM/L-mom/PM · propagación a VaR/TVaR/ES ·
incertidumbre de selección de modelo (H4) · EVT/POT/GPD · bayesiano/MCMC · PM en
AUTO · distribuciones nuevas.

**OD-11 y OD-17 permanecen abiertas y sin tocar.** No se abre ninguna OD nueva:
R1 se resuelve dentro de **OD-15**, que ya existe y estaba asignada a B16.

---

## 13. Veredicto

**READY WITH MINOR CLARIFICATIONS.**

Una sola decisión bloquea B16.1: **R1 — el papel de PM en la vista de
incertidumbre** (caminos a / b / c, recomendado **c**).

Conviene confirmar además dos elecciones ya razonadas: **`seed` dentro de la
clave de identidad** del resultado bootstrap (§3.2) y **estructura paralela sin
tocar el schema** (§6.1).

---

*Actuarial Tools by BMK — B16.0, contrato propuesto. Sin implementación.*
