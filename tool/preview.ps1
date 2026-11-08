<#
  Gera e abre a visualização do Rota Max no navegador, dentro de uma
  moldura de celular. Uso (na pasta do projeto):

      powershell -ExecutionPolicy Bypass -File tool\preview.ps1

  Parâmetros:
    -NoBuild   só serve o que já foi gerado (mais rápido)
    -Port 8080 porta do site local
#>
param(
  [switch]$NoBuild,
  [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$flutter = 'C:\src\flutter\bin\flutter.bat'
$web = Join-Path $root 'build\web'

Set-Location $root

if (-not $NoBuild) {
  Write-Host 'Gerando a versão web do app (leva 1 a 2 minutos)...'
  & $flutter build web -t lib/main_preview.dart --release --no-web-resources-cdn
  if ($LASTEXITCODE -ne 0) { throw 'O build web falhou.' }
}

Copy-Item (Join-Path $PSScriptRoot 'preview\phone.html') (Join-Path $web 'phone.html') -Force

$url = "http://localhost:$Port/phone.html"
Write-Host ''
Write-Host "Rota Max no celular: $url"
Write-Host 'Para parar o site, feche esta janela ou aperte Ctrl+C.'
Start-Process $url
python -m http.server $Port --bind 127.0.0.1 --directory $web
