#!/usr/bin/env bash
# ============================================================
# Actuarial Tools by BMK
# Verificación en R de ADR-019 / ADR-020 / ADR-021 / ADR-022
# ============================================================
#
# Ejecuta la batería completa de Tool-02 y, por haberse modificado `shared/`
# (regla 14), también la de Tool-01. Deja un log completo en verificacion_R.log.
#
#   bash verificar_adr_019_022.sh
#
# CLASIFICACIÓN DE RESULTADOS (cuatro estados distintos):
#   [PASA]        exit 0, sin errores ni warnings
#   [PASA/WARN]   exit 0, pero con warnings (se indica cuántos)
#   [FALLA]       exit != 0, o texto "Error" en la salida  -> cuenta como fallo real
#   [ERROR-VERIF] el propio script de verificación no pudo ejecutar el test
#                 (fichero ausente, Rscript inaccesible...) -> cuenta como fallo
#
# El resumen final solo dice "TODO CORRECTO" si no hay ningún [FALLA] ni
# [ERROR-VERIF]. Los warnings NO ocultan un fallo, pero se reportan aparte.
#
# Historial: la versión anterior evaluaba `if (... | tee ...)`, es decir el
# estado de salida de `tee` (siempre 0), por lo que marcaba [PASA] incluso con
# `Error:`. Se corrige con captura explícita del código de salida.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$ROOT/verificacion_R.log"
: > "$LOG"

PASA=0        # tests correctos
PASA_WARN=0   # correctos pero con warnings
FALLA=0       # fallos reales del test
ERR_VERIF=0   # fallos del propio script de verificación
TOTAL=0

# Ejecuta un script de R y clasifica el resultado.
#   $1 = directorio relativo a ROOT
#   $2 = ruta del script dentro de ese directorio
ejecutar() {
  local dir="$1" script="$2"
  TOTAL=$((TOTAL + 1))
  {
    echo ""
    echo "=================================================================="
    echo ">> $dir :: $script"
    echo "=================================================================="
  } | tee -a "$LOG"

  if [ ! -f "$ROOT/$dir/$script" ]; then
    echo "   [ERROR-VERIF] no existe $dir/$script" | tee -a "$LOG"
    ERR_VERIF=$((ERR_VERIF + 1))
    return
  fi

  # Salida capturada en un temporal para poder inspeccionarla Y registrar el
  # código de salida REAL (sin que lo enmascare la tubería con tee).
  local out rc
  out="$(mktemp)"
  ( cd "$ROOT/$dir" && Rscript "$script" ) > "$out" 2>&1
  rc=$?
  cat "$out" | tee -a "$LOG" >/dev/null
  cat "$out"

  # Recuento de warnings. R traduce los mensajes según el locale, así que se
  # reconocen las formas inglesas y españolas:
  #   individuales  EN: "Warning message", "Warning messages", "In addition: Warning"
  #                 ES: "Aviso:", "Avisos:", "Mensaje(s) de aviso"
  #   resumen       EN: "There were N warnings"      ES: "Hubo N avisos"
  #   tope de R     EN: "50 or more warnings"        ES: "Hubo 50 o más avisos"
  # La tilde de "más" se busca con '.' para no depender de la codificación del log.
  local re_indiv='^(Warning messages?|In addition: Warning|Avisos?:|Mensajes? de aviso)'
  local re_total='(There were ([0-9]+) warnings|Hubo ([0-9]+) avisos)'
  local re_tope='(50 or more warnings|Hubo 50 o m.s avisos)'

  local n_warn suma_warn
  n_warn=$(grep -c -E "$re_indiv" "$out" 2>/dev/null || true)
  suma_warn=$(grep -o -E "$re_total" "$out" 2>/dev/null | grep -o -E "[0-9]+" | head -1 || true)
  if grep -q -E "$re_tope" "$out" 2>/dev/null; then
    suma_warn="50+"
  fi
  [ -z "${suma_warn:-}" ] && suma_warn="$n_warn"

  # Un test se considera fallido si el código de salida no es 0 O si aparece un
  # "Error" en la salida (defensa por si un script no propaga el estado).
  local hay_error=0
  grep -q -E "^Error|Error in |Error:" "$out" 2>/dev/null && hay_error=1

  if [ "$rc" -ne 0 ] || [ "$hay_error" -eq 1 ]; then
    echo "   [FALLA] $dir/$script  (exit=$rc, warnings=$suma_warn)" | tee -a "$LOG"
    echo "   primera línea de error:" | tee -a "$LOG"
    grep -m1 -E "^Error|Error in |Error:" "$out" 2>/dev/null | sed 's/^/     /' | tee -a "$LOG"
    FALLA=$((FALLA + 1))
  elif [ "$suma_warn" != "0" ]; then
    echo "   [PASA/WARN] $dir/$script  (exit=0, warnings=$suma_warn)" | tee -a "$LOG"
    PASA_WARN=$((PASA_WARN + 1))
  else
    echo "   [PASA] $dir/$script" | tee -a "$LOG"
    PASA=$((PASA + 1))
  fi
  rm -f "$out"
}

command -v Rscript >/dev/null 2>&1 || {
  echo "ERROR-VERIF: Rscript no está en el PATH." | tee -a "$LOG"; exit 2;
}

{
  echo "R: $(Rscript -e 'cat(R.version.string)' 2>/dev/null)"
  echo "Fecha: $(date)"
} | tee -a "$LOG"

# --- Tool-02: batería completa ------------------------------------------------
for t in b1_unit_tests b2_unit_tests b2_2_unit_tests b3_unit_tests b4_unit_tests \
         b5_unit_tests b6_unit_tests b7_unit_tests b8_smoke_test import_csv_tests; do
  ejecutar "tools/distribution-fitting" "tests/$t.R"
done

# --- Tool-01: obligatorio por haber tocado shared/ (regla 14) ------------------
for t in smoke_test acceptance_example integration_view_model; do
  ejecutar "tools/kernel-density" "tests/$t.R"
done

# --- Hipótesis sobre los ficheros de muestra ----------------------------------
# Vive en su propio fichero .R: así no hay código R embebido en comillas del
# shell (el escapado de "\\.csv$" provocaba 'unrecognized escape' en R 4.4).
ejecutar "tools/distribution-fitting" "tests/hipotesis_muestras.R"

# --- Resumen ------------------------------------------------------------------
{
  echo ""
  echo "=================================================================="
  echo "RESUMEN"
  echo "  scripts ejecutados : $TOTAL"
  echo "  [PASA]             : $PASA"
  echo "  [PASA/WARN]        : $PASA_WARN"
  echo "  [FALLA]            : $FALLA"
  echo "  [ERROR-VERIF]      : $ERR_VERIF"
  echo "------------------------------------------------------------------"
} | tee -a "$LOG"

TOTAL_FALLOS=$((FALLA + ERR_VERIF))
if [ "$TOTAL_FALLOS" -eq 0 ] && [ "$PASA_WARN" -eq 0 ]; then
  echo "TODO CORRECTO — $TOTAL scripts, 0 fallos, 0 warnings" | tee -a "$LOG"
elif [ "$TOTAL_FALLOS" -eq 0 ]; then
  echo "CORRECTO CON WARNINGS — 0 fallos, pero $PASA_WARN script(s) con warnings" | tee -a "$LOG"
else
  echo "HAY FALLOS — $TOTAL_FALLOS de $TOTAL scripts (fallos reales: $FALLA, errores de verificación: $ERR_VERIF)" | tee -a "$LOG"
fi
echo "Log completo: $LOG" | tee -a "$LOG"
echo "==================================================================" | tee -a "$LOG"

exit "$TOTAL_FALLOS"
