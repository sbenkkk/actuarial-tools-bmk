# ============================================================
# Tool: distribution-fitting (Tool-02)
# Archivo: tests/b5_unit_tests.R
# Tests unitarios de B5 (Text Builders): estructura del bloque textual,
# consumo PURO de las capas anteriores, determinismo y avisos derivados
# únicamente de flags existentes. No valida estadística (B1-B4, congelados).
# Autor: BMK — Última actualización: 2026-07-25
# ============================================================
#
#   Rscript tests/b5_unit_tests.R      # desde la raíz de la herramienta
#   Rscript b5_unit_tests.R            # desde la carpeta tests/

.locate_script <- function() {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    return(normalizePath(sub("^--file=", "", file_arg[1]), mustWork = FALSE))
  }
  for (i in rev(seq_len(sys.nframe()))) {
    of <- sys.frame(i)$ofile
    if (!is.null(of)) return(normalizePath(of, mustWork = FALSE))
  }
  NULL
}
.tool_root <- local({
  s <- .locate_script()
  if (!is.null(s)) dirname(dirname(s))
  else if (file.exists("R/calc.R")) normalizePath(".")
  else if (file.exists(file.path("..", "R", "calc.R"))) normalizePath("..")
  else stop("No se pudo localizar la raíz de la herramienta.", call. = FALSE)
})
source(file.path(.tool_root, "R", "calc.R"))

check <- function(cond, msg) {
  if (!isTRUE(cond)) stop(sprintf("FALLO: %s", msg), call. = FALSE)
  cat(sprintf("  OK  - %s\n", msg))
}
has_text <- function(x, pattern) any(grepl(pattern, x, fixed = TRUE))

cat("== B5 UNIT TESTS (Text Builders) — distribution-fitting ==\n")

xc <- c(120.3, 340.7, 550.1, 610.4, 800.9, 1200.2, 1500.6, 2100.8, 2600.5, 3400.1, 5200.7, 9800.4)
xd <- c(0, 1, 0, 2, 1, 3, 0, 1, 2, 4, 1, 0, 2, 1, 5)
xz <- c(0, 120.3, 340.7, 800.9, 2100.8, 5200.7)

# ------------------------------------------------------------
# 1. Estructura del bloque textual
# ------------------------------------------------------------
cat("\n-- 1. Estructura --\n")
rc <- dist_fit_analyze(data.frame(loss_amount = xc), "loss_amount")
tb <- rc$text_builder
check(all(c("summary", "recommendation", "insights", "warnings", "distribution_cards")
          %in% names(tb)),
      "text_builder: expone summary/recommendation/insights/warnings/cards")
check(is.character(tb$summary) && nchar(tb$summary) > 0, "summary: texto no vacío")
check(all(c("headline", "confidence", "main_reason", "alternatives") %in% names(tb$recommendation)),
      "recommendation: headline/confidence/main_reason/alternatives")
check(all(c("why_won", "strengths", "weaknesses", "observations") %in% names(tb$insights)),
      "insights: why_won/strengths/weaknesses/observations")
check(is.character(tb$warnings), "warnings: vector de texto")

# ------------------------------------------------------------
# 2. Coherencia con el assessment (sin recalcular)
# ------------------------------------------------------------
cat("\n-- 2. Coherencia con B4 --\n")
lab_top <- rc$motor$fits[[rc$assessment$recommendation$level1$id]]$label
check(has_text(tb$recommendation$headline, lab_top),
      "recommendation: nombra la distribución recomendada por B4")
check(has_text(tb$recommendation$confidence, rc$assessment$recommendation$level1$confidence),
      "recommendation: refleja el nivel de confianza de B4")
check(length(tb$distribution_cards) ==
        length(rc$assessment$ranking) + length(rc$assessment$excluded),
      "cards: una por candidata evaluada + una por descartada")
check(tb$distribution_cards[[1]]$id == rc$assessment$ranking[[1]]$id &&
        tb$distribution_cards[[1]]$rank == 1L,
      "cards: la primera corresponde al top del ranking")
check(identical(tb$distribution_cards[[1]]$score, rc$assessment$ranking[[1]]$composite),
      "cards: el score se copia del assessment (no se recalcula)")
check(has_text(tb$summary, "loss_amount") && has_text(tb$summary, "continua"),
      "summary: menciona la variable y el tipo detectado")

# ------------------------------------------------------------
# 3. Consumidor PURO: funciona con objetos sintéticos (sin datos ni ajuste)
# ------------------------------------------------------------
cat("\n-- 3. Consumidor puro --\n")
fake_fit <- function(id, label, np) {
  list(id = id, label = label, method = "mle", method_reason = "solicitado",
       n_params = np, role = "candidate", n_used = 10L,
       n_excluded = list(zeros = 0L, negatives = 0L), params = list(a = 1),
       logLik = -10, converged = TRUE, message = NA_character_)
}
fake_motor <- list(method = "mle", family = "continuous",
                   fits = list(alpha = fake_fit("alpha", "Alfa", 1L),
                               beta  = fake_fit("beta",  "Beta", 2L)),
                   control_fits = list())
fake_assess <- list(
  family = "continuous", weights = list(A = 0.7, B = 0.3),
  ranking = list(
    list(id = "alpha", rank = 1L, composite = 90, pillar_scores = list(A = 95, B = 80), n_params = 1L),
    list(id = "beta",  rank = 2L, composite = 40, pillar_scores = list(A = 20, B = 60), n_params = 2L)),
  excluded = list(), control_check = NULL, deferred = list(x = "diferido"),
  recommendation = list(level1 = list(id = "alpha", composite = 90,
                                      confidence = "alta", confidence_reason = "separación amplia")),
  decision_engine_version = "0.2")
fake_profile <- list(variable = "sintetica", n_valid = 10L, pct_na = 0)
tf <- .text_builders(fake_profile, NULL, fake_motor, NULL, fake_assess)
check(has_text(tf$recommendation$headline, "Alfa") && has_text(tf$recommendation$headline, "90,0"),
      "puro: usa el ganador y el score del assessment sintético")
check(has_text(tf$recommendation$confidence, "alta"), "puro: usa la confianza sintética")
check(length(tf$distribution_cards) == 2L,   "puro: genera una card por entrada del ranking")
check(has_text(tf$summary, "sintetica"),     "puro: usa la variable del profile sintético")
check(length(tf$warnings) == 0L,             "puro: sin flags problemáticos, no inventa avisos")

# ------------------------------------------------------------
# 4. Determinismo (mismas entradas -> mismo texto)
# ------------------------------------------------------------
cat("\n-- 4. Determinismo --\n")
check(identical(.text_builders(fake_profile, NULL, fake_motor, NULL, fake_assess), tf),
      "determinismo: la misma entrada produce exactamente el mismo texto")

# ------------------------------------------------------------
# 5. Warnings a partir de flags existentes
# ------------------------------------------------------------
cat("\n-- 5. Warnings --\n")
tz <- dist_fit_analyze(data.frame(loss_amount = xz), "loss_amount")$text_builder
check(has_text(tz$warnings, "cero"),
      "warnings: informa de la exclusión de ceros (soporte estrictamente positivo)")
check(!has_text(tb$warnings, "cero"),
      "warnings: sin ceros en los datos, no aparece ese aviso")
check(!has_text(tb$warnings, "inestables"),
      "warnings: no inventa avisos de estabilidad (Pilar D diferido)")

# ------------------------------------------------------------
# 6. Familia discreta
# ------------------------------------------------------------
cat("\n-- 6. Discreta --\n")
td <- dist_fit_analyze(data.frame(count = xd), "count")$text_builder
check(has_text(td$summary, "discreta"),         "summary (discreta): refleja el tipo de variable")
check(has_text(td$recommendation$headline, "Binomial Negativa"),
      "recommendation (discreta): recomienda la binomial negativa")

# ------------------------------------------------------------
# 7. Veredicto por distribución (determinista, matriz de bandas)
# ------------------------------------------------------------
cat("\n-- 7. Veredicto --\n")
cards <- tb$distribution_cards
check(all(vapply(cards, function(c) is.character(c$verdict) && nzchar(c$verdict),
                 logical(1))),
      "cada card incluye un veredicto no vacío")
bands <- decision_engine_spec()$text_bands
check(identical(.verdict_of(95, 95, bands), .verdict_of(90, 80, bands)),
      "veredicto determinista: misma banda -> misma frase")
check(!identical(.verdict_of(95, 95, bands), .verdict_of(95, 10, bands)),
      "bandas distintas -> veredictos distintos")
check(grepl("parsimonia", .verdict_of(95, 95, bands), fixed = TRUE),
      "ajuste fuerte + parsimonia fuerte -> menciona la parsimonia")
check(grepl("complejidad", .verdict_of(95, 10, bands), fixed = TRUE),
      "ajuste fuerte + parsimonia débil -> menciona la complejidad")
check(grepl("pobre", .verdict_of(10, 95, bands), fixed = TRUE),
      "ajuste débil -> lo declara explícitamente")

# ------------------------------------------------------------
# 8. Comparación con la recomendada (✔/✘ deterministas)
# ------------------------------------------------------------
cat("\n-- 8. Comparación con la recomendada --\n")
rec_card <- cards[[1]]
check(length(rec_card$vs_recommended) == 0L,
      "la propia recomendada no se compara consigo misma")
otra_card <- cards[[2]]
check(length(otra_card$vs_recommended) == 3L,
      "cada candidata se compara en ajuste, parsimonia y proximidad")
check(all(vapply(otra_card$vs_recommended,
                 function(it) is.logical(it$ok) && nzchar(it$text), logical(1))),
      "cada observación trae marca (ok) y texto")

# Determinismo sobre entradas sintéticas.
mk <- function(id, A, B, comp) list(id = id, composite = comp,
                                    pillar_scores = list(A = A, B = B))
rec_e <- mk("rec", 90, 90, 90)
peor  <- .compare_to_recommended(mk("x", 50, 50, 50), rec_e, close_gap = 10)
check(all(!vapply(peor, function(i) i$ok, logical(1))),
      "peor en todo -> tres observaciones desfavorables")
mejor <- .compare_to_recommended(mk("y", 95, 95, 89), rec_e, close_gap = 10)
check(all(vapply(mejor, function(i) i$ok, logical(1))),
      "mejor o próxima -> tres observaciones favorables")
check(identical(peor, .compare_to_recommended(mk("x", 50, 50, 50), rec_e, 10)),
      "determinismo: misma entrada -> mismas observaciones")

cat("\nB5 UNIT TESTS SUPERADOS\n")
