* Set the end-of-line comment character (and enable EOL comment)
$eolCom //

SET
	r		"Regions"
			/ A, B /
;

ALIAS (r,rr);

TABLE ref_YM(r,rr)	"Benchmark trade quantity from r to rr (kt)"
	A	B	// Supply (rowSums)
A	800	200	// 1000
B	400	1800	// 2200
* Demand (colSums)
*	1200	2000
;

TABLE tcost(r,rr)	"Transport cost from r to rr (USD)"
	A	B	
A	100	60	
B	90	0	
;

PARAMETER
	epsilon		"Price elasticity of demand"
			/ -1 /
	ref_PM(rr,r)	"Benchmark import price (USD)"
	sha_PM(rr,r)	"Benchmark share of PM"
	ref_YA(r)	"Benchmark final demand (kt)"
	ref_PA(r)	"Benchmark final price (USD)"
	ref_P(r)	"Benchmark producer price (USD)"
			/ A  190, B  220 /
	rep_YM(*,r,rr)	"Report: Trade quantity"
	rep_YA(*,r)	"Report: Final demand"
	rep_PA(*,r)	"Report: Final price"
;

* Benchmark import price
ref_PM(rr,r) = ref_P(rr) + tcost(rr,r);

* Benchmark demand is sum for each column
ref_YA(r) = sum(rr, ref_YM(rr,r));

* Benchmark final price
ref_PA(r) = sum(rr, ref_YM(rr,r) * ref_PM(rr,r)) / ref_YA(r);

* Benchmark share
sha_PM(rr,r) = ref_YM(rr,r) * ref_PM(rr,r) / sum(rr.local, ref_YM(rr,r) * ref_PM(rr,r));

* Macro for cost function
$macro C_PM(r)	sum(rr.local, sha_PM(rr,r) * (PM(rr,r) / ref_PM(rr,r)))

* Macro for report
$macro report(scenario)	\
	rep_YM(scenario,r,rr) = YM.l(r,rr);	\
	rep_YA(scenario,r) = YA.l(r);	\
	rep_PA(scenario,r) = PA.l(r);

* Model definition 
NONNEGATIVE VARIABLES
	YM(r,rr)	"Import quantity from r to rr (kt)"
	PM(r,rr)	"Import price from r to rr (USD)"
	YA(r)		"Final demand (kt)"
	PA(r)		"Final price (USD)"
;

EQUATIONS
	zpf_YM(rr,r)	"Zero profit condition: Import"
	mkt_PM(rr,r)	"Market clearing condition: Import"
	zpf_YA(r)	"Zero profit condition: Armington"
	mkt_PA(r)	"Market clearing condition: Armington"
;

mkt_PM(rr,r).. 	// supply >= demand (A2.7)
	YM(rr,r) =g= ref_YM(rr,r) * (1 + epsilon * (C_PM(r) - 1));

zpf_YM(rr,r).. 	// unit cost >= price (A2.8)
	ref_P(rr) + tcost(rr,r) =g= PM(rr,r);  // ref_P(i) nehme unsere produktionsfunktion

mkt_PA(r).. 	// supply >= demand (A2.9)
	YA(r) =g= ref_YA(r) * (1 + epsilon * (PA(r) / ref_PA(r) - 1));

zpf_YA(r).. 	// unit cost >= price (A2.10)
	ref_PA(r) * C_PM(r) =g= PA(r);

MODEL trade
	/
	mkt_PM.PM
	zpf_YM.YM
	mkt_PA.PA
	zpf_YA.YA
	/
;

* Set benchmark values
YM.l(r,rr)	= ref_YM(r,rr);
PM.l(rr,r)	= ref_PM(rr,r);
YA.l(r)		= ref_YA(r);
PA.l(r)		= ref_PA(r);

* Calibration check
trade.iterlim	= 0;
SOLVE trade using MCP;

report("Benchmark")

* Effect of doubling transport cost from B to A
trade.iterlim	= 1000;
tcost("B","A") = tcost("B","A") * 2;
SOLVE trade using MCP;
report("Policy 1")

* Effect of not having transport costs
tcost(r,rr) = 0;
SOLVE trade using MCP;
report("Policy 2")

display rep_YM, rep_YA, rep_PA;

execute_unload 'output/gams/trade_results.gdx' 