# Project Documentation and Structure

## Directory Structure

*   **`gams/`**: Reference implementation in GAMS.
    *   `simple_steel.gms`: Core model.
*   **`gamspy/`**: Python implementation using GAMSPy.
    *   `simple_steel.py`: Core model.
    *   `requirements.txt`: Python dependencies.
*   **`julia/`**: Julia implementation.
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

The intended workflow for this project is:

1.  **Data Generation**: Run either the R or Python script to generate the input data (GDX for GAMS/GAMSPy, HDF5 for Julia).
    *   **Option A (R)**:
        ```bash
        Rscript R/simple_steel_data.R
        ```
    *   **Option B (Python)**:
        ```bash
        python gamspy/simple_steel_data.py
        ```
    *Output*: `data/simple_steel_data.gdx` and `data/generated/steel_data.h5`

2.  **Model Execution**:
    *   **GAMS**: Run the GAMS model. It reads inputs from `data/simple_steel_data.gdx`.
        ```bash
        gams gams/simple_steel.gms
        ```
    *   **GAMSPy**: Run the Python model.
        ```bash
        python gamspy/simple_steel.py
        ```

3.  **Visualization**: Run the R visualization script.
    ```bash
    Rscript R/visualize_results.R
    ```

## Orchestration

A PowerShell script `run_pipeline.ps1` is provided to automate the data generation and visualization steps.
