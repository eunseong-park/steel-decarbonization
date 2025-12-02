import pandas as pd
import matplotlib.pyplot as plt
import os

# ------------------------------------------------------------------------------
# 5. PANDAS DATAFRAME & VISUALIZATION
# ------------------------------------------------------------------------------

results_path = "output/gamspy/simple_steel_results.csv"

if not os.path.exists(results_path):
    print(f"Results file not found: {results_path}. Please run 'python gamspy/simple_steel.py' first.")
    exit(1)

df_results = pd.read_csv(results_path)
print("\nResults DataFrame:")
print(df_results.round(2))

# Set up the plot
fig, axes = plt.subplots(1, 3, figsize=(15, 6))
fig.suptitle("Steel Industry Model Results (GAMSPy)", fontsize=16)

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
fig.savefig("output/gamspy/simple_steel_results.pdf")
print("Plots saved to output/gamspy/simple_steel_results.pdf")
