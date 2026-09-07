# ============================================================
# Actuarial Tools by BMK — Punto de entrada de DESPLIEGUE (Connect Cloud)
# ============================================================
#
# Este archivo NO forma parte de ninguna herramienta ni del framework: es solo el
# punto de entrada que Connect Cloud necesita en la raíz del repositorio para
# desplegar UNA herramienta manteniendo intacta la estructura del proyecto
# (shared/ + tools/<slug>/). Lanza la herramienta en su propia carpeta, de modo
# que sus rutas relativas (../../shared, R/, data/) resuelven correctamente.
#
# Para desplegar otra herramienta, cambia el slug de abajo (o usa una rama).

shiny::shinyAppDir("tools/kernel-density")
