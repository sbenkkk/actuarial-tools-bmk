"""B11.1 - (a) mecanismo de saturacion de D  (b) tests deterministas de configuracion."""
import sys, warnings; sys.path.insert(0,'.'); warnings.filterwarnings("ignore")
from pm_core import *
import numpy as np, math, csv

print("=== (a) MECANISMO: saturacion del objetivo D en espacio de probabilidad ===")
rng=np.random.default_rng(20260830)
x=CAT["lognormal"]["rng"](1000,[7.0,1.3],rng); p=np.array([.25,.5,.75]); qh=np.quantile(x,p)
JD=make_objective("D","lognormal",p,qh,x); JC=make_objective("C","lognormal",p,qh,x)
print(f"{'meanlog':>9} {'F_theta(q_emp)':>34} {'J_D':>10} {'J_C':>12}")
for ml in (1.75, 3.5, 5.25, 7.0, 8.75):
    th=np.array([ml,1.3]); F=CAT["lognormal"]["F"](qh,th)
    print(f"{ml:9.2f}   {np.array2string(F,precision=6,suppress_small=False):>30} {JD(th):10.5f} {JC(th):12.4f}")
print("  -> con meanlog lejano, F_theta(q_emp) satura en 1: J_D se aplana (gradiente ~ 0)")
print("     y el optimizador se queda en el arranque. J_C conserva pendiente.")

print("\n=== (b) TESTS DETERMINISTAS DE CONFIGURACION (OD-2) ===")
def validate(p, k, n=None):
    """Contrato propuesto. Devuelve (estado, motivo)."""
    if p is None or len(p)==0:              return "REJECT","conjunto de percentiles vacio"
    a=np.asarray(p,dtype=float)
    if np.any(~np.isfinite(a)):             return "REJECT","percentil no finito (NA/NaN/Inf)"
    if np.any(a<=0) or np.any(a>=1):        return "REJECT","percentil fuera del intervalo abierto (0,1)"
    if len(np.unique(a))<len(a):            return "REJECT","percentiles duplicados: restriccion redundante"
    m=len(np.unique(a))
    if m<k:                                 return "REJECT",f"m={m} < k={k}: sistema estructuralmente insuficiente"
    w=[]
    d=np.min(np.diff(np.sort(a)))
    if d<0.01:                              w.append(f"percentiles muy proximos (separacion minima {d:.4f})")
    if n is not None and (a.min()*n<5 or (1-a.max())*n<5):
        w.append(f"percentil extremo con n={n}: menos de 5 observaciones en la cola")
    return ("WARN" if w else "ACCEPT"), "; ".join(w) if w else "configuracion valida"

CASES=[("p = 0",[0.0,0.5,0.75],2,None), ("p = 1",[0.25,0.5,1.0],2,None),
       ("p < 0",[-0.1,0.5,0.75],2,None), ("p > 1",[0.25,0.5,1.7],2,None),
       ("NA/None",[0.25,None,0.75],2,None), ("NaN",[0.25,float('nan'),0.75],2,None),
       ("Inf",[0.25,float('inf'),0.75],2,None), ("duplicados",[0.5,0.5,0.75],2,None),
       ("vector vacio",[],2,None), ("m<k (m=1,k=2)",[0.5],2,None),
       ("m<k (m=2,k=3 Burr)",[0.25,0.75],3,None),
       ("m=k (k=2)",[0.25,0.75],2,None), ("preset 25/50/75 k=2",[0.25,0.5,0.75],2,None),
       ("preset 25/50/75 k=3 Burr",[0.25,0.5,0.75],3,None),
       ("m>k 10/25/50/75/90",[0.1,0.25,0.5,0.75,0.9],2,None),
       ("muy proximos",[0.50,0.505,0.75],2,None),
       ("extremos con n=100",[0.01,0.5,0.99],2,100),
       ("extremos con n=10000",[0.01,0.5,0.99],2,10000)]
rows=[]
print(f"{'caso':28s} {'k':>2} {'estado':>7}  motivo")
for lab,pp,k,n in CASES:
    try:
        pp2=[q for q in pp] if pp is not None else None
        if pp2 is not None and any(q is None for q in pp2):
            st,rs="REJECT","percentil ausente (NA)"
        else:
            st,rs=validate(pp2,k,n)
    except Exception as e:
        st,rs="REJECT",f"error de validacion: {e}"
    print(f"{lab:28s} {k:2d} {st:>7}  {rs}")
    rows.append(dict(caso=lab,k=k,n=n if n else "",estado=st,motivo=rs))
with open("results/pm_contract_tests.csv","w",newline="") as fh:
    w=csv.DictWriter(fh,fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
print("\nCSV: results/pm_contract_tests.csv")
