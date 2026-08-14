<#
Push-to-remote helper that prompts for GitHub credentials (username + PAT) and uses git credential to approve them for the push.
Usage (PowerShell, run from repo root):
  .\push-with-credentials.ps1 -RemoteUrl 'https://github.com/owner/repo.git' -Branch 'master' -ForceWithLease
#>
param(
	[Parameter(Mandatory=$true)][string]$RemoteUrl,
	[Parameter(Mandatory=$false)][string]$Branch = 'master',
	[switch]$ForceWithLease
)

function Ensure-Git {
	if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
		Write-Error 'git is not available in PATH. Install Git for Windows and try again.'
		exit 1
	}
}

function Get-HostFromUrl([string]$url){
	try { return ([uri]$url).Host } catch { return 'github.com' }
}

Ensure-Git

Write-Host "Remote: $RemoteUrl"
Write-Host "Branch: $Branch"

# Stage & commit
git add -A
$st = git status --porcelain
if ($st) {
	$msg = Read-Host 'Enter commit message (or press Enter to use default)'
	if ([string]::IsNullOrWhiteSpace($msg)) { $msg = 'Update from local workspace' }
	git commit -m "$msg"
} else {
	Write-Host 'No changes to commit.'
}

# Set origin
try { git remote remove origin 2>$null } catch {}
git remote add origin $RemoteUrl

# Ensure credential helper
git config --global credential.helper manager-core 2>$null

# Prompt for credentials (use GitHub username and PAT as password)
$cred = Get-Credential -Message 'Enter GitHub credentials (username and PAT as password)'
if (-not $cred) { Write-Error 'No credentials provided'; exit 1 }

# Approve credential to credential helper
$host = Get-HostFromUrl $RemoteUrl
$protocol = if ($RemoteUrl.StartsWith('https:', [System.StringComparison]::InvariantCultureIgnoreCase)) { 'https' } else { 'https' }
$input = "protocol=$protocol`nhost=$host`nusername=$($cred.UserName)`npassword=$($cred.GetNetworkCredential().Password)`n"
$input | git credential approve

# Push
$pushCmd = 'git push origin ' + $Branch
if ($ForceWithLease.IsPresent) { $pushCmd = 'git push --force-with-lease origin ' + $Branch }
Write-Host "Running: $pushCmd"
Invoke-Expression $pushCmd
$exitCode = $LASTEXITCODE

# Optionally remove cached credential
# $input | git credential reject

if ($exitCode -ne 0) {
	Write-Error "Push failed with exit code $exitCode"
	exit $exitCode
}

Write-Host 'Push succeeded.'
