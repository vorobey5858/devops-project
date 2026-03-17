param(
    [ValidateSet("dev", "preview", "stage")]
    [string]$Environment = "dev",
    [string]$ArchiveDirectory = ".bootstrap\\images",
    [switch]$ImportToK3s
)

$ErrorActionPreference = "Stop"

function Get-ImageTag {
    param([string]$Path)

    $tagLine = Select-String -Path $Path -Pattern 'tag:\s*"(?<tag>[^"]+)"' | Select-Object -First 1
    if (-not $tagLine) {
        throw "Unable to find immutable image tag in $Path"
    }

    return $tagLine.Matches[0].Groups["tag"].Value
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$archiveRoot = Join-Path $repoRoot $ArchiveDirectory

if (-not (Test-Path $archiveRoot)) {
    New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null
}

$k3sCommand = Get-Command "k3s" -ErrorAction SilentlyContinue
$services = @(
    @{ Name = "api-gateway"; Dockerfile = "demo-microservices/services/api-gateway/Dockerfile" },
    @{ Name = "orders-service"; Dockerfile = "demo-microservices/services/orders-service/Dockerfile" },
    @{ Name = "payments-service"; Dockerfile = "demo-microservices/services/payments-service/Dockerfile" }
)

foreach ($service in $services) {
    $tagPath = Join-Path $repoRoot "demo-microservices/services/$($service.Name)/values/$Environment.yaml"
    $tag = Get-ImageTag -Path $tagPath
    $imageRef = "devops/$($service.Name):$tag"

    Write-Host "Building $imageRef"
    docker build `
        --file (Join-Path $repoRoot $service.Dockerfile) `
        --tag $imageRef `
        $repoRoot

    $archivePath = Join-Path $archiveRoot "$($service.Name)-$tag.tar"
    docker save --output $archivePath $imageRef
    Write-Host "Saved archive $archivePath"

    if ($ImportToK3s) {
        if (-not $k3sCommand) {
            throw "k3s is not available in PATH. Run this script on the k3s host or omit -ImportToK3s."
        }

        Write-Host "Importing $imageRef into k3s containerd"
        & $k3sCommand.Source ctr -n k8s.io images import $archivePath

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to import $imageRef into k3s."
        }
    }
}

Write-Host "Image build workflow completed for environment $Environment."
