# Tool-02 — Protocolo de aceptación manual (previo a publicación)

| Campo | Valor |
|---|---|
| **Herramienta** | Ajuste de Distribuciones (`distribution-fitting`) v1.0.1 |
| **Objeto** | Validación manual de release. Complementa la batería automática (**17 scripts**, 0 fallos, incluidos los 3 de ADR-026/027/028) |
| **Ejecutado por** | |
| **Fecha** | |
| **Resolución de pantalla** | |
| **Versión de R** | |

## Preparación

Desde la **raíz del repositorio**, en R o RStudio:

```r
shiny::runApp("tools/distribution-fitting")
```

`runApp()` sitúa el directorio de trabajo en la carpeta de la herramienta, que
es lo que necesitan las rutas relativas de `app.R` (`../../shared/load_shared.R`,
`R/calc.R`, `manifest.yml`, `data/example_data.csv`). Si abres `app.R` y pulsas
*Run App* en RStudio, el efecto es el mismo.

Antes de empezar, comprueba que el pie de página muestra **v1.0.1**.

Ten a mano: los ficheros de `data/samples/` (24 sintéticos + `real_cost_claims_reducido.csv`),
**tu CSV real de siniestralidad** y la consola de R visible durante toda la sesión.

**Reglas de anotación**

- Marca `PASS` solo si el resultado coincide **exactamente** con lo esperado.
- Cualquier desviación es `FAIL`, aunque parezca menor; descríbela en Observaciones.
- Anota **cualquier** error o aviso que aparezca en consola (los de
  `package 'shiny'/'bslib' was built under R version 4.4.3` son de entorno y
  están aceptados: no cuentan como fallo).
- Salvo que la prueba indique lo contrario, **la recomendación oficial no debe
  cambiar** al explorar, comparar o restablecer.
- Los avisos de la herramienta son **notificaciones flotantes y transitorias**
  (esquina de la pantalla, desaparecen solas). Aparecen una sola vez, justo
  después de calcular: no te distraigas en ese instante. La evidencia
  permanente equivalente está en la ficha técnica, bloque *Evaluación*, fila
  **«Observaciones usadas»**.
- v1.0.1 **no** ofrece: percentile matching, errores estándar o intervalos de los
  parámetros, bootstrap, pilar C (cola) ni pilar D (estabilidad). Su ausencia
  **no es un FAIL**: son funcionalidades de v1.1 y posteriores.

> Los resultados esperados por fichero están detallados en
> `data/samples/README.md`; este protocolo comprueba el comportamiento de la
> interfaz, no los valores numéricos (ya verificados contra SciPy).

---

## 1. Carga de CSV

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Observaciones |
|---|---|---|---|---|---|
| C-01 | CSV real de siniestralidad | Subir tu fichero real → elegir variable → Calcular | Carga sin error; el selector ofrece las columnas numéricas; el análisis se completa | PASS| |
| C-01b | **Dataset real con masa en cero** | Subir `data/samples/real_cost_claims_reducido.csv` → `Cost_claims_year` → Calcular | 5.030 válidas; aviso único de **4.111 ceros excluidos**; las 7 candidatas con **919 observaciones usadas**; Pareto con AIC finito (~13.563), **no** −1,15·10⁸; ΔAIC ≈ −128 | PASS| |
| C-02 | Con cabecera, coma | Subir `continua_lognormal.csv` | Columna `loss_amount` en el selector; nombres respetados | PASS| |
| C-03 | **Sin** cabecera, 1 columna | Subir `formato_sin_cabecera_1col.csv` → Calcular | Columna `Variable_1`. En la ficha técnica → *Evaluación* → **«Observaciones usadas» = 200** (no 199: no se pierde la primera observación) | PASS| |
| C-04 | **Sin** cabecera, separador `;` | Subir `formato_sin_cabecera_pyc.csv` → Calcular | Tres columnas `Variable_1`, `Variable_2`, `Variable_3` en el selector; *Observaciones usadas* = **180** | PASS| |
| C-05 | Con cabecera, separador `;` | Subir `formato_cabecera_pyc.csv` | Columnas `severidad` y `exposicion` | PASS| |
| C-06 | Separador tabulador | Subir `formato_tabulador.csv` | Columnas `importe` y `exposicion` |PASS| |
| C-07 | BOM + CRLF | Subir `formato_bom_crlf.csv` | Primer nombre de columna limpio, sin caracteres extraños |PASS | |
| C-08 | Varias columnas numéricas + texto/fecha | Subir `formato_columnas_mixtas.csv` | El selector ofrece **solo** `paid_loss`, `incurred_loss`, `exposure` (no `claim_id`, `fecha` ni `zona`). Aviso flotante: *"Se han detectado 3 columna(s) numérica(s) de 6"* | PASS| |
| C-09 | Selección libre de variable | En C-08, cambiar a `exposure` → Calcular | El análisis se rehace sobre `exposure`; la ficha y los gráficos reflejan la nueva variable | | |
| C-10 | Nombres con acentos y símbolos | Subir `formato_nombres_raros.csv` | Carga correcta; `Importe Siniestro (€)` seleccionable | | |
| C-11 | Celdas vacías y `NA` | Subir `formato_con_na.csv` → Calcular | Carga correcta; se informa del porcentaje de ausentes | | |
| C-12 | **Sin columnas numéricas → modal** | Subir `formato_sin_numericas.csv` | **Ventana modal bloqueante** "El archivo no contiene datos numéricos", con las columnas leídas y su tipo. **No** aparece además el aviso flotante. El cálculo no se habilita | | |
| C-13 | Recuperación tras el modal | Cerrar el modal y subir `continua_gamma.csv` | La aplicación se recupera y calcula con normalidad | | |
| C-14 | Datos de ejemplo | En el conmutador **"Datos de ejemplo / Subir CSV"** elegir *Datos de ejemplo* → Calcular | Análisis completo sin tocar ningún otro input | | |
| C-15 | Descarga de plantilla | Pulsar "Descargar datos de ejemplo" | Se descarga un CSV válido y reutilizable como plantilla | | |

---

## 2. Detección del tipo de variable

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Observaciones |
|---|---|---|---|---|---|
| T-01 | Severidad continua | `continua_lognormal.csv` → Calcular | Familia **continua**; 7 candidatas; ficha con **AD / KS / CvM** | | |
| T-02 | Recuento discreto | `discreta_poisson.csv` → Calcular | Familia **discreta**; 3 candidatas; ficha con **chi-cuadrado, gl y sobredispersión** (no AD/KS/CvM) | | |
| T-03 | Sobredispersión | `discreta_binomial_negativa.csv` → Calcular | Familia discreta; binomial negativa en cabeza; **sobredispersión > 1** en la ficha | | |
| T-04 | Enteros de alta cardinalidad (ADR-020) | `limite_enteros_grandes.csv` → Calcular | Se trata como **continua** (199 valores distintos > 50). **Responde al instante**, sin bloqueo ni spinner infinito | | |
| T-05 | Ceros — **muestra común (ADR-026)** | `limite_con_ceros.csv` → Calcular | **Un solo** aviso global de exclusión de ceros, con el recuento y la advertencia de que se modeliza severidad **condicionada**. En la ficha, «Observaciones usadas» es **idéntica para las 7 candidatas**: la exponencial ya **no** conserva los ceros. El resumen de la interpretación declara la muestra modelizada, no el total de válidas | | |
| T-06 | Negativos — **muestra común** | `limite_con_negativos.csv` → Calcular | **Un solo** aviso global de exclusión de los 15 negativos (antes de ADR-026 se emitía uno por distribución). «Observaciones usadas» = **185, idéntica en las 7** | | |
| T-10 | **La discreta conserva los ceros** | `discreta_poisson.csv` (46 ceros) → Calcular | **NO** aparece ningún aviso de exclusión de ceros: las 3 candidatas discretas admiten el 0, así que el soporte común los conserva. «Observaciones usadas» = **300**. Es el contrapunto de T-05: verifica que la regla de ADR-026 no se aplica de más | | |
| T-07 | Muestra pequeña | `limite_muestra_pequena.csv` (n=8) → Calcular | Funciona; confianza **baja**; no hay error | | |
| T-08 | Varianza casi nula | `limite_casi_constante.csv` → Calcular | La aplicación **no falla**; si alguna candidata no converge, aparece marcada como descartada con su motivo | | |
| T-09 | Bimodal | `continua_bimodal.csv` → Calcular | Ninguna distribución ajusta bien; QQ-plot visiblemente curvado. La herramienta no lo oculta | | |

---

## 3. Métodos de estimación

Los cuatro métodos de v1.0.1 son **MLE**, **Automático**, **Momentos (MoM)** y
**L-momentos**. No hay más, y `Burr` no dispone de MoM ni de L-momentos por
diseño.

Aviso importante para M-04 a M-06: MoM y L-momentos **no siempre son aplicables
a unos datos concretos**, aunque estén implementados. La Pareto por MoM exige
CV² > 1 y por L-momentos exige cola pesada (k < 0). `continua_gamma.csv` tiene
CV² ≈ 0,35 y k ≈ +1,07, así que en ese fichero la Pareto queda descartada por
ambos métodos. **Es el comportamiento correcto**, no un fallo.

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Observaciones |
|---|---|---|---|---|---|
| M-01 | MLE (por defecto) | `continua_gamma.csv`, método **MLE (máxima verosimilitud)** → Calcular | Ficha: "… · método MLE · 2 parámetro(s)"; debajo, *"Método seleccionado manualmente por el usuario."* Las 7 candidatas se evalúan | | |
| M-02 | AUTO | Mismo fichero, método **Automático** → Calcular | Resultado equivalente al MLE (AUTO es MLE-first); el texto pasa a *"Método seleccionado automáticamente para esta distribución."* | | |
| M-03 | MoM | Método **Momentos (MoM)** → Calcular | Se recalcula; los parámetros cambian respecto a MLE; la ficha indica **método MOM** | | |
| M-04 | **No disponibilidad** con MoM | Con MoM, revisar el ranking completo | Aparecen **dos** filas descartadas: `Burr` (sin estimador MoM) y `Pareto (Lomax)` (CV² ≤ 1). El texto del Estado es *"Descartada: método 'mom' no disponible para …"*. Las otras 5 se evalúan | | |
| M-05 | L-momentos, cola ligera | Método **L-momentos** sobre `continua_gamma.csv` → Calcular | Se recalcula **sin error**, pero el ranking se queda con **una sola fila: Exponencial**. Las otras 6 aparecen descartadas. Confianza **Media**, justificada como *"candidata única"*. La Normal es control y **nunca** aparece en el ranking | | |
| M-06 | L-momentos, cola pesada | Método **L-momentos** sobre `continua_pareto_cola_pesada.csv` → Calcular | Ahora sí se evalúan **Exponencial y Pareto (Lomax)** (k ≈ −0,40 < 0); las otras 5 quedan descartadas | | |
| M-07 | Profundidad | Volver a MLE y cambiar a **Comprehensive** → Calcular | Se recalcula sin error; no aparece ninguna funcionalidad nueva (la profundidad solo queda registrada en el perfil de la ejecución) | | |
| M-08 | Coherencia | Volver a **MLE** + **Standard** → Calcular | Se reproduce exactamente el resultado de M-01 | | |

---

## 4. Resultados

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Observaciones |
|---|---|---|---|---|---|
| R-01 | Distribución recomendada | `continua_lognormal.csv` → Calcular | Metric card "Distribución recomendada" con un nombre legible; coherente con el nº 1 del ranking | | |
| R-02 | Confianza | Misma pantalla | Card "Confianza" con Alta / Media / Baja; el texto de interpretación explica el **ΔAIC** que la justifica | | |
| R-03 | Ranking completo | Revisar la tabla | Una fila por candidata, ordenadas por puntuación; columnas #, Distribución, Puntuación, Ajuste, Parsimonia, Parámetros, AIC, Estado; la recomendada marcada | | |
| R-04 | Descartadas visibles | `limite_casi_constante.csv` o M-05 | Las descartadas aparecen **al final con su motivo**, no ocultas | | |
| R-05 | Parámetros estimados | Ficha técnica | Nombre = valor por parámetro, coherentes con la distribución mostrada | | |
| R-06 | LogLik / AIC / BIC | Ficha técnica, bloque "Criterios de información" | Los tres valores presentes y finitos | | |
| R-07 | GoF continua | Ficha, bloque "Bondad de ajuste" | Anderson-Darling, Kolmogorov-Smirnov y Cramér-von Mises | | |
| R-08 | GoF discreta | `discreta_geometrica.csv` → ficha | Chi-cuadrado, grados de libertad y sobredispersión (la ficha se adapta sola) | | |
| R-09 | Evaluación | Ficha, bloque "Evaluación" | Puntuación global, nivel de ajuste y nivel de parsimonia (0–100) | | |
| R-10 | Interpretación | Caja de interpretación | Texto **específico de estos datos** (menciona la variable, el nº de observaciones y la distribución), no genérico | | |
| R-11 | Avisos | `limite_con_ceros.csv` | Un **único** aviso de exclusión con el recuento exacto (40 ceros) y la advertencia de severidad **condicionada**; ningún aviso duplicado por distribución | | |
| R-12 | Coherencia numérica | Comparar card, ranking y ficha | La puntuación de la recomendada coincide en los tres sitios | | |
| R-13 | **Piezas diferidas declaradas** | Revisar la 4.ª metric card | "Calidad de cola" muestra **"—"** con la nota *"diferido: requiere Pilar C"*. **Esto es PASS**: la herramienta declara lo que no hace en lugar de ocultarlo. Solo es FAIL si muestra un número inventado o si desaparece la nota | | |

---

## 5. Explorador

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Observaciones |
|---|---|---|---|---|---|
| E-01 | Selección inicial | `continua_pareto_cola_pesada.csv` → Calcular | La distribución mostrada es **la recomendada**; su fila aparece resaltada | | |
| E-02 | Clic en el ranking | Clic en la fila 3 | La curva de esa distribución se resalta en el gráfico; el resto se atenúa; histograma y KDE **no cambian** | | |
| E-03 | Ficha sigue la selección | Tras E-02 | Parámetros y métricas pasan a ser los de la distribución seleccionada | | |
| E-04 | QQ / PP siguen la selección | Tras E-02 | Ambos gráficos corresponden a la **distribución mostrada**, no a la recomendada | | |
| E-05 | **Recomendación inmutable** | Tras E-02 | La metric card superior "Distribución recomendada" **no cambia**. En la ficha, la card "Recomendación oficial" sigue mostrando la misma y la card "Distribución mostrada" indica *"exploración manual · puesto N de M"* | | |
| E-06 | **Leyenda = visibilidad (ADR-029)** | Clic sobre una entrada de la leyenda del gráfico principal; volver a pulsarla | La curva se **oculta** y con el segundo clic **reaparece**. **NO** cambia: la fila seleccionada del ranking, QQ/PP, la ficha técnica ni la recomendación oficial. En consola **no** aparece el aviso `plotly_legendclick ... is not registered` | | |
| E-07 | Comparación con la recomendada | Con una distribución no recomendada seleccionada | Aparece la tabla comparativa (puntuación, AIC, BIC, tests, nº parámetros) y el bloque **¿Por qué no es la recomendada?** con marcas ✔/✘ | | |
| E-08 | Sin comparación en la recomendada | Seleccionar la recomendada | El bloque comparativo **desaparece** (no se compara consigo misma) | | |
| E-09 | Restablecer análisis | Pulsar "Restablecer análisis" | Vuelve a la recomendada, **desmarca** "Modo comparación" y devuelve las casillas a las 2 primeras del ranking. Aviso: *"Análisis restablecido a la recomendación oficial."* **No se recalcula** (respuesta inmediata, sin spinner) | | |

---

## 6. Modo comparación

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Observaciones |
|---|---|---|---|---|---|
| K-01 | Activar | `continua_pareto_cola_pesada.csv` → activar "Modo comparación" | Aparece el panel de casillas con las candidatas y una preselección | | |
| K-02 | Comparar 2 | Dejar 2 marcadas | El gráfico muestra **solo** esas dos curvas, cada una con **color propio**; histograma y KDE siguen visibles | | |
| K-03 | Comparar 4 | Marcar 4 | Cuatro curvas con colores distinguibles; leyenda coherente con las casillas | | |
| K-04 | Añadir / quitar | Marcar y desmarcar varias veces | El gráfico responde de inmediato, sin recalcular ni parpadear | | |
| K-05 | Límite máximo | Intentar marcar 5 | Aviso *"Puedes comparar como máximo 4 distribuciones."* y la selección se recorta automáticamente a 4 | | |
| K-06 | **Límite mínimo con aviso (ADR-029)** | Dejar solo 1 marcada; después volver a marcar una segunda | Con 1: la casilla *Modo comparación* **sigue marcada**, la selección se conserva, el gráfico vuelve a exploración y aparece un **aviso inline** en el panel (*"Marca al menos 2 distribuciones…"*). Al marcar la segunda, la comparación reaparece **sin reactivar el modo a mano** | | |
| K-07 | **Leyenda no altera la comparación (ADR-029)** | Con comparación activa, clic en una entrada de la leyenda | Solo cambia la **visibilidad** de esa curva. Las casillas de *Distribuciones a comparar* **no** se marcan ni se desmarcan, y el conjunto comparado no cambia | | |
| K-08 | **Ficha durante comparación (ADR-029)** | Con comparación activa, seleccionar en el **ranking** una distribución que NO esté entre las comparadas | La ficha sigue mostrando **una** distribución y su comparación con la recomendada. La nota de la card *"Distribución mostrada"* dice **"seleccionada en el ranking"** y añade **"no está entre las comparadas: su curva no se dibuja"** | | |
| K-09 | Desactivar | Desmarcar "Modo comparación" | Vuelve la vista con todas las curvas y la seleccionada resaltada | | |

---

## 7. Rendimiento

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Observaciones |
|---|---|---|---|---|---|
| P-01 | Fichero pequeño | `limite_muestra_pequena.csv` (n=8) → Calcular | Respuesta prácticamente instantánea | | |
| P-02 | Varios cientos de filas | `continua_lognormal.csv` (400) → Calcular | Cálculo en pocos segundos | | |
| P-03 | Fichero grande | `limite_grande_20k.csv` → Calcular | Completa el cálculo **sin bloquearse**; anota el tiempo: ______ s | | |
| P-04 | **Exploración tras el cálculo grande** | Sobre el resultado de P-03: clic en varias filas del ranking, cronometrando | (a) El **histograma** y la curva discontinua de la **KDE** no cambian: solo varían color y grosor de las curvas ajustadas. (b) La respuesta es una **fracción** del cálculo de P-03; anota ambos: ____ s vs ____ s. (c) La recomendación oficial no cambia. **El spinner reaparece y eso es correcto**: `bmk_loading()` envuelve QQ y PP, que deben seguir a la distribución mostrada | | |
| P-05 | Comparación tras el cálculo grande | Activar comparación y cambiar las casillas | Respuesta inmediata | | |
| P-06 | Cambio de variable sí recalcula | En `formato_columnas_mixtas.csv`, cambiar de variable → Calcular | Aquí **sí** debe recalcular (es un análisis nuevo) | | |
| P-07 | Enteros de alta cardinalidad | `limite_enteros_grandes.csv` → Calcular | **Sin bloqueo** (el bug de las 48.828 categorías está corregido) | | |

---

## 8. Revisión visual a 1366 × 768

Ajusta la ventana del navegador a esa resolución antes de empezar.

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Observaciones |
|---|---|---|---|---|---|
| V-01 | Sidebar | Revisar de arriba abajo | Todas las secciones legibles y accesibles; nada cortado | | |
| V-02 | Metric cards | Revisar la fila superior | Las 4 cards caben en una fila, sin solaparse ni truncar el texto | | |
| V-03 | Gráfico principal | Revisar | Se ve completo, con leyenda legible y sin desbordar | | |
| V-04 | QQ / PP | Revisar | Las dos columnas caben; ejes y etiquetas legibles | | |
| V-05 | Tabla de ranking | Revisar | Todas las columnas visibles o con scroll horizontal razonable; sin texto cortado | | |
| V-06 | Ficha técnica | Revisar | Parámetros y métricas legibles; la columna "Bloque" agrupa correctamente | | |
| V-07 | Tabla comparativa | Con una distribución no recomendada | Las tres columnas caben y se entienden | | |
| V-08 | Textos | Interpretación y avisos | Sin solapamientos, sin cortes, tildes correctas | | |
| V-09 | Scroll | Recorrer toda la página | Scroll fluido; nada queda inaccesible | | |
| V-10 | Botones | Calcular, Restablecer, Exportar, Descargar ejemplo | Todos visibles, pulsables y con la misma altura/estilo | | |
| V-11 | Modal | Subir `formato_sin_numericas.csv` | El modal cabe en pantalla, es legible y se cierra correctamente | | |
| V-12 | Header y footer | Revisar | Header con nombre y marca; footer con **v1.0.1**, disclaimer y aviso de privacidad | | |

---

## 9. Exportación

| ID | Qué probar | Acción | Resultado esperado | PASS/FAIL | Observaciones |
|---|---|---|---|---|---|
| X-01 | Descargar CSV | `continua_lognormal.csv` → Calcular → "Exportar CSV" | Se descarga un fichero con nombre `distribution-fitting_<fecha>.csv` | | |
| X-02 | Abrir el CSV | Abrir en Excel o editor | Se abre correctamente, con cabecera y una fila por distribución evaluada | | |
| X-03 | **Coincidencia con lo mostrado** | Comparar el CSV con el ranking en pantalla | Columnas: distribucion, posicion, puntuacion, ajuste, parsimonia, parametros, metodo, **valores** (parámetros), aic, bic. Los valores coinciden con la tabla, **con más decimales** (puntuación 2 vs 1; AIC 3 vs 2): eso es correcto, no un FAIL | | |
| X-04 | Exportación en familia discreta | `discreta_poisson.csv` → Calcular → Exportar | El CSV se genera correctamente para la familia discreta | | |
| X-05 | Exportación tras explorar | Seleccionar otra distribución → Exportar | El CSV contiene **todas las candidatas evaluadas** en orden de ranking, no solo la mostrada. Las **descartadas no se exportan** (es el contrato actual). La recomendación oficial no ha cambiado | | |

---

## Cierre

| Concepto | Valor |
|---|---|
| Pruebas totales | **89** (C 16 · T 10 · M 8 · R 13 · E 9 · K 9 · P 7 · V 12 · X 5) |
| PASS | |
| FAIL | |
| Errores en consola (excluidos los de entorno) | |
| **Veredicto** | ☐ Apto para publicar ☐ Requiere correcciones |

**Criterio de cierre de la baseline v1.0.1.** Se declara cerrada si y solo si:

1. **0 FAIL** en las 89 pruebas, o bien todo FAIL registrado queda reclasificado
   por acuerdo explícito como (a) defecto de este protocolo, o (b) alcance
   diferido ya declarado en `RELEASE_AUDIT.md` §2.
2. **0 errores** en consola. Los avisos `package 'shiny'/'bslib' was built under
   R version 4.4.3` no cuentan.
3. La batería automática sigue en **0 `[FALLA]`** y **0 `[ERROR-VERIF]`**.
4. Ninguna incidencia obliga a tocar `calc.R`, `mod_tool.R`, `manifest.yml` ni
   `decision_engine.md`. **Si alguna lo obliga, la baseline no se cierra**: se
   corrige primero y se repite el protocolo completo.

Cerrada la baseline, el código de Tool-02 queda **congelado** y todo cambio
posterior entra por la vía v1.1 (ADR previo).

**Incidencias detectadas** (ID, descripción, gravedad):

1.
2.
3.

Si el veredicto es *Apto*, los siguientes pasos son: desplegar en shinyapps.io,
actualizar `manifest.yml` (`status: published` + `published_date`), marcar la
herramienta como terminada en `ROADMAP.md` y preparar la captura o GIF de
demostración.

---

*Actuarial Tools by BMK — Protocolo de aceptación manual de Tool-02.*
