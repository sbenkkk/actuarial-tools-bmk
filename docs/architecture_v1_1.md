# Actuarial Tools by BMK — Especificación Técnica de Arquitectura

| Campo | Valor |
|---|---|
| **Nombre del proyecto** | Actuarial Tools by BMK |
| **Documento** | `docs/architecture_v1.md` |
| **Versión** | **1.1** |
| **Fecha** | Julio 2026 |
| **Estado** | **Approved** |
| **Sustituye a** | v1.0 (correcciones de consistencia; ninguna decisión de alto nivel modificada) |
| **Vigencia** | Congelada durante la Fase 1 (meses 1 a 8-9). A partir del inicio de la Fase 2 se admiten modificaciones, siempre registradas previamente en `docs/decisions_log.md` |

**Objetivo del documento**

Este documento es la especificación técnica oficial y única referencia de arquitectura del proyecto *Actuarial Tools by BMK*. Define la filosofía de producto, la arquitectura de software, los componentes reutilizables, la estructura del repositorio, las convenciones de programación, los criterios de finalización de cada herramienta, el roadmap de evolución, los riesgos identificados y el contrato técnico del proyecto.

Toda herramienta desarrollada dentro del proyecto debe cumplir lo aquí especificado. Este documento es autosuficiente: no requiere ningún contexto adicional, conversación previa ni documento complementario para ser aplicado.

---

## Changelog v1.1

Correcciones aplicadas sobre la v1.0 tras auditoría externa de arquitectura. Ninguna decisión de alto nivel ha sido modificada; todas las correcciones son de consistencia interna, nomenclatura, contratos y referencias cruzadas.

| # | Corrección | Apartados afectados |
|---|---|---|
| 1 | **Regla del prefijo `bmk_` reformulada con excepciones explícitas.** Los módulos Shiny compartidos usan prefijo `mod_`; las funciones de theming usan el patrón `theme_bmk*()`. `validate_data()` pasa a denominarse `bmk_validate_data()` en todo el documento. Se aclara que el prefijo aplica a nombres de función, no a nombres de archivo | 7.2, 7.3, 7.4, 10 (regla 3), 11, 13, 14 |
| 2 | **Reparto de responsabilidad en los límites de datos.** El límite de tamaño de archivo (10 MB) se aplica en `mod_data_input`, con configuración explícita de `shiny.maxRequestSize`; el límite de filas (100.000) se aplica en `bmk_validate_data()`. Se elimina de `bmk_validate_data()` la validación de tamaño de archivo, técnicamente imposible desde su firma | 7.2, 7.4, 7.5, 13, 14 |
| 3 | **Unificación del trigger de entrada en Fase 2.** Existía un único hito con tres condiciones distintas (25-30 herramientas, 15-20 herramientas, más de 5 herramientas afectadas). El roadmap (apartado 12) pasa a ser la única fuente de verdad; el apartado 8 referencia la fase sin cifras propias | 8, 12 |
| 4 | **Corrección del criterio de conversión a paquete formal.** El criterio anterior ("cuando un fix requiera tocar más de 5 herramientas") era inalcanzable bajo la arquitectura `shared/` + `source()`. Se sustituye por la fricción real: re-despliegue y ausencia de versionado del código compartido | 8, 12 |
| 5 | **Corrección de referencia cruzada rota.** La regla de promoción a `shared/` está en el apartado 10 (regla 4), no en el 7.4 | 2.2 |
| 6 | **Separación de `shared/utils/` y `shared/actuarial/`.** Las funciones de cálculo promovidas residen en `shared/actuarial/` (sin dependencia de Shiny); `shared/utils/` queda reservado a helpers de formato y presentación | 2.2, 9 |
| 7 | **Unificación del formato de versión y fuente única de verdad.** Semver de tres componentes en todo el proyecto; `manifest.yml` es la única fuente del versionado de cada herramienta y alimenta el valor mostrado por `bmk_footer_ui()` | 4.1, 7.2, 9.2, 11.3, 14 |
| 8 | **Alineación de la vigencia del documento con el periodo de congelación.** La congelación cubre la Fase 1 (meses 1 a 8-9), no los 12 meses completos | Cabecera, 14, 15 |
| 9 | **Asignación de fase a las herramientas 31-40.** La publicación continúa durante la Fase 2 hasta completar el objetivo de 30-40 herramientas | 12 |
| 10 | **Unificación de la nomenclatura de los archivos de `docs/`.** Todos en `snake_case`: `data-contract.md` pasa a `data_contract.md` | 7.6, 9, 14, 15 |
| 11 | **Aclaración del criterio de finalización relativo a la validación.** Lo que se implementa por herramienta es el contrato de columnas esperadas; `bmk_validate_data()` es una función compartida que se integra, no se reimplementa | 11.1 |
| 12 | **Aclaración de la regla de versionado del propio documento.** Las correcciones de consistencia generan versión menor sobre el mismo archivo; los cambios de decisión generan un archivo nuevo | 15 |

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
- Cada herramienta debe poder utilizarse en **menos de un minuto**.
- Cada herramienta debe ser intuitiva incluso para alguien que nunca la haya utilizado.
- Si una funcionalidad no aporta valor real, no se añade.

### 1.4 Jerarquía de prioridades

Ante cualquier decisión con varias opciones posibles, se prioriza siempre en este orden:

```
simplicidad  >  complejidad
claridad     >  cantidad de funcionalidades
calidad      >  velocidad
```

### 1.5 Reutilización como criterio permanente

Todo el código se diseña pensando en su futura reutilización. Cada herramienta es una pieza de un sistema mayor y debe poder convertirse en un módulo de Internal Model Studio, ORSA Platform o Actuarial Risk Hub sin reescritura de la lógica actuarial.

### 1.6 Alcance de la Tool 0

La Tool 0 no es una aplicación actuarial y no se publica externamente. Es la **plantilla base** del proyecto: un esqueleto funcional que arranca y muestra header, sidebar, entrada de datos, resultados, exportación y footer con la identidad visual definitiva, sin ningún cálculo actuarial dentro.

Su función es eliminar de todas las herramientas futuras las decisiones repetidas de maquetación, estilo, estructura de carpetas y flujo de usuario, garantizando consistencia visual y técnica a lo largo de las 40 aplicaciones y reduciendo el tiempo de desarrollo por herramienta.

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
- **Lógica estadística y actuarial**: se implementa manualmente siempre que sea razonable (integración numérica, kernels, estimación por máxima verosimilitud vía `optim()`, bootstrap, Monte Carlo, ajuste de distribuciones). Estas funciones constituyen el valor diferencial del proyecto, deben estar documentadas y ser auditables, y residen en el `calc.R` de cada herramienta o, cuando aplique la regla de promoción del **apartado 10, regla 4**, en `shared/actuarial/`.

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
- Los valores por defecto de todos los inputs deben ser razonables: el usuario nunca se enfrenta a una pantalla vacía que le obligue a configurar antes de obtener un resultado.

### 4.3 Aviso de privacidad y disclaimer

Toda herramienta muestra de forma visible, en el footer o junto al componente de carga de datos:

- Un aviso de privacidad indicando que los datos no se almacenan ni se envían a servidores externos. Este aviso debe ser cierto en la implementación.
- Un disclaimer de uso indicando que los resultados no constituyen asesoramiento actuarial certificado.

---

## 5. Experiencia de usuario

Cualquier herramienta de la serie debe transmitir, en los primeros cinco segundos de uso:

**Profesionalidad.** Header limpio con marca y nombre de la herramienta. Sin colores estridentes, banners ni mensajes de bienvenida informales.

**Rapidez.** El usuario puede cargar sus datos o generar datos de ejemplo con un clic y obtener un resultado en menos de un minuto. Sin asistentes de varios pasos ni configuración obligatoria innecesaria.

**Claridad.** Ningún número se muestra sin contexto. Todo resultado numérico lleva etiqueta clara y, cuando aplica, interpretación en lenguaje natural. El usuario nunca debe deducir si un output es alto, bajo, favorable o desfavorable.

**Fiabilidad.** Ante un CSV mal formado o un parámetro fuera de rango, la aplicación no falla en silencio ni muestra errores crípticos de R: emite una notificación clara mediante `bmk_notify()` explicando qué ha ocurrido y qué hacer. Los spinners confirman que el cálculo está en curso.

**Coherencia entre herramientas.** La posición del uploader, de la exportación y el significado de los colores es idéntica en las 40 aplicaciones. Esta coherencia es lo que convierte una colección de aplicaciones en una plataforma.

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
| Paquete de R formal (`bmkTools` instalable) | `shared/` con `source()` es suficiente para el volumen actual | Fase 2, cuando el re-despliegue de herramientas afectadas por cambios en `shared/`, o la ausencia de versionado sobre dicho código compartido, genere fricción medible |
| `testthat` sobre componentes de UI | No aporta valor en un proyecto de un solo desarrollador; genera falsa sensación de seguridad y queda obsoleto | Nunca para UI. Sí sobre `calc.R` y `shared/actuarial/` desde Fase 2, priorizando herramientas de mayor riesgo reputacional |
| Exportación a PDF | El motor de renderizado (`rmarkdown`, pandoc, LaTeX) es la parte más frágil del despliegue; CSV cubre el 80 % del valor real | Fase 2 |
| Exportación a PNG de gráficos | `plotly` ya incluye descarga de imagen nativa en su modebar | Ya cubierto para gráficos interactivos. Se evaluará en Fase 2 solo si se requiere para `ggplot2` estático |
| Modo oscuro / toggle de tema | No aporta valor actuarial y duplica la superficie de CSS a mantener | Fuera de alcance de forma permanente |
| Sistema semántico de color completo (éxito/alerta/error como design system) | Innecesario para el tipo de contenido | No se ampliará; uso limitado a `bmk_notify()` |
| Botones "Ayuda" y "•••" en el header | Botones sin función definida replicados 40 veces constituyen deuda técnica | Fase 2, como enlace simple a documentación si se detecta necesidad real |
| Internacionalización (i18n) | Código, comentarios y público objetivo son en español | Fase 3, solo ante expansión comercial que lo justifique |
| `renv.lock` por herramienta | 40 lockfiles independientes son mantenimiento redundante | Nunca. Un único lockfile en la raíz cubre el mismo riesgo |
| CI/CD automatizado de despliegue | El ritmo de publicación previsto no lo justifica | Fase 2, cuando el volumen de despliegues manuales genere fricción real |
| Persistencia de datos, base de datos, autenticación | Las herramientas son calculadoras sin estado, no un SaaS con cuentas de usuario | Fase 4, solo si Internal Model Studio lo exige como producto |
| Launcher o catálogo multi-herramienta | Es, por definición, Internal Model Studio | Fase 4 |
| Shiny modules como patrón opcional | Convertido en obligatorio; no existe como alternativa | No aplica |

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
│   ├── distribution-fitting/
│   ├── bootstrap-mse/
│   ├── scenario-generation/
│   ├── extreme-value-theory/
│   └── ...                          # ~40 carpetas, nombradas por slug descriptivo
│
├── docs/
│   ├── architecture_v1.md           # este documento
│   ├── decisions_log.md
│   ├── data_contract.md
│   └── roadmap.md
│
├── renv.lock
├── .Rprofile
└── README.md
```

### 9.1 Nomenclatura de carpetas de herramienta

Las carpetas de herramienta se nombran con un **slug descriptivo en `kebab-case`**, sin numeración. Un slug es estable frente a reordenaciones futuras por categoría y no rompe URLs ya compartidas públicamente. El orden y la agrupación por categoría se gestionan como metadato en `manifest.yml`, nunca como nombre de carpeta.

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
   - Los módulos Shiny compartidos usan prefijo `mod_` (`mod_data_input`, `mod_export_csv`), por ser la convención estándar de la comunidad Shiny y por eliminar toda ambigüedad sobre si un elemento es módulo o función.
   - Las funciones de theming usan el patrón `theme_bmk*()` (`theme_bmk()`, `theme_bmk_ggplot()`), por convención de `ggplot2`.

   Las funciones locales de una herramienta no llevan prefijo, ya que viven en scope local y no requieren desambiguación.
4. **Regla de 2 para promover a `shared/`:** una función se traslada a `shared/` únicamente cuando es necesaria en 2 o más herramientas. Hasta entonces permanece local. No se generaliza por anticipado. Las funciones de cálculo promovidas van a `shared/actuarial/`; las de formato y presentación, a `shared/utils/`.
5. **Módulo frente a función:** si mantiene estado reactivo o necesita namespace propio, es un módulo Shiny; si es UI estática o transformación pura, es una función. Sin excepciones.
6. **`app.R` es exclusivamente orquestación.** Carga `shared/`, monta el módulo de la herramienta y arranca `shinyApp()`. Nunca contiene lógica de cálculo.
7. **`calc.R` y `shared/actuarial/` no dependen de Shiny.** Deben poder ejecutarse mediante `source()` sin Shiny cargado. Esto garantiza que la lógica actuarial sea auditable, testeable y reutilizable fuera de la aplicación, incluida una futura migración a Python o a una API.
8. **Sin números ni cadenas mágicas en `calc.R`.** Todo valor con significado se declara como constante nombrada o parámetro de función.
9. **Toda función lleva documentación en formato roxygen (`#'`)**, aunque el proyecto no se compile como paquete: título, `@param` y `@return` como mínimo. Esto mantiene barata la futura extracción a paquete formal.
10. **Cabecera obligatoria** en todo `calc.R` y `mod_tool.R`:

    ```r
    # ============================================================
    # Tool: <nombre de la herramienta>
    # Archivo: <propósito de este archivo>
    # Autor: BMK
    # Última actualización: <fecha>
    # ============================================================
    ```

11. **Cada herramienta es autocontenida y ejecutable de forma independiente** mediante `shiny::runApp("tools/<slug>")`, sin depender de ninguna otra carpeta dentro de `tools/`.
12. **`manifest.yml` obligatorio** en toda herramienta, con los campos definidos en el apartado 9.2. Es la fuente única del nombre y la versión mostrados en la interfaz.
13. **Convenio de commits:** prefijo con el ámbito afectado, `[shared] ...` o `[kernel-density] ...`.
14. **Ninguna herramienta publicada se modifica retroactivamente** por un cambio en `shared/` sin decisión explícita de re-despliegue. `shared/` mantiene compatibilidad hacia atrás por defecto; todo cambio incompatible se documenta en `docs/decisions_log.md` **antes** de aplicarse.
15. **Orden interno fijo de `app.R`:** `library()` → carga de `shared/` → definición de `ui` → definición de `server` → `shinyApp()`.
16. **Ninguna herramienta contiene CSS o HTML suelto** fuera del sistema de componentes de `shared/`.
17. **Toda idea adicional surgida durante el desarrollo de una herramienta va al backlog**, nunca a la herramienta en curso.

---

## 11. Definición de "Tool terminada"

Una herramienta se considera terminada únicamente si cumple **todos** los puntos siguientes. No se admite el cumplimiento parcial.

### 11.1 Funcional

- [ ] Acepta datos mediante CSV subido y mediante "generar datos de ejemplo".
- [ ] Contrato de columnas esperadas definido y `bmk_validate_data()` integrada en `mod_data_input`, probada con al menos un caso de error real (columna faltante, tipo incorrecto o dataset vacío).
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
- [ ] `manifest.yml` completo, con `version` en formato semver; el nombre y la versión mostrados en la interfaz coinciden con los declarados en él.
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
- La arquitectura no se revisa salvo bug crítico que bloquee la publicación.

### Fase 2 — Optimización
*Criterio de entrada: 25-30 herramientas publicadas, o antes si el mantenimiento de `shared/` genera fricción medible*

- Continúa la publicación de herramientas hasta completar el objetivo global de 30-40, en paralelo a las tareas de optimización.
- Evaluación, con datos reales de mantenimiento y no por intuición, de la conversión de `shared/` en paquete formal. Criterio: fricción generada por el re-despliegue de herramientas afectadas por cambios en `shared/` y por la ausencia de versionado sobre dicho código.
- Incorporación de exportación a PDF.
- Introducción de tests automatizados exclusivamente sobre `calc.R` y `shared/actuarial/`, priorizando las herramientas de mayor riesgo reputacional (VaR, capital, reservas).
- Evaluación de CI/CD simple para reducir la fricción del despliegue manual.
- Pase de revisión de consistencia visual sobre las herramientas ya publicadas.

### Fase 3 — Migración parcial
*Meses 9-12; puede solaparse con la Fase 2*

- Exploración —no obligación— de la migración de funciones puras de `calc.R` y `shared/actuarial/` a Python, donde exista sentido comercial (servicios reutilizables, API).
- La interfaz permanece en Shiny/R durante toda esta fase.
- Esta fase no se adelanta por presión externa ni por tendencia tecnológica, únicamente por necesidad comercial concreta.

### Fase 4 — Internal Model Studio / ORSA Platform / Actuarial Risk Hub
*Año 2 en adelante*

- Construcción de una aplicación contenedora que monta los módulos `mod_<tool>` ya existentes como pestañas o secciones.
- Generación automática del catálogo y del menú a partir de los `manifest.yml` de cada herramienta.
- Único punto del roadmap donde se contempla añadir complejidad de producto real: autenticación, persistencia de sesión y roles, deliberadamente fuera de alcance en las fases 1 a 3.

### 12.1 Aceleración esperada por herramienta

A partir de la primera herramienta, el flujo de creación se reduce a:

1. Copiar `tools/tool-00-template/` a `tools/<slug>/`.
2. Escribir `calc.R` con la lógica actuarial específica.
3. Conectar esa lógica a los componentes existentes desde `mod_tool.R`.
4. Redactar el texto dinámico de la caja de interpretación.
5. Completar `manifest.yml` y `README.md`.
6. Verificar la checklist del apartado 11 y publicar.

Toda mejora aplicada a `shared/` se propaga a las herramientas ya publicadas en su siguiente re-despliegue, conforme a la regla 14.

---

## 13. Riesgos del proyecto

| Riesgo | Probabilidad | Impacto | Estrategia de mitigación |
|---|---|---|---|
| Scope creep por herramienta | Alta | Alto | Checklist de "Tool terminada" como límite estricto; toda idea adicional va al backlog, nunca a la herramienta en curso (regla 17) |
| Deriva de versiones de `shared/` entre herramientas publicadas | Media-Alta | Medio | `renv.lock` único versionado; regla 14 de no modificación retroactiva sin decisión explícita |
| Degradación de la calidad de la interpretación automática | Alta | Medio | La checklist exige texto específico como criterio de finalización; auditoría periódica de 1 de cada 5 herramientas contra las primeras publicadas |
| Cambios en `shared/` que rompen herramientas antiguas | Media | Alto | Compatibilidad hacia atrás por defecto; todo cambio incompatible documentado en `docs/decisions_log.md` antes de aplicarse |
| Límites de hosting gratuito al escalar a 40 aplicaciones activas | Alta | Medio | Monitorización mensual de horas de uso; presupuestar la ampliación de plan antes de alcanzar el límite |
| Punto único de fallo (un solo desarrollador, sin revisión externa) | Constante | Alto si se detiene el ritmo | `docs/decisions_log.md` como memoria externa; checklist como sustituto parcial de code review; ritmo sostenible priorizado sobre velocidad máxima |
| Error de cálculo actuarial no detectado (riesgo reputacional principal) | Media | Muy alto | Verificación manual obligatoria contra caso conocido antes de publicar (checklist 11.1); tests automatizados priorizados por sensibilidad desde Fase 2 |
| Uso indebido de una herramienta con datos reales de terceros | Baja-Media | Alto | Disclaimer de privacidad y de uso obligatorio y visible en toda herramienta (apartado 4.3) |
| Presión por migrar a Python antes de tiempo | Media | Medio | La Fase 3 reserva espacio explícito y acotado; no se adelanta sin necesidad comercial real |
| Sobrecarga de la aplicación por volumen de datos de entrada | Media | Medio | Límites del apartado 7.5, aplicados desde `mod_data_input` (tamaño de archivo) y `bmk_validate_data()` (número de filas) |
| Divergencia entre la versión mostrada al usuario y el metadato de la herramienta | Baja | Medio | `manifest.yml` como fuente única de verdad; verificación incluida en la checklist 11.3 |

---

## 14. Contrato técnico

Resumen ejecutivo y definitivo de todas las decisiones aprobadas.

1. `shared/` es una carpeta de funciones cargadas mediante `source()`, **no** un paquete de R formal, durante toda la Fase 1.
2. Cada herramienta es un módulo Shiny (`mod_<tool>_ui` / `mod_<tool>_server`) desde la Tool 0. Sin excepciones.
3. `app.R` es orquestación pura. `calc.R` y `shared/actuarial/` son lógica pura, sin dependencia de Shiny.
4. Exportación de resultados: **solo CSV** en Fase 1. PDF llega en Fase 2. La descarga de imagen de gráficos interactivos ya está resuelta de forma nativa por `plotly`.
5. Un único `renv.lock` en la raíz del repositorio. Cero lockfiles por herramienta.
6. Despliegue manual en shinyapps.io durante la Fase 1. CI/CD se evalúa en Fase 2.
7. Sin modo oscuro, sin i18n, sin persistencia de datos, sin autenticación: fuera de alcance hasta la Fase 4 como muy pronto, y solo si el producto lo exige.
8. Módulo frente a función se decide por una única regla: estado reactivo → módulo; sin estado → función.
9. Una función se promueve a `shared/` únicamente cuando la necesitan 2 o más herramientas (regla de 2). Cálculo → `shared/actuarial/`; formato y presentación → `shared/utils/`.
10. Carpetas de herramienta: slug en `kebab-case`, sin numeración. Archivos R y de `docs/`: `snake_case`. Funciones de `shared/`: prefijo `bmk_`, salvo módulos compartidos (`mod_`) y funciones de theming (`theme_bmk*()`). Funciones locales: sin prefijo.
11. `manifest.yml` obligatorio en toda herramienta desde el primer día, y fuente única de verdad del nombre y la versión mostrados en la interfaz. Versionado en semver.
12. `bsicons` es la única librería de iconografía del proyecto.
13. Los colores de éxito, alerta y error se limitan al componente `bmk_notify()` y no constituyen un sistema semántico de diseño.
14. Límites de datos de entrada: 10 MB de tamaño de archivo, aplicado desde `mod_data_input`; 100.000 filas, aplicado desde `bmk_validate_data()`.
15. Toda herramienta muestra aviso de privacidad y disclaimer de uso de forma visible.
16. Los nombres de columna estándar se definen en `docs/data_contract.md` y nunca se improvisan por herramienta.
17. Ninguna herramienta se considera terminada sin superar la checklist completa del apartado 11.
18. Esta especificación permanece congelada durante la Fase 1 (meses 1 a 8-9). A partir del inicio de la Fase 2 se admiten modificaciones, siempre registradas previamente en `docs/decisions_log.md`.
19. El apartado 12 (Roadmap) es la única fuente de verdad sobre los criterios de entrada en cada fase.

---

## 15. Cómo utilizar este documento

Este documento es la **única referencia de arquitectura** del proyecto *Actuarial Tools by BMK*. Está redactado para ser autosuficiente: puede entregarse como contexto completo a cualquier colaborador, o al inicio de cualquier nueva sesión de trabajo con un asistente de IA, sin necesidad de aportar ningún historial previo.

**Reglas de uso:**

1. **Todo nuevo desarrollo debe seguir esta arquitectura.** Antes de comenzar una herramienta, se revisan los apartados 6 (arquitectura), 7 (componentes), 9 (estructura del repositorio) y 10 (reglas del proyecto).
2. **Ninguna herramienta se publica sin superar íntegramente la checklist del apartado 11.**
3. **Cualquier modificación futura de esta arquitectura debe registrarse en `docs/decisions_log.md` antes de implementarse**, nunca después. El registro debe incluir: fecha, decisión anterior, decisión nueva, motivo del cambio y herramientas afectadas.
4. **Esta especificación permanece congelada durante la Fase 1.** Las preferencias de momento, las tendencias tecnológicas y las ideas surgidas a mitad de desarrollo no constituyen motivo suficiente para reabrirla: van al backlog. A partir de la Fase 2, las modificaciones son admisibles bajo el procedimiento de la regla 3 anterior.
5. **Toda ampliación del contrato de datos** (nuevos nombres de columna estándar) se registra en `docs/data_contract.md`.
6. **Versionado de este documento:**
   - Las **correcciones de consistencia**, que no alteran ninguna decisión de alto nivel, incrementan la versión menor (v1.0 → v1.1) sobre el mismo archivo `docs/architecture_v1.md`, y se resumen en el apartado *Changelog*.
   - Los **cambios de decisión** generan un archivo nuevo (`docs/architecture_v2.md`), conservando el anterior. Las versiones mayores no se sobrescriben.

---

*Actuarial Tools by BMK — Especificación Técnica de Arquitectura v1.1 — Estado: Approved*
