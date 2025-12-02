import numpy as np
import pandas as pd
import h5py
import os
from gamspy import Container, Set, Parameter, Sum

def generate_data():
    print("Generating data using GAMSPy...")
    
    # Initialize Container
    m = Container()

    # ------------------------------------------------------------------------------
    # 1. DECLARE PARAMETERS, SETS, DATA
    # ------------------------------------------------------------------------------

    # Sets
    i_recs = [f"i{k}" for k in range(1, 16)]
    i = Set(m, "i", records=i_recs, description="Steel plants")
    
    f_recs = ["iore", "coal", "scrp", "elec", "ngas"]
    f = Set(m, "f", records=f_recs, description="Factors")
    
    t_recs = ["bof", "eaf", "dri"]
    t = Set(m, "t", records=t_recs, description="Technology type")

    # Mapping plants to technologies
    it_recs = []
    for k in range(1, 16):
        plant = f"i{k}"
        if k <= 5:
            tech = "bof"
        elif k <= 10:
            tech = "eaf"
        else:
            tech = "dri"
        it_recs.append((plant, tech))

    it = Set(
        m,
        "it",
        domain=[i, t],
        records=it_recs,
        description="Link between plants and technologies",
    )

    # Parameters
    # Load from CSVs in data/raw
    raw_data_dir = "data/raw"

    # abar: Factor use per ton
    # CSV has columns: t, f, value
    abar_df = pd.read_csv(os.path.join(raw_data_dir, "abar.csv"))
    abar = Parameter(
        m, "abar", domain=[t, f], records=abar_df,
        description="Factor use per ton crude steel production"
    )

    # vbar: Reference factor market prices
    # CSV has columns: f, value
    vbar_df = pd.read_csv(os.path.join(raw_data_dir, "vbar.csv"))
    vbar = Parameter(
        m, "vbar", domain=[f], records=vbar_df,
        description="Reference factor market prices"
    )

    # rho: Price elasticity in factor supply
    # CSV has columns: f, value
    rho_df = pd.read_csv(os.path.join(raw_data_dir, "rho.csv"))
    rho = Parameter(
        m, "rho", domain=[f], records=rho_df,
        description="Price elasticity in factor supply"
    )

    # kappa: Carbon emissions coefficient
    # CSV has columns: f, value
    kappa_df = pd.read_csv(os.path.join(raw_data_dir, "kappa.csv"))
    kappa = Parameter(
        m, "kappa", domain=[f], records=kappa_df,
        description="Carbon emissions coefficient"
    )

    epsilon = Parameter(
        m, "epsilon", records=-0.3, description="Price elasticity of steel demand"
    )

    # Random Generation Data
    np.random.seed(42)
    n_plants = 15
    n_factors = 5

    # Flatten the factor records to a list of strings for iteration
    # f.records is a DataFrame
    f_list = f_recs

    tau_data = np.random.uniform(0, 0.1, size=(n_plants, n_factors))
    tau_df = pd.DataFrame(
        [
            (f"i{r + 1}", f_name, tau_data[r, c])
            for r in range(n_plants)
            for c, f_name in enumerate(f_list)
        ],
        columns=["i", "f", "val"],
    )
    tau = Parameter(
        m, "tau", domain=[i, f], records=tau_df,
        description="Plant-specific additional cost (e.g. transport)"
    )

    ylim_data = np.random.uniform(10, 15, size=n_plants)
    ylim_df = pd.DataFrame(
        [(f"i{r + 1}", ylim_data[r]) for r in range(n_plants)], columns=["i", "val"]
    )
    ylim = Parameter(
        m, "ylim", domain=[i], records=ylim_df,
        description="Plant-specific production capacity"
    )

    ybar_init_data = ylim_data - np.random.uniform(0, 5, size=n_plants)
    ybar_df = pd.DataFrame(
        [(f"i{r + 1}", ybar_init_data[r]) for r in range(n_plants)],
        columns=["i", "val"],
    )
    ybar = Parameter(
        m, "ybar", domain=[i], records=ybar_df,
        description="Reference output by plant"
    )

    # dbar = sum(i, ybar(i))
    # We can calculate this in python or via gamspy
    dbar_val = ybar_df["val"].sum()
    dbar = Parameter(m, "dbar", records=dbar_val, description="Reference aggregate demand")

    print(f"Data generated. dbar: {dbar_val}")
    
    # Define Policy parameter (needed for model structure)
    chi = Parameter(m, "chi", records=0, description="Emissions reduction target")

    # ------------------------------------------------------------------------------
    # EXPORT TO GDX
    # ------------------------------------------------------------------------------
    if not os.path.exists("data"):
        os.makedirs("data")
    
    gdx_path = os.path.abspath("data/generated/steel_data.gdx")
    m.write(gdx_path)
    print(f"GDX file written to: {gdx_path}")

    # ------------------------------------------------------------------------------
    # EXPORT TO HDF5 (Structure matching R export)
    # ------------------------------------------------------------------------------
    if not os.path.exists("data/generated"):
        os.makedirs("data/generated")
        
    h5_path = "data/generated/steel_data.h5"
    
    with h5py.File(h5_path, 'w') as f:
        # Sets
        f.create_dataset("sets/i", data=np.array(i_recs, dtype='S'))
        f.create_dataset("sets/f", data=np.array(f_recs, dtype='S'))
        f.create_dataset("sets/t", data=np.array(t_recs, dtype='S'))
        
        # it (DataFrame)
        # Convert list of tuples to dataframe for easier saving or numpy structured array
        it_df = pd.DataFrame(it_recs, columns=["i", "t"])
        # Save as compound dataset or strings. 
        # R's hdf5r often saves dataframes as compound types. 
        # Simplest for cross-compat: save columns as separate arrays or struct array.
        # Let's use numpy struct array which h5py supports well
        it_arr = np.array([tuple(x) for x in it_recs], dtype=[('i', 'S10'), ('t', 'S10')])
        f.create_dataset("sets/it", data=it_arr)

        # Parameters
        # Helpers
        def save_param(path, df, dtype):
            # Convert dataframe to numpy structured array
            recs = df.to_records(index=False)
            # Ensure string cols are S type
            new_dtype = []
            for name, d in dtype:
                new_dtype.append((name, d))
            
            # Cast
            arr = np.array(recs, dtype=new_dtype)
            f.create_dataset(path, data=arr)

        save_param("params/abar", abar_df, [('t', 'S10'), ('f', 'S10'), ('value', 'f8')])
        save_param("params/vbar", vbar_df, [('f', 'S10'), ('value', 'f8')])
        save_param("params/rho", rho_df, [('f', 'S10'), ('value', 'f8')])
        save_param("params/kappa", kappa_df, [('f', 'S10'), ('value', 'f8')])
        
        save_param("params/tau", tau_df.rename(columns={"val":"value"}), [('i', 'S10'), ('f', 'S10'), ('value', 'f8')])
        save_param("params/ylim", ylim_df.rename(columns={"val":"value"}), [('i', 'S10'), ('value', 'f8')])
        save_param("params/ybar", ybar_df.rename(columns={"val":"value"}), [('i', 'S10'), ('value', 'f8')])
        
        # Scalars
        f.create_dataset("scalars/dbar", data=dbar_val)
        f.create_dataset("scalars/epsilon", data=-0.3)
        f.create_dataset("scalars/chi", data=0.0)

    print(f"HDF5 file written to: {h5_path}")

if __name__ == "__main__":
    generate_data()
