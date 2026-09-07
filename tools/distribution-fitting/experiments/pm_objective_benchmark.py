"""B11.1 - Benchmark Monte Carlo de formulaciones de Percentile Matching (OD-1).
Ejecutar:  python3 pm_objective_benchmark.py
Salida:    results/pm_objective_benchmark.csv
"""
import sys, time, csv, math
sys.path.insert(0, '.')
from pm_core import *
import numpy as np

MASTER_SEED = 20260830
R_REPS      = 300
NS          = [100, 1000, 10000]
OBJS        = ["A", "B", "Bg", "C", "D"]

DGPS = [  # (dist, etiqueta, theta_true)
 ("exponential", "exp_m100",      [0.01]),
 ("exponential", "exp_m1000",     [0.001]),
 ("gamma",       "gam_moderada",  [2.0, 500.0]),
 ("gamma",       "gam_asimetrica",[0.6, 1500.0]),
 ("gamma",       "gam_casi_sim",  [5.0, 200.0]),
 ("weibull",     "wei_moderada",  [1.5, 600.0]),
 ("weibull",     "wei_hazard_dec",[0.7, 500.0]),
 ("weibull",     "wei_ligera",    [2.5, 800.0]),
 ("lognormal",   "lnorm_moderada",[7.0, 0.6]),
 ("lognormal",   "lnorm_asim",    [7.0, 1.3]),
 ("lognormal",   "lnorm_pesada",  [5.0, 2.0]),
 ("loglogistic", "llog_moderada", [3.0, 300.0]),
 ("loglogistic", "llog_pesada",   [1.5, 300.0]),
 ("pareto",      "par_var_finita",[3.5, 700.0]),
 ("pareto",      "par_pesada",    [1.8, 600.0]),
 ("burr",        "burr_moderada", [2.0, 1.5, 500.0]),
 ("burr",        "burr_pesada",   [1.2, 0.8, 400.0]),
 ("normal",      "norm_positiva", [100.0, 15.0]),
 ("normal",      "norm_estandar", [0.0, 1.0]),
]

def configs_for(dist):
    k = CAT[dist]["k"]
    mk = {1: [0.50], 2: [0.25, 0.75], 3: [0.25, 0.50, 0.75]}[k]
    out = {"P3c": [.25,.50,.75], "P3w": [.10,.50,.90], "P5": [.10,.25,.50,.75,.90]}
    if mk not in out.values(): out["Pmk"] = mk
    return out

def seed_for(dgp, n, rep):
    """Semilla determinista por escenario/repeticion: anadir un escenario no
    desplaza los demas (requisito §25 del encargo)."""
    h = 2166136261
    for tok in (dgp, str(n), str(rep)):
        for ch in tok:
            h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return (MASTER_SEED ^ h) & 0x7FFFFFFF

def main(lo=0, hi=len(DGPS)):
    rows, t0 = [], time.time()
    for dist, lab, true in DGPS[lo:hi]:
        spec = CAT[dist]; names = spec["names"]
        for n in NS:
            cfgs = configs_for(dist)
            acc = {(cn, ob): [] for cn in cfgs for ob in OBJS}
            fail = {(cn, ob): {} for cn in cfgs for ob in OBJS}
            for rep in range(R_REPS):
                rng = np.random.default_rng(seed_for(lab, n, rep))
                x = spec["rng"](n, true, rng)
                for cn, p in cfgs.items():
                    for ob in OBJS:
                        th, st = fit_pm(dist, x, p, ob)
                        if st == "success": acc[(cn, ob)].append(th)
                        else: fail[(cn, ob)][st] = fail[(cn, ob)].get(st, 0) + 1
            for cn, p in cfgs.items():
                for ob in OBJS:
                    est = np.array(acc[(cn, ob)]); f = fail[(cn, ob)]
                    ns_ = len(est)
                    for j, pname in enumerate(names):
                        tv = true[j]
                        if ns_ > 0:
                            b = est[:, j].mean() - tv
                            rmse = math.sqrt(np.mean((est[:, j] - tv) ** 2))
                            rb = b / tv if abs(tv) > 1e-12 else float('nan')
                            rr = rmse / abs(tv) if abs(tv) > 1e-12 else float('nan')
                            sdj = est[:, j].std(ddof=1) if ns_ > 1 else float('nan')
                        else:
                            b = rmse = rb = rr = sdj = float('nan')
                        rows.append(dict(
                            dist=dist, dgp=lab, n=n, cfg=cn, m=len(p), k=spec["k"],
                            objective=ob, parameter=pname, theta_true=tv,
                            R=R_REPS, n_success=ns_, conv_rate=ns_/R_REPS,
                            bias=b, rel_bias=rb, rmse=rmse, rel_rmse=rr, sd=sdj,
                            fail_not_applicable=f.get("not_applicable", 0),
                            fail_optimizer=f.get("optimizer_failure", 0),
                            fail_boundary=f.get("boundary_guard", 0),
                            fail_nonfinite=f.get("nonfinite", 0)))
            print(f"  {lab:16s} n={n:<6d} {time.time()-t0:7.1f}s", flush=True)
    out = f"results/part_{lo:02d}_{hi:02d}.csv"
    with open(out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
    print(f"\nfilas={len(rows)}  tiempo total={time.time()-t0:.1f}s  R={R_REPS}")

if __name__ == "__main__":
    lo = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    hi = int(sys.argv[2]) if len(sys.argv) > 2 else len(DGPS)
    main(lo, hi)
