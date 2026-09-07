# Ficheros de prueba — Tool-02 (Ajuste de Distribuciones)

Juego de casos para validar manualmente la herramienta. Generados de forma
determinista (semilla `20260728`). No forman parte de la aplicación: son datos de
QA, equivalentes a `data/samples/` de Tool-01.

Para cada fichero se indica **qué se comprueba** y **qué debería ocurrir**.

---

## A. Importación y formato

Estos casos validan el lector robusto (ADR-017) y la selección de variable
(ADR-018). Lo relevante es que **el archivo se cargue** y el selector se rellene.

| Fichero | Caso | Qué debe ocurrir |
|---|---|---|
| `formato_sin_cabecera_1col.csv` | 1 columna, **sin cabecera**, CRLF | Columna `Variable_1` y **200 filas** (no 199: no se pierde la primera observación) |
| `formato_sin_cabecera_pyc.csv` | 3 columnas, sin cabecera, separador `;` | `Variable_1..3`, 180 filas |
| `formato_cabecera_pyc.csv` | Cabecera + `;` | Columnas `severidad` y `exposicion` |
| `formato_tabulador.csv` | Separador tabulador | Columnas `importe` y `exposicion` |
| `formato_bom_crlf.csv` | BOM + CRLF | Se lee sin caracteres extraños en el primer nombre de columna |
| `formato_columnas_mixtas.csv` | Texto, fecha y 3 numéricas | El selector ofrece **solo** `paid_loss`, `incurred_loss` y `exposure` |
| `formato_con_na.csv` | Celdas vacías y `NA` | Carga correcta; el perfilado reporta el % de ausentes |
| `formato_nombres_raros.csv` | Acentos, espacios y símbolos en los nombres | Carga correcta (los nombres no se validan) |
| `formato_sin_numericas.csv` | **Ninguna columna numérica** | **Ventana modal bloqueante** (ADR-022) con el título "El archivo no contiene datos numéricos", la tabla de columnas leídas con su tipo y las causas habituales. El cálculo no se habilita |

---

## B. Familia continua (motor y recomendación)

Cada fichero procede de la distribución que indica su nombre. Sirven para
comprobar que el ranking es sensato y que la recomendación es defendible.

| Fichero | Origen | Expectativa razonable |
|---|---|---|
| `continua_lognormal.csv` | Lognormal | Lognormal en cabeza del ranking |
| `continua_gamma.csv` | Gamma | Gamma o Weibull arriba (son vecinas) |
| `continua_weibull.csv` | Weibull | Weibull o Gamma arriba |
| `continua_exponencial.csv` | Exponencial | Exponencial muy arriba: mismo ajuste con **1 solo parámetro** (premio de parsimonia) |
| `continua_pareto_cola_pesada.csv` | Pareto (Lomax, α≈2,2) | Pareto/Burr/Loglogística arriba; ligeras (Gamma, Exponencial) hundidas |
| `continua_bimodal.csv` | Mezcla de dos normales | **Ninguna** ajusta bien: puntuaciones bajas y QQ-plot claramente curvado. Caso didáctico |

> Nota: el ranking pondera ajuste (70 %) y parsimonia (30 %), así que la
> distribución "verdadera" no siempre gana — y eso es correcto.

---

## C. Familia discreta

| Fichero | Origen | Expectativa razonable |
|---|---|---|
| `discreta_poisson.csv` | Poisson (λ≈1,8) | Familia **discreta** detectada; Poisson competitiva; sobredispersión ≈ 1 |
| `discreta_binomial_negativa.csv` | Binomial negativa | Binomial negativa arriba; **sobredispersión > 1** |
| `discreta_geometrica.csv` | Geométrica | Geométrica competitiva; muchos ceros |

En los tres, la ficha técnica debe mostrar **chi-cuadrado, grados de libertad y
sobredispersión** en lugar de AD/KS/CvM.

---

## D. Casos límite

| Fichero | Caso | Qué debe ocurrir |
|---|---|---|
| `limite_con_ceros.csv` | 40 ceros de 250 | Las distribuciones estrictamente positivas (Lognormal, Pareto…) **excluyen los ceros y lo declaran** en los avisos; Exponencial los conserva |
| `limite_con_negativos.csv` | 15 valores negativos | Se reportan y excluyen con aviso |
| `limite_muestra_pequena.csv` | n = 8 | Debe funcionar; confianza **baja** (ΔAIC ≈ −0,08: candidatas indistinguibles) |
| `limite_enteros_grandes.csv` | Importes redondeados a entero (n = 200, **199 valores distintos**) | **Se clasifica como continua** desde ADR-020: supera el umbral de 50 valores distintos, luego no es un recuento. Top **lognormal**, confianza **alta** (ΔAIC ≈ 10,4). Antes se clasificaba como discreta y el chi² generaba 48.828 categorías → NaN y bloqueo de la interfaz (ADR-019). En modo manual puede forzarse la familia discreta |
| `limite_casi_constante.csv` | Varianza ≈ 0 | Caso extremo: algunos ajustes pueden no converger y aparecer como descartados, **sin que la aplicación falle** |
| `limite_grande_20k.csv` | 20.000 filas | Prueba de rendimiento: el cálculo puede tardar; después, explorar y comparar debe ser **instantáneo** (no se recalcula el motor) |

---

## E. Datos reales (regresión)

| Fichero | Caso | Qué debe ocurrir |
|---|---|---|
| `real_cost_claims_reducido.csv` | **Datos reales** de seguro de automóvil. 5.030 filas, **4.111 ceros (81,7 %)**, 919 severidades positivas, máximo 71.968,87. Muestreo sistemático determinista (1 de cada 19) del original de 95.554 filas; sin RNG, reproducible byte a byte | Un **único** aviso de exclusión de los 4.111 ceros, declarando severidad **condicionada**. Las 7 candidatas con **919 observaciones usadas**. Pareto sana (`shape ≈ 1,785`, `scale ≈ 599,5`, AIC ≈ 13.563). Recomendada **lognormal**, ΔAIC ≈ **−128**, confianza **baja** |

**Por qué existe este fichero.** Con los ceros dentro, este dataset destapó tres
defectos que los 24 ficheros sintéticos no encontraron: la verosimilitud no
acotada de Lomax con átomo en cero (AIC = −114.612.053), la comparación de
criterios entre muestras distintas y la superposición de un histograma
incondicional sobre densidades condicionadas. Corregidos en ADR-026/027/028; el
fichero se conserva como regresión permanente (`tests/regresion_cost_claims.R`).

---

## Recorrido de prueba sugerido

1. `formato_sin_cabecera_1col.csv` — el caso que provocaba el bug.
2. `formato_columnas_mixtas.csv` — cambia de variable en el selector y recalcula.
3. `continua_pareto_cola_pesada.csv` — activa **modo comparación** (Pareto vs Gamma).
4. `discreta_binomial_negativa.csv` — comprueba que la ficha cambia a tests discretos.
5. `limite_con_ceros.csv` — revisa los avisos de exclusión.
6. `limite_grande_20k.csv` — calcula una vez y explora: debe ir fluido.
7. `limite_enteros_grandes.csv` — debe resolverse al instante y como **continua**.
8. `formato_sin_numericas.csv` — debe salir la **ventana modal** de error.

En todos: la **recomendación oficial** no debe cambiar al explorar, y no deben
aparecer errores ni warnings en consola.
