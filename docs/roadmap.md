# Roadmap — Actuarial Tools by BMK

Fuente única de verdad de los criterios de entrada en cada fase (apartado 12 de
`architecture_v1_1.md`). Resumen operativo; el detalle vinculante está en la
especificación.

## Fase 1 — Portfolio · meses 1 a 8-9 · 25-30 herramientas
`shared/` con `source()`, un módulo Shiny por herramienta, CSV como único
formato de exportación, despliegue manual en shinyapps.io. Arquitectura congelada.

## Fase 2 — Optimización
Entrada: 25-30 herramientas publicadas, o antes si `shared/` genera fricción de
mantenimiento medible. Evaluación de paquete formal, exportación PDF, tests sobre
`calc.R` y `shared/actuarial/`, CI/CD, pase de consistencia visual.

## Fase 3 — Migración parcial · meses 9-12
Exploración de migración de funciones puras a Python donde exista sentido
comercial. La interfaz permanece en Shiny/R.

## Fase 4 — Internal Model Studio / ORSA Platform / Actuarial Risk Hub · año 2+
Aplicación contenedora que monta los mod_<tool> existentes; catálogo automático
desde los manifest.yml; autenticación y persistencia solo si el producto lo exige.
