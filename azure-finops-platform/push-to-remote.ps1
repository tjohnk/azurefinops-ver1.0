# Push current repository to specified remote and branch (HTTPS)
# Usage: Open PowerShell, cd to repo root, then: .\push-to-remote.ps1 -RemoteUrl "https://github.com/tjohnk/azure-estate-finops-intelligence-platform-pack" -Branch "master"
param(
	[Parameter(Mandatory=$true)][string]$RemoteUrl,
	[Parameter(Mandatory=$false)][string]$Branch = "master",
	[switch]$ForceWithLease
)

Write-Host "Repository path: $(Get-Location)"
Write-Host "Remote: $RemoteUrl"
Write-Host "Branch: $Branch"

# Ensure git is available
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
	Write-Error "git not found in PATH. Install Git for Windows and try again."
	exit 1
}

# Show status
git status

# Stage and commit any changes
Write-Host "Staging changes..."
git add -A

$st = git status --porcelain
if ($st) {
	$msg = Read-Host "Enter commit message (or press Enter to use default)"
	if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "Update from local workspace" }
	git commit -m "$msg"
} else {
	Write-Host "No changes to commit."
}

# Set remote URL
Write-Host "Setting remote origin to $RemoteUrl"
git remote remove origin 2>$null | Out-Null
git remote add origin $RemoteUrl

# Configure credential helper (Windows)
try { git config --global credential.helper manager-core } catch { }

# Push
$pushCmd = "git push origin $Branch"
if ($ForceWithLease) { $pushCmd = "git push --force-with-lease origin $Branch" }

Write-Host "About to run: $pushCmd"
Write-Host "You will be prompted for credentials if required (use GitHub username and PAT for HTTPS)."

Invoke-Expression $pushCmd

if ($LASTEXITCODE -ne 0) {
	Write-Error "Push failed. See output above. If you have SSL or proxy errors, configure Git proxy or use SSH per README."
	exit $LASTEXITCODE
}

Write-Host "Push succeeded."