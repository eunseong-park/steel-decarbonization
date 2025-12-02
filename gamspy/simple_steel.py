import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from gamspy import Container, Set, Parameter, Variable, Equation, Model, Sum, Sense, Options
import sys

# Initialize Container and load GDX
# This automatically creates Set/Parameter objects for everything in the GDX
m = Container(load_from="data/generated/steel_data.gdx")

# ------------------------------------------------------------------------------
# 1. DECLARE PARAMETERS, SETS, DATA
# ------------------------------------------------------------------------------

# Retrieve symbols loaded from GDX
i = m["i"]
f = m["f"]
t = m["t"]
it = m["it"]

abar = m["abar"]
vbar = m["vbar"]
rho = m["rho"]
kappa = m["kappa"]
epsilon = m["epsilon"]
tau = m["tau"]
ylim = m["ylim"]
ybar = m["ybar"]
dbar = m["dbar"]

# Policy parameter (loaded from GDX if it exists, otherwise create)
if "chi" in m.data:
    chi = m["chi"]
else:
    chi = Parameter(m, "chi")

# Placeholders for calculated parameters (not in GDX, so we create them)
ebar = Parameter(m, "ebar", domain=[f])
rbar = Parameter(m, "rbar", domain=[i])
hbar = Parameter(m, "hbar", domain=[f])
pbar = Parameter(m, "pbar")

# We manually set chi to 0 overrides whatever was in GDX
chi.setRecords(0)

# ------------------------------------------------------------------------------
# 2. CALIBRATION (LP)
# ------------------------------------------------------------------------------

TC = Variable(m, "TC")
Y = Variable(m, "Y", domain=[i], type="Positive")

costs = Equation(m, "costs")
demand = Equation(m, "demand")

# Use t.where[it[i, t]] to correctly sum over technologies for a specific plant
costs[...] = TC == Sum(
    (i, f), Sum(t.where[it[i, t]], abar[t, f]) * (vbar[f] + tau[i, f]) * Y[i]
)
demand[...] = Sum(i, Y[i]) >= dbar

# Incorporate capacity constraints
Y.up[i] = ylim[i]

mincost = Model(
    m, "mincost", equations=[costs, demand], problem="LP", sense=Sense.MIN, objective=TC
)

mincost.solve()

# Obtain reference pricess and quantities from LP model:
pbar[...] = demand.m
ybar[...] = Y.l
hbar[...] = Sum(i, Sum(t.where[it[i, t]], abar[t, f]) * ybar[i])
rbar[...] = -1 * Y.m
ebar[...] = Sum(i, Sum(t.where[it[i, t]], abar[t, f] * kappa[f] * ybar[i]))

# ------------------------------------------------------------------------------
# 3. MCP MODEL
# ------------------------------------------------------------------------------

P = Variable(m, "P", type="Positive", description="Price of steel")
V = Variable(m, "V", domain=[f], type="Positive", description="Price of factors")
R = Variable(
    m, "R", domain=[i], type="Positive", description="Shadow price of capacity"
)
W = Variable(m, "W", type="Positive", description="Carbon price")

zpf_y = Equation(m, "zpf_y", domain=[i])
mkt_y = Equation(m, "mkt_y")
mkt_f = Equation(m, "mkt_f", domain=[f])
capacity = Equation(m, "capacity", domain=[i])
mkt_co2 = Equation(m, "mkt_co2")

# Equilibrium conditions
zpf_y[i] = (
    Sum(f, Sum(t.where[it[i, t]], abar[t, f]) * (V[f] + tau[i, f]))
    + R[i]
    + Sum(f, W * kappa[f] * Sum(t.where[it[i, t]], abar[t, f]))
    >= P
)

mkt_y[...] = Sum(i, Y[i]) >= dbar * (1 + epsilon * (P / pbar - 1))

mkt_f[f] = hbar[f] * (1 + rho[f] * (V[f] / vbar[f] - 1)) >= Sum(
    i, Sum(t.where[it[i, t]], abar[t, f]) * Y[i]
)

capacity[i] = ylim[i] >= Y[i]

mkt_co2[...] = chi * Sum(f, ebar[f]) >= Sum(
    (f, i), Sum(t.where[it[i, t]], abar[t, f] * kappa[f]) * Y[i]
)

# Relax upper bound on capacity for MCP
Y.up[i] = np.inf

# Set starting values
P.l[...] = pbar
R.l[...] = rbar
Y.l[...] = ybar
V.l[...] = vbar
W.fx[...] = 0

simple = Model(
    m,
    "simple",
    matches={zpf_y: Y, mkt_y: P, mkt_f: V, capacity: R, mkt_co2: W},
    problem="MCP",
)

# Replication Check
print("--- Starting Replication Check ---")
simple.solve(
    options=Options(iteration_limit=0, report_solution=1),
    output=sys.stdout
)


# ------------------------------------------------------------------------------
# 4. SCENARIO EXECUTION & DATA COLLECTION
# ------------------------------------------------------------------------------

temp = Parameter(m, "temp")  # Temporary parameter for calculations

results = []
def collect_results(scenario_name):
    """Helper to calculate aggregates and store in list"""
    # Calculate values using GAMS expressions evaluated at current levels
    total_prod = Sum(i, Y.l[i]).toValue()

    # Complex sum for emissions
    temp[...] = Sum(
        (f, i), Sum(t.where[it[i, t]], abar[t, f] * kappa[f]) * Y.l[i]
    )
    total_emissions = temp.toValue()

    steel_price = P.toValue()
    carbon_price = W.toValue()

    results.append(
        {
            "Scenario": scenario_name,
            "Production": total_prod,
            "Emissions": total_emissions,
            "Steel Price": steel_price,
            "Carbon Price": carbon_price,
        }
    )


# --- Reference Scenario ---
print("Running Reference...")
simple.solve(options=Options(iteration_limit=0, report_solution=1), output=sys.stdout)
collect_results("Reference")

# --- Policy 1: Cap and Trade (20% reduction) ---
print("Running Cap & Trade...")
chi[...] = 0.8
W.lo[...] = 0
W.up[...] = np.inf
simple.solve(options=Options(iteration_limit=1000))
collect_results("Cap (-20%)")

# --- Policy 2: Carbon Tax ---
print("Running Carbon Tax...")
chi[...] = 0  # Disable quantity constraint logic
W.fx[...] = 10  # Fix price
simple.solve() 
collect_results("Tax ($10/tCO2)")

# ------------------------------------------------------------------------------
# 5. PANDAS DATAFRAME & VISUALIZATION
# ------------------------------------------------------------------------------

df_results = pd.DataFrame(results)
print("\nResults DataFrame:")
print(df_results.round(2))

# Set up the plot
fig, axes = plt.subplots(1, 3, figsize=(15, 6))
fig.suptitle("Steel Industry Model Results", fontsize=16)

# Plot 1: Production
axes[0].bar(df_results["Scenario"], df_results["Production"], color="steelblue")
axes[0].set_title("Total Steel Production (Mt)")
axes[0].set_ylabel("Million Tonnes")
axes[0].grid(axis="y", linestyle="--", alpha=0.7)

# Plot 2: Emissions
axes[1].bar(df_results["Scenario"], df_results["Emissions"], color="indianred")
axes[1].set_title("Total Carbon Emissions (MtCO2)")
axes[1].set_ylabel("Mt CO2")
axes[1].grid(axis="y", linestyle="--", alpha=0.7)

# Plot 3: Prices (Grouped Bar for Steel vs Carbon)
# Using dual axis or just side-by-side. Let's do side-by-side bars.
x = np.arange(len(df_results["Scenario"]))
width = 0.35

rects1 = axes[2].bar(
    x - width / 2, df_results["Steel Price"], width, label="Steel Price (USD/t)", color="grey"
)
rects2 = axes[2].bar(
    x + width / 2,
    df_results["Carbon Price"],
    width,
    label="Carbon Price (USD/tCO2)",
    color="green",
)

axes[2].set_title("Market Prices")
axes[2].set_ylabel("Price")
axes[2].set_xticks(x)
axes[2].set_xticklabels(df_results["Scenario"])
axes[2].legend()
axes[2].grid(axis="y", linestyle="--", alpha=0.7)

plt.tight_layout(rect=[0, 0.03, 1, 0.95])
plt.show()

# Optional: Export DataFrame to CSV
df_results.to_csv("output/gamspy/simple_steel_results.csv", index=False)

# save figure
fig.savefig("output/gamspy/simple_steel_results.pdf")
