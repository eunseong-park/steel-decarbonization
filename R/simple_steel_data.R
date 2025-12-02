# R/simple_steel_data.R

library(data.table)
library(gamstransfer)

set.seed(42) # For reproducibility


# Sets -------------------------------------------------------------------

i <- paste0("i", 1:15)

f_names <- c(
  "iore" = "Iron ore (tonnes)",
  "coal" = "Coking coal (tonnes)",
  "scrp" = "Steel scrap (tonnes)",
  "elec" = "Electricity (MWh)",
  "ngas" = "Natural gas (tonnes)"
)

f <- names(f_names)

t_names <- c(
  "bof" = "BF-BOF Route",
  "eaf" = "Scrap-EAF Route",
  "dri" = "DRI-EAF Route"
)

t_tech <- names(t_names)

# Link between plants and technologies
# (i1 * i5).bof, (i6 * i10).eaf, (i11 * i15).dri
it <- data.table(
  i = i,
  t = c(rep("bof", 5), rep("eaf", 5), rep("dri", 5))
)

# Parameters -------------------------------------------------------------

# abar: Factor use per ton crude steel production
abar <- fread("data/raw/abar.csv")

# vbar: Reference factor market prices
vbar <- fread("data/raw/vbar.csv")

# rho: Price elasticity in factor supply
rho <- fread("data/raw/rho.csv")

# kappa: Carbon emissions coefficient
kappa <- fread("data/raw/kappa.csv")

epsilon <- -0.3


# Random Data Generation -------------------------------------------------

# tau: Plant-specific additional cost (e.g. transport)
# tau(i, f) = uniform(0, 0.1)
tau <- CJ(i = i, f = f)
tau[, value := runif(.N, min = 0, max = 0.1)]

# ylim: Plant-specific production capacity
# ylim(i) = uniform(10, 15)
ylim <- data.table(i = i)
ylim[, value := runif(.N, min = 10, max = 15)]

# ybar: Reference output by plant
# ybar(i) = ylim(i) - uniform(0, 5)
ybar <- copy(ylim)
ybar[, value := value - runif(.N, min = 0, max = 5)]


# dbar: Reference aggregate demand
# dbar = sum(i, ybar(i))
dbar <- sum(ybar$value)

# Policy Parameter
chi <- 0

# Output to check
print("Data generation complete.")
print(paste("dbar:", dbar))

# ------------------------------------------------------------------------------
# HDF5 EXPORT (Structured)
# ------------------------------------------------------------------------------

if (!require("hdf5r")) install.packages("hdf5r", repos = "http://cran.us.r-project.org")
library(hdf5r)

# --- HDF5 Test: Can we create any HDF5 file? ---
tryCatch({
  test_file <- tempfile(fileext = ".h5")
  test_h5 <- H5File$new(test_file, mode = "w")
  test_h5[["test_data"]] <- 1:10
  test_h5$close_all()
  message("HDF5 test file created successfully at: ", test_file)
  file.remove(test_file)
  message("HDF5 test file removed.")
}, error = function(e) {
  stop("Failed to create basic HDF5 test file. HDF5 library or hdf5r package might be misconfigured: ", e$message)
})
# --- End HDF5 Test ---

# Create directory if not exists
if (!dir.exists("data/generated")) dir.create("data/generated", recursive = TRUE)

h5_file <- "data/generated/steel_data.h5"
if (file.exists(h5_file)) file.remove(h5_file)

file.h5 <- H5File$new(h5_file, mode = "w")

# --- 1. Sets ---
# Explicitly create groups
sets_group <- file.h5$create_group("sets")

# Write simple sets as 1D arrays
sets_group$create_dataset("i", i)
sets_group$create_dataset("f", f)
sets_group$create_dataset("t", t_tech)

# Write mapping 'it' as a dataframe/compound type
sets_group$create_dataset("it", it)

# --- 2. Parameters ---
params_group <- file.h5$create_group("params")

# We write them as they are (DataTables).
params_group$create_dataset("abar", abar)
params_group$create_dataset("vbar", vbar)
params_group$create_dataset("rho", rho)
params_group$create_dataset("kappa", kappa)

params_group$create_dataset("tau", tau)
params_group$create_dataset("ylim", ylim)
params_group$create_dataset("ybar", ybar)

# --- 3. Scalars ---
scalars_group <- file.h5$create_group("scalars")

scalars_group$create_dataset("dbar", dbar)
scalars_group$create_dataset("epsilon", epsilon)
scalars_group$create_dataset("chi", chi)
file.h5$close_all()

print(paste("All data written to single HDF5 file:", h5_file))

# ------------------------------------------------------------------------------
# GDX EXPORT
# ------------------------------------------------------------------------------

m <- Container$new()

# Sets
# For sets with descriptions, we format records as data frame 
# with 'uni' and 'element_text'
i_set <- Set$new(
  m,
  "i",
  records = i,
  description = "Steel plants"
)

f_records <- data.frame(
  uni = names(f_names),
  element_text = as.character(f_names)
)

f_set <- Set$new(
  m,
  "f",
  records = f_records,
  description = "Factors"
)

t_records <- data.frame(
  uni = names(t_names),
  element_text = as.character(t_names)
)

t_set <- Set$new(
  m,
  "t",
  records = t_records,
  description = "Technology type"
)

it_set <- Set$new(
  m,
  "it",
  domain = c(i_set, t_set),
  records = it,
  description = "Link between plants and technologies"
)

# Parameters
abar_p <- Parameter$new(
  m,
  "abar",
  domain = c(t_set, f_set),
  records = abar,
  description = "Factor use per ton crude steel production"
)

vbar_p <- Parameter$new(
  m,
  "vbar",
  domain = f_set,
  records = vbar,
  description = "Reference factor market prices"
)

rho_p <- Parameter$new(
  m,
  "rho",
  domain = f_set,
  records = rho,
  description = "Price elasticity in factor supply"
)

kappa_p <- Parameter$new(
  m,
  "kappa",
  domain = f_set,
  records = kappa,
  description = "Carbon emissions coefficient"
)

epsilon_p <- Parameter$new(
  m,
  "epsilon",
  records = epsilon,
  description = "Price elasticity of steel demand"
)

tau_p <- Parameter$new(
  m,
  "tau",
  domain = c(i_set, f_set),
  records = tau,
  description = "Plant-specific additional cost (e.g. transport)"
)

ylim_p <- Parameter$new(
  m,
  "ylim",
  domain = i_set,
  records = ylim,
  description = "Plant-specific production capacity"
)

ybar_p <- Parameter$new(
  m,
  "ybar",
  domain = i_set,
  records = ybar,
  description = "Reference output by plant"
)

dbar_p <- Parameter$new(
  m,
  "dbar",
  records = dbar,
  description = "Reference aggregate demand"
)

chi_p <- Parameter$new(
  m,
  "chi",
  records = chi,
  description = "Emissions reduction target"
)

# Write GDX
if (!dir.exists("data")) dir.create("data", recursive = TRUE)
gdx_path <- "data/generated/steel_data.gdx"
m$write(gdx_path)
print(paste("GDX file written to:", gdx_path))