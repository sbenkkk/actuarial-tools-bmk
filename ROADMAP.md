# Actuarial Tools by BMK — Roadmap de herramientas

Progreso del proyecto. La infraestructura (**BMK Framework v1.0**) está terminada;
a partir de aquí cada herramienta se construye clonando `tools/tool-00-template/`
(apartado 12.1 de la arquitectura).

## Estado por Sprint

- ✔ **Sprint 0 — Arquitectura** · **COMPLETADO** (2026-07-25). Arquitectura de plataforma
  aprobada y congelada (`docs/architecture_v2.md`, v2.0), diseño de Tool-02 aprobado.
  Acta de cierre: `docs/sprint0_closure.md`. Release base: `docs/releases.md` (v2.0.0, Architecture Frozen).
- ✔ **Sprint 1 — Implementación de Tool-02 (`distribution-fitting`)** · **CODE-COMPLETE**
  (2026-07-25). Bloques B0–B8 APPROVED y auditoría B9 realizada
  (`tools/distribution-fitting/RELEASE_AUDIT.md`, ADR-016). Pendiente de publicación:
  prueba con CSV real, revisión visual, despliegue, captura y paso de `manifest.yml`
  a `status: published`.

> Este documento sigue el **progreso de las herramientas**. El roadmap de fases
> del framework vive en `docs/roadmap.md`.

**Leyenda:** ✅ Terminada · 🟡 En curso · ⬜ Pendiente

| Estado | Herramienta | Slug | Prioridad |
|:---:|---|---|---|
| ✅ | BMK Framework v1.0 | *(infraestructura)* | Finalizado |
| 🟡 | Kernel Density Estimation | `kernel-density` | Próxima |
| 🟡 | Distribution Fitting | `distribution-fitting` | Code-complete (pendiente de publicar) |
| ⬜ | Goodness of Fit | `goodness-of-fit` | Pendiente |
| ⬜ | Exploratory Data Analysis | `exploratory-data-analysis` | Pendiente |
| ⬜ | Extreme Value Theory | `extreme-value-theory` | Pendiente |

## Orden y razonamiento

Kernel Density → Distribution Fitting → Goodness of Fit forman un **bloque
temático coherente** (estimación y ajuste de distribuciones). La EDA se sitúa
después por ser más **transversal**: podrá reutilizar ideas y código de las tres
primeras para resultar una herramienta más completa. Extreme Value Theory cierra
el primer bloque.

## Objetivo global

Entre 30 y 40 herramientas (apartado 1.1). Fase 1: 25-30 publicadas. Esta tabla
se ampliará a medida que se definan nuevas herramientas; cada una se añade con su
slug en `kebab-case` (apartado 9.1).
