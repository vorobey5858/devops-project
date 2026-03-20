param(
  [string]$KubeconfigPath = "",
  [switch]$SkipClusterCheck,
  [switch]$SkipFoundation,
  [switch]$SkipObservability,
  [switch]$SkipSecurityBaseline,
  [switch]$SkipGitOps,
  [switch]$SkipValidation,
  [switch]$EnableSignaturePolicy
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$bootstrapRoot = Join-Path $repoRoot "bootstrap"
$localSecretsRoot = Join-Path $repoRoot ".secrets"

if ($KubeconfigPath) {
  $env:KUBECONFIG = (Resolve-Path $KubeconfigPath).Path
}

function Assert-Command {
  param([string]$Name)

  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' is not installed or is not available in PATH."
  }
}

function Ensure-Directory {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    $null = New-Item -ItemType Directory -Path $Path -Force
  }
}

function Invoke-CommandChecked {
  param(
    [string]$FilePath,
    [string[]]$Arguments
  )

  Write-Host ">" $FilePath ($Arguments -join " ")
  & $FilePath @Arguments

  if ($LASTEXITCODE -ne 0) {
    throw "Command failed: $FilePath $($Arguments -join ' ')"
  }
}

function Ensure-Namespace {
  param([string]$Name)

  $null = & kubectl get namespace $Name 2>$null
  if ($LASTEXITCODE -ne 0) {
    Invoke-CommandChecked "kubectl" @("create", "namespace", $Name)
  }
}

function New-RandomSecretValue {
  param([int]$ByteCount = 24)

  $buffer = New-Object byte[] $ByteCount
  [System.Security.Cryptography.RandomNumberGenerator]::Fill($buffer)
  return [Convert]::ToHexString($buffer).ToLowerInvariant()
}

function Get-LocalSecretValue {
  param(
    [string]$FileName,
    [string]$EnvironmentVariable,
    [int]$ByteCount = 24
  )

  Ensure-Directory -Path $localSecretsRoot

  $environmentValue = [Environment]::GetEnvironmentVariable($EnvironmentVariable)
  if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
    return $environmentValue.Trim()
  }

  $path = Join-Path $localSecretsRoot $FileName
  if (Test-Path $path) {
    $existingValue = (Get-Content -Raw $path).Trim()
    if (-not [string]::IsNullOrWhiteSpace($existingValue)) {
      return $existingValue
    }
  }

  $generatedValue = New-RandomSecretValue -ByteCount $ByteCount
  Set-Content -Path $path -Value $generatedValue -NoNewline
  Write-Host "Generated local secret at $path"
  return $generatedValue
}

function Apply-GenericSecret {
  param(
    [string]$Namespace,
    [string]$Name,
    [hashtable]$StringData
  )

  Ensure-Namespace -Name $Namespace

  $arguments = @(
    "create", "secret", "generic", $Name,
    "--namespace", $Namespace,
    "--dry-run=client",
    "-o", "yaml"
  )

  foreach ($entry in $StringData.GetEnumerator()) {
    $arguments += "--from-literal=$($entry.Key)=$($entry.Value)"
  }

  Write-Host ">" "kubectl" ($arguments -join " ")
  $manifest = & kubectl @arguments

  if ($LASTEXITCODE -ne 0) {
    throw "Command failed: kubectl $($arguments -join ' ')"
  }

  $manifest | & kubectl apply -f -

  if ($LASTEXITCODE -ne 0) {
    throw "Command failed: kubectl apply -f -"
  }
}

function Ensure-GrafanaAdminSecret {
  $password = Get-LocalSecretValue -FileName "grafana-admin-password.txt" -EnvironmentVariable "GRAFANA_ADMIN_PASSWORD"
  Apply-GenericSecret -Namespace "monitoring" -Name "grafana-admin-credentials" -StringData @{
    "admin-user" = "admin"
    "admin-password" = $password
  }
}

function Ensure-DemoServiceSecrets {
  $apiGatewaySecret = @{
    "JWT_SHARED_SECRET" = Get-LocalSecretValue -FileName "api-gateway-jwt-shared-secret.txt" -EnvironmentVariable "API_GATEWAY_JWT_SHARED_SECRET"
    "UPSTREAM_API_TOKEN" = Get-LocalSecretValue -FileName "api-gateway-upstream-api-token.txt" -EnvironmentVariable "API_GATEWAY_UPSTREAM_API_TOKEN"
  }

  $ordersSecret = @{
    "DB_USERNAME" = "orders"
    "DB_PASSWORD" = Get-LocalSecretValue -FileName "orders-db-password.txt" -EnvironmentVariable "ORDERS_DB_PASSWORD"
  }

  $paymentsSecret = @{
    "PROVIDER_API_KEY" = Get-LocalSecretValue -FileName "payments-provider-api-key.txt" -EnvironmentVariable "PAYMENTS_PROVIDER_API_KEY"
    "PROVIDER_API_SECRET" = Get-LocalSecretValue -FileName "payments-provider-api-secret.txt" -EnvironmentVariable "PAYMENTS_PROVIDER_API_SECRET"
  }

  foreach ($namespace in @("demo-dev", "demo-preview", "demo-stage")) {
    Apply-GenericSecret -Namespace $namespace -Name "api-gateway-secrets" -StringData $apiGatewaySecret
    Apply-GenericSecret -Namespace $namespace -Name "orders-service-secrets" -StringData $ordersSecret
    Apply-GenericSecret -Namespace $namespace -Name "payments-service-secrets" -StringData $paymentsSecret
  }
}

function Install-HelmRelease {
  param(
    [string]$ReleaseName,
    [string]$Chart,
    [string]$Namespace,
    [string]$ValuesFile
  )

  Ensure-Namespace -Name $Namespace

  Invoke-CommandChecked "helm" @(
    "upgrade", "--install", $ReleaseName, $Chart,
    "--namespace", $Namespace,
    "--values", $ValuesFile
  )
}

function Wait-Deployments {
  param([string]$Namespace)

  $deployments = & kubectl -n $Namespace get deployment -o name 2>$null
  if (-not $deployments) {
    return
  }

  foreach ($deployment in $deployments) {
    Invoke-CommandChecked "kubectl" @("-n", $Namespace, "rollout", "status", $deployment, "--timeout=5m")
  }
}

function Apply-Manifest {
  param([string]$RelativePath)

  Invoke-CommandChecked "kubectl" @("apply", "-f", (Join-Path $repoRoot $RelativePath))
}

function Get-OriginUrl {
  $origin = & git -C $repoRoot remote get-url origin 2>$null
  if ($LASTEXITCODE -ne 0) {
    return $null
  }

  return $origin.Trim()
}

Assert-Command -Name "git"
Assert-Command -Name "kubectl"
Assert-Command -Name "helm"

$originUrl = Get-OriginUrl

if (-not $SkipGitOps -and [string]::IsNullOrWhiteSpace($originUrl)) {
  throw "GitOps bootstrap requires a configured 'origin' remote."
}

if (-not $SkipClusterCheck) {
  Invoke-CommandChecked "kubectl" @("cluster-info")
}

Invoke-CommandChecked "helm" @("repo", "add", "ingress-nginx", "https://kubernetes.github.io/ingress-nginx")
Invoke-CommandChecked "helm" @("repo", "add", "jetstack", "https://charts.jetstack.io")
Invoke-CommandChecked "helm" @("repo", "add", "argo", "https://argoproj.github.io/argo-helm")
Invoke-CommandChecked "helm" @("repo", "add", "prometheus-community", "https://prometheus-community.github.io/helm-charts")
Invoke-CommandChecked "helm" @("repo", "add", "grafana", "https://grafana.github.io/helm-charts")
Invoke-CommandChecked "helm" @("repo", "add", "kyverno", "https://kyverno.github.io/kyverno")
Invoke-CommandChecked "helm" @("repo", "update")

if (-not $SkipFoundation) {
  Install-HelmRelease -ReleaseName "ingress-nginx" -Chart "ingress-nginx/ingress-nginx" -Namespace "ingress-nginx" -ValuesFile (Join-Path $bootstrapRoot "helm-values\ingress-nginx-values.yaml")
  Wait-Deployments -Namespace "ingress-nginx"

  Install-HelmRelease -ReleaseName "cert-manager" -Chart "jetstack/cert-manager" -Namespace "cert-manager" -ValuesFile (Join-Path $bootstrapRoot "helm-values\cert-manager-values.yaml")
  Wait-Deployments -Namespace "cert-manager"

  Install-HelmRelease -ReleaseName "argocd" -Chart "argo/argo-cd" -Namespace "argocd" -ValuesFile (Join-Path $bootstrapRoot "helm-values\argocd-values.yaml")
  Wait-Deployments -Namespace "argocd"

  Install-HelmRelease -ReleaseName "kyverno" -Chart "kyverno/kyverno" -Namespace "kyverno" -ValuesFile (Join-Path $bootstrapRoot "helm-values\kyverno-values.yaml")
  Wait-Deployments -Namespace "kyverno"

  Install-HelmRelease -ReleaseName "argo-rollouts" -Chart "argo/argo-rollouts" -Namespace "argo-rollouts" -ValuesFile (Join-Path $bootstrapRoot "helm-values\argo-rollouts-values.yaml")
  Wait-Deployments -Namespace "argo-rollouts"
}

if (-not $SkipObservability) {
  Ensure-GrafanaAdminSecret
  Install-HelmRelease -ReleaseName "kube-prometheus-stack" -Chart "prometheus-community/kube-prometheus-stack" -Namespace "monitoring" -ValuesFile (Join-Path $bootstrapRoot "helm-values\kube-prometheus-stack-values.yaml")
  Wait-Deployments -Namespace "monitoring"

  Install-HelmRelease -ReleaseName "loki" -Chart "grafana/loki" -Namespace "logging" -ValuesFile (Join-Path $bootstrapRoot "helm-values\loki-values.yaml")

  Apply-Manifest -RelativePath "platform-core\kubernetes\observability\grafana-dashboard-commerce-platform.yaml"
  Apply-Manifest -RelativePath "platform-core\kubernetes\observability\monitoring-ui-ingresses.yaml"
}

if (-not $SkipSecurityBaseline) {
  Apply-Manifest -RelativePath "secure-delivery\policies\kyverno\disallow-latest-tag.yaml"
  Apply-Manifest -RelativePath "secure-delivery\policies\kyverno\require-resources.yaml"
  Apply-Manifest -RelativePath "secure-delivery\policies\kyverno\require-security-context.yaml"

  if ($EnableSignaturePolicy) {
    Apply-Manifest -RelativePath "secure-delivery\policies\kyverno\require-signed-images.yaml"
  }
}

if (-not $SkipGitOps) {
  Apply-Manifest -RelativePath "platform-core\kubernetes\namespaces\demo-environments.yaml"
  Ensure-DemoServiceSecrets
  if (-not $SkipSecurityBaseline) {
    Apply-Manifest -RelativePath "secure-delivery\argo-rollouts\analysis-templates.yaml"
  }
  Apply-Manifest -RelativePath "platform-core\kubernetes\argocd\project-platform.yaml"
  Apply-Manifest -RelativePath "platform-core\kubernetes\argocd\app-demo-services.yaml"
}

if (-not $SkipValidation) {
  $validationArgs = @()
  if ($SkipFoundation) { $validationArgs += "-SkipFoundation" }
  if ($SkipObservability) { $validationArgs += "-SkipObservability" }
  if ($SkipSecurityBaseline) { $validationArgs += "-SkipSecurityBaseline" }
  if ($SkipGitOps) { $validationArgs += "-SkipGitOps" }

  & (Join-Path $PSScriptRoot "validate-local.ps1") @validationArgs
}
