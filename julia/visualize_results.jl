using DataFrames
using CSV
using StatsPlots
using Printf
using Measures

# Load Results
results_path = "output/julia/results_policy_scenarios.csv"
if !isfile(results_path)
    error("Results file not found: $results_path. Please run simple_steel.jl first.")
end

df_results = DataFrame(CSV.File(results_path))

println("Loaded results:")
println(df_results)

# ------------------------------------------------------------------------------
# Plot 1: Total Steel Production
# ------------------------------------------------------------------------------
p1 = @df df_results bar(
    :Scenario, 
    :Production, 
    title = "Total Steel Production", 
    ylabel = "Million Tonnes",
    legend = false,
    color = :steelblue
)

# ------------------------------------------------------------------------------
# Plot 2: Total Carbon Emissions
# ------------------------------------------------------------------------------
p2 = @df df_results bar(
    :Scenario, 
    :Emissions, 
    title = "Total Carbon Emissions", 
    ylabel = "Mt CO2",
    legend = false,
    color = :indianred
)

# ------------------------------------------------------------------------------
# Plot 3: Market Prices (Grouped Bar)
# ------------------------------------------------------------------------------
# StatsPlots grouped bar requires "Long" format or matrix.
# Let's reshape manually for clarity or use matrix form.
scenarios = df_results.Scenario
prices = Matrix(df_results[:, [:SteelPrice, :CarbonPrice]])

p3 = groupedbar(
    prices,
    xticks = (1:nrow(df_results), scenarios),
    title = "Market Prices",
    ylabel = "Price",
    bar_position = :dodge,
    bar_width = 0.7,
    labels = ["Steel Price" "Carbon Price"]
)

# ------------------------------------------------------------------------------
# Combine and Save
# ------------------------------------------------------------------------------
# Use @layout macro for explicit layout definition, which often satisfies linters better
l = @layout [a b c]
final_plot = plot(p1, p2, p3, layout = l, size = (1200, 500), margin = 5mm)

output_dir = "output/julia"
if !isdir(output_dir)
    mkpath(output_dir)
end

output_file = joinpath(output_dir, "julia_plots.pdf")
savefig(final_plot, output_file)

println("Plots saved to: $output_file")
