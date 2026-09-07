"""B11.1 - Identificabilidad efectiva: multiples arranques y valle plano."""
import sys, warnings; sys.path.insert(0,'.'); warnings.filterwarnings("ignore")
from pm_core import *
import numpy as np, math, csv
MASTER=20260830
def seed_for(*t):
    h=2166136261
    for tok in t:
        for ch in str(tok): h=((h^ord(ch))*16777619)&0xFFFFFFFF
    return (MASTER^h)&0x7FFFFFFF
CASES=[("pareto","par_var_finita",[3.5,700.0]),("pareto","par_pesada",[1.8,600.0]),
       ("burr","burr_moderada",[2.0,1.5,500.0]),("burr","burr_pesada",[1.2,0.8,400.0]),
       ("lognormal","lnorm_asim",[7.0,1.3]),("gamma","gam_moderada",[2.0,500.0])]
CFGS={"P3c":[.25,.50,.75],"P5":[.10,.25,.50,.75,.90],"P7":[.05,.10,.25,.50,.75,.90,.95]}
MULT=[0.25,0.5,1.0,2.0,4.0]        # multiplicadores del arranque por defecto
rows=[]
print(f"{'dist':10s} {'dgp':16s} {'cfg':4s} {'obj':>3s} {'disp.theta':>11s} {'disp.J':>10s} {'valle plano?':>13s}")
for dist,lab,true in CASES:
    spec=CAT[dist]; k=spec["k"]
    for cn,p in CFGS.items():
        for ob in ["A","Bg","C","D"]:
            spread_t=[]; spread_J=[]
            for r in range(40):
                rng=np.random.default_rng(seed_for(lab,"ident",r))
                x=spec["rng"](1000,true,rng)
                qh=np.quantile(x,p); J=make_objective(ob,dist,np.asarray(p),qh,x)
                sols=[]
                base=start_values(dist,x)
                for mu in MULT:
                    th,st=fit_pm(dist,x,p,ob,start=base*mu)
                    if st=="success": sols.append((th,J(th)))
                if len(sols)>=2:
                    T=np.array([s[0] for s in sols]); Jv=np.array([s[1] for s in sols])
                    # dispersion relativa de los parametros entre arranques
                    rel=np.max(np.abs(T-T[0])/np.maximum(np.abs(T[0]),1e-30))
                    jrel=(Jv.max()-Jv.min())/max(abs(Jv.min()),1e-30)
                    spread_t.append(rel); spread_J.append(jrel)
            if spread_t:
                mt=float(np.median(spread_t)); mj=float(np.median(spread_J))
                flat = "SI" if (mt>0.05 and mj<0.01) else "no"
                print(f"{dist:10s} {lab:16s} {cn:4s} {ob:>3s} {mt:11.4f} {mj:10.2e} {flat:>13s}")
                rows.append(dict(dist=dist,dgp=lab,cfg=cn,m=len(p),k=k,objective=ob,
                                 median_theta_spread=mt,median_J_spread=mj,flat_valley=flat))
with open("results/pm_identifiability.csv","w",newline="") as fh:
    w=csv.DictWriter(fh,fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
print("\nCSV: results/pm_identifiability.csv")
