# Platform Release Log — Actuarial Tools by BMK

Punto de referencia permanente de las versiones de plataforma. Cada release fija un estado congelado y auditable desde el que continúa el desarrollo. Se añade una entrada por versión; las anteriores no se sobrescriben.

---

## Platform Release

```
Version:       v2.0.0
Status:        Architecture Frozen
Sprint:        Sprint 0
Release Date:  2026-07-25

Scope:
  • Platform architecture approved
  • Governance approved
  • Tool-02 approved
  • Decision Engine approved
  • Sprint 1 ready
```

**Documentos de la release.** Arquitectura vigente: `docs/architecture_v2.md` (v2.0, Approved). Diseño de Tool-02: `tools/distribution-fitting/tool_02_distribution_fitting_design.md` (v1.0, Approved). Criterio: `tools/distribution-fitting/decision_engine.md` (estructura aprobada). Registro de decisiones: `docs/decisions_log.md` (ADR-000…013). Acta de cierre: `docs/sprint0_closure.md` (Sprint 0 → CLOSED).

Esta versión constituye el **punto base** desde el que comienza el desarrollo. Equivale al hito `v2.0.0 · Architecture Frozen · Sprint 0 Closed · Tool-02 Ready` (no es necesario crear el tag Git; queda reflejado documentalmente aquí).

---

## Cambio oficial de fase

- **Hasta Sprint 0:** el objetivo era **diseñar** la plataforma.
- **Desde Sprint 1:** el objetivo es **implementar** la plataforma. La arquitectura aprobada pasa a ser un **contrato**.

Cualquier modificación arquitectónica requiere: **(1)** un ADR, **(2)** una justificación técnica y **(3)** demostrar un beneficio claro respecto a la arquitectura vigente. En ausencia de ello, **la arquitectura no se modifica**.

---

## Principio de gobernanza (Sprint 1 en adelante)

> La arquitectura deja de ser un documento de diseño y pasa a ser un **contrato de implementación**.
> Durante el Sprint 1, **la implementación se adapta a la arquitectura, no la arquitectura a la implementación**.
> Solo un ADR aprobado podrá romper este principio.

Registrado en `docs/decisions_log.md` (ADR-011, ADR-012, ADR-013).

---

*Actuarial Tools by BMK — Release v2.0.0 · Architecture Frozen · 2026-07-25.*
