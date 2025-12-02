# Project Documentation and Structure

## Directory Structure

*   **`gams/`**: Reference implementation in GAMS.
    *   `simple_steel.gms`: Core model.
*   **`gamspy/`**: Python implementation using GAMSPy.
    *   `simple_steel.py`: Core model.
    *   `requirements.txt`: Python dependencies.
*   **`julia/`**: Julia implementation using JuMP.
*   **`R/`**: Data generation and visualization.
    *   `simple_steel_data.R`: Generates input data and exports to GDX (`data/simple_steel_data.gdx`) and HDF5.
    *   `visualize_results.R`: Visualizes results from GDX.
*   **`data/`**: Input data.
    *   `raw/`: CSV files for model parameters.
    *   `simple_steel_data.gdx`: Generated GDX data file.
    *   `generated/steel_data.h5`: Generated HDF5 data file.
*   **`output/`**: Generated results.

## Setup

### Python Environment
To create a `.venv` and install dependencies (`gamspy`, `pandas`, `h5py`, etc.):
```powershell
./setup_python.ps1
```

### Julia Environment
To automate the creation of the Julia virtual environment and install dependencies (`JuMP`, `HDF5`, etc.), run the provided setup script:
```powershell
./setup_julia.ps1
```

## Workflow

The pipeline is organized by language ecosystem:

1.  **Data Generation (Common)**:
    *   Generates `data/simple_steel_data.gdx` and `data/generated/steel_data.h5`.
    *   Run via `Rscript R/simple_steel_data.R` (or Python alternative).

2.  **GAMS Pipeline**:
    *   **Model**: `gams/simple_steel.gms` (Reads GDX).
    *   **Viz**: `R/visualize_results.R` (Reads GAMS output GDX).

3.  **GAMSPy Pipeline**:
    *   **Model**: `python gamspy/simple_steel.py` (Reads GDX).
    *   **Viz**: `python gamspy/visualize_results.py` (Reads CSV output).

4.  **Julia Pipeline**:
    *   **Model**: `julia --project=julia julia/simple_steel.jl` (Reads H5).
    *   **Viz**: `julia --project=julia julia/visualize_results.jl` (Reads CSV output).

### Automation
Run the full pipeline using the PowerShell script:
```powershell
./run_pipeline.ps1
```
