# Actuarial Tools by BMK — Especificación Técnica de Arquitectura

| Campo | Valor |
|---|---|
| **Nombre del proyecto** | Actuarial Tools by BMK |
| **Documento** | `docs/architecture_v2.md` |
| **Versión** | **2.0** |
| **Fecha** | Julio 2026 |
| **Estado** | **Approved** |
| **Sustituye a** | v1.1. **Cambio de decisión de alto nivel** (filosofía de coste computacional y principios de plataforma). Conforme a la regla §15.6, v1.1 se conserva y no se sobrescribe |
| **Vigencia** | Congelada. A partir de esta versión, todo cambio arquitectónico requiere un *Architectural Decision Record* (ADR) en `docs/decisions_log.md` que demuestre beneficio claro respecto a la arquitectura vigente (§10, regla 20) |

**Objetivo del documento**

Este documento es la especificación técnica oficial y única referencia de arquitectura del proyecto *Actuarial Tools by BMK*. Define la filosofía de producto, la arquitectura de software, los componentes reutilizables, la estructura del repositorio, las convenciones de programación, los criterios de finalización de cada herramienta, el roadmap de evolución, los riesgos identificados y el contrato técnico del proyecto.

Toda herramienta desarrollada dentro del proyecto debe cumplir lo aquí especificado. Este documento es autosuficiente: no requiere ningún contexto adicional, conversación previa ni documento complementario para ser aplicado.

---

## Changelog v2.0

Cambios de decisión de alto nivel aprobados al cierre del Sprint 0 de Tool-02. A diferencia de la v1.1 (correcciones de consistencia), esta versión modifica decisiones de producto y se registra en `docs/decisions_log.md`.

| # | Cambio | Origen (ADR) | Apartados afectados |
|---|---|---|---|
| 1 | **Retirada de la promesa de "resultado en menos de un minuto".** Se sustituye por una filosofía de plataforma basada en calidad, robustez estadística, reproducibilidad y transparencia. El tiempo de ejecución es consecuencia del problema, no un objetivo | ADR-007 | 1.3, 1.4, 1.7, 5 |
| 2 | **Profundidad del análisis controlada por el usuario** (perfiles *Standard* / *Comprehensive*), sin degradación automática por tamaño de dataset. La diferencia es profundidad, no velocidad | ADR-007 | 1.7, 10 (regla 19) |
| 3 | **Principio explícito "optimizar la implementación: sí; degradar el análisis automáticamente: no"** | ADR-007 | 1.7, 10 (regla 19) |
| 4 | **Filosofía de transparencia del progreso**, derivada de las capas de la arquitectura | ADR-007 | 1.7, 5 |
| 5 | **Principio de validez estadística**: los procedimientos cuya validez dependa de la estimación de parámetros deben ser válidos para ese contexto; su implementación pertenece al motor matemático, no al criterio ni al View Model | ADR-008 | 1.8, 10 (regla 18) |
| 6 | **Versionado del View Model (`schema_version`) y del criterio parametrizado (`decision_engine_version`)**, y tupla de reproducibilidad | ADR-009 | 10 (regla 20), 14 |
| 7 | **Proceso ADR obligatorio** para todo cambio arquitectónico posterior al Sprint 0 | ADR-011 | Cabecera, 10 (regla 20), 15 |

Estos principios son de **plataforma**: los heredan automáticamente todas las herramientas presentes y futuras (Tool-01, Tool-02, Tool-03 EVT, Tool-04 Aggregate Models, Tool-05 Pricing, Internal Model Studio, ORSA Platform).

---

## Changelog v1.1

Correcciones aplicadas sobre la v1.0 tras auditoría externa de arquitectura. Ninguna decisión de alto nivel fue modificada; todas las correcciones fueron de consistencia interna, nomenclatura, contratos y referencias cruzadas. Se conserva íntegro por trazabilidad.

| # | Corrección | Apartados afectados |
|---|---|---|
| 1 | **Regla del prefijo `bmk_` reformulada con excepciones explícitas.** Los módulos Shiny compartidos usan prefijo `mod_`; las funciones de theming usan el patrón `theme_bmk*()`. `validate_data()` pasa a denominarse `bmk_validate_data()` en todo el documento. Se aclara que el prefijo aplica a nombres de función, no a nombres de archivo | 7.2, 7.3, 7.4, 10 (regla 3), 11, 13, 14 |
| 2 | **Reparto de responsabilidad en los límites de datos.** El límite de tamaño de archivo (10 MB) se aplica en `mod_data_input`, con configuración explícita de `shiny.maxRequestSize`; el límite de filas (100.000) se aplica en `bmk_validate_data()`. Se elimina de `bmk_validate_data()` la validación de tamaño de archivo, técnicamente imposible desde su firma | 7.2, 7.4, 7.5, 13, 14 |
| 3 | **Unificación del trigger de entrada en Fase 2.** El roadmap (apartado 12) pasa a ser la única fuente de verdad; el apartado 8 referencia la fase sin cifras propias | 8, 12 |
| 4 | **Corrección del criterio de conversión a paquete formal.** Se sustituye por la fricción real: re-despliegue y ausencia de versionado del código compartido | 8, 12 |
| 5 | **Corrección de referencia cruzada rota.** La regla de promoción a `shared/` está en el apartado 10 (regla 4), no en el 7.4 | 2.2 |
| 6 | **Separación de `shared/utils/` y `shared/actuarial/`** | 2.2, 9 |
| 7 | **Unificación del formato de versión y fuente única de verdad.** Semver de tres componentes; `manifest.yml` como única fuente del versionado | 4.1, 7.2, 9.2, 11.3, 14 |
| 8 | **Alineación de la vigencia del documento con el periodo de congelación** | Cabecera, 14, 15 |
| 9 | **Asignación de fase a las herramientas 31-40** | 12 |
| 10 | **Unificación de la nomenclatura de los archivos de `docs/`** en `snake_case` | 7.6, 9, 14, 15 |
| 11 | **Aclaración del criterio de finalización relativo a la validación** | 11.1 |
| 12 | **Aclaración de la regla de versionado del propio documento** | 15 |

---

## 1. Filosofía del proyecto

### 1.1 Naturaleza del proyecto

*Actuarial Tools by BMK* es una colección de entre 30 y 40 aplicaciones actuariales independientes, desarrolladas a lo largo de aproximadamente un año.

No se trata de una única aplicación de gran tamaño, sino de un ecosistema de herramientas autónomas, cada una enfocada en resolver un problema actuarial concreto.

Cada aplicación debe ser suficientemente útil como para ser utilizada tanto por estudiantes como por profesionales del sector asegurador.

### 1.2 Objetivos del proyecto

- Construcción de portfolio técnico.
- Construcción de marca personal.
- Creación de un repositorio de código reutilizable.
- Base para productos comerciales futuros: **Internal Model Studio**, **ORSA Platform**, **Actuarial Risk Hub**.

### 1.3 Principios de diseño de producto

- **Cada aplicación resuelve un único problema.** Esta es la decisión de producto más importante del proyecto y tiene prioridad sobre cualquier decisión técnica.
- No se construyen aplicaciones enormes.
- No se construyen interfaces con veinte pestañas.
- No se construyen configuraciones complejas.
- Se prefiere una aplicación extremadamente sencilla pero excelente.
- **Cada herramienta prioriza la calidad y la robustez del análisis sobre el tiempo de ejecución.** El tiempo es una consecuencia del problema analizado, no un objetivo de diseño (ver §1.7). No existe una promesa de tiempo máximo de ejecución.
- Cada herramienta debe ser intuitiva incluso para alguien que nunca la haya utilizado.
- Si una funcionalidad no aporta valor real, no se añade.

### 1.4 Jerarquía de prioridades

Ante cualquier decisión con varias opciones posibles, se prioriza siempre en este orden:

```
simplicidad                >  complejidad
claridad                   >  cantidad de funcionalidades
calidad y robustez         >  velocidad
reproducibilidad           >  inmediatez
```

### 1.5 Reutilización como criterio permanente

Todo el código se diseña pensando en su futura reutilización. Cada herramienta es una pieza de un sistema mayor y debe poder convertirse en un módulo de Internal Model Studio, ORSA Platform o Actuarial Risk Hub sin reescritura de la lógica actuarial.

### 1.6 Alcance de la Tool 0

La Tool 0 no es una aplicación actuarial y no se publica externamente. Es la **plantilla base** del proyecto: un esqueleto funcional que arranca y muestra header, sidebar, entrada de datos, resultados, exportación y footer con la identidad visual definitiva, sin ningún cálculo actuarial dentro.

Su función es eliminar de todas las herramientas futuras las decisiones repetidas de maquetación, estilo, estructura de carpetas y flujo de usuario, garantizando consistencia visual y técnica a lo largo de las 40 aplicaciones y reduciendo el tiempo de desarrollo por herramienta.

### 1.7 Filosofía de coste computacional, profundidad y transparencia (principio de plataforma)

*(Introducido en v2.0 — ADR-007. Aplica a todas las herramientas presentes y futuras.)*

La plataforma **no** establece una promesa de tiempo máximo de ejecución. Estas herramientas se utilizan en proyectos actuariales reales, no compiten con calculadoras online, y es aceptable que un análisis tarde varios minutos cuando ello aporta mayor robustez y confianza. La prioridad, en orden, es: **calidad del análisis → robustez estadística → reproducibilidad → confianza en las recomendaciones.**

Cuatro principios concretan esta filosofía:

**a) Sin degradación automática por tamaño.** Ninguna herramienta reduce o desactiva análisis de forma automática en función del volumen de datos. Hacerlo haría que el rigor dependiera del tamaño del dataset sin que el usuario lo supiera — un riesgo de reproducibilidad y auditoría.

**b) Profundidad controlada por el usuario (perfiles enumerados).** La profundidad del análisis es una decisión explícita del usuario, expresada como un conjunto pequeño, fijo y documentado de perfiles:

| Perfil | Orientado a |
|---|---|
| **Standard** (defecto) | El modo recomendado para la mayoría de análisis actuariales |
| **Comprehensive** | Análisis exhaustivo para documentación técnica, estudios avanzados o revisión actuarial |

La diferencia entre perfiles es la **profundidad** del análisis (qué validaciones se ejecutan y con qué presupuesto de remuestreo), **no** la velocidad. Los perfiles no se describen como "rápido" ni "lento". Cambiar de perfil altera amplitud y precisión Monte Carlo, **nunca** la validez de un estadístico; cada perfil respeta suelos mínimos de remuestreo documentados. `Standard` es el defecto para que un usuario nuevo no dispare por accidente un análisis largo. El vocabulario de perfiles es común a toda la plataforma, de modo que Internal Model Studio u ORSA puedan solicitar una profundidad coherente a una batería de herramientas.

**c) Transparencia del progreso.** Cuando un análisis dure varios minutos, el usuario debe comprender siempre qué está haciendo la herramienta. El progreso se deriva de la propia arquitectura por capas (la secuencia ordenada de fases del cálculo), se comunica por conteo real donde hay iteraciones conocidas y por estado donde no las hay, y nunca mediante porcentajes fabricados ni ETAs inventadas. El canal de progreso observa el cálculo, jamás lo altera (consistente con la pureza de `calc.R`).

**d) Optimizar la implementación: sí. Degradar el análisis automáticamente: no.** Son dos palancas distintas que no deben confundirse:

| | Optimizar la implementación | Reducir el contenido del análisis |
|---|---|---|
| Qué cambia | *Cómo de rápido* se calcula | *Qué* se calcula |
| Ejemplos | Paralelización, vectorización, gradientes/Hessianos analíticos, mejores valores iniciales, cacheo, C++ donde se justifique | Menos remuestreos, omitir validaciones, tests más gruesos, submuestreo |
| ¿Permitido? | **Sí, siempre y fomentado** | **No de forma automática:** solo por perfil de profundidad explícito o justificación estadística documentada |

### 1.8 Validez estadística de los procedimientos (principio de plataforma)

*(Introducido en v2.0 — ADR-008. Aplica a todas las herramientas presentes y futuras.)*

Cuando una herramienta emplee procedimientos estadísticos cuya validez dependa del método de estimación de parámetros —por ejemplo, p-valores de tests de bondad de ajuste calculados sobre parámetros estimados con la misma muestra (Kolmogorov-Smirnov, Cramér-von Mises)—, deberá emplear procedimientos **estadísticamente válidos para ese contexto** (p. ej. calibración por bootstrap paramétrico o simulación, en lugar de valores críticos tabulados que asumen parámetros conocidos).

La **elección concreta del procedimiento pertenece al motor matemático** de cada herramienta (la capa de cálculo, `calc.R`), **no al criterio actuarial ni al View Model**. Este documento congela el requisito; no impone la implementación.

---

## 2. Stack tecnológico

Durante la Fase 1 se utiliza exclusivamente R. No se propone ni se introduce Python salvo solicitud expresa.

| Librería | Uso | Justificación |
|---|---|---|
| `shiny` | Framework base | Obligatorio |
| `bslib` | Theming (Bootstrap 5), tarjetas, layout | Permite aplicar la identidad visual completa sin CSS manual excesivo |
| `ggplot2` | Gráficos estáticos exportables | Estándar de facto; control total de estética vía tema propio |
| `plotly` | Gráficos interactivos | Solo donde la interactividad aporta valor real (zoom, hover con detalle numérico) |
| `DT` | Tablas interactivas | Buscador, orden y paginación con buen rendimiento |
| `dplyr` | Manipulación de datos | Estándar, legible, consistente entre tools |
| `tidyr` | Reestructuración de datos | Complemento de `dplyr` |
| `readr` | Lectura de CSV | Más robusto que `read.csv` base, mejor manejo de tipos |
| `glue` | Construcción de texto dinámico | Legibilidad en las cajas de interpretación automática |
| `shinycssloaders` | Spinners de carga | Feedback visual durante el cálculo |
| `bsicons` | Iconografía | Integrada con `bslib`, estilo *outline* coherente. **Decisión cerrada**: es la única librería de iconos del proyecto |
| `htmlwidgets` | Infraestructura de `plotly` y `DT` | Dependencia indirecta |
| `yaml` | Lectura de `manifest.yml` | Necesaria ya en Fase 1: el header y el footer leen de `manifest.yml` el nombre y la versión de la herramienta |
| `renv` | Gestión de dependencias | Un único `renv.lock` en la raíz del repositorio |

### 2.1 Librerías explícitamente excluidas

| Librería | Motivo de exclusión |
|---|---|
| `shinydashboard` | Estética anticuada; incompatible conceptualmente con `bslib` moderno |
| `golem` | Sobredimensionado para el tamaño actual del proyecto |
| `shiny.semantic` y frameworks de theming de terceros | Rompen la identidad visual propia |
| `rmarkdown` | Excluida en Fase 1 (exportación PDF diferida a Fase 2) |
| `testthat` | Excluida en Fase 1 (ver apartado 8) |

### 2.2 Política de implementación propia frente a librerías de terceros

- **Infraestructura de aplicación** (Shiny, bslib, DT, plotly, dplyr): se utilizan librerías estándar de la industria. No se reimplementan.
- **Lógica estadística y actuarial**: se implementa manualmente siempre que sea razonable (integración numérica, kernels, estimación por máxima verosimilitud vía `optim()`, bootstrap, Monte Carlo, ajuste de distribuciones). Estas funciones constituyen el valor diferencial del proyecto, deben estar documentadas y ser auditables, y residen en el `calc.R` de cada herramienta o, cuando aplique la regla de promoción del **apartado 10, regla 4**, en `shared/actuarial/`. Los procedimientos cuya validez dependa de la estimación de parámetros cumplen el principio del apartado §1.8.

---

## 3. Identidad visual

Referencia estética: **Bloomberg Terminal**, **Power BI**, **TradingView**. Fondo neutro, tipografía técnica, acentos de color muy controlados, cero decoración gratuita, alta densidad de información bien organizada.

Se evita de forma explícita: colores llamativos, interfaces infantiles, exceso de botones, gradientes, emoji.

### 3.1 Paleta de colores

| Rol | Color | Hex | Uso |
|---|---|---|---|
| Fondo principal | Gris casi blanco | `#F5F6F8` | Fondo de la aplicación |
| Superficie | Blanco | `#FFFFFF` | Tarjetas, tablas, contenedores |
| Texto principal | Gris carbón | `#1C1E21` | Texto y títulos |
| Texto secundario | Gris medio | `#6B7280` | Descripciones, labels |
| Bordes y separadores | Gris claro | `#E5E7EB` | Líneas y bordes de card |
| **Marca (primario)** | Azul marino profundo | `#0B3D91` | Header, botones primarios, enlaces |
| Acento secundario | Azul acero | `#3B82C4` | Highlights en gráficos, hover |
| Éxito | Verde atenuado | `#2E7D57` | Notificaciones de sistema |
| Alerta | Ámbar | `#B8860B` | Notificaciones de sistema |
| Error | Rojo apagado | `#B3261E` | Notificaciones de sistema |

**Reglas de color:**

- Máximo **2 colores de acento activos** en pantalla simultáneamente, además de la paleta neutra.
- Si un gráfico necesita más categorías, se utiliza una escala secuencial de azules y grises, nunca una paleta multicolor.
- El azul marino `#0B3D91` es el color de marca y se reserva para header, botones primarios y logo, de forma que mantenga peso visual.
- Los colores de éxito, alerta y error **no constituyen un sistema semántico de diseño**: su uso está limitado exclusivamente al componente de notificaciones (`bmk_notify()`).

### 3.2 Tipografía

- **Familia principal:** `Inter`. Alternativa admitida: `IBM Plex Sans`.
- Los gráficos utilizan la misma familia tipográfica que la interfaz.

| Elemento | Tamaño | Peso |
|---|---|---|
| Título de la aplicación (header) | 22 px | Semibold |
| Título de sección | 16 px | Semibold |
| Texto cuerpo | 14 px | Regular |
| Texto auxiliar y labels | 12 px | Regular (color secundario) |
| Números destacados (metric cards) | 28–32 px | Bold, `font-variant-numeric: tabular-nums` |

### 3.3 Iconografía

- Librería única: `bsicons`.
- Estilo *outline* exclusivamente. Nunca *filled*.
- Prohibido el uso de emoji en cualquier parte de la interfaz.
- Icono de marca: símbolo abstracto y simple, definido una única vez, reutilizado como favicon y logo del header en todas las herramientas.

### 3.4 Distribución, espaciado y superficie

- `padding` estándar en cards: 16–24 px.
- `border-radius`: 6 px. Nunca superior a 8 px.
- `box-shadow`: `0 1px 3px rgba(0,0,0,0.06)`. No se utilizan sombras pronunciadas.

### 3.5 Especificaciones de componentes visuales

**Tarjetas (cards)**
Fondo blanco, borde `1px solid #E5E7EB`, sombra sutil.

**Metric cards**
Patrón fijo: label pequeño en gris en la parte superior, número grande centrado en azul marino o negro, nota auxiliar pequeña en la parte inferior cuando aplique.

**Tablas**
`DT` con tema minimalista: cabecera con fondo `#F5F6F8`, texto carbón, sin líneas verticales, líneas horizontales sutiles. Números alineados a la derecha, texto a la izquierda. Paginación y buscador discretos.

**Botones**

| Tipo | Estilo |
|---|---|
| Primario | Fondo azul marino, texto blanco, sin borde |
| Secundario | Fondo transparente, borde gris, texto carbón |
| Destructivo | Fondo transparente, borde y texto en rojo apagado |

Altura consistente aproximada de 38 px, `border-radius` 6 px, hover limitado a un oscurecimiento del 8 %.

**Sidebar**
Fondo blanco o gris muy claro (`#FAFAFA`), separado del panel principal por un borde fino, nunca por sombra. Ancho fijo aproximado de 300 px en escritorio. Inputs agrupados en secciones tituladas.

**Gráficos**
Tema propio `theme_bmk_ggplot()`: fondo blanco, grid mayor ligero, grid menor eliminado, ejes en gris, paleta restringida a la de marca más escala secuencial de azules. Los gráficos interactivos aplican `bmk_plotly_layout()` para garantizar la misma estética.

---

## 4. Layout estándar de todas las herramientas

### 4.1 Wireframe

```
┌──────────────────────────────────────────────────────────────────┐
│  HEADER                                                           │
│  [Logo]  Actuarial Tools by BMK · <Nombre de la Tool>             │
├───────────────┬──────────────────────────────────────────────────┤
│               │  MAIN PANEL                                       │
│  SIDEBAR      │  ┌────────────────────────────────────────────┐  │
│               │  │  Descripción breve de la herramienta       │  │
│  • Carga de   │  └────────────────────────────────────────────┘  │
│    datos      │                                                   │
│    (Upload /  │  ┌──────────┬──────────┬──────────┬───────────┐  │
│     Ejemplo)  │  │ Metric   │ Metric   │ Metric   │ Metric    │  │
│               │  │ Card 1   │ Card 2   │ Card 3   │ Card 4    │  │
│  • Parámetros │  └──────────┴──────────┴──────────┴───────────┘  │
│    de config. │                                                   │
│               │  ┌────────────────────────────────────────────┐  │
│  • Botón      │  │  Gráfico principal                          │  │
│    Calcular   │  └────────────────────────────────────────────┘  │
│               │                                                   │
│               │  ┌────────────────────────────────────────────┐  │
│               │  │  Tabla de resultados (DT)                   │  │
│               │  └────────────────────────────────────────────┘  │
│               │                                                   │
│               │  ┌────────────────────────────────────────────┐  │
│               │  │  Interpretación / notas técnicas            │  │
│               │  └────────────────────────────────────────────┘  │
│               │                                                   │
│               │  [Exportar CSV]                                   │
├───────────────┴──────────────────────────────────────────────────┤
│  FOOTER — Actuarial Tools by BMK · v1.0.0 · disclaimer · privacidad│
└──────────────────────────────────────────────────────────────────┘
```

La versión mostrada en el footer sigue el formato semver de tres componentes (`MAJOR.MINOR.PATCH`) y procede siempre del campo `version` del `manifest.yml` de la herramienta (ver apartados 7.2 y 9.2).

### 4.2 Reglas de layout

- **Sidebar a la izquierda para inputs; panel principal a la derecha para outputs.** Patrón universalmente reconocido; curva de aprendizaje nula.
- **Metric cards en la parte superior del panel principal.** Los 3–4 números relevantes se muestran antes que cualquier gráfico o tabla.
- **Gráfico antes que tabla.** El gráfico permite validar el resultado en segundos; la tabla aporta el detalle exacto y el material de exportación.
- **Caja de interpretación como bloque explícito y separado.** Elemento diferencial del proyecto: traduce el output técnico a lenguaje comprensible.
- **Exportación siempre al final y siempre en la misma posición** en todas las herramientas.
- **Footer fijo** con versión, disclaimer de uso y aviso de privacidad de datos.
- Los valores por defecto de todos los inputs deben ser razonables: el usuario nunca se enfrenta a una pantalla vacía que le obligue a configurar antes de obtener un resultado. Entre esos valores por defecto está el **perfil de profundidad `Standard`** (§1.7).

### 4.3 Aviso de privacidad y disclaimer

Toda herramienta muestra de forma visible, en el footer o junto al componente de carga de datos:

- Un aviso de privacidad indicando que los datos no se almacenan ni se envían a servidores externos. Este aviso debe ser cierto en la implementación.
- Un disclaimer de uso indicando que los resultados no constituyen asesoramiento actuarial certificado.

---

## 5. Experiencia de usuario

Cualquier herramienta de la serie debe transmitir, en los primeros cinco segundos de uso:

**Profesionalidad.** Header limpio con marca y nombre de la herramienta. Sin colores estridentes, banners ni mensajes de bienvenida informales.

**Profundidad y transparencia.** El usuario puede cargar sus datos o generar datos de ejemplo con un clic y lanzar el análisis sin configuración obligatoria. Cuando un análisis requiere varios minutos por su profundidad (§1.7), la herramienta comunica el progreso de forma honesta y comprensible; **nunca degrada la calidad del análisis para ganar tiempo**. Sin asistentes de varios pasos ni configuración obligatoria innecesaria. Los spinners y los mensajes de fase confirman que el cálculo está en curso.

**Claridad.** Ningún número se muestra sin contexto. Todo resultado numérico lleva etiqueta clara y, cuando aplica, interpretación en lenguaje natural. El usuario nunca debe deducir si un output es alto, bajo, favorable o desfavorable.

**Fiabilidad.** Ante un CSV mal formado o un parámetro fuera de rango, la aplicación no falla en silencio ni muestra errores crípticos de R: emite una notificación clara mediante `bmk_notify()` explicando qué ha ocurrido y qué hacer.

**Coherencia entre herramientas.** La posición del uploader, de la exportación, el significado de los colores y el vocabulario de perfiles de profundidad es idéntico en las 40 aplicaciones. Esta coherencia es lo que convierte una colección de aplicaciones en una plataforma.

---

## 6. Arquitectura definitiva

### 6.1 Decisiones estructurales

**`shared/` como carpeta de funciones, no como paquete de R.**
Durante toda la Fase 1, el código compartido reside en una carpeta `shared/` cargada mediante `source()` a través de un único punto de entrada, `shared/load_shared.R`. No se crean `DESCRIPTION`, `NAMESPACE` ni compilación de paquete. La conversión a paquete formal se evalúa en Fase 2 conforme al criterio del apartado 8.

**Cada herramienta es un módulo Shiny desde la Tool 0.**
Toda herramienta se construye como un par `mod_<tool>_ui()` / `mod_<tool>_server()` con namespacing correcto mediante `NS(id)`. El `app.R` de cada herramienta es una capa de orquestación mínima que carga `shared/`, monta ese único módulo y arranca la aplicación. No existe la opción de construir una herramienta de forma monolítica.

**Separación estricta entre lógica y presentación.**
`calc.R` contiene la lógica actuarial y no depende de Shiny. `mod_tool.R` contiene la interfaz y la reactividad. `app.R` no contiene lógica de cálculo bajo ninguna circunstancia.

### 6.2 Alcance de implementación en Fase 1

**Se implementa ahora:**

- Carpeta `shared/` completa: theming, componentes de UI, módulos genéricos (`mod_data_input`, `mod_export_csv`), validación de datos y utilidades de formato.
- Patrón de módulo por herramienta (`mod_tool.R` + `calc.R` separados).
- Exportación en CSV únicamente.
- Despliegue manual en shinyapps.io.
- Un único `renv.lock` en la raíz del repositorio.
- `manifest.yml` por herramienta.
- `docs/decisions_log.md` como registro de decisiones.

**Se difiere explícitamente:**

- Empaquetado formal de `shared/` como paquete de R instalable.
- Exportación a PDF.
- Tests automatizados.
- CI/CD de despliegue.
- Cualquier launcher, catálogo o contenedor multi-herramienta (constituye Internal Model Studio, Fase 4).

---

## 7. Componentes reutilizables obligatorios

### 7.1 Regla de clasificación

Se aplica sin excepción y sin criterio subjetivo:

> Si un componente mantiene estado reactivo o necesita namespace propio de inputs → **es un módulo Shiny**.
> Si únicamente devuelve marcado HTML o realiza una transformación pura de datos → **es una función**.

### 7.2 Catálogo de componentes

| Componente | Objetivo | Responsabilidad | ¿Módulo? | Depende de |
|---|---|---|---|---|
| `theme_bmk()` / tokens de color | Identidad visual única de la marca | Definir el objeto `bslib::bs_theme()`, paleta y tipografía | No | — (base del sistema) |
| `theme_bmk_ggplot()` | Estética de gráficos estáticos | Tema `ggplot2` de marca | No | Tokens de color |
| `bmk_plotly_layout()` | Estética de gráficos interactivos | Aplicar layout y colores BMK a un objeto `plotly` | No | Tokens de color |
| `bmk_header_ui()` | Cabecera consistente | Devolver el HTML del header: logo, marca y nombre de la herramienta, leídos de `manifest.yml` | No | Tema, `manifest.yml` |
| `bmk_footer_ui()` | Pie consistente | Devolver HTML con versión (campo `version` de `manifest.yml`), disclaimer de privacidad y copyright | No | Tema, `manifest.yml` |
| `bmk_sidebar_section()` | Agrupar inputs con título | Envoltorio visual para bloques del sidebar | No | Tema |
| `bmk_metric_card()` | Mostrar un KPI | Devolver tarjeta con label, valor y nota | No | Tema |
| `bmk_plot_container()` | Envolver un output de gráfico | Card con título y `plotOutput` / `plotlyOutput` | No | Tema |
| `bmk_table_container()` | Envolver una tabla | Card con título y `DTOutput` con opciones preconfiguradas | No | Tema |
| `bmk_interpretation_box()` | Traducir resultado técnico a texto llano | Recibir un string construido con `glue()` en la herramienta y mostrarlo con estilo fijo | No | Tema |
| `bmk_notify()` | Notificaciones de sistema | Wrapper de `showNotification()` con tres estados: info, warning, error | No | Tema |
| `bmk_loading()` | Feedback de carga | Wrapper de `shinycssloaders::withSpinner()` | No | Tema |
| `bmk_validate_data()` | Validar el dataset de entrada | Función pura: recibe un `data.frame` y un contrato de columnas esperadas; devuelve `list(valid, data, errors)` | No | — |
| `mod_data_input` | Entrada de datos de cada herramienta | Gestionar el toggle "Subir CSV / Generar datos de ejemplo", aplicar el límite de tamaño de archivo, ejecutar `bmk_validate_data()` y mantener el estado reactivo del dataset activo | **Sí** | `bmk_validate_data()`, `bmk_notify()` |
| `mod_export_csv` | Exportación de resultados | `downloadButton` y `downloadHandler` genéricos; recibe cualquier `reactive()` de tipo `data.frame` | **Sí** | — |
| `mod_<tool>` | Núcleo funcional de cada herramienta | Orquestar `mod_data_input`, invocar `calc.R`, renderizar métricas, gráfico, tabla e interpretación, y montar `mod_export_csv` | **Sí** | Todos los anteriores |

### 7.3 Contrato fijo de `mod_data_input`

El servidor de `mod_data_input` devuelve siempre un `reactive()` con la siguiente forma:

```r
list(
  data     = <data.frame>,   # dataset activo, ya validado
  is_valid = <logical>,      # TRUE si ha superado la validación
  errors   = <character>,    # vector de mensajes de error (vacío si is_valid)
  source   = <character>     # "upload" | "example"
)
```

Todas las herramientas consumen este contrato sin excepción. Cualquier herramienta del proyecto debe poder entenderse sin releer el código de las demás.

`mod_data_input` es, además, el único responsable de:

- Configurar y aplicar el límite de tamaño de archivo definido en el apartado 7.5.
- Comunicar al usuario, mediante `bmk_notify()`, los errores devueltos por `bmk_validate_data()`.

### 7.4 Contrato de `bmk_validate_data()`

`bmk_validate_data()` es una función pura que opera sobre un `data.frame` ya cargado en memoria. Debe cubrir, como mínimo, los siguientes casos:

- Dataset vacío (cero filas).
- Columnas obligatorias ausentes.
- Columnas con nombre incorrecto.
- Tipos de datos erróneos.
- Exceso de valores ausentes (`NA`).
- Superación del límite de filas definido en el apartado 7.5.

Devuelve siempre `list(valid, data, errors)`. Nunca emite notificaciones ni interactúa con la interfaz: la responsabilidad de comunicar el error corresponde a `mod_data_input` mediante `bmk_notify()`.

La validación del tamaño del archivo en disco queda fuera del alcance de esta función, por no ser deducible desde un `data.frame`, y se asigna a `mod_data_input`.

### 7.5 Política de tamaño y rendimiento de datos

Las herramientas están diseñadas para volúmenes de datos de trabajo analítico, no para procesamiento masivo.

| Límite | Valor | Componente responsable | Mecanismo |
|---|---|---|---|
| Tamaño de archivo | **10 MB** | `mod_data_input` | `options(shiny.maxRequestSize = 10 * 1024^2)` y verificación del objeto de `fileInput` antes de la lectura |
| Número de filas | **100.000** | `bmk_validate_data()` | Verificación sobre el `data.frame` cargado |

Superado cualquiera de los dos límites, la interfaz informa al usuario del límite aplicable mediante `bmk_notify()`. Estos límites forman parte del contrato del proyecto y no se superan en ninguna herramienta sin decisión registrada en `docs/decisions_log.md`.

Nota (v2.0): estos límites acotan el **volumen de datos de entrada**; no constituyen una promesa de tiempo de ejecución. La profundidad del análisis y su coste se rigen por §1.7.

### 7.6 Contrato de datos entre herramientas

Cuando varias herramientas manipulan el mismo tipo de información, los nombres de columna son comunes. Esta convención es la que permitirá que el output de una herramienta alimente a otra dentro de Internal Model Studio.

| Concepto | Nombre de columna |
|---|---|
| Importe de siniestro / severidad | `loss_amount` |
| Fecha de ocurrencia | `date_occurred` |
| Identificador de póliza | `policy_id` |
| Identificador de siniestro | `claim_id` |
| Exposición | `exposure` |

Esta lista es un punto de partida ampliable. Todo nombre de columna estándar nuevo se añade a `docs/data_contract.md`. Nunca se improvisa un nombre a nivel de herramienta.

---

## 8. Componentes y funcionalidades descartados

El apartado 12 (Roadmap) es la única fuente de verdad sobre cuándo comienza cada fase. Las referencias de esta tabla identifican la fase, sin definir criterios de entrada propios.

| Elemento | Motivo de descarte | Fase de posible incorporación |
|---|---|---|
| Paquete de R formal (`bmkTools` instalable) | `shared/` con `source()` es suficiente para el volumen actual | Fase 2, cuando el re-despliegue o la ausencia de versionado del código compartido genere fricción medible |
| `testthat` sobre componentes de UI | No aporta valor en un proyecto de un solo desarrollador | Nunca para UI. Sí sobre `calc.R` y `shared/actuarial/` desde Fase 2, priorizando herramientas de mayor riesgo reputacional |
| Exportación a PDF | El motor de renderizado es la parte más frágil del despliegue; CSV cubre el 80 % del valor real | Fase 2 |
| Exportación a PNG de gráficos | `plotly` ya incluye descarga de imagen nativa | Ya cubierto para gráficos interactivos. Se evaluará para `ggplot2` estático en Fase 2 |
| Modo oscuro / toggle de tema | No aporta valor actuarial y duplica la superficie de CSS | Fuera de alcance de forma permanente |
| Sistema semántico de color completo | Innecesario para el tipo de contenido | No se ampliará; uso limitado a `bmk_notify()` |
| Botones "Ayuda" y "•••" en el header | Botones sin función definida replicados 40 veces constituyen deuda técnica | Fase 2, como enlace simple a documentación si se detecta necesidad real |
| Internacionalización (i18n) | Código, comentarios y público objetivo son en español | Fase 3, solo ante expansión comercial que lo justifique |
| `renv.lock` por herramienta | 40 lockfiles independientes son mantenimiento redundante | Nunca. Un único lockfile en la raíz cubre el mismo riesgo |
| CI/CD automatizado de despliegue | El ritmo de publicación previsto no lo justifica | Fase 2, cuando el volumen de despliegues manuales genere fricción real |
| Persistencia de datos, base de datos, autenticación | Las herramientas son calculadoras sin estado | Fase 4, solo si Internal Model Studio lo exige como producto |
| Launcher o catálogo multi-herramienta | Es, por definición, Internal Model Studio | Fase 4 |

---

## 9. Estructura definitiva del repositorio

```
actuarial-tools-bmk/
│
├── shared/
│   ├── theme/
│   │   ├── theme_bmk.R              # theme_bmk(), theme_bmk_ggplot(), bmk_plotly_layout()
│   │   ├── colors.R                 # constantes de paleta
│   │   └── styles.css
│   ├── components/
│   │   ├── ui_header.R
│   │   ├── ui_footer.R
│   │   ├── ui_sidebar_section.R
│   │   ├── ui_metric_card.R
│   │   ├── ui_plot_container.R
│   │   ├── ui_table_container.R
│   │   ├── ui_interpretation_box.R
│   │   ├── notify.R
│   │   └── loading.R
│   ├── modules/
│   │   ├── mod_data_input.R
│   │   └── mod_export_csv.R
│   ├── validation/
│   │   └── validate_data.R          # define bmk_validate_data()
│   ├── utils/
│   │   └── format_helpers.R         # helpers de formato y presentación
│   ├── actuarial/                   # funciones de cálculo promovidas (sin dependencia de Shiny)
│   └── load_shared.R                # único punto de entrada: source() de todo lo anterior
│
├── tools/
│   ├── tool-00-template/            # infraestructura, no entrada de catálogo
│   │   ├── app.R
│   │   ├── R/
│   │   │   ├── mod_tool.R
│   │   │   └── calc.R
│   │   ├── data/
│   │   │   └── example_data.csv
│   │   ├── manifest.yml
│   │   └── README.md
│   │
│   ├── kernel-density/
│   ├── distribution-fitting/        # Tool-02
│   │   ├── tool_02_distribution_fitting_design.md   # diseño de la herramienta (Sprint 0)
│   │   ├── decision_engine.md                       # parametrización del criterio (versionada)
│   │   └── ...                       # app.R, R/, data/, manifest.yml, README.md (en implementación)
│   ├── bootstrap-mse/
│   ├── scenario-generation/
│   ├── extreme-value-theory/
│   └── ...                          # ~40 carpetas, nombradas por slug descriptivo
│
├── docs/
│   ├── architecture_v1_1.md         # conservado (superado por v2.0)
│   ├── architecture_v2.md           # este documento (vigente)
│   ├── decisions_log.md
│   ├── data_contract.md
│   └── roadmap.md
│
├── renv.lock
├── .Rprofile
└── README.md
```

### 9.1 Nomenclatura de carpetas de herramienta

Las carpetas de herramienta se nombran con un **slug descriptivo en `kebab-case`**, sin numeración. El orden y la agrupación por categoría se gestionan como metadato en `manifest.yml`, nunca como nombre de carpeta.

La numeración se conserva únicamente en `tool-00-template`, por tratarse de infraestructura interna y no de una entrada del catálogo.

Los archivos de `docs/` siguen `snake_case`, igual que los archivos de código.

### 9.2 Contenido obligatorio de `manifest.yml`

```yaml
slug: kernel-density
name: Estimación de Densidades por Kernel
category: Estimación de densidades
version: 1.0.0               # semver MAJOR.MINOR.PATCH — fuente única de verdad
status: published            # draft | published
description: Descripción corta de una línea.
input_columns:
  - loss_amount
output_type: table+plot
published_date: 2026-08-15
```

Este archivo es obligatorio desde la primera herramienta. Es la fuente única de verdad del nombre y la versión que muestran `bmk_header_ui()` y `bmk_footer_ui()`, y constituye la base gratuita del futuro catálogo automático de Internal Model Studio.

---

## 10. Reglas del proyecto

Reglas innegociables durante toda la Fase 1.

1. **Nombres de archivo:** `snake_case.R` siempre. El prefijo de marca aplica a nombres de función, no a nombres de archivo.
2. **Nombres de carpeta de herramienta:** `kebab-case`, slug descriptivo, sin numeración (excepción: `tool-00-template`).
3. **Nomenclatura de funciones en `shared/`:** toda función de `shared/` lleva prefijo `bmk_`, con dos excepciones de convención:
   - Los módulos Shiny compartidos usan prefijo `mod_` (`mod_data_input`, `mod_export_csv`).
   - Las funciones de theming usan el patrón `theme_bmk*()` (`theme_bmk()`, `theme_bmk_ggplot()`).

   Las funciones locales de una herramienta no llevan prefijo.
4. **Regla de 2 para promover a `shared/`:** una función se traslada a `shared/` únicamente cuando es necesaria en 2 o más herramientas. Cálculo → `shared/actuarial/`; formato y presentación → `shared/utils/`.
5. **Módulo frente a función:** si mantiene estado reactivo o necesita namespace propio, es un módulo Shiny; si es UI estática o transformación pura, es una función. Sin excepciones.
6. **`app.R` es exclusivamente orquestación.** Carga `shared/`, monta el módulo de la herramienta y arranca `shinyApp()`. Nunca contiene lógica de cálculo.
7. **`calc.R` y `shared/actuarial/` no dependen de Shiny.** Deben poder ejecutarse mediante `source()` sin Shiny cargado. Esto garantiza que la lógica actuarial sea auditable, testeable y reutilizable fuera de la aplicación, incluida una futura migración a Python o a una API.
8. **Sin números ni cadenas mágicas en `calc.R`.** Todo valor con significado se declara como constante nombrada o parámetro de función. Los valores del criterio de decisión, cuando existan, se externalizan (p. ej. `decision_engine.md`).
9. **Toda función lleva documentación en formato roxygen (`#'`)**: título, `@param` y `@return` como mínimo.
10. **Cabecera obligatoria** en todo `calc.R` y `mod_tool.R`:

    ```r
    # ============================================================
    # Tool: <nombre de la herramienta>
    # Archivo: <propósito de este archivo>
    # Autor: BMK
    # Última actualización: <fecha>
    # ============================================================
    ```

11. **Cada herramienta es autocontenida y ejecutable de forma independiente** mediante `shiny::runApp("tools/<slug>")`.
12. **`manifest.yml` obligatorio** en toda herramienta, con los campos definidos en el apartado 9.2.
13. **Convenio de commits:** prefijo con el ámbito afectado, `[shared] ...` o `[kernel-density] ...`.
14. **Ninguna herramienta publicada se modifica retroactivamente** por un cambio en `shared/` sin decisión explícita de re-despliegue. Todo cambio incompatible se documenta en `docs/decisions_log.md` **antes** de aplicarse.
15. **Orden interno fijo de `app.R`:** `library()` → carga de `shared/` → definición de `ui` → definición de `server` → `shinyApp()`.
16. **Ninguna herramienta contiene CSS o HTML suelto** fuera del sistema de componentes de `shared/`.
17. **Toda idea adicional surgida durante el desarrollo de una herramienta va al backlog**, nunca a la herramienta en curso.
18. **Validez estadística (principio de plataforma, ADR-008).** Cuando una herramienta emplee procedimientos cuya validez dependa del método de estimación de parámetros, debe usar procedimientos válidos para ese contexto. La implementación concreta pertenece al motor matemático de cada herramienta, no al criterio actuarial ni al View Model (ver §1.8).
19. **Coste computacional y profundidad (principio de plataforma, ADR-007).** No se degrada automáticamente el análisis por el tamaño del dataset. La profundidad la controla el usuario mediante perfiles enumerados y documentados (`Standard` por defecto, `Comprehensive` para estudios exhaustivos); la diferencia es profundidad, no velocidad. Optimizar la implementación está siempre permitido; reducir el contenido estadístico solo por elección explícita de perfil o por justificación estadística documentada (ver §1.7).
20. **Versionado y gobernanza (principio de plataforma, ADR-009 y ADR-011).** El View Model de cada herramienta declara `schema_version`; las herramientas con criterio parametrizado versionan además ese criterio (p. ej. `decision_engine_version`). A partir de la aprobación de esta versión de la arquitectura, todo cambio arquitectónico requiere un ADR en `docs/decisions_log.md` que demuestre beneficio claro respecto a la arquitectura vigente; en su ausencia, la prioridad es implementar la arquitectura existente, no rediseñarla.

---

## 11. Definición de "Tool terminada"

Una herramienta se considera terminada únicamente si cumple **todos** los puntos siguientes. No se admite el cumplimiento parcial.

### 11.1 Funcional

- [ ] Acepta datos mediante CSV subido y mediante "generar datos de ejemplo".
- [ ] Contrato de columnas esperadas definido y `bmk_validate_data()` integrada en `mod_data_input`, probada con al menos un caso de error real.
- [ ] Resultado numérico verificado manualmente contra un caso conocido (paper, script previo o cálculo de referencia).
- [ ] Al menos un gráfico principal.
- [ ] Tabla de resultados.
- [ ] Caja de interpretación con texto específico generado dinámicamente. No genérico. No copiado de otra herramienta.
- [ ] Exportación CSV funcional.
- [ ] La aplicación funciona de extremo a extremo sin modificar ningún input, únicamente pulsando "generar ejemplo" y "calcular".

### 11.2 Visual

- [ ] Utiliza exclusivamente componentes de `shared/`, sin CSS ni HTML fuera del sistema.
- [ ] Paleta de colores respetada sin excepciones.
- [ ] No se rompe en resolución de portátil estándar (1366 × 768).
- [ ] Header y footer estándar presentes.

### 11.3 Técnico

- [ ] `app.R` sin lógica de cálculo.
- [ ] `calc.R` ejecutable de forma independiente sin Shiny cargado.
- [ ] `mod_tool.R` sigue el patrón de módulo definido, con namespacing correcto.
- [ ] `manifest.yml` completo, con `version` en formato semver; el nombre y la versión mostrados coinciden con los declarados.
- [ ] El View Model declara `schema_version`; si la herramienta tiene criterio parametrizado, también `decision_engine_version` (regla 20).
- [ ] Los procedimientos estadísticos dependientes de la estimación de parámetros son válidos para ese contexto (regla 18).
- [ ] Si la herramienta ofrece perfiles de profundidad, `Standard` es el defecto y el perfil aplicado se registra en el resultado (regla 19).
- [ ] `README.md` de la herramienta: qué hace, columnas de entrada esperadas y limitaciones conocidas.
- [ ] Cero errores y cero warnings en consola durante el uso normal.
- [ ] Probada con al menos un CSV real o realista, no solo con datos de ejemplo generados.
- [ ] Límites de datos del apartado 7.5 aplicados y verificados.
- [ ] Disclaimer de privacidad y de uso visible.

### 11.4 Publicación

- [ ] Desplegada y accesible mediante URL.
- [ ] Captura o GIF de demostración preparado.
- [ ] Entrada añadida al listado general del proyecto.

---

## 12. Roadmap de evolución

Este apartado es la única fuente de verdad sobre los criterios de entrada en cada fase.

### Fase 1 — Portfolio
*Meses 1 a 8-9 · 25-30 herramientas publicadas*

Ejecución estricta de esta especificación sin modificaciones. Prioridad absoluta: ritmo de publicación sostenido.

- `shared/` cargado con `source()`.
- Un módulo Shiny por herramienta.
- CSV como único formato de exportación.
- Despliegue manual en shinyapps.io.
- La arquitectura no se revisa salvo bug crítico que bloquee la publicación, o mediante el proceso ADR (regla 20).

### Fase 2 — Optimización
*Criterio de entrada: 25-30 herramientas publicadas, o antes si el mantenimiento de `shared/` genera fricción medible*

- Continúa la publicación de herramientas hasta completar el objetivo global de 30-40.
- Evaluación de la conversión de `shared/` en paquete formal, con datos reales de mantenimiento.
- Incorporación de exportación a PDF.
- Introducción de tests automatizados exclusivamente sobre `calc.R` y `shared/actuarial/`, priorizando las herramientas de mayor riesgo reputacional (VaR, capital, reservas).
- Evaluación de CI/CD simple.
- Pase de revisión de consistencia visual sobre las herramientas ya publicadas.

### Fase 3 — Migración parcial
*Meses 9-12; puede solaparse con la Fase 2*

- Exploración —no obligación— de la migración de funciones puras de `calc.R` y `shared/actuarial/` a Python, donde exista sentido comercial.
- La interfaz permanece en Shiny/R durante toda esta fase.

### Fase 4 — Internal Model Studio / ORSA Platform / Actuarial Risk Hub
*Año 2 en adelante*

- Construcción de una aplicación contenedora que monta los módulos `mod_<tool>` ya existentes.
- Generación automática del catálogo a partir de los `manifest.yml`.
- Único punto del roadmap donde se contempla añadir complejidad de producto real: autenticación, persistencia de sesión y roles.

### 12.1 Aceleración esperada por herramienta

A partir de la primera herramienta, el flujo de creación se reduce a:

1. Copiar `tools/tool-00-template/` a `tools/<slug>/`.
2. Escribir `calc.R` con la lógica actuarial específica.
3. Conectar esa lógica a los componentes existentes desde `mod_tool.R`.
4. Redactar el texto dinámico de la caja de interpretación.
5. Completar `manifest.yml` y `README.md`.
6. Verificar la checklist del apartado 11 y publicar.

---

## 13. Riesgos del proyecto

| Riesgo | Probabilidad | Impacto | Estrategia de mitigación |
|---|---|---|---|
| Scope creep por herramienta | Alta | Alto | Checklist de "Tool terminada"; toda idea adicional va al backlog (regla 17); proceso ADR (regla 20) |
| Deriva de versiones de `shared/` entre herramientas | Media-Alta | Medio | `renv.lock` único; regla 14 de no modificación retroactiva |
| Degradación de la calidad de la interpretación automática | Alta | Medio | La checklist exige texto específico; auditoría periódica |
| Cambios en `shared/` que rompen herramientas antiguas | Media | Alto | Compatibilidad hacia atrás por defecto; documentación previa en `decisions_log.md` |
| Límites de hosting gratuito al escalar a 40 aplicaciones | Alta | Medio | Monitorización mensual; presupuestar ampliación antes del límite |
| Punto único de fallo (un solo desarrollador) | Constante | Alto | `decisions_log.md` como memoria externa; checklist como sustituto parcial de code review |
| Error de cálculo actuarial no detectado | Media | Muy alto | Verificación manual obligatoria contra caso conocido (checklist 11.1); validez estadística (regla 18); tests priorizados desde Fase 2 |
| Uso indebido con datos reales de terceros | Baja-Media | Alto | Disclaimer de privacidad y de uso obligatorio (apartado 4.3) |
| Presión por migrar a Python antes de tiempo | Media | Medio | La Fase 3 reserva espacio explícito y acotado |
| Sobrecarga por volumen de datos de entrada | Media | Medio | Límites del apartado 7.5 |
| Divergencia entre versión mostrada y metadato | Baja | Medio | `manifest.yml` como fuente única de verdad |

---

## 14. Contrato técnico

Resumen ejecutivo y definitivo de todas las decisiones aprobadas.

1. `shared/` es una carpeta de funciones cargadas mediante `source()`, **no** un paquete de R formal, durante toda la Fase 1.
2. Cada herramienta es un módulo Shiny (`mod_<tool>_ui` / `mod_<tool>_server`) desde la Tool 0. Sin excepciones.
3. `app.R` es orquestación pura. `calc.R` y `shared/actuarial/` son lógica pura, sin dependencia de Shiny.
4. Exportación de resultados: **solo CSV** en Fase 1. PDF llega en Fase 2.
5. Un único `renv.lock` en la raíz del repositorio.
6. Despliegue manual en shinyapps.io durante la Fase 1.
7. Sin modo oscuro, sin i18n, sin persistencia, sin autenticación: fuera de alcance hasta la Fase 4 como muy pronto.
8. Módulo frente a función se decide por una única regla: estado reactivo → módulo; sin estado → función.
9. Una función se promueve a `shared/` únicamente cuando la necesitan 2 o más herramientas. Cálculo → `shared/actuarial/`; formato → `shared/utils/`.
10. Carpetas de herramienta: slug en `kebab-case`. Archivos R y de `docs/`: `snake_case`. Funciones de `shared/`: prefijo `bmk_`, salvo módulos (`mod_`) y theming (`theme_bmk*()`).
11. `manifest.yml` obligatorio y fuente única de verdad del nombre y la versión. Versionado en semver.
12. `bsicons` es la única librería de iconografía.
13. Los colores de éxito, alerta y error se limitan a `bmk_notify()`.
14. Límites de datos de entrada: 10 MB de tamaño de archivo (`mod_data_input`); 100.000 filas (`bmk_validate_data()`). No constituyen promesa de tiempo de ejecución.
15. Toda herramienta muestra aviso de privacidad y disclaimer de uso.
16. Los nombres de columna estándar se definen en `docs/data_contract.md`.
17. Ninguna herramienta se considera terminada sin superar la checklist completa del apartado 11.
18. El apartado 12 (Roadmap) es la única fuente de verdad sobre los criterios de entrada en cada fase.
19. **(v2.0)** La plataforma prioriza calidad, robustez estadística, reproducibilidad y transparencia sobre el tiempo de ejecución. **No existe promesa de tiempo máximo.** La profundidad la controla el usuario (`Standard` / `Comprehensive`) y nunca se degrada el análisis automáticamente por tamaño (§1.7; reglas 19).
20. **(v2.0)** Los procedimientos estadísticos cuya validez dependa de la estimación de parámetros deben ser válidos para ese contexto; su implementación pertenece al motor matemático, no al criterio ni al View Model (§1.8; regla 18).
21. **(v2.0)** El View Model se versiona (`schema_version`); el criterio parametrizado, si existe, también (`decision_engine_version`). La reproducibilidad de un resultado se define por la tupla {datos, semilla, `analysis_depth`, `schema_version`, `decision_engine_version`}.
22. **(v2.0)** Esta especificación permanece congelada. Todo cambio arquitectónico posterior requiere un ADR en `docs/decisions_log.md` con beneficio demostrado (regla 20).

---

## 15. Cómo utilizar este documento

Este documento es la **única referencia de arquitectura** del proyecto *Actuarial Tools by BMK*. Está redactado para ser autosuficiente.

**Reglas de uso:**

1. **Todo nuevo desarrollo debe seguir esta arquitectura.** Antes de comenzar una herramienta, se revisan los apartados 6, 7, 9 y 10.
2. **Ninguna herramienta se publica sin superar íntegramente la checklist del apartado 11.**
3. **Cualquier modificación futura de esta arquitectura debe registrarse como un ADR en `docs/decisions_log.md` antes de implementarse**, nunca después, y demostrar un beneficio claro respecto a la arquitectura vigente. El registro debe incluir: fecha, motivo, decisión adoptada, impacto y documentos afectados.
4. **Esta especificación permanece congelada.** Las preferencias de momento, las tendencias tecnológicas y las ideas surgidas a mitad de desarrollo no constituyen motivo suficiente para reabrirla: van al backlog. En ausencia de un ADR con beneficio demostrado, la prioridad es implementar la arquitectura existente, no rediseñarla.
5. **Toda ampliación del contrato de datos** se registra en `docs/data_contract.md`.
6. **Versionado de este documento:**
   - Las **correcciones de consistencia**, que no alteran ninguna decisión de alto nivel, incrementan la versión menor sobre el mismo archivo, y se resumen en el apartado *Changelog*.
   - Los **cambios de decisión** generan un archivo nuevo, conservando el anterior (v1.1 → v2.0 es un ejemplo de esta regla). Las versiones mayores no se sobrescriben.

---

*Actuarial Tools by BMK — Especificación Técnica de Arquitectura v2.0 — Estado: Approved. Sustituye a v1.1 (conservada). Cambios registrados en `docs/decisions_log.md`.*
