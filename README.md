# Project Documentation and Structure

## Directory Structure

*   **`gams/`**: Reference implementation in GAMS.
    *   `simple_steel.gms`: Core model.
*   **`gamspy/`**: Python implementation using GAMSPy.
    *   `simple_steel.py`: Core model.
    *   `requirements.txt`: Python dependencies.
*   **`julia/`**: Julia implementation.
*   **`R/`**: Data generation and visualization.
    *   `simple_steel_data.R`: Generates input data and exports to GDX (`data/simple_steel_data.gdx`).
    *   `visualize_results.R`: Visualizes results from GDX.
*   **`data/`**: Input data.
    *   `raw/`: CSV files for model parameters.
    *   `simple_steel_data.gdx`: Generated GDX data file.
*   **`output/`**: Generated results.

## Setup

### Python Environment
To create a `.venv` and install dependencies (`gamspy`, `pandas`, `pyarrow`, etc.):
```powershell
./setup_python.ps1
```

### Julia Environment
To automate the creation of the Julia virtual environment and install dependencies (`JuMP`, `Parquet`, etc.), run the provided setup script:
```powershell
./setup_julia.ps1
```

## Workflow

The intended workflow for this project is:

1.  **Data Generation**: Run the R script to generate the input data and export it to a GDX file.
    ```bash
    Rscript R/simple_steel_data.R
    ```
    *Output*: `data/simple_steel_data.gdx`

2.  **Model Execution**:
    *   **GAMS**: Run the GAMS model. It contains its own data generation logic for demonstration purposes.
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
