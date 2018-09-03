$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$netBiosDomain = $env:COMPUTERNAME -split '-' | Select -First 1
$batchFilePath = "\\{0}-dc01\ScriptLibrary\Install\Rapid7\Agent\agentInstaller-x86_64.bat" -f $netBiosDomain
$jsonFilePath  = "\\{0}-dc01\ScriptLibrary\Install\Rapid7\Agent\files\config.json" -f $netBiosDomain

# Replace domainname token in config.json as needed
(Get-Content -Path $jsonFilePath) | % { $_ -Replace '%DOMAINNAME%', $netBiosDomain } | Out-File -FilePath $jsonFilePath

# Install Rapid7 Agent
& $batchFilePath
