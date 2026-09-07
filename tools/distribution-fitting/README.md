# Ajuste de Distribuciones (Tool-02)

Herramienta de la serie *Actuarial Tools by BMK*. Ajusta automáticamente
distribuciones paramétricas —continuas o discretas— a una variable numérica y
recomienda cuál utilizar y por qué, desde un punto de vista estadístico y
actuarial.

Diseño aprobado: `tool_02_distribution_fitting_design.md` (v1.0). Parametrización
del criterio: `decision_engine.md`. Arquitectura de plataforma:
`docs/architecture_v2.md` (v2.0).

## Estado

**Code-complete (v1.0)** — bloques B0–B8 aprobados y auditoría de release
realizada (`RELEASE_AUDIT.md`). Pendiente de publicación: prueba con CSV real,
revisión visual, despliegue y captura.

**Alcance entregado en v1.0.** La evaluación pondera **ajuste global (Pilar A)** y
**parsimonia (Pilar B)**, y produce **ranking relativo** + **recomendación Nivel 1**
con nivel de confianza. Quedan **diferidos** (decisión de proyecto, ver
`RELEASE_AUDIT.md` §2 y ADR-016): pilares de cola (C), estabilidad (D) y
predicción (E); categorías absolutas (Fase 1); adecuación por caso de uso
(Nivel 2); detección EVT; gráficos mean-excess y VaR/TVaR; y p-valores de bondad
de ajuste. La interfaz declara explícitamente lo diferido.

Arquitectura por capas: Profiler → Motor → Diagnostics → Assessment →
Text Builders → View Model ↘ Visual Engine → UI Shiny.

- ✅ **B0 — Andamiaje.** La aplicación arranca sobre el framework compartido con
  la identidad de la herramienta.
- ✅ **B1 — Infraestructura del motor (capa 0 + cableado).** `R/calc.R` implementa
  el **Data Profiler** (`profile_dataset`), el **detector de tipo de variable**
  (`detect_variable_type`, §3.3), el **selector de candidatas** por familia
  (`select_candidate_distributions`, §4) y el **cableado** del pipeline
  (`dist_fit_analyze`).
- 🟡 **B2 — Motor de estimación (Capa 1).** En curso, en dos incrementos:
  - ✅ **B2.1 — MLE** (APPROVED, congelado): ajuste por máxima verosimilitud de
    las 7 candidatas continuas + Normal de control y las 3 discretas (`.motor`),
    devolviendo parámetros, `logLik` y convergencia; tratamiento explícito de
    ceros para distribuciones estrictamente positivas (§3.5). Implementación
    propia sobre `optim()`/`optimize()` (ver *Notas técnicas*).
  - 🟡 **B2.2 — MoM + L-momentos + AUTO** (implementado): Método de los Momentos
    (donde el momento existe: no en burr; loglogística/pareto solo con forma > 2;
    negbin solo con sobredispersión) y L-momentos (exponencial, normal, pareto;
    resto diferido). Selección **AUTO** (opt-in vía `method="auto"`): MLE-first con
    fallback por no-convergencia. El **método por defecto sigue siendo MLE**
    (`method="mle"`), por decisión del owner para preservar los contratos de test
    congelados; AUTO se activa explícitamente (ADR-015).
  Evaluación, texto y View Model siguen como *stubs* (B4–B6).
- 🟡 **B3 — Diagnostics (Capa 2)** (implementado): por cada ajuste convergente,
  bondad de ajuste —KS, Cramér-von Mises y Anderson-Darling en continua;
  chi-cuadrado y sobredispersión en discreta— y criterios de información (AIC,
  AICc, BIC); objeto `diagnostics` (`per_fit` + `control`). **Sin p-valores**
  (con parámetros estimados exigen bootstrap paramétrico, ADR-008; diferido) y
  sin ranking ni recomendación (B4+).
- 🟡 **B4 — Assessment (Capa 3)** (implementado, alcance A+B): normalización de
  métricas, pilares A (ajuste) y B (parsimonia), score compuesto (pesos de
  `decision_engine.md`), **ranking relativo**, desempates (parsimonia → AIC → id)
  y **recomendación Nivel 1** con nivel de confianza, calculado sobre el **ΔAIC**
  entre la 1.ª y la 2.ª candidata (criterio de Burnham & Anderson: < 2 baja,
  2–10 media, ≥ 10 alta; ADR-021). **Diferido** (requiere
  pilares C/D o p-valores): categorías absolutas (Fase 1), detección EVT,
  adecuación por uso (Nivel 2) y estabilidad. Sin texto ni ViewModel (B5–B6).
- 🟡 **B5 — Text Builders (Capa 4)** (implementado): consumidor **puro** de las
  capas anteriores (no calcula estadística ni llama hacia atrás). Genera
  `summary`, `recommendation` (resumen ejecutivo, confianza, motivo principal,
  alternativas), `insights` (por qué ganó, fortalezas, debilidades,
  observaciones), `distribution_cards` (una por candidata, incluidas las
  descartadas) y `warnings` (derivados **solo** de flags ya existentes: ceros y
  negativos excluidos, método alternativo, descartes, datos insuficientes).
  Texto plano determinista, sin HTML, markdown, iconos ni i18n (eso es B6).
- 🟡 **B6 — ViewModel (Capa 5)** (implementado): `prepare_view_model()` construye
  el payload de presentación del §12 (meta con `schema_version` y
  `decision_engine_version`, `input_summary`, `dataset_diagnosis`, `metric_cards`,
  tabla de `ranking` para DT, `recommendation`, `fits`, `plots`, `interpretation`,
  `warnings`, `export_table` y `presentation` con orden, iconos y tonos).
  Presentación pura: no calcula, no altera el ranking y no genera texto nuevo.
  Los **colores** se emiten como *tokens semánticos* (nunca hex: `calc.R` no
  depende de `shared/theme`, regla 16) y los **iconos** como nombres de `bsicons`.
  La sección `plots` es **especificación sin datos**: la evaluación de las
  funciones ajustadas corresponde al **Visual Engine (B7)**.
- 🟡 **B7 — Visual Engine** (implementado): `build_visual_data()` genera los
  datasets numéricos de los gráficos consumiendo **solo** los parámetros ya
  ajustados en B2 (no reestima). Incluye rejilla de evaluación, PDF/PMF ajustadas
  por candidata, histograma (Sturges), ECDF, KDE gaussiano (Silverman), QQ y PP
  de la distribución recomendada. `mean_excess` y `var_tvar` siguen diferidos
  (requieren Pilar C). Devuelve una estructura **independiente** del ViewModel:
  la UI consume ambos (VM para presentación, visual data para los gráficos).
- 🟡 **B8 — Interfaz Shiny** (implementado): `R/mod_tool.R` renderiza la
  herramienta consumiendo **solo** el ViewModel (B6) y los datos del Visual
  Engine (B7). Sidebar con carga de datos, selección de variable, método de
  estimación y profundidad; panel principal con metric cards, gráfico de ajuste
  (histograma/frecuencias + densidades ajustadas + KDE), QQ y PP, tabla de
  ranking (DT), caja de interpretación y exportación CSV. Sin lógica
  estadística, de decisión ni generación de texto; solo componentes de
  `shared/` (regla 16).

Tests unitarios deterministas: `tests/b1_unit_tests.R` (profiler, detector,
selector, cableado), `tests/b2_unit_tests.R` (motor MLE), `tests/b2_2_unit_tests.R`
(MoM, L-momentos y AUTO), `tests/b3_unit_tests.R` (diagnostics: GoF + AIC/BIC) y
`tests/b4_unit_tests.R` (assessment: score, ranking, recomendación) y
`tests/b5_unit_tests.R` (text builders: estructura, consumo puro, determinismo y
avisos) y `tests/b6_unit_tests.R` (view model: secciones del §12, copia fiel, presentación
y spec de gráficos), `tests/b7_unit_tests.R` (visual engine: histograma, KDE,
QQ, PP y pureza) y `tests/b8_smoke_test.R` (interfaz de extremo a extremo con
`shiny::testServer`); las referencias estadísticas se calculan con
`numpy`/`scipy`. Ejecutar desde la carpeta de la herramienta, p. ej.
`Rscript tests/b8_smoke_test.R`.

## Datos de entrada

La herramienta acepta **cualquier CSV**: los nombres de las columnas **no forman
parte de la validación** (ADR-018). La única exigencia es que exista **al menos
una columna numérica**; tras cargar el archivo, el selector *Variable a
modelizar* se rellena automáticamente con las columnas numéricas detectadas.

La importación es robusta (ADR-017):

| Situación | Comportamiento |
|---|---|
| Separador `,`, `;` o tabulador | Se detecta automáticamente |
| Sin cabecera (la primera fila ya son datos) | Se detecta, se relee el archivo y las columnas se nombran `Variable_1`, `Variable_2`, … **sin perder la primera observación** |
| Con cabecera | Se conservan los nombres originales |
| BOM / saltos de línea CRLF | Tolerados |
| Sin columnas numéricas | Se avisa al usuario y no se habilita el cálculo |

Los decimales deben usar **punto**. Límites: 10 MB y 100.000 filas (apartado 7.5).
El CSV de ejemplo incluye `policy_id`, `claim_id`, `date_occurred`,
`loss_amount` y `exposure`.

### Muestra común: qué se modeliza exactamente (ADR-026)

Todas las candidatas de un mismo ranking se ajustan sobre **exactamente las
mismas observaciones**. La muestra se restringe una sola vez, antes de estimar
nada, al **soporte común** a todas ellas:

| Familia | Soporte común | Ceros |
|---|---|---|
| **Continua** | `(0, Inf)` — cinco de las siete candidatas exigen soporte estrictamente positivo | **Se excluyen** |
| **Discreta** | enteros no negativos — las tres candidatas los admiten | **Se conservan** |

No es un detalle interno: la comparación por AIC solo es válida entre modelos
ajustados a **datos idénticos**. Si cada distribución recortase la muestra a su
gusto, el ranking compararía magnitudes incomparables.

**Consecuencia actuarial que debes tener presente.** Con una variable de coste
que vale 0 cuando no hubo siniestro —lo habitual en una cartera—, la herramienta
modeliza la **severidad condicionada a que exista coste**, `X | X > 0`, no la
variable completa. La aplicación lo declara explícitamente: el aviso indica
cuántos ceros se han excluido y el resumen de la interpretación anuncia la
muestra realmente modelizada, no el total de observaciones válidas. Si lo que
necesitas es la distribución de la pérdida agregada por póliza (con su masa en
cero), este no es el modelo adecuado: hace falta un modelo de frecuencia +
severidad, o una familia con inflación de ceros (fuera del alcance de v1).

## Cómo se usa

`shiny::runApp("tools/distribution-fitting")` → "Datos de ejemplo" (o subir un
CSV) → elegir la **variable a modelizar** → "Calcular". La herramienta detecta si
la variable es continua o discreta, ajusta las candidatas de esa familia y
muestra la recomendación, el ranking, los gráficos de ajuste (histograma +
densidades, QQ, PP) y la interpretación; los resultados se exportan a CSV.
Funciona de extremo a extremo sin tocar ningún input adicional.

## Arquitectura final (flujo de datos)

```
Motor estadístico (calc.R, sin Shiny)
  Profiler -> Estimation -> Diagnostics -> Assessment -> Text Builders
        |
        v
ViewModel  (prepare_view_model)          contrato único de presentación
        |
        v
Visual Engine (build_visual_data / build_qq_pp_data)
        |
        +-- Visualización PESADA  (se calcula UNA vez por análisis)
        |     · histograma / frecuencias observadas
        |     · KDE empírica
        |     · curvas ajustadas de todas las candidatas
        |
        +-- Visualización LIGERA  (se recalcula al cambiar de distribución)
              · QQ-plot
              · PP-plot
              · ficha técnica (datos ya presentes en el ViewModel)
        |
        v
Interfaz interactiva (mod_tool.R)        solo renderiza; no calcula
```

**Rendimiento.** Un clic durante la exploración **nunca** vuelve a estimar
distribuciones, ni ejecuta Diagnostics o Assessment, ni regenera el histograma,
la KDE o las curvas: todo eso depende únicamente del botón *Calcular*. Al
explorar solo se actualizan la distribución mostrada, QQ, PP, la ficha técnica,
la comparación, el resaltado de curvas y la selección del ranking.

## Flujo de trabajo

La pantalla sigue el razonamiento habitual de un análisis actuarial:

| Paso | Dónde |
|---|---|
| 1. Seleccionar la variable | Sidebar · Datos |
| 2. Elegir el método de estimación | Sidebar · Configuración |
| 3. Ajustar distribuciones | Sidebar · Calcular |
| 4. Ver el resultado y el ajuste | Metric cards + gráfico principal |
| 5. Comparar candidatas | Ranking (y modo comparación) |
| 6. Diagnosticar la elegida | QQ-plot y PP-plot |
| 7. Analizar parámetros, criterios de información y tests | Ficha técnica |
| 8. Entender por qué una es preferible | Comparación con la recomendación |
| 9. Decidir y documentar | Interpretación + exportación CSV |

## Explorador interactivo de distribuciones

El ranking y los gráficos están **sincronizados**. Al hacer clic en una fila del
ranking (o en una entrada de la leyenda del gráfico principal) esa distribución
pasa a ser la **distribución mostrada**: se resalta su curva, se atenúan las
demás y el QQ-plot, el PP-plot, los parámetros y las métricas pasan a
corresponder a ella.

**Distribución recomendada vs distribución mostrada.** Son conceptos distintos y
la interfaz lo declara siempre:

- **Recomendación automática** — la calculada por el Assessment (B4). Aparece en
  la metric card de cabecera y en la interpretación. **Nunca cambia** al explorar.
- **Distribución mostrada** — estado de interfaz. Al recalcular vuelve por
  defecto a la recomendada; si es otra, la tarjeta indica "Exploración manual" y
  recuerda cuál sigue siendo la recomendación oficial.

**Modo comparación.** Permite superponer entre 2 y 4 distribuciones a la vez,
cada una con su color de la paleta categórica de marca, mediante un panel de
casillas sincronizado con la leyenda del gráfico. El histograma y la KDE
permanecen siempre visibles. No se recalcula nada: todas las curvas ya existen en
el Visual Engine; solo cambia cuáles se muestran.

**Ficha técnica.** Organizada en el orden natural de un análisis actuarial:

1. **Identificación** — distribución, estado, método de estimación (indicando si
   se eligió automáticamente o lo fijó el usuario) y número de parámetros.
2. **Parámetros estimados** — nombre y valor.
3. **Criterios de información** — log-verosimilitud, AIC y BIC.
4. **Bondad de ajuste** — Anderson-Darling, Kolmogorov-Smirnov y Cramér-von Mises
   en continua; chi-cuadrado, grados de libertad y sobredispersión en discreta.
   La ficha se adapta automáticamente al tipo de distribución.
5. **Evaluación** — puntuación global, nivel de ajuste y nivel de parsimonia.

**Comparación con la recomendación.** Al explorar una distribución distinta de la
recomendada aparece una tabla que enfrenta ambas (puntuación, AIC, BIC, tests de
bondad de ajuste y número de parámetros) y un bloque **¿Por qué no es la
recomendada?** con observaciones ✔/✘ sobre ajuste, parsimonia y proximidad. Esas
observaciones las redactan los **Text Builders** combinando resultados del
Assessment —sin IA— y la interfaz solo las renderiza. Ningún valor se recalcula.

**Restablecer análisis.** Devuelve la interfaz a su estado inicial (recomendación
oficial, modo comparación desactivado, selecciones limpias) **sin volver a
ejecutar el motor**.

**Ampliaciones futuras preparadas.** `build_qq_pp_data()` es puro y está
parametrizado por distribución, de modo que mostrar varios QQ o PP simultáneos —o
comparar parámetros entre modelos— solo requiere mapear sobre varios ids desde la
interfaz, sin volver a modificar el Visual Engine.

El gráfico principal usa `plotly` (librería aprobada, con `bmk_plotly_layout()`
de `shared/`) porque la interacción con la leyenda no es posible con un gráfico
estático. QQ y PP se mantienen en `ggplot2` y se generan con el bloque ligero del
Visual Engine (`build_qq_pp_data()`), de modo que cambiar de distribución no
recomputa el histograma, la KDE ni las curvas.

## Notas técnicas

**Tipografía de los gráficos.** La identidad visual define `Inter`
(`shared/theme/theme_bmk.R`). Esa familia se sirve al **navegador** como webfont
(`bslib::font_google`), pero los gráficos se dibujan en el **servidor** con el
dispositivo gráfico de R, que solo puede usar fuentes instaladas en el sistema
operativo. Si `Inter` no está instalada (habitual en macOS sin instalarla y en
los servidores Linux de despliegue), el dispositivo ya dibujaba con su fuente
sustitutiva y además emitía un warning por cada elemento de texto. Para evitar
ese ruido sin alterar el aspecto, `mod_tool.R` resuelve la familia una sola vez
(`.plot_family()`): usa `Inter` cuando está realmente disponible y, si no, la
familia por defecto del dispositivo — exactamente la que ya se estaba usando. No
modifica `shared/theme/` (congelado, compartido con Tool-01) ni añade
dependencias. Instalar `Inter` en el sistema devuelve la tipografía de marca a
los gráficos sin ningún cambio de código.

**Estimación MLE en escala logarítmica (`.mle_optim`).** Las estimaciones por
`optim()` (gamma, weibull, loglogística, pareto, burr) se optimizan sobre
`log(parámetros)` en lugar de sobre los parámetros en escala natural. Motivo: los
parámetros de forma y escala tienen magnitudes muy dispares (p. ej. `shape ~ 1`,
`scale ~ 10³`); con L-BFGS-B y gradiente por diferencias finitas ese mal escalado
provoca **convergencia prematura** lejos del máximo (gamma y pareto quedaban por
debajo del MLE; pareto incluso por debajo de su límite exponencial). En escala
logarítmica los parámetros son O(1) (problema bien condicionado) y no requieren
cotas, de modo que el optimizador alcanza el verdadero MLE. El óptimo es idéntico
(misma verosimilitud, distinta coordenada): **no cambia el modelo estadístico ni
la API pública**. Registrado en `docs/decisions_log.md` (ADR-014).

## Limitaciones conocidas

Fuera del alcance de la v1 (según diseño): censura y truncamiento, modelos con
inflación de ceros, selección de umbral para EVT y *splicing* cuerpo-cola.
Límites de datos: 10 MB de archivo, 100.000 filas (apartado 7.5).

## Referencia de cálculo

**Completada.** Todos los resultados numéricos del motor se contrastaron contra
una réplica independiente en `NumPy`/`SciPy`, conforme al apartado 13 del diseño:

| Bloque | Contraste |
|---|---|
| B2 — MLE | Parámetros y `logLik` de las 11 distribuciones frente a `scipy.stats` (`.fit` y optimización propia) |
| B2.2 — MoM / L-momentos | Estimadores replicados fórmula a fórmula |
| B3 — Bondad de ajuste | KS y Cramér-von Mises cruzados con `scipy.stats`; Anderson-Darling por doble implementación; chi-cuadrado y sobredispersión recalculados |
| B7 — Visual Engine | Funciones cuantil propias (loglogística, Pareto, Burr) frente a `scipy` (~1e-12); histograma, KDE (ancho de Silverman), QQ y PP verificados |

Las referencias quedan fijadas como valores esperados en los tests de
`tests/`, que se ejecutan con `bash verificar_adr_019_022.sh` desde la raíz del
repositorio.
