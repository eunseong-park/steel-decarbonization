import gamspy as gp
import pandas as pd
import sys

m = gp.Container()

r = gp.Set(container=m, name="r", description="Regions")
r.setRecords(['A', 'B'])
rr = m.addAlias(name="rr", alias_with=r)
rrr = m.addAlias(name="rrr", alias_with=r)

quantities = pd.DataFrame(
    [
        ["A", "A",  800],
        ["A", "B",  200],
        ["B", "A",  400],
        ["B", "B", 1800]
    ],
    columns=["from", "to", "quantity"]
).set_index(["from", "to"])

ref_YM = gp.Parameter(
    container=m,
    name="ref_YM",
    domain=[r,rr],
    description="Benchmark trade quantity (kt)",
    records=quantities.reset_index(),
)

costs = pd.DataFrame(
    [
        ["A", "A", 100],
        ["A", "B",  60],
        ["B", "A",  90],
        ["B", "B",   0]
    ],
    columns=["from", "to", "costs"]
).set_index(["from", "to"])

tcost = gp.Parameter(
    container=m,
    name="tcost",
    domain=[r,rr],
    description="Transport cost (USD)",
    records=costs.reset_index(),
)

epsilon = gp.Parameter(m, "epsilon", records=-1)

ref_PM = gp.Parameter(
    container=m,
    name="ref_PM",
    domain=[r,rr],
    description="Benchmark import price (USD)"
)
ref_CM = gp.Parameter(
    container=m,
    name="ref_CM",
    domain=r,
    description="Benchmark total import cost"
)
sha_PM = gp.Parameter(
    container=m,
    name="sha_PM",
    domain=[r,rr],
    description="Benchmark share of PM"
)
ref_YA = gp.Parameter(
    container=m,
    name="ref_YA",
    domain=r,
    description="Benchmark final demand (kt)"
)
ref_PA = gp.Parameter(
    container=m,
    name="ref_PA",
    domain=r,
    description="Benchmark final price (USD)"
)
ref_P = gp.Parameter(
    container=m,
    name="ref_P",
    domain=r,
    records=[("A", 190), ("B", 220)],
    description="Benchmark producer price (USD)"
)

# Benchmark import price
ref_PM[r,rr] = ref_P[r] + tcost[r,rr]

# Benchmark demand is sum for each column
ref_YA[r] = gp.Sum(rr, ref_YM[rr,r])

# Benchmark final price
ref_PA[r] = gp.Sum(rr, ref_YM[rr,r] * ref_PM[rr,r]) / ref_YA[r]

# Benchmark total import cost
ref_CM[r] = gp.Sum(rr, ref_YM[rr,r] * ref_PM[rr,r])

# Benchmark share
sha_PM[rr,r] = (ref_YM[rr,r] * ref_PM[rr,r]) / ref_CM[r]

# macro for cost function
def C_PM(r):
    return gp.Sum(rrr, sha_PM[rrr,r] * (PM[rrr,r] / ref_PM[rrr,r]))

# Model definition ------------------------------------------------
# Variables
YM = gp.Variable(m, type="positive", domain=[r,rr], description="Trade quantity (kt)")
PM = gp.Variable(m, type="positive", domain=[r,rr], description="Import price (USD)")
PA = gp.Variable(m, type="positive", domain=r, description="Final price (USD)")
YA = gp.Variable(m, type="positive", domain=r, description="Final demand (kt)")

# Equations
zpf_YM = gp.Equation(
    m,
    name="zpf_YM",
    domain=[r,rr],
    description="Zero profit condition: import",
    definition=YM[r,rr] >= ref_YM[r,rr] * (1 + epsilon * ((C_PM(rr) - 1)))
)
mkt_PM = gp.Equation(
    m,
    name="mkt_PM",
    domain=[r,rr],
    description="Market clearing: import",
    definition=ref_P[r] + tcost[r,rr] >= PM[r,rr]
)
zpf_YA = gp.Equation(
    m,
    name="zpf_YA",
    domain=r,
    description="Zero profit condition: final good",
    definition=YA[r] >= ref_YA[r] * (1 + epsilon * (PA[r] / ref_PA[r] - 1))
)
mkt_PA = gp.Equation(
    m,
    name="mkt_PA",
    domain=r,
    description="Market clearing condition: final good",
    definition=ref_PA[r] * C_PM(r) >= PA[r]
)
trade = gp.Model(
    m,
    problem=gp.Problem.MCP,
    matches={zpf_YM: YM, mkt_PM: PM, zpf_YA: YA, mkt_PA: PA}
)

import gamspy as gp
import pandas as pd
import sys
import os

m = gp.Container()

r = gp.Set(container=m, name="r", description="Regions")
r.setRecords(['A', 'B'])
rr = m.addAlias(name="rr", alias_with=r)
rrr = m.addAlias(name="rrr", alias_with=r)

quantities = pd.DataFrame(
    [
        ["A", "A",  800],
        ["A", "B",  200],
        ["B", "A",  400],
        ["B", "B", 1800]
    ],
    columns=["from", "to", "quantity"]
).set_index(["from", "to"])

ref_YM = gp.Parameter(
    container=m,
    name="ref_YM",
    domain=[r,rr],
    description="Benchmark trade quantity (kt)",
    records=quantities.reset_index(),
)

costs = pd.DataFrame(
    [
        ["A", "A", 100],
        ["A", "B",  60],
        ["B", "A",  90],
        ["B", "B",   0]
    ],
    columns=["from", "to", "costs"]
).set_index(["from", "to"])

tcost = gp.Parameter(
    container=m,
    name="tcost",
    domain=[r,rr],
    description="Transport cost (USD)",
    records=costs.reset_index(),
)

epsilon = gp.Parameter(m, "epsilon", records=-1)

ref_PM = gp.Parameter(
    container=m,
    name="ref_PM",
    domain=[r,rr],
    description="Benchmark import price (USD)"
)
ref_CM = gp.Parameter(
    container=m,
    name="ref_CM",
    domain=r,
    description="Benchmark total import cost"
)
sha_PM = gp.Parameter(
    container=m,
    name="sha_PM",
    domain=[r,rr],
    description="Benchmark share of PM"
)
ref_YA = gp.Parameter(
    container=m,
    name="ref_YA",
    domain=r,
    description="Benchmark final demand (kt)"
)
ref_PA = gp.Parameter(
    container=m,
    name="ref_PA",
    domain=r,
    description="Benchmark final price (USD)"
)
ref_P = gp.Parameter(
    container=m,
    name="ref_P",
    domain=r,
    records=[("A", 190), ("B", 220)],
    description="Benchmark producer price (USD)"
)

# Benchmark import price
ref_PM[r,rr] = ref_P[r] + tcost[r,rr]

# Benchmark demand is sum for each column
ref_YA[r] = gp.Sum(rr, ref_YM[rr,r])

# Benchmark final price
ref_PA[r] = gp.Sum(rr, ref_YM[rr,r] * ref_PM[rr,r]) / ref_YA[r]

# Benchmark total import cost
ref_CM[r] = gp.Sum(rr, ref_YM[rr,r] * ref_PM[rr,r])

# Benchmark share
sha_PM[rr,r] = (ref_YM[rr,r] * ref_PM[rr,r]) / ref_CM[r]

# macro for cost function
def C_PM(r):
    return gp.Sum(rrr, sha_PM[rrr,r] * (PM[rrr,r] / ref_PM[rrr,r]))

# Model definition ------------------------------------------------
# Variables
YM = gp.Variable(m, type="positive", domain=[r,rr], description="Trade quantity (kt)")
PM = gp.Variable(m, type="positive", domain=[r,rr], description="Import price (USD)")
PA = gp.Variable(m, type="positive", domain=r, description="Final price (USD)")
YA = gp.Variable(m, type="positive", domain=r, description="Final demand (kt)")

# Equations
zpf_YM = gp.Equation(
    m,
    name="zpf_YM",
    domain=[r,rr],
    description="Zero profit condition: import",
    definition=YM[r,rr] >= ref_YM[r,rr] * (1 + epsilon * ((C_PM(rr) - 1)))
)
mkt_PM = gp.Equation(
    m,
    name="mkt_PM",
    domain=[r,rr],
    description="Market clearing: import",
    definition=ref_P[r] + tcost[r,rr] >= PM[r,rr]
)
zpf_YA = gp.Equation(
    m,
    name="zpf_YA",
    domain=r,
    description="Zero profit condition: final good",
    definition=YA[r] >= ref_YA[r] * (1 + epsilon * (PA[r] / ref_PA[r] - 1))
)
mkt_PA = gp.Equation(
    m,
    name="mkt_PA",
    domain=r,
    description="Market clearing condition: final good",
    definition=ref_PA[r] * C_PM(r) >= PA[r]
)
trade = gp.Model(
    m,
    problem=gp.Problem.MCP,
    matches={zpf_YM: YM, mkt_PM: PM, zpf_YA: YA, mkt_PA: PA}
)

# initial values
YM.l[r,rr] = ref_YM[r,rr]
PM.l[r,rr] = ref_PM[r,rr]
PA.l[r] = ref_PA[r]
YA.l[r] = ref_YA[r]

# Data collection
results = []

def collect_results(scenario_name):
    # Extract levels (.l) or values from variables
    # GAMSPy variables records are dataframes with columns for sets and 'level', 'marginal', etc.
    # We want 'level'.
    
    # PA(r)
    df_pa = PA.records[['r', 'level']]
    for _, row in df_pa.iterrows():
        results.append({
            "Scenario": scenario_name,
            "Variable": "PA",
            "Region_From": row['r'],
            "Region_To": None,
            "Value": row['level']
        })
        
    # YA(r)
    df_ya = YA.records[['r', 'level']]
    for _, row in df_ya.iterrows():
        results.append({
            "Scenario": scenario_name,
            "Variable": "YA",
            "Region_From": row['r'],
            "Region_To": None,
            "Value": row['level']
        })

    # YM(r, rr)
    df_ym = YM.records[['r', 'rr', 'level']]
    for _, row in df_ym.iterrows():
        results.append({
            "Scenario": scenario_name,
            "Variable": "YM",
            "Region_From": row['r'],
            "Region_To": row['rr'],
            "Value": row['level']
        })

    # PM(r, rr)
    df_pm = PM.records[['r', 'rr', 'level']]
    for _, row in df_pm.iterrows():
        results.append({
            "Scenario": scenario_name,
            "Variable": "PM",
            "Region_From": row['r'],
            "Region_To": row['rr'],
            "Value": row['level']
        })

# Solve Benchmark
print("--- Solving Benchmark ---")
trade.solve(options=gp.Options(iteration_limit=0, report_solution=1), output=sys.stdout)
collect_results("Benchmark")

# Solve Policy
print("--- Solving Policy (Double Transport Cost) ---")
tcost["B","A"] = tcost["B","A"]*2
trade.solve(options=gp.Options(iteration_limit=100, report_solution=1), output=sys.stdout)
collect_results("Double_TC_BA")

# Export
output_dir = "output/python"
if not os.path.exists(output_dir):
    os.makedirs(output_dir)

df_res = pd.DataFrame(results)
out_path = os.path.join(output_dir, "trade_results_gamspy.csv")
df_res.to_csv(out_path, index=False)
print(f"\nResults saved to {out_path}")