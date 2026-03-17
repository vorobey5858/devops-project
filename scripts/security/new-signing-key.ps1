param(
    [string]$OutputDirectory = ".bootstrap/cosign"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$targetDirectory = Join-Path $repoRoot $OutputDirectory
$privateKeyPath = Join-Path $targetDirectory "cosign.key"
$publicKeyPath = Join-Path $targetDirectory "cosign.pub"

if (-not (Test-Path $targetDirectory)) {
    New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
}

@'
from pathlib import Path
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
import sys

target = Path(sys.argv[1])
private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

(target / "cosign.key").write_bytes(
    private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
)

(target / "cosign.pub").write_bytes(
    private_key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
)
'@ | python - $targetDirectory

Write-Host "Generated local signing key pair:"
Write-Host "  Private: $privateKeyPath"
Write-Host "  Public : $publicKeyPath"
Write-Host "Copy the public key into secure-delivery/policies/kyverno/require-signed-images.yaml if you want a local enforcement key."
