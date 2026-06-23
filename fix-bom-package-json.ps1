#Requires -Version 5.1
# fix-bom-package-json.ps1
# Quita el BOM (caracter invisible) que quedo al principio de package.json
# tras una escritura anterior con Set-Content -Encoding UTF8 (PowerShell
# 5.1 siempre anade BOM con ese parametro, y un BOM rompe el parseo JSON
# de Vercel: "Unexpected token, ... is not valid JSON").

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"

if (-not (Test-Path $RepoPath)) {
    Write-Host "ERROR: no se encuentra el repo en $RepoPath" -ForegroundColor Red
    exit 1
}
Set-Location $RepoPath

$pkgPath = "package.json"
if (-not (Test-Path $pkgPath)) {
    Write-Host "ERROR: no se encuentra package.json" -ForegroundColor Red
    exit 1
}

$bytes = [System.IO.File]::ReadAllBytes($pkgPath)
$hasBom = ($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)

if (-not $hasBom) {
    Write-Host "OK: package.json ya estaba sin BOM, no hace falta tocar nada." -ForegroundColor Green
} else {
    # Quitar los 3 bytes del BOM y reescribir SIN BOM, usando una codificacion
    # UTF8 explicitamente configurada sin marca de orden de bytes (esto es lo
    # que Set-Content -Encoding UTF8 NO hace en PowerShell 5.1).
    $cleanBytes = $bytes[3..($bytes.Length - 1)]
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $text = $utf8NoBom.GetString($cleanBytes)
    [System.IO.File]::WriteAllText($pkgPath, $text, $utf8NoBom)
    Write-Host "OK: BOM eliminado de package.json" -ForegroundColor Green
}

Write-Host ""
Write-Host "Verificando JSON valido..." -ForegroundColor Cyan
try {
    Get-Content -Path $pkgPath -Raw | ConvertFrom-Json | Out-Null
    Write-Host "OK: package.json es JSON valido." -ForegroundColor Green
    Write-Host ""
    Write-Host "Siguiente paso:" -ForegroundColor Green
    Write-Host '  git add package.json'
    Write-Host '  git commit -m "fix: quitar BOM de package.json que rompia el build en Vercel"'
    Write-Host '  git push'
} catch {
    Write-Host "ERROR: package.json sigue sin ser JSON valido. Revisa el archivo a mano." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
