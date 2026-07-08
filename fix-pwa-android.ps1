#Requires -Version 5.1
# fix-pwa-android.ps1
# Corrige la instalacion PWA en Android:
# 1. manifest.json: start_url="/" (no "/dashboard" que requiere auth y
#    hace que Chrome rechace la instalacion por redirect loop)
# 2. manifest.json: iconos separados por purpose any/maskable
# 3. sw.js: actualizado a v2, evita interceptar llamadas a Supabase/API

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Escribiendo archivos PWA" -ForegroundColor Cyan

$dst = "public\manifest.json"
$content = @'
{
  "name": "ObrasPlan — Loynek",
  "short_name": "ObrasPlan",
  "description": "Planificación y gestión de obras — Loynek Soluciones Técnicas",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#DC2626",
  "orientation": "any",
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
  ],
  "scope": "/",
  "prefer_related_applications": false
}
'@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: public\manifest.json" -ForegroundColor Green

$dst = "public\sw.js"
$content = @'
const CACHE_NAME = "obrasplan-v2";
const OFFLINE_URL = "/offline.html";

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll([OFFLINE_URL, "/icon-192.png", "/icon-512.png"]);
    })
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(
        names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  // Solo interceptar navegaciones (no APIs ni Supabase)
  if (
    event.request.mode === "navigate" &&
    !event.request.url.includes("supabase") &&
    !event.request.url.includes("/api/")
  ) {
    event.respondWith(
      fetch(event.request).catch(() => caches.match(OFFLINE_URL))
    );
  }
});
'@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: public\sw.js" -ForegroundColor Green

$ok1 = Select-String -Path "public\manifest.json" -Pattern '"start_url": "/"' -Quiet
$ok2 = Select-String -Path "public\sw.js" -Pattern "obrasplan-v2" -Quiet
if ($ok1) { Write-Host "    OK: start_url corregido a /" -ForegroundColor Green }
else { Write-Host "    ERROR manifest" -ForegroundColor Red }
if ($ok2) { Write-Host "    OK: sw.js v2" -ForegroundColor Green }
else { Write-Host "    ERROR sw.js" -ForegroundColor Red }
Write-Host ""
Write-Host '  git add public\manifest.json public\sw.js'
Write-Host '  git commit -m "fix: PWA Android - start_url correcto, sw v2, iconos separados"'
Write-Host '  git push'
Write-Host ""
Write-Host "TRAS EL DEPLOY en Android Chrome:" -ForegroundColor Cyan
Write-Host "  1. Abre obrasplan.vercel.app"
Write-Host "  2. Menu tres puntos -> Anade a pantalla de inicio"
Write-Host "  O espera el banner automatico (puede tardar 30s)"
