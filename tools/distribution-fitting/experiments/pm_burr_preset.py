"""B11.1-R2 - Burr: P3c vs P3w vs P5. R_MC=300, 6 DGP, objetivo normalizado."""
import sys, warnings; sys.path.insert(0,'.'); warnings.filterwarnings("ignore")
from pm_core import *
import numpy as np, csv
MASTER=20260902; R_MC=300; N=1000
def seed_for(tag,rep):
    s=MASTER
    for ch in (tag+"_"+str(rep)).encode(): s=(s*31+ch)%2147483647
    return s
DGPS=[("moderada",        [2.0,1.5,500.0]),
      ("pesada",          [1.2,0.8,400.0]),
      ("shapes_suaves",   [3.0,2.5,600.0]),
      ("shape2_alto",     [2.0,4.0,500.0]),
      ("shape2_bajo",     [2.0,0.5,500.0]),
      ("escala_x1000",    [2.0,1.5,500000.0])]
CFG={"P3c":[.25,.50,.75],"P3w":[.10,.50,.90],"P5":[.10,.25,.50,.75,.90]}
NAMES=["shape1","shape2","scale"]
rows=[]
print(f"{'dgp':16s} {'cfg':4s} {'conv':>6s} {'param':>7s} {'relRMSE':>10s} {'med|relerr|':>12s} {'p90':>9s} {'p95':>9s} {'catastr':>8s}")
for lab,true in DGPS:
    for cn,p in CFG.items():
        est=[];
        for r in range(R_MC):
            rng=np.random.default_rng(seed_for(lab+cn,r))
            x=CAT["burr"]["rng"](N,true,rng)
            th,st=fit_pm("burr",x,p,"Bg")
            if st=="success": est.append(th)
        E=np.array(est); ok=len(E)
        for j,nm in enumerate(NAMES):
            tv=true[j]
            if ok:
                e=E[:,j]; rel=np.abs(e-tv)/abs(tv)
                b=e.mean()-tv; rmse=float(np.sqrt(np.mean((e-tv)**2)))
                med=float(np.median(rel)); p90=float(np.percentile(rel,90))
                p95=float(np.percentile(rel,95)); cat=int(np.sum(rel>1.0))
            else: b=rmse=med=p90=p95=float('nan'); cat=0
            rows.append(dict(dgp=lab,cfg=cn,m=len(p),k=3,parameter=nm,theta_true=tv,
                R=R_MC,n=N,n_success=ok,conv_rate=ok/R_MC,bias=b,rel_bias=b/tv,
                rmse=rmse,rel_rmse=rmse/abs(tv),median_abs_rel_err=med,
                p90_rel_err=p90,p95_rel_err=p95,catastrophic=cat,
                catastrophic_rate=cat/max(ok,1)))
            print(f"{lab:16s} {cn:4s} {ok/R_MC:6.3f} {nm:>7s} {rmse/abs(tv):10.4f} {med:12.4f} "
                  f"{p90:9.4f} {p95:9.4f} {cat:5d}/{ok:<3d}")
with open("results/pm_burr_preset.csv","w",newline="") as fh:
    w=csv.DictWriter(fh,fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
print("\nCSV: results/pm_burr_preset.csv")
