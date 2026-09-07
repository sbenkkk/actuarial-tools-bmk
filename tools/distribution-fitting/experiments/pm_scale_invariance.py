"""B11.1 - Invariancia de escala. Ajusta X y c*X y compara la equivarianza."""
import sys; sys.path.insert(0,'.')
from pm_core import *
import numpy as np, math, csv, warnings
warnings.filterwarnings("ignore")
MASTER=20260830; R=200; C=1000.0
def seed_for(*t):
    h=2166136261
    for tok in t:
        for ch in str(tok): h=((h^ord(ch))*16777619)&0xFFFFFFFF
    return (MASTER^h)&0x7FFFFFFF
# familias con parametro de escala; indice del parametro de escala
SCALE_IDX={"exponential":None,"gamma":1,"weibull":1,"lognormal":None,
           "loglogistic":1,"pareto":1,"burr":2,"normal":None}
DGPS=[("exponential","exp_m100",[0.01]),("gamma","gam_moderada",[2.0,500.0]),
      ("weibull","wei_moderada",[1.5,600.0]),("lognormal","lnorm_asim",[7.0,1.3]),
      ("loglogistic","llog_moderada",[3.0,300.0]),("pareto","par_var_finita",[3.5,700.0]),
      ("burr","burr_moderada",[2.0,1.5,500.0]),("normal","norm_positiva",[100.0,15.0])]
cfg=[.25,.50,.75]; OBJ=["A","B","Bg","C","D"]
rows=[]
print(f"{'dist':12s} {'obj':>3s} {'conv_X':>7s} {'conv_cX':>8s} {'max|dif rel| forma':>19s} {'dif rel escala':>15s}")
for dist,lab,true in DGPS:
    spec=CAT[dist]; k=spec["k"]; si=SCALE_IDX[dist]
    for ob in OBJ:
        d_shape=[]; d_scale=[]; ok1=ok2=0
        for r in range(R):
            rng=np.random.default_rng(seed_for(lab,"scale",r))
            x=spec["rng"](1000,true,rng)
            t1,s1=fit_pm(dist,x,cfg,ob)
            t2,s2=fit_pm(dist,x*C,cfg,ob)
            ok1+=(s1=="success"); ok2+=(s2=="success")
            if s1=="success" and s2=="success":
                for j in range(k):
                    # Equivarianza esperada bajo X' = c X, por parametrizacion real:
                    #   escala directa (gamma/weibull/llog/pareto/burr scale) -> x c
                    #   exponencial rate                                       -> / c  (escala INVERSA)
                    #   lognormal meanlog -> + log c ; sdlog -> invariante
                    #   normal mean y sd                                       -> x c
                    exp2 = t1[j]*C if (si is not None and j==si) else t1[j]
                    if dist=="exponential":            exp2 = t1[0]/C
                    if dist=="lognormal" and j==0:     exp2 = t1[0]+math.log(C)
                    if dist=="normal":                 exp2 = t1[j]*C
                    rel=abs(t2[j]-exp2)/max(abs(exp2),1e-30)
                    (d_scale if (si is not None and j==si) else d_shape).append(rel)
        ms=max(d_shape) if d_shape else float('nan')
        mc=max(d_scale) if d_scale else float('nan')
        print(f"{dist:12s} {ob:>3s} {ok1/R:7.3f} {ok2/R:8.3f} {ms:19.3e} {mc:15.3e}")
        rows.append(dict(dist=dist,dgp=lab,objective=ob,R=R,c=C,
                         conv_X=ok1/R,conv_cX=ok2/R,
                         max_rel_dev_shape=ms,max_rel_dev_scale=mc))
with open("results/pm_scale_invariance.csv","w",newline="") as fh:
    w=csv.DictWriter(fh,fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
print("\nCSV: results/pm_scale_invariance.csv")
