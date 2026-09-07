# Tool-02 — Protocolo de aceptación manual v1.1 (capa de incertidumbre)

| Campo | Valor |
|---|---|
| **Herramienta** | Ajuste de Distribuciones (`distribution-fitting`) — candidata **v1.1.0** |
| **Objeto** | Aceptación manual de la **capa de incertidumbre de parámetros** (B11–B16). **Complementa**, no sustituye, a `ACCEPTANCE_MANUAL.md` (v1.0.x), que sigue siendo el protocolo del flujo principal |
| **Batería automática** | 19 scripts (B1–B16 + ADR + regresión + importación) |
| **Ejecutado por** | |
| **Fecha** | |
| **Resolución de pantalla** | |
| **Versión de R** | |
| **`manifest` en el momento de la prueba** | 1.0.2 *(el bump a 1.1.0 es el ÚLTIMO paso, tras cerrar este protocolo)* |

> **Regla de anotación.** Marcar `PASS` / `FAIL` y, ante cualquier incidencia,
> **clasificarla antes de tocar producción**: `PRODUCT BUG — BLOCKING` ·
> `TEST DEFECT` · `ENVIRONMENT WARNING` · `METHODOLOGICAL LIMITATION` ·
> `UX OBSERVATION`. Solo la primera justifica corregir código en B17.

---

## Preparación

1. Ejecutar **desde la raíz del repositorio** para que `renv` se active.
2. Datasets: `data/samples/continua_gamma.csv`, `continua_lognormal.csv`,
   `continua_pareto_cola_pesada.csv`, `discreta_poisson.csv`,
   `real_cost_claims_reducido.csv`.
3. Tener a mano `/tmp/b16.log` de la última ejecución automática.

---

## 0. Regresión del flujo v1.0 — no debe haberse roto nada

> Ejecutar el protocolo existente `ACCEPTANCE_MANUAL.md` **completo**. Esta tabla
> solo registra los puntos donde B16 pudo haber interferido.

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Obs. |
|---|---|---|---|---|---|
| R-01 | La pantalla principal no cambió | Cargar `continua_gamma.csv` → Calcular | Métricas, gráfico, ranking, QQ/PP, ficha, comparación e interpretación **en el mismo orden y aspecto** que en v1.0 | | |
| R-02 | Nuevo CTA | Mirar al final del panel principal | Aparece la tarjeta **«Incertidumbre de parámetros»** con el botón «Explorar incertidumbre →», **después** de la interpretación y **antes** de la exportación | | |
| R-03 | ADR-029 · ranking | Clicar una fila del ranking | Cambia la curva resaltada, la ficha y QQ/PP. **La recomendación oficial NO cambia** | | |
| R-04 | ADR-029 · casillas | Activar modo comparación y cambiar la selección | Cambia el conjunto comparado. **Ranking y recomendación intactos** | | |
| R-05 | ADR-029 · leyenda | Ocultar/mostrar curvas desde la leyenda de Plotly | Solo cambia la visibilidad. **Ni ficha, ni QQ/PP, ni ranking, ni recomendación** | | |
| R-06 | Restablecer | Pulsar «Restablecer análisis» | Vuelve a la recomendada **sin recalcular** | | |
| R-07 | Exportación existente | Descargar el CSV de resultados | **Una fila por distribución del ranking**, columnas idénticas a v1.0 (`distribucion`, `posicion`, `puntuacion`, `ajuste`, `parsimonia`, `parametros`, `metodo`, `valores`, `aic`, `bic`). **Sin columnas de parámetro** | | |
| R-08 | Discreta | `discreta_poisson.csv` → Calcular | Familia discreta, 3 candidatas, flujo intacto | | |

---

## 1. Navegación

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Obs. |
|---|---|---|---|---|---|
| N-01 | Entrada | Pulsar «Explorar incertidumbre →» | Se abre la **vista interna dedicada**. No se abre pestaña, ventana ni modal | | |
| N-02 | Salida | Pulsar «← Volver al análisis» | Vuelve al panel de análisis **con el mismo estado**: misma fila de ranking seleccionada, mismo conjunto comparado, misma curva resaltada | | |
| N-03 | Sin recálculo | Entrar y volver 3 veces seguidas | **No aparece el spinner de cálculo del análisis** y las métricas no parpadean con valores nuevos. El análisis no se rehace | | |
| N-04 | Sin bootstrap automático | Entrar en la vista | **No se ejecuta ningún bootstrap**. El bloque bootstrap dice «No se ha calculado bootstrap para esta selección.» | | |
| N-05 | CTA sin análisis | Recargar la app y mirar antes de pulsar «Calcular» | El CTA **no aparece** (o no es utilizable) | | |
| N-06 | Coste de volver | Cronometrar el retorno al análisis | Los gráficos se redibujan en un tiempo aceptable (< ~2 s). Si excede, anotar como `UX OBSERVATION` — la mitigación (`suspendWhenHidden`) está identificada y **no se aplica sin evidencia** | | |

---

## 2. Identidad del análisis en la cabecera

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Obs. |
|---|---|---|---|---|---|
| I-01 | Distribución y estimador | Con método **MLE**, entrar en la vista | Cabecera: «Analizando: `<Distribución>` · MLE (máxima verosimilitud)» | | |
| I-02 | Muestra modelizada | Ídem | Línea con `n` usada y soporte | | |
| I-03 | Recomendación independiente | Ídem | Texto que aclara que la recomendación oficial no cambia por explorar aquí | | |
| I-04 | **AUTO · método efectivo** | Método **Automático** → Calcular → recorrer las filas del ranking entrando en la vista | Para cada distribución, la cabecera muestra el **método realmente utilizado**. Aparece además la nota «El análisis se ejecutó en modo automático; para esta distribución el método efectivamente utilizado fue …» | | |
| I-05 | **AUTO nunca miente** | En I-04, buscar alguna distribución cuyo ajuste haya caído a MoM o L-momentos | **Nunca** se etiqueta como MLE. Si ninguna cae, anotarlo: el caso queda cubierto por el test automático con fixture | | |
| I-06 | Cambio de fila | Cambiar de fila del ranking **estando en la vista** o volviendo | La cabecera y el selector de estimador se actualizan a la nueva distribución | | |

---

## 3. Incertidumbre analítica (MLE)

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Obs. |
|---|---|---|---|---|---|
| A-01 | Inmediatez | MLE + distribución con ajuste válido → entrar en la vista | La tabla analítica aparece **sin pulsar nada** | | |
| A-02 | Contenido | Ídem | Columnas: Parámetro · Estimación · SE · IC inferior · IC superior. Debajo, «Información observada del MLE · nivel de confianza 95 %» | | |
| A-03 | Estimación oficial | Comparar con la ficha técnica del análisis | Los valores de «Estimación» **coinciden exactamente** con los parámetros del ajuste | | |
| A-04 | IC asimétrico | Mirar un parámetro positivo (p. ej. `scale`) | El IC **no** está centrado en la estimación y su extremo inferior es **> 0**. Es deliberado (OD-16): Wald en escala transformada | | |
| A-05 | No disponible | Buscar un ajuste donde B12 no produzca inferencia (o forzarlo con un dataset patológico) | Mensaje breve, **sin SE ni IC fabricados**, y el motivo real accesible en «Detalles técnicos» | | |
| A-06 | Nivel editable | Cambiar el nivel a 0,90 | La tabla analítica se recalcula con el nuevo nivel; los IC se estrechan | | |

---

## 4. MoM y L-momentos

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Obs. |
|---|---|---|---|---|---|
| M-01 | Sin vía analítica | Método **Momentos (MoM)** → Calcular → vista | «La incertidumbre analítica no está disponible para este estimador en v1.1. Puedes calcularla por bootstrap.» **Sin tabla analítica** | | |
| M-02 | Bootstrap disponible | Ídem, pulsar «Calcular incertidumbre bootstrap» | Se obtienen SE e IC bootstrap | | |
| M-03 | Estimador correcto | Abrir «Reproducibilidad y detalles técnicos» | `Estimador` = **mom** | | |
| M-04 | L-momentos | Repetir con **L-momentos** | Mismo comportamiento; `Estimador` = **lmom** | | |
| M-05 | Estimación puntual | Comparar con la ficha del análisis | Coincide con el ajuste MoM/L-mom, no con un MLE | | |

---

## 5. Percentile Matching (alternativo)

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Obs. |
|---|---|---|---|---|---|
| P-01 | Fuera del análisis | Mirar el selector «Método de estimación» de la barra lateral | **PM no aparece**. Solo MLE, Automático, MoM, L-momentos | | |
| P-02 | Disponible en la vista | En la vista, abrir «Estimador para la incertidumbre» | Dos opciones: el **método efectivo** de la distribución y **«Percentile Matching (alternativo)»** | | |
| P-03 | Aviso inequívoco | Seleccionar PM | Texto que declara que PM es **alternativo**, que no participa en el ranking ni en la recomendación, y **cuál** es el método en que sí se basan | | |
| P-04 | Estimación propia | Comparar los valores de «Estimación» con los del análisis | **Difieren**: son los de PM, no los del estimador del análisis | | |
| P-05 | Bootstrap PM | Pulsar «Calcular incertidumbre bootstrap» con PM activo | Se obtienen SE e IC. En reproducibilidad, `Estimador` = **pm** y aparece **`Percentiles PM`** (0.1 / 0.5 / 0.9 por defecto) | | |
| P-06 | Sin comparación cruzada | Con PM activo, mirar el bloque de comparación | **NO aparece** la tabla «Comparación descriptiva». Sería comparar la analítica de MLE con el bootstrap de PM: estimadores distintos | | |
| P-07 | Ranking intacto | Volver al análisis | Ranking y recomendación **idénticos** a antes de usar PM | | |
| P-08 | Gráfico con PM | Mirar el gráfico bootstrap con PM activo | La línea de estimación puntual es la de **PM** | | |

---

## 6. Controles del bootstrap

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Obs. |
|---|---|---|---|---|---|
| B-01 | Lista cerrada de B | Abrir el selector «Réplicas» | Exactamente **500 / 1000 / 2000 / 5000**. **No hay campo libre** | | |
| B-02 | Defecto | Ídem | Preseleccionado **1000** | | |
| B-03 | Nivel por defecto | Mirar «Nivel de confianza» | **0,95** | | |
| B-04 | Solo bajo demanda | Cambiar B, nivel y semilla **sin pulsar el botón** | **No se ejecuta ningún bootstrap** | | |
| B-05 | Ejecución | Pulsar «Calcular incertidumbre bootstrap» con B = 1000 | Aparece el indicador de carga y después la tabla bootstrap | | |
| B-06 | Semilla en avanzadas | Desplegar «Opciones avanzadas» | Campo «Semilla» con un valor **ya propuesto** y botón «Generar otra» | | |
| B-07 | Generar otra | Pulsar «Generar otra» | El valor cambia. **No se ejecuta bootstrap** | | |
| B-08 | Coste de B = 5000 | Ejecutar con **5000** sobre `continua_pareto_cola_pesada.csv` | Termina en un tiempo tolerable con indicador de carga visible. Si resulta molesto, anotar `UX OBSERVATION` | | |
| B-09 | Semilla inválida | Escribir `2.5` y ejecutar | Aviso de error claro; **no se ejecuta** ni se corrompe el resultado anterior | | |

---

## 7. Protección de resultados obsoletos — **CRÍTICO**

> Para cada fila: partir de un bootstrap **ya calculado y vigente**, cambiar
> **una sola** cosa y observar. Después, **restaurar** el valor original.

| ID | Qué se cambia | Resultado esperado | Al restaurar | PASS/FAIL | Obs. |
|---|---|---|---|---|---|
| S-01 | Distribución (otra fila del ranking) | Aparece «La configuración actual es distinta de la utilizada en el último bootstrap…». **La tabla bootstrap desaparece** | Vuelve a mostrarse el resultado | | |
| S-02 | Estimador (a PM y vuelta) | Ídem | Ídem | | |
| S-03 | `B` (1000 → 2000) | Ídem | Ídem | | |
| S-04 | Nivel de confianza (0,95 → 0,90) | Ídem | Ídem | | |
| S-05 | **Semilla** | Ídem | Ídem | | |
| S-06 | Percentiles PM (con PM activo) | Ídem | Ídem | | |
| S-07 | **Dataset** (cargar otro CSV y recalcular) | El resultado anterior **no reaparece** en ningún caso | — | | |
| S-08 | **Mismo `n`, datos distintos** | Cargar dos CSV con el **mismo número de filas** pero valores distintos, recalcular y volver a la vista | El bootstrap del primero **no** se presenta como válido para el segundo. La identidad la protege la **huella SHA-256**, no `n` | | |
| S-09 | Nunca silencioso | En todos los anteriores | **En ningún momento** se muestran cifras del bootstrap anterior junto a la configuración nueva | | |

---

## 8. Visualización

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Obs. |
|---|---|---|---|---|---|
| V-01 | Histograma | Tras un bootstrap válido | Histograma de las réplicas válidas | | |
| V-02 | Estimación puntual | Ídem | Línea vertical continua marcada **θ̂** | | |
| V-03 | Intervalo | Ídem | Dos líneas discontinuas «IC inf.» / «IC sup.» | | |
| V-04 | Título | Ídem | Nombre del parámetro + nº de réplicas válidas + nivel del intervalo percentil | | |
| V-05 | Selector de parámetro | Distribución con `k > 1` (Gamma, Weibull, Burr) | Botones de radio para elegir parámetro; el gráfico cambia | | |
| V-06 | `k = 1` | Exponencial | **No** aparece selector; el gráfico se muestra igual | | |
| V-07 | **Sin interpretación automática** | Mirar el gráfico y su pie | **No** hay puntuación de acuerdo, semáforo, etiqueta de estabilidad, verde/rojo ni umbral. Solo descripción | | |
| V-08 | Coherencia | Comparar los extremos del gráfico con la tabla bootstrap | Coinciden | | |

---

## 9. Comparación descriptiva (B15)

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Obs. |
|---|---|---|---|---|---|
| K-01 | Disponible | MLE con analítica válida + bootstrap ejecutado | Tabla «Comparación descriptiva» con SE e IC de **ambas** vías, y nota de que es descriptiva | | |
| K-02 | Sin criterio automático | Ídem | **Ninguna** columna de diferencia, cociente, solapamiento o acuerdo | | |
| K-03 | Niveles distintos | Ejecutar bootstrap al 95 %, luego cambiar el nivel analítico a 0,90 sin reejecutar | Se muestran **los niveles reales de cada vía**; no se armonizan ni se recalculan intervalos | | |
| K-04 | Sin las dos vías | MoM o PM | **No** aparece la tabla de comparación | | |
| K-05 | Identidad no verificada | Si se consigue el caso | No se presenta como comparación válida; se explica que no se ha podido verificar que ambas correspondan a la misma muestra | | |

---

## 10. Réplicas fallidas (OD-17)

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Obs. |
|---|---|---|---|---|---|
| F-01 | Contadores | Tras cualquier bootstrap | «Réplicas solicitadas / exitosas / fallidas» visibles | | |
| F-02 | Con fallos | Buscar un caso con fallos (Pareto o Burr sobre cola pesada) | Aviso **neutral**: algunas réplicas no produjeron ajuste válido y no entran en los resúmenes | | |
| F-03 | **Sin dirección de sesgo** | Leer ese aviso y las limitaciones | **No** se afirma que el resultado esté sesgado hacia arriba ni hacia abajo, ni que subestime o sobreestime | | |
| F-04 | **Sin umbral** | Ídem | **No** aparece porcentaje mínimo, «fiable/no fiable» ni etiqueta de calidad | | |
| F-05 | Motivos | Desplegar «Limitaciones» y «Reproducibilidad» | Los motivos de fallo aparecen agrupados | | |

---

## 11. Reproducibilidad

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Obs. |
|---|---|---|---|---|---|
| Q-01 | Bloque presente | Desplegar «Reproducibilidad y detalles técnicos» | Tabla con Análisis / Datos / Software | | |
| Q-02 | Análisis | Ídem | Distribución · Estimador · Método de incertidumbre · B solicitadas/exitosas/fallidas · Nivel · Semilla · Percentiles PM cuando aplique | | |
| Q-03 | Datos | Ídem | `n` modelizada · **huella SHA-256 de 64 caracteres** · algoritmo | | |
| Q-04 | Software | Ídem | Herramienta · Versión · **Versión de schema = 1.1.0** | | |
| Q-05 | **Metadatos congelados** | Ejecutar bootstrap con semilla `X` → cambiar la semilla a `Y` **sin reejecutar** | El resultado deja de mostrarse como vigente. Si se restaura `X`, el pasaporte sigue diciendo `X`. **En ningún momento el pasaporte de un resultado ya calculado muta a `Y`** | | |
| Q-06 | Semilla reproducible | Ejecutar dos veces con la **misma** semilla y configuración | SE e IC **idénticos** | | |
| Q-07 | Semilla distinta | Cambiar la semilla y reejecutar | Resultados ligeramente distintos, misma estructura | | |
| Q-08 | Sin gestor de configuraciones | Recorrer la vista | **No** hay «Mis configuraciones», guardar, importar ni restaurar. Correcto: es v1.2+ | | |

---

## 12. Exportación de incertidumbre

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Obs. |
|---|---|---|---|---|---|
| E-01 | Botón | Al final de la vista | «Exportar incertidumbre (CSV)» | | |
| E-02 | **Grano** | Abrir el CSV | **Una fila por parámetro** de la distribución/estimador activos | | |
| E-03 | Columnas | Ídem | `distribucion`, `estimador`, `estimador_alternativo`, `parametro`, `estimacion`, `analitico_*`, `bootstrap_*`, `b_solicitadas/exitosas/fallidas`, `seed`, `pm_percentiles`, `n_modelizada`, `fingerprint`, `fingerprint_algo/estado`, `herramienta`, `version_herramienta`, `version_schema`, `comparacion_estado` | | |
| E-04 | **Coincidencia con pantalla** | Contrastar SE, IC, `B`, semilla y huella con lo mostrado | **Idénticos** | | |
| E-05 | **Sin réplicas** | Buscar columnas de réplicas individuales | **No existen**. El CSV tiene tantas filas como parámetros, no como réplicas | | |
| E-06 | Export del ranking intacto | Descargar también el CSV principal | Sigue teniendo **una fila por distribución** y sus columnas de v1.0 | | |
| E-07 | Sin bootstrap | Exportar con solo analítica calculada | Las columnas bootstrap salen vacías; el CSV es válido | | |
| E-08 | PM | Exportar con PM activo | `estimador = pm`, `estimador_alternativo = TRUE`, `pm_percentiles` poblado | | |

---

## 13. Datos reales (ADR-026)

Dataset: **`data/samples/real_cost_claims_reducido.csv`**, variable `Cost_claims_year`.

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Obs. |
|---|---|---|---|---|---|
| D-01 | Muestra común | Calcular | 5.030 válidas · aviso de **4.111 ceros excluidos** · **919 observaciones usadas** | | |
| D-02 | Ranking intacto | Ídem | Comportamiento idéntico al registrado en v1.0 (Pareto con AIC finito ≈ 13.563) | | |
| D-03 | `n` en la vista | Entrar en incertidumbre | «Muestra modelizada: n = 919 · soporte (0, Inf) · 4111 ceros excluidos» | | |
| D-04 | **Lectura condicional** | Leer las limitaciones | Se declara que la inferencia corresponde a la **distribución condicional** restringida al soporte del análisis, **no** a la variable original completa con su masa en cero | | |
| D-05 | Huella | Reproducibilidad | Huella presente y `n_used` = 919 | | |
| D-06 | Bootstrap | Ejecutar con B = 1000 | Termina; contadores coherentes | | |
| D-07 | Recomendación invariante | Volver al análisis | Ranking y recomendación **idénticos** a antes de entrar | | |
| D-08 | Export | Exportar incertidumbre | `n_modelizada = 919`, huella presente | | |

> **H4 no se reabre.** La incertidumbre publicada es de **parámetros**, no de
> **selección de modelo**. Sigue siendo `METHODOLOGICAL LIMITATION / FUTURE WORK`.

---

## 14. Responsive

| ID | Resolución | Qué mirar | Resultado esperado | PASS/FAIL | Obs. |
|---|---|---|---|---|---|
| W-01 | **1366×768** | Vista de incertidumbre completa | Sin contenido cortado, sin controles inaccesibles, sin textos superpuestos | | |
| W-02 | 1366×768 | Fila de tres controles (Réplicas / Nivel / Estimador) | Legibles y utilizables; si se apilan, correcto | | |
| W-03 | 1366×768 | Tablas de parámetros | Sin desbordamiento sin solución | | |
| W-04 | 1366×768 | Gráfico bootstrap | Legible; ejes y etiquetas θ̂ / IC visibles | | |
| W-05 | ≥ 1920×1080 | Toda la vista | Aprovecha el ancho sin dejar huecos absurdos | | |
| W-06 | Ambas | Navegación | El enlace «← Volver al análisis» siempre accesible | | |

> Diferencias estéticas menores → `UX OBSERVATION — NON-BLOCKING`, a backlog.
> **B17 no es un rediseño visual.**

---

## Cierre

| Concepto | Valor |
|---|---|
| PASS / FAIL totales | |
| `PRODUCT BUG — BLOCKING` | |
| `TEST DEFECT` | |
| `ENVIRONMENT WARNING` | |
| `METHODOLOGICAL LIMITATION` | |
| `UX OBSERVATION` | |
| **Veredicto** | |

**El bump de `manifest` a 1.1.0 solo procede si no hay ningún
`PRODUCT BUG — BLOCKING`.**

---

*Actuarial Tools by BMK — Tool-02, aceptación manual de la capa de incertidumbre v1.1.*
