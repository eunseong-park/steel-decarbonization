using JuMP
using HiGHS       # For the LP Calibration
using PATHSolver  # For the MCP Equilibrium
using Printf
using HDF5
using DataFrames

# ==============================================================================
# 1. SETS AND DATA DEFINITION
# ==============================================================================

# Load Data from HDF5
data_path = "data/generated/steel_data.h5"

function read_h5_table(path)
    # HDF5r writes compound datasets. HDF5.jl reads them as a NamedTuple of Vectors
    # We convert that to DataFrame easily
    raw = h5read(data_path, path)
    return DataFrame(raw)
end

function read_h5_scalar(path)
    return h5read(data_path, path)[1]
end

# Sets
I = ["i$k" for k in 1:15]
F = ["iore", "coal", "scrp", "elec", "ngas"]
T_tech = ["bof", "eaf", "dri"]

# Mapping Plants (i) to Technologies (t)
df_it = read_h5_table("sets/it")
plant_tech = Dict{String,String}()
for row in eachrow(df_it)
    plant_tech[row.i] = row.t
end

# Parameters
# Note: R 'hdf5r' writes columns. We need to know the column names.
# By default R writes: t, f, value  for abar.

df_abar = read_h5_table("params/abar")
abar_data = Dict{Tuple{String,String}, Float64}()
for row in eachrow(df_abar)
    abar_data[(row.t, row.f)] = row.value
end

function get_abar(t, f)
    return get(abar_data, (t, f), 0.0)
end

df_vbar = read_h5_table("params/vbar")
vbar = Dict(row.f => row.value for row in eachrow(df_vbar))

df_rho = read_h5_table("params/rho")
rho = Dict(row.f => row.value for row in eachrow(df_rho))

df_kappa = read_h5_table("params/kappa")
kappa = Dict(row.f => row.value for row in eachrow(df_kappa))

epsilon = read_h5_scalar("scalars/epsilon")

df_tau = read_h5_table("params/tau")
tau = Dict((row.i, row.f) => row.value for row in eachrow(df_tau))

df_ylim = read_h5_table("params/ylim")
ylim = Dict(row.i => row.value for row in eachrow(df_ylim))

df_ybar = read_h5_table("params/ybar")
ybar_input = Dict(row.i => row.value for row in eachrow(df_ybar))

dbar = read_h5_scalar("scalars/dbar")

# Policy Parameter
chi = 0.0

# ==============================================================================
# 2. CALIBRATION (LP MODEL)
# ==============================================================================
println("--- Solving Calibration LP ---")

calib = Model(HiGHS.Optimizer)
set_silent(calib)

# Variables
@variable(calib, Y[i in I] >= 0)

# Objective: Minimize Total Cost
# Sum over i, f. Note: In Julia, we look up the tech 't' for plant 'i'
@objective(calib, Min,
    sum(get_abar(plant_tech[i], f) * (vbar[f] + tau[i, f]) * Y[i] for i in I, f in F)
)

# Constraints
@constraint(calib, demand_eqn, sum(Y[i] for i in I) >= dbar)

# Capacity constraints (explicitly defined to easily get shadow prices)
@constraint(calib, cap_eqn[i in I], Y[i] <= ylim[i])

optimize!(calib)

# ==============================================================================
# 3. EXTRACT REFERENCE VALUES
# ==============================================================================

if termination_status(calib) != MOI.OPTIMAL
    error("Calibration failed")
end

# Get primal values
ybar = value.(Y)

# Get dual values (Shadow Prices)
# Note: GAMS 'demand.m' is positive. 
# In JuMP Min problems, >= constraints usually have positive duals.
pbar = dual(demand_eqn)

# GAMS 'rbar' comes from Y.up constraint. 
# In JuMP, dual of <= constraint in Min problem is usually negative (cost reduction).
# We take the absolute value to match the positive price concept in GAMS.
rbar = Dict(i => abs(dual(cap_eqn[i])) for i in I)

# Calculate derived reference parameters
hbar = Dict(f => sum(get_abar(plant_tech[i], f) * ybar[i] for i in I) for f in F)
ebar = Dict(f => sum(get_abar(plant_tech[i], f) * kappa[f] * ybar[i] for i in I) for f in F)

println("Calibration complete. Reference Price (pbar): ", round(pbar, digits=2))

# ==============================================================================
# 4. MCP MODEL (Equilibrium)
# ==============================================================================

# --- Initialize Results Collection ---
results_report = DataFrame(
    Scenario=String[],
    Production=Float64[],
    Emissions=Float64[],
    SteelPrice=Float64[],
    CarbonPrice=Float64[]
)

function get_total_emissions()
    return sum(value(Y_mcp[i]) * get_abar(plant_tech[i], f) * kappa[f] for i in I, f in F)
end

function store_results!(scenario_name)
    prod_val = sum(value.(Y_mcp))
    emis_val = get_total_emissions()
    price_p = value(P)
    price_w = value(W)
    push!(results_report, (scenario_name, prod_val, emis_val, price_p, price_w))
end

println("--- Solving Equilibrium MCP ---")

mcp = Model(PATHSolver.Optimizer)
set_silent(mcp)

# VARIABLES
# ------------------------------------------------------------------------------
# In MCP, we define variables and bounds. 
@variable(mcp, P >= 0, start = pbar)
@variable(mcp, V[f in F] >= 0, start = vbar[f])
@variable(mcp, R[i in I] >= 0, start = rbar[i])
@variable(mcp, W >= 0, start = 0)
@variable(mcp, Y_mcp[i in I] >= 0, start = ybar[i]) # Renamed to Y_mcp to avoid conflict

# EQUATIONS & COMPLEMENTARITY
# ------------------------------------------------------------------------------
# Syntax: @constraint(model, F(x) ⟂ x) 
# This means F(x) >= 0, x >= 0, and F(x)*x = 0
# This matches GAMS syntax: Eq .. LHS =g= RHS  matches  Eq ⟂ Var

# 1. Zero Profit Condition: Costs >= Price ⟂ Output (Y)
@constraint(mcp, zpf_y[i in I],
    (
        sum(get_abar(plant_tech[i], f) * (V[f] + tau[i, f]) for f in F) +
        R[i] +
        sum(W * kappa[f] * get_abar(plant_tech[i], f) for f in F)
    ) - P ⟂ Y_mcp[i]
)

# 2. Market Clearance Steel: Supply >= Demand ⟂ Price (P)
# GAMS: sum(Y) =g= dbar * (1 + epsilon * (P/pbar - 1))
@constraint(mcp, mkt_y,
    sum(Y_mcp[i] for i in I) - (dbar * (1 + epsilon * (P / pbar - 1))) ⟂ P
)

# 3. Market Clearance Factors: Supply >= Demand ⟂ Factor Price (V)
# GAMS: hbar * (SupplyFunc) =g= Demand
@constraint(mcp, mkt_f[f in F],
    (hbar[f] * (1 + rho[f] * (V[f] / vbar[f] - 1))) -
    sum(get_abar(plant_tech[i], f) * Y_mcp[i] for i in I) ⟂ V[f]
)

# 4. Capacity Constraint: Limit >= Output ⟂ Rent (R)
# GAMS: ylim =g= Y
@constraint(mcp, capacity[i in I],
    ylim[i] - Y_mcp[i] ⟂ R[i]
)

# 5. Carbon Market: Target >= Emissions ⟂ Carbon Price (W)
# Note: If chi = 0, we fix W = 0 (similar to GAMS $ conditions)
if chi == 0
    fix(W, 0; force=true)
else
    @constraint(mcp, mkt_co2,
        (chi * sum(ebar[f] for f in F)) -
        sum(get_abar(plant_tech[i], f) * kappa[f] * Y_mcp[i] for f in F, i in I) ⟂ W
    )
end

# ==============================================================================
# 5. SOLVE AND CHECK
# ==============================================================================

optimize!(mcp)

# Check convergence (GAMS abort check)
# In PATH/JuMP, we check termination status
if termination_status(mcp) == MOI.LOCALLY_SOLVED
    println("Model Solved Successfully.")
    println("Objective Value (Complementarity Gap): ", objective_value(mcp))

    # Display some results
    println("\n--- Results ---")
    println("Steel Price (P): ", value(P))
    println("Total Output:    ", sum(value.(Y_mcp)))
    println("Reference Output:", dbar)
else
    println("Model did not converge. Status: ", termination_status(mcp))
end

# Store Reference Results
if termination_status(mcp) == MOI.LOCALLY_SOLVED
    store_results!("Reference")
end


# ==============================================================================
# 6. EXPORT RESULTS TO CSV
# ==============================================================================

using DataFrames
using CSV

println("--- Exporting Results to CSV ---")

# ---------------------------------------------------------
# 6.1. Export Plant-Specific Results (Set i)
# ---------------------------------------------------------
# We combine Plant ID, Technology, Output (Y), and Rent (R)
df_plants = DataFrame(
    Plant=I,
    Technology=[plant_tech[i] for i in I],
    Output_Y=[value(Y_mcp[i]) for i in I],
    Capacity_R=[value(R[i]) for i in I]
)

CSV.write("output/julia/results_plants.csv", df_plants)
println("Saved: results_plants.csv")

# ---------------------------------------------------------
# 6.2. Export Factor Market Results (Set f)
# ---------------------------------------------------------
# We combine Factor Name and Factor Price (V)
df_factors = DataFrame(
    Factor=F,
    Price_V=[value(V[f]) for f in F]
)

CSV.write("output/julia/results_factors.csv", df_factors)
println("Saved: results_factors.csv")

# ---------------------------------------------------------
# 6.3. Export Scalar Results (Prices and Totals)
# ---------------------------------------------------------
# Single values like Steel Price and Carbon Price
df_scalars = DataFrame(
    Metric=["Steel Price P", "Carbon Price W", "Total Output", "Total Emissions"],
    Value=[
        value(P),
        value(W),
        sum(value.(Y_mcp)),
        # Calculate total emissions for reporting
        sum(value(Y_mcp[i]) * get_abar(plant_tech[i], f) * kappa[f] for i in I, f in F)
    ]
)

CSV.write("output/julia/results_scalars.csv", df_scalars)
println("Saved: results_scalars.csv")


# ==============================================================================
# 7. POLICY SCENARIOS
# ==============================================================================

# ------------------------------------------------------------------------------
# SCENARIO 1: Quantity Constraint (Cap & Trade)
# Reduce emissions by 20% (chi = 0.8)
# ------------------------------------------------------------------------------
println("\n--- Running Scenario 1: Cap (chi = 0.8) ---")

# 1. Clean up W: Unfix it so it can move freely
if is_fixed(W)
    unfix(W)
    set_lower_bound(W, 0.0)
end

# 2. Safely delete the old constraint if it exists
# We use `constraint_by_name` to find it by string "mkt_co2"
# We use `unregister` so we can reuse the name "mkt_co2" in the next step without warning
existing_con = constraint_by_name(mcp, "mkt_co2")
if existing_con !== nothing
    delete(mcp, existing_con)
    unregister(mcp, :mkt_co2)
end

# 3. Define the Cap Constraint
chi_pol1 = 0.8
target_emissions = chi_pol1 * sum(values(ebar))

@constraint(mcp, mkt_co2,
    (target_emissions - sum(get_abar(plant_tech[i], f) * kappa[f] * Y_mcp[i] for f in F, i in I)) ⟂ W
)

# 4. Solve
optimize!(mcp)

if termination_status(mcp) == MOI.LOCALLY_SOLVED
    store_results!("pol1")
else
    println("Scenario 1 failed to converge.")
end

# ------------------------------------------------------------------------------
# SCENARIO 2: Carbon Tax
# Fixed Carbon Price (W = 10), No Quantity Cap
# ------------------------------------------------------------------------------
println("\n--- Running Scenario 2: Tax (W = 10.0) ---")

# 1. Fix the Carbon Price
fix(W, 10.0; force=true)

# 2. Remove the Quantity Constraint
# Again, we look it up by name to safely delete it
existing_con = constraint_by_name(mcp, "mkt_co2")
if existing_con !== nothing
    delete(mcp, existing_con)
    unregister(mcp, :mkt_co2)
end

# 3. Solve
optimize!(mcp)

if termination_status(mcp) == MOI.LOCALLY_SOLVED
    store_results!("pol2")
else
    println("Scenario 2 failed to converge.")
end

# ------------------------------------------------------------------------------
# EXPORT
# ------------------------------------------------------------------------------
println("\n--- Final Policy Report ---")
println(results_report)

CSV.write("output/julia/results_policy_scenarios.csv", results_report)
println("Results saved to 'results_policy_scenarios.csv'")