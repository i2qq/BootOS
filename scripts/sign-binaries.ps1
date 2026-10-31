# ==============================================================================
# BootOS - Digitally Sign Executables with BootOS Developer Certificate
# ==============================================================================
$workspace = Split-Path -Parent $PSScriptRoot
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -like "*BootOS Developer*" } | Select-Object -First 1

if (-not $cert) {
    Write-Error "BootOS Developer certificate not found in Cert:\CurrentUser\My"
    exit 1
}

$exes = Get-ChildItem -Path $workspace -Filter "*.exe" -File
foreach ($exe in $exes) {
    Write-Host "Signing $($exe.Name) with $($cert.Subject)..." -ForegroundColor Cyan
    try {
        Set-AuthenticodeSignature -FilePath $exe.FullName -Certificate $cert | Out-Null
        $sig = Get-AuthenticodeSignature $exe.FullName
        Write-Host "  -> [OK] Signer: $($sig.SignerCertificate.Subject)" -ForegroundColor Green
    } catch {
        Write-Warning "  -> [FAILED] $($_.Exception.Message)"
    }
}
