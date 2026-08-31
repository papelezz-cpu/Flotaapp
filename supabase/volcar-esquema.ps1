# Lanzador para PowerShell de supabase/volcar-esquema.sh
#
# En Windows, escribir `bash` en PowerShell llama al bash de WSL, que en este
# equipo no tiene ninguna distribucion instalada y falla con un error confuso.
# El bash bueno es el que viene con Git. Este archivo lo encuentra y le pasa
# el script, para no tener que acordarse de la ruta.
#
# Uso (desde la carpeta del proyecto):
#   .\supabase\volcar-esquema.ps1

$ErrorActionPreference = 'Stop'

$candidatos = @(
  "C:\Program Files\Git\bin\bash.exe",
  "C:\Program Files (x86)\Git\bin\bash.exe",
  "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)

$bash = $null
foreach ($c in $candidatos) { if (Test-Path $c) { $bash = $c; break } }

if (-not $bash) {
  Write-Host "No encontre el bash de Git." -ForegroundColor Red
  Write-Host "Instalalo desde https://git-scm.com/download/win y vuelve a intentar."
  exit 1
}

# La ruta del .sh se calcula desde este archivo: funciona sin importar desde
# que carpeta se invoque.
$script = Join-Path $PSScriptRoot 'volcar-esquema.sh'
if (-not (Test-Path $script)) {
  Write-Host "No encontre $script" -ForegroundColor Red
  exit 1
}

Write-Host "Usando $bash" -ForegroundColor DarkGray
Write-Host ""

& $bash $script @args
exit $LASTEXITCODE
