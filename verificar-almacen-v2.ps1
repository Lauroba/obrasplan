#Requires -Version 5.1
# verificar-almacen-v2.ps1
# Verifica que los archivos del deploy-almacen-v2 estan correctamente en su sitio.
# Los errores anteriores del script de deploy eran falsos positivos causados
# por que PowerShell interpreta [id] como patron glob en Test-Path y Select-String.

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
Set-Location $RepoPath

Write-Host ""
Write-Host "==> Verificando archivos del deploy almacen v2" -ForegroundColor Cyan

function Check-File($path, $marker) {
    $literal = Join-Path $RepoPath $path
    if (-not (Test-Path -LiteralPath $literal)) {
        Write-Host ("    ERROR archivo no existe: " + $path) -ForegroundColor Red
        return
    }
    $content = Get-Content -LiteralPath $literal -Raw
    if ($marker -and -not $content.Contains($marker)) {
        Write-Host ("    ERROR marcador no encontrado en: " + $path) -ForegroundColor Red
        Write-Host ("    Buscaba: " + $marker) -ForegroundColor DarkRed
    } else {
        Write-Host ("    OK: " + $path) -ForegroundColor Green
    }
}

Check-File "src\app\almacen\almacenes\page.tsx"          "v_resumen_almacenes"
Check-File "src\app\almacen\almacenes\[id]\page.tsx"     "ajuste"
Check-File "src\app\obras\[id]\obra-detail.tsx"          "crear_almacen_obra"
Check-File "src\app\obras\nueva\page.tsx"                "crear_almacen_obra"

Write-Host ""
Write-Host "Si todos son OK, ejecuta:" -ForegroundColor Green
Write-Host '  git add -A'
Write-Host '  git commit -m "feat: almacen v2 - detalle, ajustes, historico, auto-almacen por obra"'
Write-Host '  git push'
