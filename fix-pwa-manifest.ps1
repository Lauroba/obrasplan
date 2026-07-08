#Requires -Version 5.1
# fix-pwa-manifest.ps1
# Corrige el manifest.json para que Chrome en Android muestre el banner
# de instalacion PWA. El problema era que los iconos tenian un unico
# objeto con purpose "any maskable" — Chrome requiere entradas separadas.

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Escribiendo public/manifest.json" -ForegroundColor Cyan

$dst = "public\manifest.json"
$content = @'
{
  "name": "ObrasPlan — Loynek",
  "short_name": "ObrasPlan",
  "description": "Planificación y gestión de obras — Loynek Soluciones Técnicas",
  "start_url": "/dashboard",
  "scope": "/",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#DC2626",
  "orientation": "any",
  "prefer_related_applications": false,
  "icons": [
    {
      "src": "/icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any"
    },
    {
      "src": "/icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "maskable"
    },
    {
      "src": "/icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any"
    },
    {
      "src": "/icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "maskable"
    }
  ]
}
'@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: $dst" -ForegroundColor Green

$ok = Select-String -Path "public\manifest.json" -Pattern "prefer_related_applications" -Quiet
if ($ok) { Write-Host "    OK: manifest corregido" -ForegroundColor Green }
else { Write-Host "    ERROR" -ForegroundColor Red }
Write-Host ""
Write-Host '  git add public/manifest.json'
Write-Host '  git commit -m "fix: PWA manifest iconos separados por purpose para Android"'
Write-Host '  git push'
Write-Host ""
Write-Host "Tras el deploy, en Chrome Android:"
Write-Host "  1. Abre obrasplan.vercel.app"
Write-Host "  2. Menu (tres puntos) -> Anade a pantalla de inicio"
Write-Host "  3. O espera el banner automatico de instalacion"
