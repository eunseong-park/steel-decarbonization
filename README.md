# Project Documentation and Structure

## Project Context

**Course:** Applied Equilibrium Analysis in Environmental and Energy Economics (Heidelberg University, Prof. Dr. Sebastian Rausch)

**Topic:** Emissions Reduction in the Global Steel Industry and Policy Measures

This repository serves as the codebase for a group project aimed at analyzing the economic and environmental impacts of decarbonizing the global steel industry. The objective is to implement, extend, and analyze a partial equilibrium model using one of the provided programming frameworks (GAMS, Python/GAMSPy/Pyomo, Julia/JuMP). Students are expected to use this codebase to generate results for their final report and presentation.

**Model Summary:**
The starting point is a simplified single-country partial equilibrium model of the steel industry, largely based on Mathiesen and Maestad (2004). The model simulates heterogeneous steel plants employing different technologies (BOF, EAF, DRI) and consuming various factors (iron ore, coal, scrap, electricity, natural gas). It is calibrated using synthetic data to establish a baseline for economic analysis.

**Key Tasks:**

* Extend the base model to a multi-region framework.
* Simulate and assess climate policy instruments such as carbon taxes, emissions trading systems (ETS), and technology standards.
* Calculate potential carbon leakage rates and evaluate the effectiveness of Border Carbon Adjustments (BCA) in mitigating leakage while ensuring global emission reductions.

## Modeling Frameworks

The mathematical model is equivalently implemented in several frameworks. A detailed description of the model is provided in `tex/description.pdf`.

* **GAMS**

  * **GAMS**: (General Algebraic Modeling System) A high-level modeling system for mathematical programming and optimization.
* **Python**

  * **GAMSPy**: A Python package that combines the flexibility of Python with the high-performance optimization capabilities of the GAMS execution system.
  * **Pyomo**: (Python Optimization Modeling Objects) A Python-based open-source optimization modeling language that supports defining and solving diverse optimization problems.
* **Julia**

  * **JuMP**: (Julia for Mathematical Programming) A domain-specific modeling language for mathematical optimization embedded in Julia, known for its speed and intuitive syntax.

## Directory Structure

* **`gams/`**: Reference implementation in GAMS.
  * `simple_steel.gms`: Core model.
* **`python/`**: Python implementations using GAMSPy and Pyomo.
  * `simple_steel_gamspy.py`: GAMSPy model implementation.
  * `simple_steel_pyomo.py`: Pyomo model implementation.
  * `simple_steel_data.py`: Data generation (GAMSPy based).
  * `visualize_results.py`: Visualizes results from CSV.
  * `requirements.txt`: Python dependencies.
* **`julia/`**: Julia implementation using JuMP.
* **`R/`**: Data generation and visualization.
  * `simple_steel_data.R`: Generates input data and exports to GDX (`data/generated/steel_data.gdx`) and HDF5.
  * `visualize_results.R`: Visualizes results from GDX.
* **`data/`**: Input data.
  * `raw/`: CSV files for model parameters.
  * `generated/steel_data.gdx`: Generated GDX data file.
  * `generated/steel_data.h5`: Generated HDF5 data file.
* **`output/`**: Generated results.

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

### Solvers Installation

* **GAMS / GAMSPy**:

  * **GAMS**: Requires a standard GAMS system installation, which includes various solvers (e.g., PATH, CONOPT, CPLEX). Ensure the GAMS system directory is in your system `PATH`.
  * **GAMSPy**: The `gamspy` package automatically installs a bundled GAMS execution system (via the `gamspy_base` dependency) which includes the necessary solvers. A separate GAMS installation is not required.
  * **Licenses**: Through the GAMS Academic Program ([https://academic.gams.com/](https://academic.gams.com/)), FREE + full-featured GAMSPy licenses and GAMS community licenses are available for academic purposes.
* **Julia**: Solver binaries (e.g., HiGHS, PATH) are automatically managed and downloaded by the Julia package manager.
* **Pyomo**: Requires manual installation of external solvers. Ensure the solver executables are added to your system's `PATH` environment variable.

  * **PATH Solver** (for MCP problems):
    * **Download**: Visit the [PATH Solver website](https://pages.cs.wisc.edu/~ferris/path/) and download the AMPL version (e.g., `path_5.0.05_Win64.zip` for Windows).
    * **Setup**: Unzip and add the folder containing `pathampl.exe` to your system `PATH`.
    * **License**: The free version is limited to 300 variables and 2000 nonzeros. For larger problems, obtain a [temporary license](https://pages.cs.wisc.edu/~ferris/path/license).
  * **IPOPT Solver** (for NLP problems):
    * **Download**: Visit the [COIN-OR binary archive](https://www.coin-or.org/download/binary/Ipopt/) and download the latest binary (e.g., `Ipopt-3.11.1-win64-intel13.1.zip` for Windows).
    * **Setup**: Unzip and add the `bin` folder (containing `ipopt.exe`) to your system `PATH`.
    * **License**: IPOPT is open-source and released under the Eclipse Public License (EPL).

## Workflow

The pipeline is organized by language ecosystem:

1. **Data Generation (Common)**:

   * Generates `data/generated/steel_data.gdx` and `data/generated/steel_data.h5`.
   * Run via `Rscript R/simple_steel_data.R` (or Python `python/simple_steel_data.py`).
2. **GAMS Pipeline**:

   * **Model**: `gams/simple_steel.gms` (Reads GDX).
   * **Viz**: `R/visualize_results.R` (Reads GAMS output GDX).
3. **GAMSPy Pipeline**:

   * **Model**: `python python/simple_steel_gamspy.py` (Reads GDX).
   * **Viz**: `python python/visualize_results.py` (Reads CSV output from `output/python`).
4. **Pyomo Pipeline**:

   * **Model**: `python python/simple_steel_pyomo.py` (Reads HDF5).
   * **Viz**: `python python/visualize_results.py` (Reads CSV output from `output/python`).
   * **Note**: Requires a solver (e.g., IPOPT, PATH) installed and available in the system PATH.
5. **Julia Pipeline**:

   * **Model**: `julia --project=julia julia/simple_steel.jl` (Reads H5).
   * **Viz**: `julia --project=julia julia/visualize_results.jl` (Reads CSV output).

### Automation

Run the full pipeline using the PowerShell script:

```powershell
./run_pipeline.ps1
```

## Author

Eunseong Park ([eunseong.park@zew.de](mailto:eunseong.park@zew.de))

ZEW – Leibniz Centre for European Economic Research
