# setup_python.ps1

Write-Host "--- Setting up Python Virtual Environment ---" -ForegroundColor Cyan

# Check if Python is installed
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Error "Python is not found in PATH. Please install Python first."
    exit 1
}

# Navigate to project root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Create venv if it doesn't exist
if (-not (Test-Path ".venv")) {
    Write-Host "Creating virtual environment (.venv)..." -ForegroundColor Yellow
    python -m venv .venv
}

# Activate venv
Write-Host "Activating virtual environment..."
if ($IsWindows) {
    . .venv\Scripts\Activate.ps1
} else {
    # Fallback for Git Bash / WSL if running this script there (though .ps1 is usually Windows)
    . .venv/bin/activate
}

# Install requirements
Write-Host "Installing/Updating Dependencies..." -ForegroundColor Yellow
pip install --upgrade pip
pip install -r gamspy/requirements.txt

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n[Success] Python environment is ready." -ForegroundColor Green
    Write-Host "To use it, run: .venv\Scripts\Activate.ps1; python gamspy/simple_steel.py"
} else {
    Write-Error "`n[Error] Failed to install Python dependencies."
    exit 1
}
