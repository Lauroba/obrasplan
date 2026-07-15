#Requires -Version 5.1
# fix-partes-upload-galeria.ps1
# Fix galería móvil: el input[type=file] activado con .click() programático
# no abre la galería en iOS/Android — solo la cámara.
# Solución: label que envuelve directamente el input, sin .click() programático.
# El click del usuario va directo al input -> el navegador abre galería correctamente.

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath

$File = Join-Path $RepoPath "src\app\partes\[id]\page.tsx"
Write-Host "" ; Write-Host "==> Fix upload galeria movil" -ForegroundColor Cyan

$content = [System.IO.File]::ReadAllText($File, [System.Text.Encoding]::UTF8)

# Reemplazar boton con .click() programatico por label que envuelve el input
$oldBtn = '            <button onClick={() => { console.log("Click subir"); fileInputRef.current?.click(); }} disabled={uploading} className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-white bg-brand-500 rounded-lg hover:bg-brand-600 disabled:opacity-60">' + "`n" +
          '              {uploading ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Upload className="w-3.5 h-3.5" />}Subir' + "`n" +
          '            </button>'

$newBtn = '            <label className={`flex items-center gap-1 px-3 py-1.5 text-xs font-medium text-white rounded-lg cursor-pointer ${uploading ? "bg-brand-400 opacity-60 pointer-events-none" : "bg-brand-500 hover:bg-brand-600"}`}>' + "`n" +
          '              {uploading ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Upload className="w-3.5 h-3.5" />}Subir' + "`n" +
          '              <input' + "`n" +
          '                type="file"' + "`n" +
          '                multiple' + "`n" +
          '                accept="image/*,.pdf,.doc,.docx,.xls,.xlsx,.txt"' + "`n" +
          '                className="hidden"' + "`n" +
          '                onChange={handleUploadFile}' + "`n" +
          '                disabled={uploading}' + "`n" +
          '              />' + "`n" +
          '            </label>'

if ($content.Contains($oldBtn)) {
    $content = $content.Replace($oldBtn, $newBtn)
    Write-Host "  OK: label envuelve input" -ForegroundColor Green
} else {
    Write-Host "  WARN: patron boton no encontrado" -ForegroundColor Yellow
}

# Quitar input suelto del final si existe
$oldInput = '      {/* Input file fuera de contenedor flex — garantiza galería en iOS/Android */}' + "`n" +
            '      <input' + "`n" +
            '        ref={fileInputRef}' + "`n" +
            '        type="file"' + "`n" +
            '        multiple' + "`n" +
            '        accept="image/*,.pdf,.doc,.docx,.xls,.xlsx,.txt"' + "`n" +
            '        className="hidden"' + "`n" +
            '        onChange={handleUploadFile}' + "`n" +
            '      />'
if ($content.Contains($oldInput)) {
    $content = $content.Replace($oldInput, "")
    Write-Host "  OK: input suelto eliminado" -ForegroundColor Green
}

# Quitar fileInputRef ref (ya no se usa)
$content = $content.Replace("  const fileInputRef = useRef<HTMLInputElement>(null);`n", "")
# Quitar reset del ref en handleUploadFile
$content = $content.Replace('    if (fileInputRef.current) fileInputRef.current.value = "";' + "`n", "")

Write-Host "  OK: fileInputRef limpiado" -ForegroundColor Green

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($File, $content, $utf8NoBom)
Write-Host "  OK: archivo guardado" -ForegroundColor Green

# Verificar
$c2 = [System.IO.File]::ReadAllText($File, [System.Text.Encoding]::UTF8)
$hasLabel = $c2.Contains('label className=') -and $c2.Contains('type="file"')
$noSuelto = -not $c2.Contains('Input file fuera')
$noRef    = -not $c2.Contains('fileInputRef')
if ($hasLabel)  { Write-Host "  OK: label con input" -ForegroundColor Green } else { Write-Host "  ERROR" -ForegroundColor Red }
if ($noSuelto)  { Write-Host "  OK: sin input suelto" -ForegroundColor Green } else { Write-Host "  ERROR" -ForegroundColor Red }
if ($noRef)     { Write-Host "  OK: fileInputRef eliminado" -ForegroundColor Green } else { Write-Host "  WARN: queda fileInputRef" -ForegroundColor Yellow }

Write-Host ""
Write-Host '  git add "src\app\partes\[id]\page.tsx"'
Write-Host '  git commit -m "fix: galeria movil - label envuelve input directo sin .click() programatico"'
Write-Host '  git push'
