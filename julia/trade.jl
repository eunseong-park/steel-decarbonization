using JuMP
using PATHSolver
using DataFrames
using Printf

# ==============================================================================
# 1. SETS AND PARAMETERS
# ==============================================================================

R = ["A", "B"]

# Initial Data
# ref_YM(r, rr): Benchmark trade quantity from r (supply) to rr (demand)
ref_YM_data = Dict(
    ("A", "A") => 800.0, ("A", "B") => 200.0,
    ("B", "A") => 400.0, ("B", "B") => 1800.0
)

# tcost(r, rr): Transport cost from r to rr
tcost_data = Dict(
    ("A", "A") => 100.0, ("A", "B") => 60.0,
    ("B", "A") => 90.0,  ("B", "B") => 0.0
)

# ref_P(r): Benchmark producer price
ref_P_data = Dict("A" => 190.0, "B" => 220.0)

epsilon = -1.0

# Helper accessors
ref_YM(r, rr) = ref_YM_data[(r, rr)]
tcost(r, rr) = tcost_data[(r, rr)]
ref_P(r) = ref_P_data[r]

# Calculated Benchmark Parameters
ref_PM = Dict{Tuple{String,String}, Float64}()
ref_YA = Dict{String, Float64}()
ref_PA = Dict{String, Float64}()
sha_PM = Dict{Tuple{String,String}, Float64}()

function calc_benchmarks!()
    # ref_PM(rr, r) = ref_P(rr) + tcost(rr, r)
    # Note: GAMS indices are (rr, r) meaning from rr to r?
    # GAMS: ref_PM(rr,r) = ref_P(rr) + tcost(rr,r);
    # GAMS: YM(r,rr) Import quantity from r to rr.
    # Let's stick to From -> To convention. 
    # In GAMS code: YM(r,rr) is from r to rr.
    # zpf_YM(rr,r): ref_P(rr) + tcost(rr,r) =g= PM(rr,r)
    # This implies PM(rr,r) is price of goods FROM rr TO r.
    
    for r in R, rr in R
        # Price of goods produced in rr and sold in r
        ref_PM[(rr, r)] = ref_P(rr) + tcost(rr, r)
    end

    for r in R
        # Total demand in r (sum of imports from all rr)
        ref_YA[r] = sum(ref_YM(rr, r) for rr in R)
        
        # Weighted average price
        total_val = sum(ref_YM(rr, r) * ref_PM[(rr, r)] for rr in R)
        ref_PA[r] = total_val / ref_YA[r]
    end

    for r in R, rr in R
        # Share of value
        val = ref_YM(rr, r) * ref_PM[(rr, r)]
        total_val_r = sum(ref_YM(src, r) * ref_PM[(src, r)] for src in R)
        sha_PM[(rr, r)] = val / total_val_r
    end
end

calc_benchmarks!()

# ==============================================================================
# 2. MODEL DEFINITION
# ==============================================================================

function solve_trade_model(scenario_name)
    # Re-calculate benchmarks if tcost changed? 
    # GAMS keeps ref_* fixed usually, but let's check usage.
    # C_PM(r) uses ref_PM.
    # Logic: ref_* parameters are FIXED at initial calibration. 
    # Changes in tcost affect the equilibrium conditions, not the reference params.
    
    model = Model(PATHSolver.Optimizer)
    set_silent(model)

    # Variables
    # YM(r, rr): Import FROM r TO rr
    @variable(model, YM[r in R, rr in R] >= 0, start = ref_YM(r, rr))
    
    # PM(r, rr): Price of import FROM r TO rr
    @variable(model, PM[r in R, rr in R] >= 0, start = ref_PM[(r, rr)])
    
    # YA(r): Final demand in r
    @variable(model, YA[r in R] >= 0, start = ref_YA[r])
    
    # PA(r): Final price in r
    @variable(model, PA[r in R] >= 0, start = ref_PA[r])

    # Macros / Expressions
    # Cost function C_PM(r)
    # sum(rr.local, sha_PM(rr,r) * (PM(rr,r) / ref_PM(rr,r)))
    # This represents the price index of the composite good in region r
    Expression_C_PM(r) = sum(sha_PM[(src, r)] * (PM[src, r] / ref_PM[(src, r)]) for src in R)

    # Equations ----------------------------------------------------------------

    # mkt_PM(rr, r): Market clearing for imports (Supply = Demand)
    # Note: GAMS indices (rr,r). 
    # GAMS: YM(rr,r) =g= ref_YM(rr,r) * (1 + epsilon * (C_PM(r) - 1));
    # Here YM(rr,r) is the demand function derived from CES/Cobb-Douglas linearization?
    # Or simply linear demand.
    # Equation matches PM(rr,r).
    @constraint(model, mkt_PM[src in R, dst in R],
        YM[src, dst] - ref_YM(src, dst) * (1 + epsilon * (Expression_C_PM(dst) - 1)) ⟂ PM[src, dst]
    )

    # zpf_YM(rr, r): Zero Profit for trade
    # GAMS: ref_P(rr) + tcost(rr,r) =g= PM(rr,r)
    # Unit cost of getting good from rr to r vs Price in r
    # Matches YM(rr,r)
    @constraint(model, zpf_YM[src in R, dst in R],
        (ref_P(src) + tcost(src, dst)) - PM[src, dst] ⟂ YM[src, dst]
    )

    # mkt_PA(r): Market clearing for Final Demand
    # GAMS: YA(r) =g= ref_YA(r) * (1 + epsilon * (PA(r) / ref_PA(r) - 1))
    # Matches PA(r)
    @constraint(model, mkt_PA[r in R],
        YA[r] - ref_YA[r] * (1 + epsilon * (PA[r] / ref_PA[r] - 1)) ⟂ PA[r]
    )

    # zpf_YA(r): Zero Profit Armington
    # GAMS: ref_PA(r) * C_PM(r) =g= PA(r)
    # Unit cost of composite good vs Price
    # Matches YA(r)
    @constraint(model, zpf_YA[r in R],
        (ref_PA[r] * Expression_C_PM(r)) - PA[r] ⟂ YA[r]
    )

    optimize!(model)

    if termination_status(model) == MOI.LOCALLY_SOLVED
        println("Scenario: $scenario_name | Solved.")
        # Return results
        return (value.(YM), value.(YA), value.(PA))
    else
        println("Scenario: $scenario_name | Failed.")
        return nothing
    end
end

# ==============================================================================
# 3. RUN SCENARIOS
# ==============================================================================

println("---" * " SCENARIO: Benchmark ---")
# No changes to tcost
res_bench = solve_trade_model("Benchmark")

println("\n---" * " SCENARIO: Policy 1 (Double Transport Cost B->A) ---")
# tcost("B","A") = tcost("B","A") * 2
# GAMS: tcost("B","A") = 90 * 2 = 180
tcost_data[("B", "A")] = 180.0
res_pol1 = solve_trade_model("Policy 1")

println("\n---" * " SCENARIO: Policy 2 (Zero Transport Cost) ---")
# tcost(r,rr) = 0
for k in keys(tcost_data)
    tcost_data[k] = 0.0
end
res_pol2 = solve_trade_model("Policy 2")

# ==============================================================================
# 4. DISPLAY RESULTS
# ==============================================================================

if res_bench !== nothing && res_pol1 !== nothing && res_pol2 !== nothing
    println("\n=== RESULTS COMPARISON ===")
    
    # Helper to print matrix
    function print_res(name, r_b, r_p1, r_p2)
        println("\nVariable: $name")
        println("Region  Benchmark    Policy 1    Policy 2")
        println("-----------------------------------------")
        if ndims(r_b) == 2
            # r_b is a DenseAxisArray 2D
            for src in R, dst in R
                v_b = r_b[src, dst]
                v_p1 = r_p1[src, dst]
                v_p2 = r_p2[src, dst]
                @printf("%s->%s    %8.2f    %8.2f    %8.2f\n", src, dst, v_b, v_p1, v_p2)
            end
        else
            # 1D array
            for r in R
                v_b = r_b[r]
                v_p1 = r_p1[r]
                v_p2 = r_p2[r]
                @printf("%s       %8.2f    %8.2f    %8.2f\n", r, v_b, v_p1, v_p2)
            end
        end
    end

    print_res("YM (Trade)", res_bench[1], res_pol1[1], res_pol2[1])
    print_res("YA (Final Demand)", res_bench[2], res_pol1[2], res_pol2[2])
    print_res("PA (Final Price)", res_bench[3], res_pol1[3], res_pol2[3])
end
