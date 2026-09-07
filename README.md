# Actuarial Tools by BMK

Colección de 30-40 herramientas actuariales independientes construidas sobre una
infraestructura común (**BMK Framework**). Cada herramienta resuelve un único
problema, priorizando la calidad y la robustez del análisis sobre el tiempo de
ejecución.

Base futura de **Internal Model Studio**, **ORSA Platform** y **Actuarial Risk Hub**.

## Estructura

- `shared/` — infraestructura común cargada con `source()` (theming, componentes,
  módulos, validación, utilidades, cálculo promovido).
- `tools/` — una carpeta por herramienta (slug en `kebab-case`). `tool-00-template`
  es la plantilla base, no una entrada de catálogo.
- `docs/` — arquitectura, registro de decisiones, contrato de datos y roadmap.
- `renv.lock` — único lockfile de dependencias del proyecto.

## Arquitectura

La referencia única y vinculante es **`docs/architecture_v2.md` (v2.0, Approved)**,
que sustituye a `docs/architecture_v1_1.md` (conservada). Congelada; toda
modificación arquitectónica requiere un ADR en `docs/decisions_log.md` (regla 20).

## Stack (Fase 1)

R · Shiny · bslib · ggplot2 · plotly · DT · dplyr · tidyr · readr · glue ·
shinycssloaders · bsicons · yaml · renv.

## Ejecutar una herramienta

```r
shiny::runApp("tools/<slug>")
```

Cada herramienta es autocontenida y ejecutable de forma independiente (regla 11).
