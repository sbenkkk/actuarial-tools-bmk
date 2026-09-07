# HIPÓTESIS pendientes de verificar en R — ADR-019/020/021/022

> **AVISO. Esto NO es una verificación.** Ninguna cifra de este documento se ha
> obtenido ejecutando el motor real. Son **predicciones** calculadas con una
> réplica del motor escrita en Python, porque el entorno donde se editó el código
> no tiene R ni puede instalarlo (sin privilegios de root y con CRAN bloqueado
> por el proxy).
>
> **No usar como comportamiento esperado ni citar en documentación** hasta que
> `bash verificar_adr_019_022.sh` termine con `TODO CORRECTO` y esta tabla se
> haya contrastado contra la salida real.

**Qué respalda la réplica y qué no.** Reproduce a 6 decimales todos los valores
de referencia ya congelados en `b3_unit_tests.R` (KS, CvM, AD, AIC, AICc, BIC y
sobredispersión), lo que hace razonable pensar que los estimadores y los
estadísticos coinciden. Pero **no** ejecuta el código de `calc.R`: no valida su
sintaxis, ni el enrutado de familia real, ni la lectura de CSV de
`mod_data_input`, ni nada de la capa Shiny (gráficos, QQ/PP, tiempos, bloqueos).
Un error de escritura en R que la réplica no puede tener seguiría ahí.

**Hipótesis principales a confirmar:**

1. `limite_enteros_grandes.csv` se clasifica como **continua** (ADR-020).
2. En ese fichero gana **lognormal** con confianza **alta** (ΔAIC ≈ 10,4).
3. `poisson` sobre el vector de B3 da **chi² = 1,673333** con **df = 3** y 5 celdas.
4. El reparto de confianza sobre los 24 ficheros es **4 alta / 12 media / 7 baja**.
5. Ni el chi² ni los gráficos bloquean la interfaz con soportes grandes.

| Fichero | Variable | Familia | Ranking (top 3) | Confianza | ΔAIC | Notas |
|---|---|---|---|---|---|---|
| `continua_bimodal.csv` | loss_amount | cont | exponential > pareto > loglogistic | baja | -72.54 |  |
| `continua_exponencial.csv` | loss_amount | cont | exponential > pareto > gamma | baja | 1.88 |  |
| `continua_gamma.csv` | loss_amount | cont | gamma > burr > weibull | media | 3.57 |  |
| `continua_lognormal.csv` | loss_amount | cont | lognormal > burr > loglogistic | media | 6.67 |  |
| `continua_pareto_cola_pesada.csv` | loss_amount | cont | burr > pareto > weibull | baja | 1.43 |  |
| `continua_weibull.csv` | loss_amount | cont | weibull > burr > gamma | media | 2.00 |  |
| `discreta_binomial_negativa.csv` | n_siniestros | disc | negative_binomial > geometric > poisson | alta | 46.18 | chi²=7.987 df=6 celdas=9 |
| `discreta_geometrica.csv` | n_reclamaciones | disc | negative_binomial > geometric > poisson | baja | 0.84 | chi²=5.655 df=6 celdas=9 |
| `discreta_poisson.csv` | n_siniestros | disc | poisson > negative_binomial > geometric | media | 2.00 | chi²=7.541 df=4 celdas=6 |
| `formato_bom_crlf.csv` | loss_amount | cont | lognormal > loglogistic > burr | media | 4.87 |  |
| `formato_cabecera_pyc.csv` | severidad | cont | lognormal > loglogistic > burr | media | 4.87 |  |
| `formato_columnas_mixtas.csv` | paid_loss | cont | lognormal > loglogistic > burr | media | 2.39 |  |
| `formato_con_na.csv` | loss_amount | cont | loglogistic > burr > lognormal | baja | -0.32 |  |
| `formato_nombres_raros.csv` | Importe Siniestro (€) | cont | lognormal > loglogistic > burr | media | 4.87 |  |
| `formato_sin_cabecera_1col.csv` | Variable_1 | cont | lognormal > loglogistic > burr | media | 4.69 |  |
| `formato_sin_cabecera_pyc.csv` | Variable_1 | cont | lognormal > loglogistic > burr | media | 4.87 |  |
| `formato_sin_numericas.csv` | — | — | — | — | — | modal de error: sin columnas numéricas |
| `formato_tabulador.csv` | importe | cont | lognormal > loglogistic > burr | media | 4.87 |  |
| `limite_casi_constante.csv` | valor | cont | lognormal > burr > loglogistic | alta | 16.39 |  |
| `limite_con_ceros.csv` | paid_loss | cont | lognormal > loglogistic > burr | media | 7.36 |  |
| `limite_con_negativos.csv` | resultado | cont | loglogistic > burr > lognormal | baja | -1.30 |  |
| `limite_enteros_grandes.csv` | importe_entero | cont | lognormal > loglogistic > burr | alta | 10.42 |  |
| `limite_grande_20k.csv` | loss_amount | cont | lognormal > burr > loglogistic | alta | 389.94 |  |
| `limite_muestra_pequena.csv` | loss_amount | cont | loglogistic > lognormal > gamma | baja | -0.08 |  |

## Distribución del nivel de confianza

- alta: 4 · media: 12 · baja: 7

Antes de ADR-021 casi todos los ficheros caían en **baja**, porque la separación
del compuesto no tiene escala comparable entre datasets.
