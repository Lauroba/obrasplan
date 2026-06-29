#Requires -Version 5.1
# verificar-articulos-v2.ps1
# Verifica los archivos de deploy-articulos-v2 usando -LiteralPath
# para evitar que PowerShell interprete [id] como patron glob.

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
Set-Location $RepoPath

Write-Host ""
Write-Host "==> Verificando archivos deploy-articulos-v2" -ForegroundColor Cyan

function Check($path, $marker, $label) {
    $literal = Join-Path $RepoPath $path
    if (-not (Test-Path -LiteralPath $literal)) {
        Write-Host ("    ERROR no existe: " + $path) -ForegroundColor Red
        return
    }
    $content = Get-Content -LiteralPath $literal -Raw
    if ($marker -and -not $content.Contains($marker)) {
        Write-Host ("    ERROR marcador no encontrado en: " + $label) -ForegroundColor Red
    } else {
        Write-Host ("    OK: " + $label) -ForegroundColor Green
    }
}

Check "src\components\shared\FotoArticulo.tsx"          "group/foto"            "FotoArticulo con group/foto"
Check "src\app\almacen\articulos\page.tsx"               "detalleOpen"           "Modal detalle en articulos"
Check "src\app\almacen\articulos\page.tsx"               "detalleTab"            "Tabs en modal detalle"
Check "src\app\almacen\articulos\page.tsx"               "proximo_mantenimiento" "Campo mantenimiento maquinaria"
Check "src\app\almacen\almacenes\[id]\page.tsx"          "dias_en_almacen"       "Dias en almacen"
Check "src\app\almacen\almacenes\[id]\page.tsx"          "v_stock_actual_ext"    "Vista v_stock_actual_ext"
Check "src\app\obras\[id]\almacen\page.tsx"              "v_stock_actual_ext"    "Vista ext en obra almacen"
Check "src\app\almacen\movimientos\page.tsx"             "FotoArticulo"          "FotoArticulo en movimientos"

Write-Host ""
Write-Host "Si todo OK, ejecutar:" -ForegroundColor Green
Write-Host "  1. Supabase SQL Editor: 036_articulos_mantenimiento.sql"
Write-Host "  2. git add -A"
Write-Host '  3. git commit -m "feat: detalle articulo, hover foto, dias en almacen, mantenimiento maquinaria"'
Write-Host "  4. git push"
Write-Host "  5. Vercel: Promote to Production"
