#Requires -Version 5.1
# fix-partes-comentario-jsx.ps1
# Causa real y definitiva del error de compilacion:
# En la linea "{/* Observaciones */" faltaba el "}" de cierre del comentario JSX.
# Correcto: {/* Observaciones */}
# El parser de SWC trataba todo lo siguiente como contenido del comentario
# hasta encontrar el proximo }, rompiendo el arbol JSX.

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath

$File = Join-Path $RepoPath "src\app\partes\[id]\page.tsx"
Write-Host "" ; Write-Host "==> Fix comentario JSX mal cerrado" -ForegroundColor Cyan

$content = [System.IO.File]::ReadAllText($File, [System.Text.Encoding]::UTF8)

# Fix 1: comentario JSX sin } de cierre
$old1 = "        {/* Observaciones */" + "`n" + "        <div className=`"card p-6`">"
$new1 = "        {/* Observaciones */}" + "`n" + "        <div className=`"card p-6`">"
if ($content.Contains($old1)) {
    $content = $content.Replace($old1, $new1)
    Write-Host "  OK: comentario Observaciones corregido" -ForegroundColor Green
} else {
    Write-Host "  WARN: patron no encontrado - puede ya estar corregido" -ForegroundColor Yellow
}

# Fix 2: quitar la } extra del final si existe (} doble al final)
$trimmed = $content.TrimEnd()
if ($trimmed.EndsWith("`n}") -and $trimmed.EndsWith("`n}`n}")) {
    $content = $trimmed.Substring(0, $trimmed.LastIndexOf("`n}")) + "`n"
    Write-Host "  OK: } extra eliminada del final" -ForegroundColor Green
}

# Fix 3: quitar acento en comentario si queda
$content = $content.Replace(
    "resolver la obra segun su asignacion de ese d" + [char]0x00ED + "a",
    "resolver la obra segun su asignacion de ese dia"
)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($File, $content, $utf8NoBom)
Write-Host "  OK: archivo guardado" -ForegroundColor Green
Write-Host ""
Write-Host '  git add "src\app\partes\[id]\page.tsx"'
Write-Host '  git commit -m "fix: comentario JSX Observaciones sin cerrar - causa del error de compilacion"'
Write-Host '  git push'
