#Requires -Version 5.1
# fix-partes-comentarios-ascii.ps1
# Causa real del error de compilacion:
# SWC (compilador de Next.js 14) falla con caracteres UTF-8 no-ASCII
# (acentos, tildes, em-dash) en comentarios dentro de funciones,
# concretamente ANTES del primer return() del componente.
# Las lineas problemáticas eran:
#   - "el operario está asignado"  (á)
#   - "según su asignación de ese día"  (ú, ó, é, í)
#   - "Envío automático —"  (í, á, em-dash U+2014)
# Fix: reemplazar esos comentarios con versiones ASCII puras.
# No embebe el archivo completo - hace find/replace directo.

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath

$File = Join-Path $RepoPath "src\app\partes\[id]\page.tsx"
Write-Host "" ; Write-Host "==> Fix comentarios ASCII en partes/[id]/page.tsx" -ForegroundColor Cyan

# Leer como UTF-8
$content = [System.IO.File]::ReadAllText($File, [System.Text.Encoding]::UTF8)

$replacements = @(
    @{ Old = "// Obras a las que el operario est" + [char]0x00E1 + " asignado en la fecha actual del parte"
       New = "// Obras a las que el operario esta asignado en la fecha actual del parte" },
    @{ Old = "resolver la obra segun su asignacion de ese d" + [char]0x00ED + "a"
       New = "resolver la obra segun su asignacion de ese dia" },
    @{ Old = "// Env" + [char]0x00ED + "o autom" + [char]0x00E1 + "tico " + [char]0x2014 + " siempre a lauroba.eneko@gmail.com (sin confirm)"
       New = "// Envio automatico - siempre a lauroba.eneko@gmail.com (sin confirm)" },
    @{ Old = "resolver/forzar la obra seg" + [char]0x00FA + "n su asignaci" + [char]0x00F3 + "n de ese"
       New = "resolver la obra segun su asignacion de ese" }
)

$changed = 0
foreach ($r in $replacements) {
    if ($content.Contains($r.Old)) {
        $content = $content.Replace($r.Old, $r.New)
        $changed++
        Write-Host "  OK: reemplazado comentario con acento" -ForegroundColor Green
    }
}

# Guardar sin BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($File, $content, $utf8NoBom)

Write-Host ""
Write-Host "  $changed comentario(s) corregido(s)" -ForegroundColor Cyan
Write-Host ""
Write-Host '  git add "src\app\partes\[id]\page.tsx"'
Write-Host '  git commit -m "fix: quitar acentos en comentarios - SWC falla con UTF-8 no-ASCII antes del return"'
Write-Host '  git push'
