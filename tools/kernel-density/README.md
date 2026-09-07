# Tool-01 — Kernel Density Estimation

**Actuarial Tools by BMK** · slug `kernel-density` · versión `1.0.0`

Estimación no paramétrica de la densidad de una variable de severidad y lectura
de su VaR, con diagnóstico e interpretación actuarial automática.

Este documento es la referencia oficial de la herramienta: permite entender,
ejecutar y mantener Tool-01 sin necesidad de revisar el historial de desarrollo.

---

## 1. Descripción

**Objetivo.** Permitir a un actuario explorar la distribución de una variable de
severidad (importe de siniestro) sin asumir ninguna forma paramétrica previa, y
leer directamente el riesgo de cola (VaR) que se desprende de la densidad
estimada por kernel.

**Problema actuarial que resuelve.** Antes de comprometerse con un modelo
paramétrico (lognormal, gamma, Pareto…), el actuario necesita ver la forma real
de la severidad —asimetría, multimodalidad, peso de la cola— y obtener una
lectura rápida y honesta del VaR. La herramienta responde en menos de un minuto,
sin programar.

**Casos de uso.**

- Exploración de la forma de la severidad antes de ajustar una distribución.
- Cálculo rápido de un VaR no paramétrico (95 % / 99 % / 99,5 %) de severidad.
- Análisis de sensibilidad al ancho de banda (¿la conclusión de cola depende del
  suavizado?).
- Comparación entre el VaR kernel y el cuantil empírico crudo.
- Uso docente: con "Generar ejemplo" se ilustra el KDE sin datos propios.

---

## 2. Metodología

Enfoque práctico; la teoría completa está en el material del Máster que sirvió de
base.

**Kernel Density Estimation.** La densidad se estima como
`f̂(x) = (1 / (n·h)) · Σᵢ K((x − xᵢ) / h)`, con `K` el núcleo y `h` el ancho de
banda. Se implementan cinco kernels normalizados y simétricos: gaussiano,
Epanechnikov, uniforme, triangular y biweight.

**Selección de bandwidth.** Cuatro métodos, con nomenclatura fiel a la literatura
y verificada contra R base:

| Método | Fórmula | Equivale a |
|---|---|---|
| Silverman (Rule of Thumb) | `0.9 · min(sd, IQR/1.349) · n^(−1/5)` | `stats::bw.nrd0` |
| Scott | `1.06 · min(sd, IQR/1.349) · n^(−1/5)` | `stats::bw.nrd` |
| Normal Reference | `1.06 · sd · n^(−1/5)` | regla normal de referencia |
| Manual | valor `h` elegido por el usuario | — |

**VaR mediante KDE.** La función de distribución se obtiene de forma analítica
como `F̂(x) = (1 / n) · Σᵢ G((x − xᵢ) / h)`, con `G` la CDF del kernel. El VaR es
`F̂⁻¹(p)`, resuelto por inversión numérica de la CDF analítica. **Decisión de
arquitectura congelada:** el VaR es independiente de la rejilla de dibujo; la
rejilla y la comprobación por acumulación (`cumsum`) solo sirven para
visualización y validación cruzada.

**Comparación con el VaR empírico.** Se calcula también el cuantil empírico
(`stats::quantile`) y se muestra junto al VaR kernel: el suavizado redistribuye
la masa de cola en lugar de anclarla al máximo observado.

**Diagnóstico actuarial.** A partir de estadísticos descriptivos, detección de
outliers (regla de Tukey) y clasificación del bandwidth (under/near/over), se
construye un *Assessment* categórico que alimenta los textos prudentes de
Actuarial Insights.

---

## 3. Arquitectura

Cinco capas, con separación estricta entre cálculo y presentación:

```
                 R/calc.R                (motor matemático puro, sin Shiny)
                    │
                    ▼
           Analysis Contract            (salida de kde_analyze(): 7 bloques)
                    │
                    ▼
        prepare_view_model()            (adaptador puro y determinista)
                    │
                    ▼
             View Model                 (7 bloques organizados por componente UI)
                    │
                    ▼
             R/mod_tool.R               (UI + reactividad; solo consume el VM)
                    │
                    ▼
                 app.R                  (ensamblador: carga, monta y arranca)
```

**Responsabilidad de cada capa.**

- **`calc.R`** — toda la matemática (kernels, bandwidth, densidad, CDF, VaR,
  diagnóstico, assessment, textos). Ejecutable en consola sin Shiny. No conoce la
  interfaz.
- **Analysis Contract** — contrato de salida congelado de `kde_analyze()`. Es la
  API pública del motor.
- **`prepare_view_model()`** — función pura y determinista que adapta el contrato
  del motor al contrato de la interfaz. No accede a reactivos ni recalcula
  estadística.
- **View Model** — objeto organizado por componentes de la UI. Es lo único que la
  interfaz consume.
- **`mod_tool.R`** — módulo Shiny. Recoge inputs, invoca el motor con
  `eventReactive` (solo al pulsar Calcular), y renderiza de forma declarativa.
  No implementa cálculo estadístico.
- **`app.R`** — ensamblador puro (regla 15): carga librerías, `shared/`, `calc.R`
  y `mod_tool.R`; define `ui`/`server`; lanza `shinyApp()`.

---

## 4. Estructura del proyecto

```
tools/kernel-density/
├── app.R                       # Ensamblador (orquestación pura)
├── R/
│   ├── calc.R                  # Motor matemático (7 bloques: kernels, bandwidth,
│   │                           #   estimation, diagnostics, assessment, text, orchestrator)
│   └── mod_tool.R              # Módulo Shiny (UI + reactividad) + prepare_view_model()
├── data/
│   └── example_data.csv        # Severidad lognormal de ejemplo (semilla 20260719)
├── docs/
│   ├── design_sprint_0.md      # Diseño funcional
│   ├── design_sprint_1.md      # Diseño definitivo de UX
│   └── architecture_tool.md    # Arquitectura técnica de la herramienta
├── tests/
│   ├── integration_view_model.R
│   ├── acceptance_example.R
│   └── smoke_test.R
├── manifest.yml                # Fuente única de nombre y versión
└── README.md                   # Este documento
```

Depende de `shared/` (en la raíz del repositorio) para theming, componentes,
módulos genéricos, validación y formatters. No añade ninguna dependencia nueva
sobre el stack del framework.

---

## 5. Contrato de entrada

La herramienta admite CSV subido o datos de ejemplo. El contrato de columnas se
valida con `bmk_validate_data()` mediante `c(loss_amount = "numeric")`.

| Campo | Valor |
|---|---|
| Columna obligatoria | `loss_amount` |
| Tipo | `numeric` |
| Unidades | monetarias (u.m.) |
| Restricciones | sin NA (se avisa); severidad positiva (los ≤ 0 generan aviso, no bloqueo); mínimo 5 observaciones; máximo 100.000 filas y 10 MB (límites del framework) |
| Columnas adicionales | permitidas; el selector de columna elige la severidad (por defecto `loss_amount`) |

**Ejemplo (`data/example_data.csv`):**

```
claim_id,loss_amount
CLM00001,301.08
CLM00002,224.03
CLM00003,291.17
...
```

---

## 6. Contrato del motor

API pública: **`kde_analyze(x, kernel, method, h_manual, levels, tool_version, seed)`**.

Devuelve siempre una lista con estos siete bloques (contrato congelado):

| Bloque | Contenido |
|---|---|
| `input` | `n_input`, `n_used`, `n_removed`, `kernel`, `method`, `levels`, `domain` |
| `bandwidth` | `h`, `method`, `automatic` (los h de los métodos), `classification` (under/near/over + posición) |
| `estimation` | `curve` (data.frame `x`, `density`, `cdf`), `var` (data.frame `level`, `var_kde`, `var_empirical`, `rel_gap`) |
| `diagnostics` | `stats` (n, únicos, media, mediana, sd, CV, asimetría, curtosis, min, max, IQR…), `outliers`, `is_small_sample` |
| `assessment` | estado categórico: `sample_size`, `skewness_level`, `tail_behavior`, `outlier_level`, `bandwidth_quality`, `var_gap_level`, `estimation_quality`, `figures` |
| `text` | `diagnostic_notes`, `bandwidth_message`, `insights` (`quality`/`diagnosis`/`recommendation`) — todo `character`, lenguaje prudente |
| `metadata` | `tool`, `tool_version`, `engine_version`, `kernel`, `bandwidth_method`, `h`, `n_used`, `seed`, `created_at` (reproducibilidad) |

El motor no depende de Shiny: puede ejecutarse con `source("R/calc.R")` desde una
consola de R.

---

## 7. Contrato del View Model

`prepare_view_model(analysis, x, manifest)` adapta el contrato del motor a un
objeto organizado por componentes de la interfaz. **La UI consume exclusivamente
este contrato; nunca accede a `estimation`, `diagnostics` ni `assessment`
directamente.**

| Bloque | Contenido | Componente UI |
|---|---|---|
| `cards` | 4 tarjetas con `title`, `value`, `subtitle`, `icon`, `status` | Metric cards |
| `plots` | capas de densidad (histograma, KDE, VaR KDE, VaR empírico) y CDF (CDF, VaR KDE, VaR empírico, nivel de confianza) | Gráficos Plotly |
| `tables` | `risk`, `model_summary`, `diagnostic` (ya formateadas) | Tablas DT |
| `indicator` | `points` posicionados + estado del bandwidth | Indicador (ggplot) |
| `insights` | `diagnostic_notes`, `bandwidth_message`, `quality`, `diagnosis`, `recommendation` | Actuarial Insights |
| `downloads` | `diagnostics`, `risk`, `model_summary` (numérico crudo) | Exportaciones CSV |
| `metadata` | trazabilidad de la ejecución | Footer / registro |

La gramática visual de los gráficos está congelada: densidad = Histograma → KDE →
VaR KDE → VaR empírico; CDF = CDF → VaR KDE → VaR empírico → Nivel de confianza.

---

## 8. Ejecución

Requisitos: R con el stack del framework (shiny, bslib, ggplot2, plotly, DT,
dplyr, tidyr, readr, glue, shinycssloaders, bsicons, yaml).

Desde la raíz del repositorio:

```r
shiny::runApp("tools/kernel-density")
```

O abre `tools/kernel-density/app.R` en RStudio y pulsa **Run App**.

Al arrancar, la aplicación carga automáticamente el **dataset de ejemplo** y
muestra un resultado por defecto (kernel gaussiano + Silverman), sin pantalla
vacía. Para usar datos propios: en la barra lateral, sección **Datos**, elige
"Subir CSV", selecciona la columna de severidad, ajusta kernel y bandwidth y
pulsa **Calcular**.

---

## 9. Tests

Los tests son comprobaciones manuales de Fase 1 (no testthat). Ejecutar desde
`tools/kernel-density/`:

```r
Rscript tests/integration_view_model.R
Rscript tests/acceptance_example.R
Rscript tests/smoke_test.R
```

| Test | Qué verifica |
|---|---|
| `integration_view_model.R` | Que el pipeline motor → View Model funciona y respeta ambos contratos (7 bloques del motor y 7 del VM), sin Shiny. |
| `acceptance_example.R` | Escenario de aceptación sobre el dataset de ejemplo, separado en **invariantes fuertes** (estructura y propiedades matemáticas: densidad ≥ 0, CDF monótona y en [0,1], VaR creciente, conteos) y **valores de referencia** con tolerancias explícitas (h, asimetría, curtosis, CV, VaR). Fija el comportamiento para regresión. |
| `smoke_test.R` | Smoke de ejecución real (headless, `shiny::testServer`): apertura con ejemplo, cambio de kernel, cambio de bandwidth, bandwidth manual, exportaciones y dataset inválido. |

---

## 10. Limitaciones conocidas

- **Slider de bandwidth manual con rango fijo.** El control de `h` manual usa un
  rango estático; para severidades a gran escala puede no alcanzar los anchos de
  banda automáticos. Pendiente de adaptar el rango a la escala de los datos.
- **`icon` / `status` de las cards.** El View Model expone estos campos, pero el
  componente compartido `bmk_metric_card` aún no los representa. Quedan
  disponibles para una futura mejora de `shared/`.
- **Sufijo de fecha en las exportaciones.** `mod_export_csv` añade `_<fecha>.csv`
  al nombre base, de modo que los archivos se descargan como
  `diagnostics_<fecha>.csv`, `risk_summary_<fecha>.csv` y
  `model_summary_<fecha>.csv`.

---

## 11. Roadmap

La siguiente herramienta de la serie será **Tool-02 — Distribution Fitting**,
que reutilizará componentes del framework y funciones puras de `calc.R`
susceptibles de promocionarse a `shared/actuarial/` (kernels, bandwidth,
descriptivos) conforme a la regla de 2 del proyecto.

---

## Checklist final de Tool-01

| Área | Estado |
|---|---|
| **Arquitectura** | Cinco capas congeladas (calc → contrato → view model → mod_tool → app) |
| **Motor** | `calc.R` completo (7 bloques), validado matemáticamente; API `kde_analyze()` congelada |
| **View Model** | `prepare_view_model()` puro; contrato de 7 bloques por componente UI |
| **UI** | `mod_tool.R` declarativo; sin lógica estadística; solo consume el View Model |
| **App** | `app.R` ensamblador puro (regla 15) |
| **README** | Este documento (11 apartados) |
| **Tests** | integration_view_model · acceptance_example · smoke_test |
| **Documentación** | Diseños Sprint 0/1 + arquitectura técnica en `docs/` |
| **Estado** | **Funcionalmente terminada.** Pendiente de ejecución real en R (`smoke_test.R`) y despliegue (checklist 11.4 del framework). |
