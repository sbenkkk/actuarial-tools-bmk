"""
B11.1 - Nucleo del benchmark de Percentile Matching.
Replica EXACTAMENTE las parametrizaciones de tools/distribution-fitting/R/calc.R.
No forma parte del flujo productivo.
"""
import numpy as np, math
from scipy import stats, optimize

DBL_MIN = np.finfo(float).tiny          # .Machine$double.xmin

# ---------------------------------------------------------------- catalogo
# id: (nombres de parametros, k, positivos?, Q(p,theta), F(x,theta), rng)
def _q_exp(p, t):  return -np.log1p(-p) / t[0]
def _f_exp(x, t):  return 1 - np.exp(-t[0] * x)
def _q_gam(p, t):  return stats.gamma.ppf(p, a=t[0], scale=t[1])
def _f_gam(x, t):  return stats.gamma.cdf(x, a=t[0], scale=t[1])
def _q_wei(p, t):  return t[1] * (-np.log1p(-p)) ** (1 / t[0])
def _f_wei(x, t):  return 1 - np.exp(-(x / t[1]) ** t[0])
def _q_lnorm(p, t): return np.exp(t[0] + t[1] * stats.norm.ppf(p))
def _f_lnorm(x, t): return stats.norm.cdf((np.log(x) - t[0]) / t[1])
def _q_llog(p, t): return t[1] * (p / (1 - p)) ** (1 / t[0])
def _f_llog(x, t):
    z = (x / t[1]) ** t[0]; return z / (1 + z)
def _q_par(p, t):  return t[1] * ((1 - p) ** (-1 / t[0]) - 1)
def _f_par(x, t):  return 1 - (t[1] / (x + t[1])) ** t[0]
def _q_burr(p, t): return t[2] * ((1 - p) ** (-1 / t[1]) - 1) ** (1 / t[0])
def _f_burr(x, t): return 1 - (1 + (x / t[2]) ** t[0]) ** (-t[1])
def _q_norm(p, t): return stats.norm.ppf(p, t[0], t[1])
def _f_norm(x, t): return stats.norm.cdf(x, t[0], t[1])

def _r_llog(n, t, rng):
    u = rng.uniform(size=n); return _q_llog(u, t)
def _r_par(n, t, rng):
    u = rng.uniform(size=n); return _q_par(u, t)
def _r_burr(n, t, rng):
    u = rng.uniform(size=n); return _q_burr(u, t)

CAT = {
 "exponential": dict(names=["rate"], k=1, pos=[True], Q=_q_exp, F=_f_exp,
                     rng=lambda n,t,r: r.exponential(1/t[0], n), support="positive"),
 "gamma":       dict(names=["shape","scale"], k=2, pos=[True,True], Q=_q_gam, F=_f_gam,
                     rng=lambda n,t,r: r.gamma(t[0], t[1], n), support="positive"),
 "weibull":     dict(names=["shape","scale"], k=2, pos=[True,True], Q=_q_wei, F=_f_wei,
                     rng=lambda n,t,r: t[1]*r.weibull(t[0], n), support="positive"),
 "lognormal":   dict(names=["meanlog","sdlog"], k=2, pos=[False,True], Q=_q_lnorm, F=_f_lnorm,
                     rng=lambda n,t,r: r.lognormal(t[0], t[1], n), support="positive"),
 "loglogistic": dict(names=["shape","scale"], k=2, pos=[True,True], Q=_q_llog, F=_f_llog,
                     rng=_r_llog, support="positive"),
 "pareto":      dict(names=["shape","scale"], k=2, pos=[True,True], Q=_q_par, F=_f_par,
                     rng=_r_par, support="positive"),
 "burr":        dict(names=["shape1","shape2","scale"], k=3, pos=[True,True,True],
                     Q=_q_burr, F=_f_burr, rng=_r_burr, support="positive"),
 "normal":      dict(names=["mean","sd"], k=2, pos=[False,True], Q=_q_norm, F=_f_norm,
                     rng=lambda n,t,r: r.normal(t[0], t[1], n), support="real"),
}

# ------------------------------------------------- arranques (los de calc.R)
def start_values(dist, x):
    m, v = x.mean(), x.var(ddof=1)
    if dist == "exponential":  return np.array([1/m])
    if dist == "gamma":        return np.array([m*m/v, v/m])
    if dist == "weibull":
        cv = math.sqrt(v)/m; s0 = max(cv**-1.086, 0.5)
        return np.array([s0, m/math.gamma(1+1/s0)])
    if dist == "lognormal":
        lx = np.log(x); return np.array([lx.mean(), lx.std()])
    if dist == "loglogistic": return np.array([1.0, np.median(x)])
    if dist == "pareto":      return np.array([2.0, m])
    if dist == "burr":        return np.array([1.0, 1.0, np.median(x)])
    if dist == "normal":      return np.array([m, math.sqrt(v)])

# ------------------------------------------------------------- objetivos
def make_objective(kind, dist, p, qhat, x):
    spec = CAT[dist]; Q, F = spec["Q"], spec["F"]
    iqr = np.subtract(*np.percentile(x, [75, 25]))
    def J(theta):
        try:
            if kind == "D":
                d = F(qhat, theta) - p
            else:
                qt = Q(p, theta)
                if not np.all(np.isfinite(qt)): return 1e10
                if kind == "A":   d = qt - qhat
                elif kind == "B": d = (qt - qhat) / qhat          # denom = cuantil empirico
                elif kind == "Bg":d = (qt - qhat) / iqr           # denom = IQR global
                elif kind == "C":
                    if np.any(qt <= 0) or np.any(qhat <= 0): return 1e10
                    d = np.log(qt) - np.log(qhat)
            v = float(np.sum(d**2))
            return v if np.isfinite(v) else 1e10
        except Exception:
            return 1e10
    return J

APPLICABLE = {  # objetivo -> aplicable?
 "A":  lambda dist, qhat: True,
 "B":  lambda dist, qhat: bool(np.all(np.abs(qhat) > 1e-12)),
 "Bg": lambda dist, qhat: True,
 "C":  lambda dist, qhat: bool(np.all(qhat > 0)),
 "D":  lambda dist, qhat: True,
}

# ------------------------------------------------------------ optimizador
def fit_pm(dist, x, p, kind, start=None, maxit=500):
    """Devuelve (theta, status). status: success | not_applicable | optimizer_failure |
       boundary_guard | nonfinite."""
    spec = CAT[dist]; pos = spec["pos"]
    qhat = np.quantile(x, p, method="linear")     # = quantile(type = 7) de R
    if not APPLICABLE[kind](dist, qhat):
        return None, "not_applicable"
    th0 = start_values(dist, x) if start is None else np.asarray(start, float)
    J = make_objective(kind, dist, np.asarray(p, float), qhat, x)
    def to_u(th):  return np.array([math.log(t) if pos[i] else t for i, t in enumerate(th)])
    def to_th(u):  return np.array([math.exp(u[i]) if pos[i] else u[i] for i in range(len(u))])
    def Ju(u):
        th = to_th(u)
        if not np.all(np.isfinite(th)): return 1e10
        return J(th)
    try:
        r = optimize.minimize(Ju, to_u(th0), method="L-BFGS-B",
                              options=dict(maxiter=maxit, maxfun=maxit*20))
    except Exception:
        return None, "optimizer_failure"
    if not np.isfinite(r.fun) or r.fun >= 1e10:
        return None, "optimizer_failure"
    th = to_th(r.x)
    if not np.all(np.isfinite(th)):                       return None, "nonfinite"
    if np.any(np.abs(th)[np.array(pos)] < DBL_MIN):       return None, "boundary_guard"
    if r.status != 0:                                     return th, "optimizer_failure"
    return th, "success"
