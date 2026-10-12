# One-line PowerShell fix to restore official Roblox access
$hostsPath = "$env:windir\System32\drivers\etc\hosts"
if (Test-Path $hostsPath) {
    $cleaned = Get-Content $hostsPath | Where-Object {
        $_ -notmatch "roblox\.com" -and
        $_ -notmatch "rbxcdn\.com" -and
        $_ -notmatch "pekora\.rip" -and
        $_ -notmatch "oldrrt\.xyz" -and
        $_ -notmatch "74\.248\.20\.23"
    }
    Set-Content -Path $hostsPath -Value $cleaned -Force
    Clear-DnsClientCache
    ipconfig /flushdns
    Write-Host "[+] Official Roblox access restored successfully!" -ForegroundColor Green
}
