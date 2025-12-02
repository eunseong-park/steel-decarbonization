import pandas as pd
import matplotlib.pyplot as plt
import os
import sys

# ------------------------------------------------------------------------------
# 5. PANDAS DATAFRAME & VISUALIZATION
# ------------------------------------------------------------------------------

output_dir = "output/python"
path_gamspy = os.path.join(output_dir, "simple_steel_results_gamspy.csv")
path_pyomo = os.path.join(output_dir, "simple_steel_results_pyomo.csv")

results_path = None
source = None

# Check for command line argument
target_source = None
if len(sys.argv) > 1:
    target_source = sys.argv[1].lower()

if target_source == 'gamspy':
    if os.path.exists(path_gamspy):
        results_path = path_gamspy
        source = "GAMSPy"
        print(f"Found requested GAMSPy results: {results_path}")
    else:
        print(f"Error: Requested GAMSPy results not found at {path_gamspy}")
        exit(1)
elif target_source == 'pyomo':
    if os.path.exists(path_pyomo):
        results_path = path_pyomo
        source = "Pyomo"
        print(f"Found requested Pyomo results: {results_path}")
    else:
        print(f"Error: Requested Pyomo results not found at {path_pyomo}")
        exit(1)
else:
    # Default logic: Prefer GAMSPy, then Pyomo
    if os.path.exists(path_gamspy):
        results_path = path_gamspy
        source = "GAMSPy"
        print(f"Found GAMSPy results: {results_path}")
    elif os.path.exists(path_pyomo):
        results_path = path_pyomo
        source = "Pyomo"
        print(f"Found Pyomo results: {results_path}")
    else:
        print(f"No results file found in {output_dir}. Please run 'python python/simple_steel_gamspy.py' or 'python python/simple_steel_pyomo.py' first.")
        exit(1)

df_results = pd.read_csv(results_path)
print("\nResults DataFrame:")
print(df_results.round(2))

# Set up the plot
fig, axes = plt.subplots(1, 3, figsize=(15, 6))
fig.suptitle(f"Steel Industry Model Results ({source})", fontsize=16)

# Plot 1: Production
axes[0].bar(df_results["Scenario"], df_results["Production"], color="steelblue")
axes[0].set_title("Total Steel Production")
axes[0].set_ylabel("Million Tonnes")
axes[0].grid(axis="y", linestyle="--", alpha=0.7)

# Plot 2: Emissions
axes[1].bar(df_results["Scenario"], df_results["Emissions"], color="indianred")
axes[1].set_title("Total Carbon Emissions")
axes[1].set_ylabel("Mt CO2")
axes[1].grid(axis="y", linestyle="--", alpha=0.7)

# Plot 3: Prices (Grouped Bar for Steel vs Carbon)
# Using dual axis or just side-by-side. Let's do side-by-side bars.
x = range(len(df_results["Scenario"]))
width = 0.35

rects1 = axes[2].bar(
    [val - width / 2 for val in x], df_results["Steel Price"], width, label="Steel Price", color="grey"
)
rects2 = axes[2].bar(
    [val + width / 2 for val in x],
    df_results["Carbon Price"],
    width,
    label="Carbon Price",
    color="green",
)

axes[2].set_title("Market Prices")
axes[2].set_ylabel("Price")
axes[2].set_xticks(list(x))
axes[2].set_xticklabels(df_results["Scenario"])
axes[2].legend()
axes[2].grid(axis="y", linestyle="--", alpha=0.7)

plt.tight_layout(rect=[0, 0.03, 1, 0.95])
plt.show()

# save figure
output_pdf = os.path.join(output_dir, f"simple_steel_results_{source.lower()}.pdf")
fig.savefig(output_pdf)
print(f"Plots saved to {output_pdf}")
