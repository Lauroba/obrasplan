#Requires -Version 5.1
# fix-partes-llave-simple.ps1
# Añade la llave de cierre } que falta al final de partes/[id]/page.tsx
# Sin embeber el archivo completo (evita problemas con Here-strings)

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath

$FilePath = Join-Path $RepoPath "src\app\partes\[id]\page.tsx"
Write-Host "" ; Write-Host "==> Leyendo archivo actual del repo local" -ForegroundColor Cyan

# Leer el archivo tal cual está en el repo local
$content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)

# Contar llaves para verificar el problema
$opens  = ([regex]::Matches($content, '(?s)(?<![\\]){(?![^"]*(?<![\\])")')).Count
# Método simple: contar todos los { y }
$allOpens  = ($content.ToCharArray() | Where-Object { $_ -eq '{' }).Count
$allCloses = ($content.ToCharArray() | Where-Object { $_ -eq '}' }).Count
Write-Host "  Llaves abiertas:  $allOpens"
Write-Host "  Llaves cerradas:  $allCloses"
Write-Host "  Diferencia:       $($allOpens - $allCloses)"

if ($allOpens -gt $allCloses) {
    $diff = $allOpens - $allCloses
    Write-Host "  Añadiendo $diff llave(s) de cierre..." -ForegroundColor Yellow
    
    # Añadir las } faltantes al final
    $closing = "`n" * $diff
    for ($i = 0; $i -lt $diff; $i++) { $closing += "}`n" }
    # En realidad solo añadir 1 }
    $newContent = $content.TrimEnd() + "`n}`n"
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($FilePath, $newContent, $utf8NoBom)
    Write-Host "  OK: llave añadida" -ForegroundColor Green
    
    # Re-verificar
    $content2 = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
    $opens2  = ($content2.ToCharArray() | Where-Object { $_ -eq '{' }).Count
    $closes2 = ($content2.ToCharArray() | Where-Object { $_ -eq '}' }).Count
    Write-Host "  Verificación: { =$opens2  } =$closes2  diff=$($opens2-$closes2)" -ForegroundColor $(if ($opens2 -eq $closes2) { "Green" } else { "Red" })
} else {
    Write-Host "  Las llaves ya están balanceadas" -ForegroundColor Green
}

Write-Host ""
Write-Host '  git add "src\app\partes\[id]\page.tsx"'
Write-Host '  git commit -m "fix: llave faltante cierre funcion ParteDetallePage"'
Write-Host '  git push'
