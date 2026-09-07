# Checklist de aceptación manual — Tool-02 tras ADR-019/020/021/022

> **Las columnas "Predicción" contienen hipótesis NO verificadas**, calculadas con
> una réplica del motor en Python. No son el comportamiento esperado oficial. El
> objetivo de esta checklist es precisamente contrastarlas contra el motor real.
> Si lo observado difiere de lo predicho, **gana lo observado** y hay que revisar
> el código, no la predicción.

**Antes de empezar:** ejecuta `bash verificar_adr_019_022.sh` desde la raíz del
repositorio. Si termina con `HAY FALLOS`, no sigas con las pruebas manuales:
pásame `verificacion_R.log` primero.

Arranque de la aplicación:

```
cd tools/distribution-fitting
R -e 'shiny::runApp(".")'
```

---

## 0. Comprobaciones transversales (en TODOS los casos)

Marca solo las desviaciones.

| # | Qué comprobar | OK / Desviación |
|---|---|---|
| 0.1 | La consola de R no muestra **errores ni warnings** durante la carga ni el cálculo | |
| 0.2 | La **recomendación oficial no cambia** al explorar otras distribuciones | |
| 0.3 | Los gráficos QQ y PP se dibujan completos, sin huecos ni ejes vacíos | |
| 0.4 | El histograma/PMF y las curvas ajustadas se superponen correctamente | |
| 0.5 | La interfaz responde en todo momento (sin spinner infinito ni congelación) | |
| 0.6 | La ficha de la distribución muestra los tests correctos según familia: **KS/CvM/AD** en continua, **chi²/gl/sobredispersión** en discreta | |

---

## 1. Caso de regresión principal — el bug reportado

| Fichero | Qué comprobar | Predicción (sin verificar) | Observado |
|---|---|---|---|
| `limite_enteros_grandes.csv` | **Que no se quede cargando.** Cronometra desde "Calcular" hasta ver el ranking | < 3 s | |
| | Familia detectada | **continua** | |
| | Distribución recomendada | lognormal | |
| | Nivel de confianza | alta (ΔAIC ≈ 10,4) | |
| | Ranking: 2.ª y 3.ª | loglogística > burr | |
| | El gráfico de curvas ajustadas se dibuja (no un lienzo en blanco ni miles de puntos) | curva suave | |
| | QQ y PP se dibujan y son legibles | sí | |

**Prueba adicional del mismo fichero — forzar la familia a mano.** En modo manual,
fuerza **discreta** sobre este mismo fichero. Es el camino que antes producía el
bloqueo y el chi² NaN.

| Qué comprobar | Predicción (sin verificar) | Observado |
|---|---|---|
| La app **no se bloquea** al forzar discreta | responde en pocos segundos | |
| El chi² sale con un **valor numérico o un NA explicado**, nunca `NaN` ni celda vacía | valor finito o nota | |
| El ranking muestra puntuaciones (no columnas vacías) | puntuaciones visibles | |
| El gráfico de PMF se dibuja sin congelar el navegador | sí | |

---

## 2. Familia continua

| Caso pedido | Fichero | Predicción: top (sin verificar) | Confianza | Observado |
|---|---|---|---|---|
| Lognormal | `continua_lognormal.csv` | lognormal | media | |
| Gamma | `continua_gamma.csv` | gamma | media | |
| Pareto | `continua_pareto_cola_pesada.csv` | burr (> pareto) | baja | |
| Weibull | `continua_weibull.csv` | weibull | media | |
| Exponencial | `continua_exponencial.csv` | exponencial | baja | |
| Bimodal (caso didáctico) | `continua_bimodal.csv` | ninguna ajusta bien; QQ claramente curvado | baja | |

**Sobre "continua normal":** no existe un fichero de muestra Normal, porque la
Normal es la **distribución de control** (§4.3), no una candidata del ranking. Se
comprueba en cualquiera de los ficheros anteriores:

| Qué comprobar | Observado |
|---|---|
| La ficha o el texto menciona el **control Normal** y si su AIC es mejor o peor que el de la recomendada | |
| La Normal **no aparece** dentro del ranking de candidatas | |

Si quieres un fichero Normal explícito, dímelo y lo genero — no está en el juego actual.

---

## 3. Familia discreta

Aquí es donde actúa el chi² con agrupación de categorías (ADR-019).

| Caso | Fichero | Predicción: top (sin verificar) | Confianza | Predicción: chi² / gl / celdas | Observado |
|---|---|---|---|---|---|
| Poisson | `discreta_poisson.csv` | poisson | media | 7,541 / 4 / 6 | |
| Binomial negativa | `discreta_binomial_negativa.csv` | binomial negativa | alta (ΔAIC ≈ 46) | 7,987 / 6 / 9 | |
| Geométrica | `discreta_geometrica.csv` | binomial negativa (empate técnico con geométrica) | baja (ΔAIC ≈ 0,8) | 5,655 / 6 / 9 | |

| Qué comprobar además en los tres | Observado |
|---|---|
| Se muestra la **sobredispersión** (varianza/media) | |
| Los grados de libertad son un número pequeño y coherente (no miles) | |
| El diagrama de barras de la PMF observada vs ajustada se dibuja correctamente | |

---

## 4. Importación de ficheros

| Caso pedido | Fichero | Qué comprobar | Observado |
|---|---|---|---|
| CSV sin cabecera | `formato_sin_cabecera_1col.csv` | Columna llamada `Variable_1` y **200 filas** (no 199: no debe perderse la primera observación) | |
| CSV sin cabecera, varias columnas | `formato_sin_cabecera_pyc.csv` | `;` detectado, `Variable_1..3`, 180 filas | |
| CSV con `;` | `formato_cabecera_pyc.csv` | Columnas `severidad` / `exposicion` con sus nombres reales | |
| CSV con tabuladores | `formato_tabulador.csv` | Separador detectado, columna `importe` | |
| CSV con importes en euros | `formato_nombres_raros.csv` | La variable `Importe Siniestro (€)` aparece en el selector con acentos y símbolo intactos | |
| BOM + CRLF | `formato_bom_crlf.csv` | El primer nombre de columna sale limpio, sin caracteres extraños | |
| Columnas mixtas | `formato_columnas_mixtas.csv` | El selector ofrece **solo 3** columnas numéricas; al cambiar de variable, recalcula | |
| Con NA | `formato_con_na.csv` | Se reportan **8 ausentes**, n = 112 | |

### 4.1 CSV sin columnas numéricas — el modal nuevo (ADR-022)

| Fichero | Qué comprobar | Observado |
|---|---|---|
| `formato_sin_numericas.csv` | Aparece una **ventana modal que bloquea la pantalla**, no un aviso flotante en la esquina | |
| | Título: "El archivo no contiene datos numéricos" | |
| | Se muestra una **tabla con cada columna, su tipo detectado y su primer valor** | |
| | Se listan las causas habituales (coma decimal, separador de miles, moneda, texto) | |
| | El modal **no se cierra** pulsando fuera ni con Esc (solo con "Entendido") | |
| | Tras cerrarlo, el selector de variable está vacío y el cálculo **no** se habilita | |
| | No aparece **además** el aviso flotante antiguo (no debe haber mensaje duplicado) | |
| | Los colores e iconos son coherentes con el resto de la aplicación | |

---

## 5. Casos límite

| Fichero | Qué comprobar | Predicción (sin verificar) | Observado |
|---|---|---|---|
| `limite_con_ceros.csv` | Se declaran **40 ceros excluidos**, n = 210, en las distribuciones estrictamente positivas | lognormal, media | |
| `limite_con_negativos.csv` | Se declaran **15 negativos excluidos**, n = 185 | loglogística, baja | |
| `limite_muestra_pequena.csv` | n = 8: funciona sin romperse | loglogística, baja | |
| `limite_casi_constante.csv` | Varianza ≈ 0: algunos ajustes pueden aparecer descartados, **sin que la app falle** | lognormal, alta | |
| `limite_grande_20k.csv` | **Cronometra el primer cálculo**; después, cambiar de distribución y explorar debe ser instantáneo (no se recalcula el motor) | lognormal, alta | |

---

## 6. Resultado de la verificación

| | |
|---|---|
| Fecha | |
| Versión de R | |
| `verificar_adr_019_022.sh` termina con | ☐ TODO CORRECTO ☐ HAY FALLOS |
| Nº de casos manuales con desviación | |

**Si algo falla o difiere de la predicción, pásame:** el fichero, el caso, lo
observado, lo predicho, y el texto de cualquier error o warning de la consola de
R. Con eso preparo el informe (qué falla, por qué, qué cambio lo provoca, cómo
corregirlo, si afecta a `shared/` y si requiere ADR nuevo).
