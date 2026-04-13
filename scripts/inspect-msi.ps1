# One-off helper: compute SHA256 + extract ProductCode from a built MSI.
# Used once to seed the winget manifest for the first submission.
param([Parameter(Mandatory=$true)][string]$Msi)

$ErrorActionPreference = 'Stop'

$full = (Resolve-Path $Msi).Path
$hash = (Get-FileHash -Algorithm SHA256 $full).Hash
Write-Host "SHA256: $hash"

$installer = New-Object -ComObject WindowsInstaller.Installer
$db = $installer.GetType().InvokeMember('OpenDatabase','InvokeMethod',$null,$installer,@($full,0))
$view = $db.GetType().InvokeMember('OpenView','InvokeMethod',$null,$db,@("SELECT Value FROM Property WHERE Property='ProductCode'"))
$view.GetType().InvokeMember('Execute','InvokeMethod',$null,$view,$null) | Out-Null
$record = $view.GetType().InvokeMember('Fetch','InvokeMethod',$null,$view,$null)
$productCode = $record.GetType().InvokeMember('StringData','GetProperty',$null,$record,@(1))
Write-Host "ProductCode: $productCode"
