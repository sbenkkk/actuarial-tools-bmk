# Plantilla Base (Tool 0)

Plantilla oficial del proyecto *Actuarial Tools by BMK*. No es una herramienta
actuarial: es infraestructura que valida el ensamblaje del framework y sirve de
base para copiar (apartado 12.1). No es una entrada del catálogo.

## Qué hace

Carga datos (ejemplo o CSV), valida el contrato de columnas, calcula un resumen
básico (filas, columnas, medias) y permite exportarlo. Demuestra que theme,
componentes, módulos, validación, formatters y helpers funcionan juntos.

## Columnas de entrada esperadas

| Columna | Tipo | Obligatoria | Descripción |
|---------|------|-------------|-------------|
| loss_amount | numeric | Sí | Importe de siniestro (contrato de datos) |

El ejemplo incluye además `policy_id`, `date_occurred` y `exposure`.

## Cómo se usa

`shiny::runApp("tools/tool-00-template")` → "Datos de ejemplo" → "Calcular" →
"Exportar CSV". Funciona de extremo a extremo sin tocar ningún input.

## Resultados

Métricas (filas, columnas, % numéricas, siniestro medio), gráfico de registros
válidos por columna, tabla de resumen e interpretación en lenguaje natural.

## Limitaciones conocidas

Sin cálculo actuarial (por diseño). Límites de datos: 10 MB de archivo, 100.000
filas (apartado 7.5).

## Referencia de cálculo

No aplica: la operación (conteos y medias) es trivial y solo valida el flujo.
