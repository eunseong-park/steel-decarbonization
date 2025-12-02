# R/visualize_results.R

if (!require("pacman")) install.packages("pacman")
pacman::p_load(gamstransfer, data.table, ggplot2)


# 1. Load Results from GDX -----------------------------------------------

# Path to the GAMS result GDX
gdx_path <- "output/gams/steel_results.gdx"

if (!file.exists(gdx_path)) {
  stop(
    paste(
      "GDX file not found:",
      gdx_path,
      "\nPlease run the GAMS model first."
    )
  )
}

# Initialize Container and read 'report' parameter
m <- Container$new(gdx_path)
report_sym <- m["report"]
dt_results <- as.data.table(report_sym$records)

# Rename columns for clarity (assuming generic names provided by gamstransfer)
# The GDX parameter report is 2D: (metric, scenario)
# Expected columns: uni_1 (metric), uni_2 (scenario), value
setnames(
  dt_results,
  old = c("uni_1", "uni_2", "value"),
  new = c("Metric", "Scenario", "Value")
)


# 2. Process Data --------------------------------------------------------

# Pivot/Reshape if necessary, or just filter for plots
# We want rows to be Scenarios and columns to be Metrics for some plots, 
# but long format is often better for ggplot.

# Map scenario codes to nice names
scenario_map <- c(
  "benchmark" = "Reference",
  "pol1" = "Cap (-20%)",
  "pol2" = "Tax ($10/tCO2)"
)

dt_results[, Scenario_Label := scenario_map[Scenario]]

# Ensure factor order
dt_results[
  ,
  Scenario_Label := factor(
    Scenario_Label,
    levels = c("Reference", "Cap (-20%)", "Tax ($10/tCO2)")
  )
]


# 3. Create Plots --------------------------------------------------------

my_theme <- theme_minimal() + 
  theme(
    legend.position = "none"
  )

# Plot 1: Production
p1 <- ggplot(
  dt_results[Metric == "production"],
  aes(x = Scenario_Label, y = Value, fill = Scenario_Label)
) +
  geom_bar(stat = "identity", width = 0.6) +
  scale_fill_brewer(palette = "Blues") +
  labs(title = "Total Steel Production", y = "Million Tonnes", x = "") +
  my_theme

# Plot 2: Emissions
p2 <- ggplot(
  dt_results[Metric == "emissions"],
  aes(x = Scenario_Label, y = Value, fill = Scenario_Label)
) +
  geom_bar(stat = "identity", width = 0.6) +
  scale_fill_brewer(palette = "Reds") +
  labs(title = "Total Carbon Emissions", y = "Mt CO2", x = "") +
  my_theme

# Plot 3: Prices (Steel vs Carbon)
# Need to filter for both and plot side-by-side or faceted
price_data <- dt_results[Metric %in% c("steel_price", "carbon_price")]

# Rename metrics for legend
price_data[
  ,
  Metric_Label := ifelse(
    Metric == "steel_price",
    "Steel Price",
    "Carbon Price"
  )
]

price_data <- rbind(
  price_data,
  price_data[
    Scenario == "benchmark"
  ][,
    `:=`(Metric = "carbon_price", Value = 0, Metric_Label = "Carbon Price")
  ]
)

p3 <- ggplot(
  price_data,
  aes(x = Scenario_Label, y = Value, fill = Metric_Label)
) +
  geom_bar(
    stat = "identity",
    position = position_dodge(width = 0.8),
    width = 0.7
  ) +
  labs(
    title = "Market Prices",
    y = "Price ($)",
    x = "",
    fill = "Price Type"
  ) +
  scale_fill_manual(
    values = c("Steel Price" = "grey", "Carbon Price" = "forestgreen"),
    name = NULL
  ) +
  theme_minimal() +
  theme(
    legend.position = "inside",
    legend.position.inside = c(0.12, 0.9),
    legend.background = element_rect(
      fill = "white",
      linetype = "solid",
      color = "gray"
    )
  )

# 4. Save ----------------------------------------------------------------

# Create output directory if needed
if (!dir.exists("output/R")) dir.create("output/R", recursive = TRUE)

ggsave("output/R/total_production.pdf", p1, width = 6, height = 4)
ggsave("output/R/total_emissions.pdf", p2, width = 6, height = 4)
ggsave("output/R/market_prices.pdf", p3, width = 6, height = 4)

print("Plots saved to output/R")
