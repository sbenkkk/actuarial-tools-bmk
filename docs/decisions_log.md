# Registro de decisiones — Actuarial Tools by BMK

Memoria externa del proyecto (riesgo: punto único de fallo, apartado 13).

Toda modificación de la arquitectura se registra **aquí y antes** de implementarse
(apartado 15, regla 3). Cada entrada debe incluir: fecha, decisión anterior,
decisión nueva, motivo del cambio y herramientas afectadas.

Durante la Fase 1 la especificación está **congelada**: este registro solo recoge
excepciones aprobadas (p. ej. superación de un límite de datos del apartado 7.5) o
cambios incompatibles en `shared/` (regla 14).

| Fecha | Decisión anterior | Decisión nueva | Motivo | Herramientas afectadas |
|-------|-------------------|----------------|--------|------------------------|
| 2026-07-18 | Fase 1 en desarrollo (estructura del repositorio) | **Fase 1 aprobada y cerrada.** Estructura del repositorio congelada; documento oficial fijado como `docs/architecture_v1_1.md` | Fin de la fase de andamiaje; se inicia la Fase 2 (`shared/theme`). Sin cambios sobre las decisiones de alto nivel de la arquitectura v1.1 | Ninguna (infraestructura; aún no hay herramientas publicadas) |
| 2026-07-18 | Fase 2 en desarrollo (`shared/theme`) | **Fase 2 aprobada y congelada.** Sistema de tema cerrado: `colors.R`, `theme_bmk.R`, `styles.css` con tokens de color, hover, tipografía y espaciado. Todo color/espaciado deriva de `colors.R`/`theme_bmk.R` (cero literales en CSS) | Design system base estable para toda la serie. Cualquier cambio posterior de theming requiere necesidad real detectada durante el desarrollo de herramientas, no mejora teórica | Ninguna (infraestructura) |

| 2026-07-18 | (a) Constantes globales dentro de componentes; (b) estilos inline en componentes; (c) componentes sin atributos ARIA | **Ajustes de cierre de Fase 3 (autorizados por el owner):** (a) nuevo archivo `shared/config.R` para constantes globales del proyecto (fuera del árbol del apartado 9); (b) `styles.css` —Fase 2 congelada— ampliado con clases utilitarias (`.bmk-header-sep/-tool`, `.bmk-interpretation-title`, `.bmk-notification*`) para eliminar todo estilo inline; (c) atributos `role`/`aria-*` en los componentes | Mantenibilidad (constantes y estilos centralizados) y accesibilidad desde el inicio; necesidad real, no mejora teórica | Ninguna publicada. Desviación estructural respecto al apartado 9 (nuevo `config.R`); promovible a `architecture_v2.md` si se decide |

| 2026-07-18 | Fase 3 en desarrollo (`shared/components`) + ajustes de cierre | **Fase 3 aprobada y congelada.** Nueve componentes de UI + `shared/config.R`; estilos inline eliminados a favor de clases CSS reutilizables; atributos `role`/`aria-*` en los componentes | Biblioteca visual estable para toda la serie. Cambios posteriores de componentes requieren necesidad real durante el desarrollo de herramientas | Ninguna (infraestructura) |

| 2026-07-18 | `mod_data_input` fija `options(shiny.maxRequestSize)` (apartado 7.5) y define localmente `BMK_MAX_FILE_*` | **Ajustes de cierre de Fase 4 (autorizados por el owner):** (a) `options(shiny.maxRequestSize)` se traslada a la inicialización global del framework (`shared/load_shared.R`), que se implementa como punto único de carga (apartado 6.1); (b) los límites de tamaño pasan a `shared/config.R` como `bmk_config$max_file_mb/max_file_bytes`. La verificación del tamaño del `fileInput` sigue en `mod_data_input` (7.5). El contrato público 7.3 no cambia | Configuración global en un único sitio; constantes centralizadas. Desviación menor del reparto del 7.5 (solo la config global de maxRequestSize) | Ninguna publicada |

| 2026-07-18 | Fase 4 en desarrollo (`shared/modules`) + ajustes de cierre | **Fase 4 aprobada y congelada.** `mod_data_input` (contrato 7.3, delegación en `bmk_validate_data()`, verificación de tamaño) y `mod_export_csv` (exportación verbatim); `load_shared.R` implementado como punto único de carga; límites de datos en `config.R` | Módulos compartidos estables. Sin más cambios salvo necesidad real durante el desarrollo de herramientas | Ninguna |
| 2026-07-18 | Límite de filas (100.000, apartado 7.5) sin ubicación concreta | **Inicio Fase 5:** el límite de filas se añade a `shared/config.R` como `bmk_config$max_rows`, junto al de tamaño de archivo, como hogar único de los límites de datos (coherencia con la decisión de Fase 4) | Un único lugar para los límites de datos del apartado 7.5 | Ninguna |

| 2026-07-18 | Fase 5 en desarrollo (`shared/validation`) + ajustes de cierre | **Fase 5 aprobada y congelada.** `bmk_validate_data()` (función pura, contrato 7.4: vacío, columnas ausentes/mal nombradas, tipos, exceso de NA, límite de filas); parámetros `max_rows` y `max_na_prop` en `config.R`; mensajes de `errors` orientados al usuario para `bmk_notify()`. **Alcance cerrado:** la responsabilidad de `bmk_validate_data()` queda limitada a la validación ESTRUCTURAL de la arquitectura; no se ampliará con reglas de negocio, validaciones actuariales ni comprobaciones específicas de herramientas | Validación compartida estable y de alcance acotado. Toda validación de negocio vivirá en la herramienta (calc.R), no aquí | Ninguna |

| 2026-07-18 | `shared/utils/` con un único archivo `format_helpers.R` (apartado 9) | **Inicio Fase 6 (autorizado por el owner):** `shared/utils/` se implementa con dos archivos, `formatters.R` (formateo puro) y `helpers.R` (helpers generales), en lugar de `format_helpers.R`. `%||%` permanece en `theme_bmk.R` (Fase 2 congelada): no se duplica ni se mueve; `helpers.R` no lo incluye | Separar formato de helpers mejora la mantenibilidad; evitar duplicar/mover `%||%` respeta el congelado y la no-duplicación | Ninguna publicada. Desviación estructural del apartado 9 (naming de utils) |

| 2026-07-18 | Placeholder obsoleto `format_helpers.R` presente; convención de prefijos implícita | **Ajustes de cierre de Fase 6 (autorizados):** (1) `format_helpers.R` eliminado definitivamente del repositorio; (2) `%||%` permanece únicamente en `theme_bmk.R` (no se reabre la Fase 2; consolidación en backlog); (3) convención de nomenclatura fijada como estándar: en `shared/utils` (y en todo `shared/`) las funciones públicas usan `bmk_` y las internas `.bmk_`, salvo las excepciones ya sancionadas (`mod_`, `theme_bmk*`, `%||%`) | Repositorio limpio y convención uniforme verificada en todo el framework (16 públicas `bmk_`, 8 internas `.bmk_`) | Ninguna |

## Backlog de mejoras futuras (no implementadas)

Mejoras identificadas y aparcadas deliberadamente para respetar el alcance de cada fase. Se retomarán solo ante necesidad real, con registro previo en este documento.

| Fecha alta | Mejora | Motivo de aplazamiento |
|------------|--------|------------------------|
| 2026-07-18 | Token `--bmk-focus-ring` para el anillo de foco de inputs (hoy `rgba` del primario con alfa en `styles.css`) | Único punto de theming con un color no derivado de `colors.R`; se difiere para no reabrir la Fase 2 por una mejora teórica |
| 2026-07-18 | Accesibilidad avanzada de componentes (más allá de role/aria-* básicos ya añadidos): `aria-live` en outputs que se recalculan, foco gestionado, contraste AAA | Base de accesibilidad ya cubierta; el refinamiento se difiere para no ampliar el alcance de la Fase 3 |
| 2026-07-18 | Revisión del mecanismo de resolución de rutas de `load_shared.R` (hoy basado en `sys.frame()$ofile`); evaluar alternativas más robustas si aparece fricción real de carga | Funciona para `source()`; se difiere por no haber necesidad real |
| 2026-07-18 | Consolidar `%||%` en `shared/utils/helpers.R` (hoy en `theme_bmk.R`), cuando proceda reabrir la theme por otra razón real | Evita reabrir un archivo congelado solo por reubicar un operador |
