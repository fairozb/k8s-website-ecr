# ============================================================
# Quick verification that the website is live.
# Polls the NodePort URL until it responds (or times out).
# Usage: .\verify.ps1
# ============================================================
$ErrorActionPreference = "Stop"

$Url = terraform output -raw website_url
if (-not $Url) { throw "Could not read website_url. Run 'terraform apply' first." }

Write-Host "Checking $Url (first boot can take a few minutes)..."

for ($i = 1; $i -le 40; $i++) {
  try {
    $resp = Invoke-WebRequest -Uri $Url -TimeoutSec 5 -UseBasicParsing
    if ($resp.StatusCode -eq 200) {
      Write-Host "SUCCESS ($($resp.StatusCode)). Website is live at $Url"
      exit 0
    }
  }
  catch {
    Write-Host "  attempt $i/40 - not ready yet, waiting 15s..."
    Start-Sleep -Seconds 15
  }
}

Write-Host "Timed out. SSH in and check: sudo tail -n 100 /var/log/user-data.log"
exit 1
