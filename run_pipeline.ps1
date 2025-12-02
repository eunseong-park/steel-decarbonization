# run_pipeline.ps1

Write-Host "--- Starting Pipeline ---" -ForegroundColor Cyan

# 1. Data Generation
Write-Host "`n[Step 1] Generating Data..." -ForegroundColor Green
# Option A: R Generation
Write-Host "  > Running R Generator..."
Rscript R/simple_steel_data.R
if ($LASTEXITCODE -ne 0) { Write-Error "R data generation failed!"; exit 1 }

# Option B: Python Generation (Alternative)
# Write-Host "  > Running Python Generator..."
# & .venv\Scripts\python.exe gamspy/simple_steel_data.py

# 2. Model Execution
# Run GAMSPy Model
Write-Host "`n[Step 2a] Running GAMSPy Model..." -ForegroundColor Green
if (Test-Path ".venv\Scripts\python.exe") {
    & .venv\Scripts\python.exe gamspy/simple_steel.py
} else {
    python gamspy/simple_steel.py
}
if ($LASTEXITCODE -ne 0) { Write-Warning "GAMSPy model execution failed." }

# Run Julia Model
Write-Host "`n[Step 2b] Running Julia Model..." -ForegroundColor Green
julia --project=@steel_env julia/simple_steel.jl
if ($LASTEXITCODE -ne 0) { Write-Warning "Julia model execution failed." }

# 3. Visualization
Write-Host "`n[Step 3] Visualizing Results..." -ForegroundColor Green

# R Visualization
Write-Host "  > Running R Visualization..."
Rscript R/visualize_results.R

# Julia Visualization
Write-Host "  > Running Julia Visualization..."
julia --project=@steel_env julia/visualize_results.jl

if ($LASTEXITCODE -ne 0) { Write-Error "Visualization failed!"; exit 1 }

Write-Host "`n--- Pipeline Complete ---" -ForegroundColor Cyan
