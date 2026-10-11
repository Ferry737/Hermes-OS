"""Monte Carlo simulator for prop-firm challenge pass odds.

Model: each trade risks `risk` of the start balance; a win pays +R, a loss -1R,
`tail` of all trades lose 2R (slippage/gap), and every trade pays `cost` R in
commissions + slippage. Futures rules use a trailing drawdown that stops at the
start balance; crypto rules use a static drawdown. Run: python3 prop_sim.py
"""
import numpy as np
rng=np.random.default_rng(7)
def run(wr,R,risk,target,dd,trailing,ntr,cost=0.1,tail=0.02,N=200000):
    eq=np.zeros(N); peak=np.zeros(N); alive=np.ones(N,bool); passed=np.zeros(N,bool)
    for t in range(ntr):
        u=rng.random(N); win=u<wr
        r=np.where(win,R,-1.0)
        big=(~win)&(rng.random(N)<tail/(1-wr) if wr<1 else False)
        r=np.where(big,-2.0,r)-cost
        act=alive&~passed
        eq=np.where(act,eq+r*risk,eq)
        peak=np.maximum(peak,eq)
        floor=np.minimum(peak-dd,0.0) if trailing else -dd
        dead=act&(eq<=floor)
        alive&=~dead
        passed|=act&~dead&(eq>=target)
    return passed.mean(), (~alive).mean()
combos=[("Coin flip, no costs (zero edge)",0.5,1.0,0,0),("WR50% R1",0.5,1.0,.1,.02),("WR40% R2",0.4,2.0,.1,.02),
("WR60% R1 (very good)",0.6,1.0,.1,.02),("WR70% R0.5",0.7,0.5,.1,.02),("WR80% R0.3",0.8,0.3,.1,.02),("WR90% R0.15",0.9,0.15,.1,.02),
("WR55% R1.5 (strong real edge)",0.55,1.5,.1,.02)]
for name,rules in [("FUT 50K: +6% target, 4% trailing DD",(0.06,0.04,True)),("CRYPTO: +10% target, 6% static DD",(0.10,0.06,False))]:
  print("\n##",name)
  for risk in (0.02,0.01,0.005):
    for ntr in (20,):
      print(f"-- risk {risk*100}%/trade, {ntr} trades")
      for c in combos:
        ev=c[1]*c[2]-(1-c[1])-c[3]-c[4]*1
        p,f=run(c[1],c[2],risk,*rules,ntr,cost=c[3],tail=c[4])
        print(f"{c[0]:32s} EV/trade={ev:+.2f}R  pass={p*100:5.1f}%  blown={f*100:5.1f}%  unfinished={(1-p-f)*100:5.1f}%")
