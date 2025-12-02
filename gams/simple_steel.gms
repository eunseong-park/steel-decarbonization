$title  "A Simple Steel Industry Model"

* Check if data exists
$if not exist data/simple_steel_data.gdx $abort "Data file not found. Please run 'python gamspy/simple_steel_data.py' or 'Rscript R/simple_steel_data.R' first."

SETS
    i           "Steel plants"
    f           "Factors"
    t           "Technology type"
    it(i,t)     "Link between plants and technologies"
;

PARAMETERS
    abar(t,f)   "Factor use per ton crude steel production"
    vbar(f)     "Reference factor market prices"
    rho(f)      "Price elasticity in factor supply"
    kappa(f)    "Carbon emissions coefficient"
    epsilon     "Price elasticity of steel demand"
    tau(i,f)    "Plant-specific additional cost (e.g. transport)"
    ylim(i)     "Plant-specific production capacity"
    ybar(i)     "Reference output by plant"
    dbar        "Reference aggregate demand"
    chi         "Emissions reduction target" 
;

* Load data from GDX
$gdxin data/simple_steel_data.gdx
$load i f t it
$load abar vbar rho kappa epsilon tau ylim ybar dbar chi
$gdxin

PARAMETERS
    ebar(f)     "Reference carbon emissions"
    rbar(i)     "Reference shadow price of capacity/capital"
    hbar(f)     "Reference factor demand quantity"
    pbar        "Reference steel price"
;

* CALIBRATION ------------------------------------------------------------
* Compute reference quantities and prices for each plant consistent with 
* aggregate reference demand and capacity constraints using a linear program.

VARIABLE
    TC      "Objective function (Total Cost)";

NONNEGATIVE VARIABLE
    Y(i)    "Steel output by plant";

EQUATIONS
    costs   "Objective function - definition of total production cost"
    demand  "Demand constraint"
;

costs..
    TC =e= sum((i, f), sum(it(i, t), abar(t, f)) * (vbar(f) + tau(i, f)) * Y(i));

demand..
    sum(i, Y(i)) =g= dbar;

MODEL mincost   "calibration model determining price consistent with reference demand"
      /costs, demand/
;

* Incorporate capacity constraints:
Y.up(i) = ylim(i);

solve mincost minimizing TC using LP;

* Obtain reference pricess and quantities from LP model:
pbar    = demand.m;
ybar(i) = Y.l(i);
hbar(f) = sum(i, sum(it(i, t), abar(t, f)) * ybar(i));
rbar(i) = -Y.m(i);
ebar(f) = sum(i, sum(it(i, t), abar(t, f) * kappa(f) * ybar(i))); 


* MCP MODEL --------------------------------------------------------------

NONNEGATIVE VARIABLES
    P       "Price of steel"
    V(f)    "Price of factors"
    R(i)    "Plant-specific capital rental rate (shadow price of capacity constraint)" 
    W       "Carbon price"
;

EQUATIONS
    zpf_y(i)    "Zero profit: steel"
    mkt_y       "Market clearance: steel"
    mkt_f(f)    "Market clearance: factors"
    capacity(i) "Capacity constraint of plants"
    mkt_co2     "Market clearance: carbon emissions"
;

* Equilibrium conditions
zpf_y(i)..      sum(f, sum(it(i, t), abar(t, f)) * (V(f) + tau(i,f))) + R(i)
                + sum(f, W * kappa(f) * sum(it(i, t), abar(t, f)))
                =g= P;

mkt_y..         sum(i, Y(i)) =g= dbar * (1 + epsilon * (P / pbar - 1));

mkt_f(f)..      hbar(f) * (1 + rho(f) * (V(f) / vbar(f) - 1)) 
                =g= sum(i, sum(it(i, t), abar(t, f)) * Y(i));

capacity(i)..    ylim(i) =g= Y(i);

mkt_co2$chi..   chi * sum(f, ebar(f))
                =g= sum((f, i), sum(it(i, t), abar(t, f) * kappa(f) * Y(i))); 

MODEL simple /zpf_y.Y, mkt_y.P, mkt_f.V, capacity.R, mkt_co2.W/;

* Relax upper bound on capacity
Y.up(i) = inf;

* Set starting values
P.l    = pbar;
R.l(i) = rbar(i);
Y.l(i) = ybar(i);
V.l(f) = vbar(f);
W.fx$(not chi) = 0;

* Replication check:
simple.iterlim = 0;
solve simple using mcp
abort$(simple.objval > 1e-6) "Model does not calibrate.";

* Define report parameter to store key results
PARAMETER report "Summary report of key results";
$macro write_report(scenario) \
report("production", scenario) = sum(i, Y.l(i)); \
report("emissions", scenario) = sum((f,i), sum(it(i,t), abar(t,f) * kappa(f)* Y.l(i))); \
report("emissions_level", scenario) = (report("emissions", scenario) / sum(f, ebar(f))) * 100; \
report("steel_price", scenario) = P.l; \
report("steel_price_level", scenario) = (P.l / pbar) * 100; \
report("carbon_price", scenario) = W.l; \
report("share_carbon_costs", scenario) = sum((i,f), W.l * kappa(f) * sum(it(i, t), abar(t, f) * Y.l(i))) / (P.l * sum(i, Y.l(i))) * 100;

* Write out benchmark results
write_report("benchmark")

* POLICY SCENARIOS -------------------------------------------------------

simple.iterlim = 1000;

* Policy 1: Impose constraint that benchmark emissions have to be reduced by 20%:
chi  = 0.8;
W.lo = 0;
W.up = + Inf;
solve simple using mcp;

write_report("pol1")

* Policy 2: Impose a carbon tax:
chi = 0;
W.fx$(not chi) = 10;
solve simple using mcp;

write_report("pol2")

option report:2:1:1;
display report;

execute_unload 'output/gams/steel_results.gdx'

$exit