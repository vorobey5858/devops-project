param(
    [ValidateSet("demo-dev", "demo-preview", "demo-stage")]
    [string]$Namespace = "demo-stage",
    [int]$LocalPort = 18080
)

$ErrorActionPreference = "Stop"

function Wait-RolloutHealthy {
    param(
        [string]$NamespaceName,
        [string]$RolloutName
    )

    $deadline = (Get-Date).AddMinutes(5)
    while ((Get-Date) -lt $deadline) {
        $phase = & kubectl -n $NamespaceName get rollout $RolloutName -o jsonpath="{.status.phase}" 2>$null
        if ($LASTEXITCODE -eq 0 -and $phase -eq "Healthy") {
            return
        }

        Start-Sleep -Seconds 5
    }

    throw "Rollout $NamespaceName/$RolloutName did not become Healthy in time."
}

function Assert-WorkloadReady {
    param(
        [string]$NamespaceName,
        [string]$Name
    )

    $null = & kubectl -n $NamespaceName get rollout $Name 2>$null
    if ($LASTEXITCODE -eq 0) {
        Wait-RolloutHealthy -NamespaceName $NamespaceName -RolloutName $Name
        return
    }

    kubectl -n $NamespaceName rollout status deployment/$Name --timeout=120s | Out-Null
}

Assert-WorkloadReady -NamespaceName $Namespace -Name "api-gateway"
Assert-WorkloadReady -NamespaceName $Namespace -Name "orders-service"
Assert-WorkloadReady -NamespaceName $Namespace -Name "payments-service"

$portForward = Start-Process -FilePath "kubectl" -ArgumentList @("-n", $Namespace, "port-forward", "service/api-gateway", "$LocalPort:8080") -PassThru -WindowStyle Hidden

try {
    Start-Sleep -Seconds 5

    $health = Invoke-RestMethod -Uri "http://127.0.0.1:$LocalPort/health"
    $snapshot = Invoke-RestMethod -Uri "http://127.0.0.1:$LocalPort/api/demo"
    $checkout = Invoke-RestMethod `
        -Method Post `
        -ContentType "application/json" `
        -Uri "http://127.0.0.1:$LocalPort/api/checkout" `
        -Body (@{
            customer_id = "demo-user"
            items = @(
                @{
                    sku = "book-1"
                    quantity = 1
                    unit_price = 19.99
                }
            )
            currency = "USD"
        } | ConvertTo-Json -Depth 5)

    Write-Host "Health: $($health.status)"
    Write-Host "Orders snapshot total: $($snapshot.orders.total_orders)"
    Write-Host "Checkout status: $($checkout.checkout_status)"
}
finally {
    if ($portForward -and -not $portForward.HasExited) {
        Stop-Process -Id $portForward.Id -Force
    }
}
