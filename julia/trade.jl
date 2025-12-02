using JuMP
using PATHSolver
using DataFrames
using CSV
using Printf

# ==============================================================================
# 1. SETS AND PARAMETERS
# ==============================================================================

R = ["A", "B"]

# Initial Data
ref_YM_data = Dict(
    ("A", "A") => 800.0, ("A", "B") => 200.0,
    ("B", "A") => 400.0, ("B", "B") => 1800.0
)

tcost_data = Dict(
    ("A", "A") => 100.0, ("A", "B") => 60.0,
    ("B", "A") => 90.0,  ("B", "B") => 0.0
)

ref_P_data = Dict("A" => 190.0, "B" => 220.0)

epsilon = -1.0

ref_YM(r, rr) = ref_YM_data[(r, rr)]
tcost(r, rr) = tcost_data[(r, rr)]
ref_P(r) = ref_P_data[r]

# Calculated Benchmark Parameters
ref_PM = Dict{Tuple{String,String}, Float64}()
ref_YA = Dict{String, Float64}()
ref_PA = Dict{String, Float64}()
sha_PM = Dict{Tuple{String,String}, Float64}()

function calc_benchmarks!()
    for r in R, rr in R
        ref_PM[(rr, r)] = ref_P(rr) + tcost(rr, r)
    end

    for r in R
        ref_YA[r] = sum(ref_YM(rr, r) for rr in R)
        total_val = sum(ref_YM(rr, r) * ref_PM[(rr, r)] for rr in R)
        ref_PA[r] = total_val / ref_YA[r]
    end

    for r in R, rr in R
        val = ref_YM(rr, r) * ref_PM[(rr, r)]
        total_val_r = sum(ref_YM(src, r) * ref_PM[(src, r)] for src in R)
        sha_PM[(rr, r)] = val / total_val_r
    end
end

calc_benchmarks!()

# ==============================================================================
# 2. MODEL DEFINITION
# ==============================================================================

results_df = DataFrame(
    Scenario = String[],
    Variable = String[],
    Region_From = String[],
    Region_To = Union{String, Missing}[],
    Value = Float64[]
)

function solve_trade_model(scenario_name)
    model = Model(PATHSolver.Optimizer)
    set_silent(model)

    @variable(model, YM[r in R, rr in R] >= 0, start = ref_YM(r, rr))
    @variable(model, PM[r in R, rr in R] >= 0, start = ref_PM[(r, rr)])
    @variable(model, YA[r in R] >= 0, start = ref_YA[r])
    @variable(model, PA[r in R] >= 0, start = ref_PA[r])

    Expression_C_PM(r) = sum(sha_PM[(src, r)] * (PM[src, r] / ref_PM[(src, r)]) for src in R)

    @constraint(model, mkt_PM[src in R, dst in R],
        YM[src, dst] - ref_YM(src, dst) * (1 + epsilon * (Expression_C_PM(dst) - 1)) ⟂ PM[src, dst]
    )

    @constraint(model, zpf_YM[src in R, dst in R],
        (ref_P(src) + tcost(src, dst)) - PM[src, dst] ⟂ YM[src, dst]
    )

    @constraint(model, mkt_PA[r in R],
        YA[r] - ref_YA[r] * (1 + epsilon * (PA[r] / ref_PA[r] - 1)) ⟂ PA[r]
    )

    @constraint(model, zpf_YA[r in R],
        (ref_PA[r] * Expression_C_PM(r)) - PA[r] ⟂ YA[r]
    )

    optimize!(model)

    if termination_status(model) == MOI.LOCALLY_SOLVED
        println("Scenario: $scenario_name | Solved.")
        
        # Collect Results
        # PA
        for r in R
            push!(results_df, (scenario_name, "PA", r, missing, value(PA[r])))
        end
        # YA
        for r in R
            push!(results_df, (scenario_name, "YA", r, missing, value(YA[r])))
        end
        # YM and PM
        for r in R, rr in R
            push!(results_df, (scenario_name, "YM", r, rr, value(YM[r, rr])))
            push!(results_df, (scenario_name, "PM", r, rr, value(PM[r, rr])))
        end
    else
        println("Scenario: $scenario_name | Failed.")
    end
end

# ==============================================================================
# 3. RUN SCENARIOS
# ==============================================================================

println("--- SCENARIO: Benchmark ---")
solve_trade_model("Benchmark")

println("\n--- SCENARIO: Double Transport Cost B->A ---")
tcost_data[("B", "A")] = 180.0
solve_trade_model("Double_TC_BA")

# ==============================================================================
# 4. EXPORT RESULTS
# ==============================================================================

output_dir = "output/julia"
if !isdir(output_dir)
    mkpath(output_dir)
end

output_path = joinpath(output_dir, "trade_results.csv")
CSV.write(output_path, results_df)
println("\nResults saved to: $output_path")