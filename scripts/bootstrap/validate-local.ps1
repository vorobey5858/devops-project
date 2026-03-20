param(
  [int]$TimeoutSeconds = 300,
  [int]$PollIntervalSeconds = 5,
  [switch]$SkipFoundation,
  [switch]$SkipObservability,
  [switch]$SkipSecurityBaseline,
  [switch]$SkipGitOps
)

$ErrorActionPreference = "Stop"

function Wait-Until {
  param(
    [scriptblock]$Test,
    [string]$Description
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

  while ((Get-Date) -lt $deadline) {
    if (& $Test) {
      return
    }

    Start-Sleep -Seconds $PollIntervalSeconds
  }

  throw "$Description was not observed within $TimeoutSeconds seconds."
}

function Assert-Namespace {
  param([string]$Name)

  Wait-Until -Description "Namespace '$Name'" -Test {
    $null = & kubectl get namespace $Name 2>$null
    return ($LASTEXITCODE -eq 0)
  }
}

function Assert-Deployment {
  param(
    [string]$Namespace,
    [string]$Name
  )

  Wait-Until -Description "Deployment '$Namespace/$Name'" -Test {
    $null = & kubectl -n $Namespace get deployment $Name 2>$null
    return ($LASTEXITCODE -eq 0)
  }
}

function Assert-Resource {
  param(
    [string]$Namespace,
    [string]$Type,
    [string]$Name
  )

  Wait-Until -Description "$Type '$Namespace/$Name'" -Test {
    $null = & kubectl -n $Namespace get $Type $Name 2>$null
    return ($LASTEXITCODE -eq 0)
  }
}

function Assert-Application {
  param([string]$Name)

  Wait-Until -Description "ArgoCD Application '$Name'" -Test {
    $null = & kubectl -n argocd get application $Name 2>$null
    return ($LASTEXITCODE -eq 0)
  }
}

$requiredNamespaces = @()

if (-not $SkipGitOps) {
  $requiredNamespaces += @(
    "demo-dev",
    "demo-preview",
    "demo-stage"
  )
}

if (-not $SkipFoundation) {
  $requiredNamespaces += @(
    "argocd",
    "argo-rollouts",
    "cert-manager",
    "ingress-nginx",
    "kyverno"
  )
}

if (-not $SkipObservability) {
  $requiredNamespaces += @(
    "logging",
    "monitoring"
  )
}

foreach ($namespace in $requiredNamespaces) {
  Assert-Namespace -Name $namespace
}

if (-not $SkipFoundation) {
  Assert-Deployment -Namespace "ingress-nginx" -Name "ingress-nginx-controller"
  Assert-Deployment -Namespace "cert-manager" -Name "cert-manager"
  Assert-Deployment -Namespace "argocd" -Name "argocd-server"
  Assert-Deployment -Namespace "kyverno" -Name "kyverno-admission-controller"
  Assert-Deployment -Namespace "argo-rollouts" -Name "argo-rollouts"
}

if (-not $SkipObservability) {
  Assert-Deployment -Namespace "monitoring" -Name "kube-prometheus-stack-operator"
  Assert-Resource -Namespace "monitoring" -Type "secret" -Name "grafana-admin-credentials"
}

if ((-not $SkipSecurityBaseline) -and (-not $SkipGitOps)) {
  Assert-Resource -Namespace "demo-stage" -Type "analysistemplate" -Name "success-rate"
  Assert-Resource -Namespace "demo-stage" -Type "analysistemplate" -Name "p95-latency"
  Assert-Resource -Namespace "demo-stage" -Type "analysistemplate" -Name "restart-rate"
}

if (-not $SkipGitOps) {
  $requiredApplications = @(
    "demo-services",
    "demo-environments",
    "api-gateway-dev",
    "api-gateway-preview",
    "api-gateway-stage",
    "orders-service-dev",
    "orders-service-preview",
    "orders-service-stage",
    "payments-service-dev",
    "payments-service-preview",
    "payments-service-stage"
  )

  foreach ($application in $requiredApplications) {
    Assert-Application -Name $application
  }

  foreach ($namespace in @("demo-dev", "demo-preview", "demo-stage")) {
    Assert-Resource -Namespace $namespace -Type "secret" -Name "api-gateway-secrets"
    Assert-Resource -Namespace $namespace -Type "secret" -Name "orders-service-secrets"
    Assert-Resource -Namespace $namespace -Type "secret" -Name "payments-service-secrets"
  }

  Assert-Resource -Namespace "demo-stage" -Type "rollout" -Name "api-gateway"
  Assert-Resource -Namespace "demo-stage" -Type "rollout" -Name "orders-service"
  Assert-Resource -Namespace "demo-stage" -Type "rollout" -Name "payments-service"
}

Write-Host "Local bootstrap validation completed successfully."
