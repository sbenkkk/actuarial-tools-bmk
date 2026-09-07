# Tool-02 — Auditoría de Release (B9)

| Campo | Valor |
|---|---|
| **Herramienta** | Tool-02 — Ajuste de Distribuciones (`distribution-fitting`) |
| **Versión** | 1.0.0 |
| **Fecha de auditoría** | 2026-07-25 |
| **Arquitectura de referencia** | `docs/architecture_v2.md` (v2.0, Approved) — checklist §11 |
| **Diseño de referencia** | `tool_02_distribution_fitting_design.md` (v1.0, Approved) |
| **Estado del código** | **Code-complete** (B0–B8 APPROVED) + ronda de mantenimiento ADR-017…025 cerrada (§5) |
| **Estado de publicación** | **Pendiente de despliegue** (ver §3) |
| **Última verificación global** | 14 scripts · 10 `[PASA]` · 4 `[PASA/WARN]` · **0 `[FALLA]`** · 0 `[ERROR-VERIF]` |

Documento de cierre de B9. No añade funcionalidad: audita el cumplimiento de la checklist maestra de "Tool terminada" (§11), declara las desviaciones y el alcance diferido, y enumera las acciones que restan para la publicación.

---

## 1. Checklist §11 — verificado

### 11.1 Funcional

| Ítem | Estado | Evidencia |
|---|---|---|
| CSV subido + "generar datos de ejemplo" | ✅ | `mod_data_input` con `example_data.csv` (60 filas) |
| Contrato de columnas + `bmk_validate_data()` probada con error real | ✅ | `expected_columns = c(loss_amount = "numeric")`; `b8_smoke_test.R` §2 verifica caso inválido |
| Resultado numérico verificado contra caso conocido | ✅ | Parámetros y `logLik` de las 11 distribuciones contrastados con **SciPy** en 5 ficheros de test |
| Al menos un gráfico principal | ✅ | 3 gráficos: ajuste (histograma/PMF + densidades + KDE), QQ, PP |
| Tabla de resultados | ✅ | Ranking en `DT` desde el View Model |
| Caja de interpretación dinámica y específica | ✅ | Texto de los Text Builders (B5); test de determinismo y de consumo puro |
| Exportación CSV funcional | ✅ | `mod_export_csv` sobre `export_table` del View Model |
| Extremo a extremo sin tocar inputs | ✅ | `b8_smoke_test.R` §3 (validado en ejecución real) |

### 11.2 Visual

| Ítem | Estado | Evidencia |
|---|---|---|
| Solo componentes de `shared/`, sin CSS/HTML suelto | ✅ | 0 ocurrencias de `tags$style` / `HTML()` / `includeCSS` |
| Paleta respetada sin excepciones | ✅ | 0 literales hex en `mod_tool.R`; colores vía `bmk_colors`; el View Model emite tokens semánticos |
| Header y footer estándar | ✅ | `bmk_header_ui()` / `bmk_footer_ui()` en `app.R` |
| No se rompe en 1366 × 768 | ⏳ | **Verificación visual pendiente** (§3) |

### 11.3 Técnico

| Ítem | Estado | Evidencia |
|---|---|---|
| `app.R` sin lógica de cálculo | ✅ | 0 llamadas a motor/estadística |
| `calc.R` ejecutable sin Shiny | ✅ | 0 referencias a `shiny::`/`reactive`/`input$`; los 7 tests unitarios lo cargan aislado |
| `mod_tool.R` con patrón de módulo y namespacing | ✅ | `NS(id)` + `moduleServer` |
| `manifest.yml` completo, semver, coincide con la interfaz | ✅ | `version: 1.0.0`; el smoke test comprueba que el View Model refleja la versión del manifest |
| View Model declara `schema_version` (+ `decision_engine_version`) | ✅ | `schema_version = "1.0.0"`, `decision_engine_version = "0.1"` |
| Validez estadística con parámetros estimados (regla 18) | ✅ | **No se publican p-valores**: se reportan solo estadísticos; los p-valores quedan diferidos hasta disponer de bootstrap paramétrico (ADR-008) |
| `Standard` por defecto y perfil registrado (regla 19) | ✅ | Selector por defecto `standard`; viaja en `meta.analysis_depth` |
| `README.md` con qué hace, columnas y limitaciones | ✅ | Presente y actualizado por bloque |
| Cero errores y warnings en consola | ✅ | 454 warnings de fuentes diagnosticados y resueltos; smoke test con aserción automática de ausencia |
| Probada con CSV real o realista | ⚠️ | **Hueco declarado**: el ejemplo es sintético (§2) |
| Límites de datos §7.5 aplicados | ✅ | `shared/config.R` (10 MB / 100.000 filas) vía framework |
| Disclaimer de privacidad y uso visible | ✅ | `bmk_footer_ui()` |

---

## 2. Desviaciones y alcance diferido (declarados)

Tool-02 v1.0 implementa un **subconjunto explícitamente acordado** del diseño aprobado. Cada acotación fue decidida por el owner en el gate del bloque correspondiente. Se declara aquí para que nadie asuma que el §7 está completo:

| Elemento del diseño | Estado en v1.0 | Motivo / referencia |
|---|---|---|
| **Pilar C** (cola: índice de cola, mean-excess, error VaR/TVaR) | No implementado | Fuera del alcance de B3 (acotado por el owner) |
| **Pilar D** (estabilidad por bootstrap) | No implementado | Requiere infraestructura de remuestreo |
| **Pilar E** (validación cruzada) | No implementado | Ídem |
| **Fase 1 del criterio** (categorías absolutas Excelente…Rechazada) | Diferido | Requiere p-valores válidos (ADR-008); decisión del owner en B4 |
| **Nivel 2** (adecuación por uso, estrellas Pricing/Reserving/Capital) | Diferido | Requiere Pilares C y D |
| **Detección EVT → Tool-03** | Diferido | Requiere Pilar C |
| **Gráficos mean-excess y VaR/TVaR** | Diferido | Requieren Pilar C |
| **p-valores de bondad de ajuste** | No publicados | Decisión correcta: no reportar p-valores inválidos (ADR-008) |
| **Método por defecto** | `mle` en lugar de `auto` | Desviación menor del §11.1 del diseño, aprobada (**ADR-015**) |
| **Calibración de `decision_engine.md`** | Provisional (v0.1) | Pesos A=0,7 / B=0,3 y umbrales de confianza sin calibrar contra datasets de distribución conocida |

En consecuencia, la evaluación vigente pondera **ajuste global y parsimonia** y emite **ranking relativo + recomendación Nivel 1 con nivel de confianza**. La interfaz declara explícitamente lo diferido, de modo que el usuario no infiere capacidades ausentes.

**Nota sobre el marcador `view_model` del objeto de análisis.** `b1_unit_tests.R` comprueba que `dist_fit_analyze()` devuelve `view_model` con estado `"pending"`. **No es un error**: el View Model no se embebe en el objeto de análisis, se construye con la función pública `prepare_view_model()` (patrón heredado de Tool-01). La aserción refleja esa separación correctamente; lo único mejorable es la **etiqueta** `"pending"`, que induce a pensar que B6 está sin implementar. Revisable en el futuro mediante ADR; no afecta a resultados ni a la interfaz.

---

## 3. Acciones pendientes para la publicación (§11.4)

Corresponden al owner; no son de código:

1. **Probar con un CSV real o realista** de siniestralidad (§11.3). El `example_data.csv` incluido es sintético (lognormal generada), suficiente para desarrollo y test, pero la checklist exige al menos una prueba con datos reales antes de publicar.
2. **Revisión visual en 1366 × 768** (§11.2).
3. **Desplegar** en shinyapps.io y obtener URL (§11.4).
4. **Captura o GIF** de demostración (§11.4).
5. **Marcar la entrada** en `ROADMAP.md` como terminada y actualizar `manifest.yml`: `status: published` y `published_date`.

Hasta completar 1–5, Tool-02 queda como **code-complete y auditada**, no como *publicada*.

---

## 4. Inventario de entregables

```
tools/distribution-fitting/
├── app.R                                   orquestación (regla 6/15)
├── R/calc.R                                motor: Profiler -> ... -> Visual Engine (B1-B7)
├── R/mod_tool.R                            interfaz Shiny (B8)
├── data/example_data.csv                   ejemplo sintético (60 filas)
├── manifest.yml                            identidad y versión
├── README.md                               documentación de uso y estado
├── RELEASE_AUDIT.md                        este documento
├── tool_02_distribution_fitting_design.md  diseño aprobado (Sprint 0)
├── decision_engine.md                      criterio parametrizado (v0.1)
└── tests/                                  b1..b8 + diagnose_warnings.R
```

Trazabilidad de bloques: B0 · B1 · B2.1 · B2.2 · B3 · B4 · B5 · B6 · B7 · B8 → todos **APPROVED** por el owner, cada uno con su test ejecutado en R real.

---

## 5. Ronda de mantenimiento posterior — incidencias CERRADAS

Detectadas al validar la herramienta con 24 ficheros de muestra reales y al
reejecutar la batería completa. Todas verificadas en R y **cerradas** (2026-08-04).

| ADR | Incidencia | Resolución | Estado |
|---|---|---|---|
| **017** | La importación exigía coma y cabecera: un CSV sin cabecera perdía la primera observación y uno con `;` se leía como una sola columna | Lectura robusta en `shared/modules/mod_data_input.R`: detecta separador (`,`/`;`/tab), detecta cabecera ausente y nombra `Variable_1..n`, tolera BOM y CRLF | ✅ Cerrada |
| **018** | Tool-02 exigía una columna llamada `loss_amount` | `expected_columns = NULL`; el nombre de las columnas deja de validarse y el selector se puebla con las numéricas detectadas | ✅ Cerrada |
| **019** | Chi-cuadrado discreto: una categoría por valor del soporte generaba 48.828 celdas con esperanza 0 → `NaN` y bloqueo de la interfaz | Agrupación de categorías hasta esperanza mínima (5; suelo relajado de Cochran si `n` es pequeño), soporte acotado por cuantil, `NA` documentado si no hay 2 celdas válidas | ✅ Cerrada |
| **020** | Importes enteros de alta cardinalidad se clasificaban como recuento | `discrete_max_unique` calibrado de `Inf` a **50** (parámetro ya previsto por el diseño); la familia sigue siendo forzable a mano | ✅ Cerrada |
| **021** | La confianza salía "baja" casi siempre: se leía de una separación min-máx sin escala comparable entre datasets | Confianza por **ΔAIC** (Burnham & Anderson: <2 baja, 2–10 media, ≥10 alta); la separación del compuesto se conserva como dato descriptivo | ✅ Cerrada |
| **022** | Un CSV sin columnas numéricas solo emitía un aviso flotante, fácil de pasar por alto | Componente compartido `bmk_modal_alert()` y ventana modal bloqueante con las columnas leídas y las causas habituales | ✅ Cerrada |
| **023** | Dos tests de Tool-01 comprobaban un contrato de `downloads` inexistente (`summary`/`curve`) | Alineados con el contrato real y documentado: `diagnostics`/`risk`/`model_summary`. **Fallos preexistentes**, no regresiones | ✅ Cerrada |
| **024** | El smoke test de Tool-01 usaba el bloque `bandwidth` (renombrado a `indicator`) y fijaba solo el slider del bandwidth manual | Aserción alineada con `indicator$h` y se fijan ambos inputs (`h_manual` + `h_manual_num`), que `testServer()` no sincroniza | ✅ Cerrada |
| **025** | El indicador de bandwidth de Tool-01 emitía 50+ avisos por la familia tipográfica `Inter` | Fallback tipográfico local (`.plot_family()` / `.theme_plot()`), sin tocar `shared/theme` ni añadir dependencias | ✅ Cerrada |

**Warnings residuales aceptados.** Los cuatro scripts marcados `[PASA/WARN]` solo
emiten avisos **de entorno**: `package 'shiny'/'bslib' was built under R version
4.4.3` (R 4.4.1 con binarios compilados en 4.4.3). No se corrigen desde el
código; desaparecerían actualizando R o recompilando los paquetes.

---

*Actuarial Tools by BMK — Tool-02 Release Audit (B9) — 2026-07-25; §5 añadido el 2026-08-04.*
