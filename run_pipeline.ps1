# run_pipeline.ps1

Write-Host "--- Starting Pipeline ---" -ForegroundColor Green

# 1. Data Generation (Common)
Write-Host "`n[Step 1] Generating Data..." -ForegroundColor Cyan
# Option A: R Generation
Write-Host "  > Running R Generator..."
Rscript R/simple_steel_data.R
if ($LASTEXITCODE -ne 0) { Write-Error "R data generation failed!"; exit 1 }

# Option B: Python Generation (Alternative)
# Write-Host "  > Running Python Generator..."
# & .venv\Scripts\python.exe gamspy/simple_steel_data.py

# 2. GAMS Pipeline (GAMS Model -> R Visualization)
Write-Host "`n[Step 2] GAMS Pipeline..." -ForegroundColor Cyan
# Check if GAMS is in PATH (Simple check)
if (Get-Command gams -ErrorAction SilentlyContinue) {
    Write-Host "  > Running GAMS Model..."
    gams gams/simple_steel.gms o=gams/simple_steel.lst
    
    Write-Host "  > Running R Visualization (for GAMS results)..."
    Rscript R/visualize_results.R
} else {
    Write-Warning "  > GAMS not found. Skipping GAMS pipeline."
}

# 3. GAMSPy Pipeline (GAMSPy Model -> Python Visualization)
Write-Host "`n[Step 3] GAMSPy Pipeline..." -ForegroundColor Cyan
Write-Host "  > Running GAMSPy Model..."
if (Test-Path ".venv\Scripts\python.exe") {
    & .venv\Scripts\python.exe gamspy/simple_steel.py
} else {
    python gamspy/simple_steel.py
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "  > Running Python Visualization..."
    if (Test-Path ".venv\Scripts\python.exe") {
        & .venv\Scripts\python.exe gamspy/visualize_results.py
    } else {
        python gamspy/visualize_results.py
    }
} else {
    Write-Warning "  > GAMSPy model failed. Skipping visualization."
}

# 4. Julia Pipeline (Julia Model -> Julia Visualization)
Write-Host "`n[Step 4] Julia Pipeline..." -ForegroundColor Cyan
Write-Host "  > Running Julia Model..."
julia --project=julia julia/simple_steel.jl

if ($LASTEXITCODE -eq 0) {
    Write-Host "  > Running Julia Visualization..."
    julia --project=julia julia/visualize_results.jl
} else {
    Write-Warning "  > Julia model failed. Skipping visualization."
}

Write-Host "`n--- Pipeline Complete ---" -ForegroundColor Green
