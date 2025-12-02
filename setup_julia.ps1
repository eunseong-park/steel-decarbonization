# setup_julia.ps1

# --- Configuration ---
# Set this to a local path (e.g., "julia") or a shared name (e.g., "@steel_env")
$EnvPath = "julia" 
# ---------------------

Write-Host "--- Setting up Julia Virtual Environment ($EnvPath) ---" -ForegroundColor Cyan

# Check if Julia is installed
if (-not (Get-Command julia -ErrorAction SilentlyContinue)) {
    Write-Error "Julia is not found in PATH. Please install Julia first."
    exit 1
}

# Navigate to project root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Run Julia Pkg commands
Write-Host "Instantiating Dependencies from Project.toml..." -ForegroundColor Yellow

# Instantiate the environment (downloads and installs packages listed in Manifest.toml/Project.toml)
julia --project=$EnvPath -e 'import Pkg; Pkg.instantiate()'

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n[Success] Julia environment is ready." -ForegroundColor Green
    Write-Host "To use it, run: julia --project=$EnvPath julia/simple_steel.jl"
} else {
    Write-Error "`n[Error] Failed to set up Julia environment."
    exit 1
}