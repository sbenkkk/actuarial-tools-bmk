# Acta de Cierre — Sprint 0 (Arquitectura)

| Campo | Valor |
|---|---|
| **Proyecto** | Actuarial Tools by BMK |
| **Documento** | `docs/sprint0_closure.md` |
| **Sprint** | 0 — Arquitectura de plataforma y diseño de Tool-02 |
| **Fecha de cierre** | 2026-07-25 |
| **Arquitectura vigente** | `docs/architecture_v2.md` (v2.0, Approved) |
| **Estado final** | **Sprint 0 → CLOSED** |

Documento ejecutivo de certificación. No reproduce el contenido de otros documentos; remite a ellos.

---

## 1. Objetivo del Sprint 0

Definir y congelar la arquitectura de la plataforma y el diseño completo de la primera herramienta analítica (Tool-02, Distribution Fitting) **antes** de escribir código, de forma que la implementación pueda ejecutarse sin tomar decisiones de arquitectura.

## 2. Alcance

Dentro de alcance: filosofía de plataforma, arquitectura por capas, principios comunes (coste computacional, validez estadística, versionado, gobernanza) y el diseño de Tool-02 (motor, criterio, interpretación, View Model, API, plan de implementación). Fuera de alcance: escritura de código, diseño de pantallas y el diseño de herramientas posteriores a Tool-02.

## 3. Decisiones arquitectónicas principales

Registradas formalmente como ADR en `docs/decisions_log.md` (ADR-000 a ADR-012). En síntesis:

- Promoción de la arquitectura maestra a **v2.0** (ADR-000).
- Tool-02 soporta distribuciones **continuas y discretas** con enrutado por diagnóstico previo (ADR-001, ADR-005).
- La **GPD sale del ranking**; se deriva a EVT/Tool-03 (ADR-002).
- **Criterio en dos fases** (evaluación absoluta → ranking) y **recomendación dual** (ADR-004, ADR-006).
- **Criterio externalizado** a `decision_engine.md`, versionado (ADR-003, ADR-009).
- **Filosofía de coste computacional** (calidad > tiempo; profundidad Standard/Comprehensive; transparencia; optimizar ≠ degradar) — de plataforma (ADR-007).
- **Principio de validez estadística** — de plataforma (ADR-008).
- **Proceso ADR** obligatorio para todo cambio arquitectónico posterior (ADR-011).

## 4. Documentos aprobados

| Documento | Rol | Estado |
|---|---|---|
| `docs/architecture_v2.md` | Arquitectura maestra de plataforma (vigente) | Approved (v2.0) |
| `docs/architecture_v1_1.md` | Arquitectura anterior | Conservada (superada por v2.0) |
| `docs/decisions_log.md` | Registro de decisiones (histórico + ADR) | Vigente |
| `tools/distribution-fitting/tool_02_distribution_fitting_design.md` | Diseño de Tool-02 | Approved (v1.0) |
| `tools/distribution-fitting/decision_engine.md` | Parametrización del criterio de Tool-02 | Estructura aprobada; calibración pendiente (implementación) |

## 5. Cambio de fase y de gobernanza (constancia)

A partir del cierre del Sprint 0, y **sin modificar la gobernanza ya vigente** (arquitectura `architecture_v2.md`, regla 20; ADR-011), se deja constancia de que:

- La arquitectura se considera **congelada**.
- Toda modificación arquitectónica requiere un **ADR** que demuestre beneficio claro respecto a la arquitectura vigente.
- Las **mejoras menores** no requieren modificar la arquitectura; se anotan en el backlog de `docs/decisions_log.md`.
- La **prioridad del proyecto pasa a ser implementar** la arquitectura aprobada.

## 6. Principio de Sprint 1 (cambio de rol)

Queda establecido como principio del proyecto, reflejado también en `docs/decisions_log.md` (ADR-012):

> **Durante el Sprint 1, la arquitectura aprobada se considera un contrato. La prioridad ya no es rediseñar; la prioridad es implementar respetando dicho contrato.**

## 7. Siguiente hito

**Sprint 1 — Implementación de Tool-02 (`distribution-fitting`)**: desarrollo de los bloques B0–B9 definidos en el diseño aprobado. Referencia de progreso en `ROADMAP.md`.

---

**Certificación:** con la aprobación de los documentos del apartado 4 y el registro de las decisiones en `docs/decisions_log.md`, el **Sprint 0 queda oficialmente cerrado (CLOSED)** y el repositorio está preparado para comenzar la implementación de Tool-02.

*Actuarial Tools by BMK — Acta de Cierre del Sprint 0 — 2026-07-25.*
