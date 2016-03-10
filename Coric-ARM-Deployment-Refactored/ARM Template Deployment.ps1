$Deployment = 'EncryptionDeployment'
$TemplateURI = "https://raw.githubusercontent.com/AndyHerb/Azure-Resource-Group/master/Coric-ARM-Deployment/coricAzureDeploy.json"
$ParameterFile = 'C:\Users\awh\OneDrive\AHPersonal\GitHub\Azure-Resource-Group\Coric-ARM-Deployment\coricAzureParameters.json'

Try
{
    $resGroup = Get-AzureRmResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue;
}
Catch [System.ArgumentException]
{
    Write-Verbose "Couldn't find resource group:  ($ResourceGroup)";
    $resGroup = $null;
}
    
#Create a new resource group if it doesn't exist
if (-not $resGroup)
{
    Write-Verbose "Creating new resource group:  ($ResourceGroup)";
    $resGroup = New-AzureRmResourceGroup -Name $ResourceGroup -Location $Location;
    Write-Output "Created a new resource group named $ResourceGroup to place keyVault";
}


New-AzureRmResourceGroupDeployment `
        -Name $Deployment `
        -ResourceGroupName $ResourceGroup `
        -TemplateUri $TemplateURI `
        -TemplateParameterFile $ParameterFile

Get-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroup -Name $Deployment

(Get-AzureRmResourceGroupDeploymentOperation -DeploymentName $Deployment -ResourceGroupName $ResourceGroup).Properties[0].TargetResource | FL * -Force


Get-AzureRmResource -ResourceGroupName cor0014EncryptionTest -ResourceType Microsoft.Compute/virtualMachines/InstanceView -ResourceName vmcor0014-dc01 -ApiVersion '2015-06-15'

(Get-AzureRmResource -ResourceGroupName cor0014EncryptionTest -ResourceType Microsoft.Compute/virtualMachines/extensions -ResourceName vmcor0014-dc01/BitLocker/instanceView -ApiVersion 2015-06-15).Properties.Settings


$KeyVaultName = 'kvtestclient'
$rgname = 'kvtest'
$SecretName = 'aadappcertificate'
$keyEncryptionKeyName = 'diskencryptionkek'
Get-AzureRmKeyVault -VaultName $KeyVaultName -ResourceGroupName $rgname
(Get-AzureKeyVaultKey -VaultName $KeyVaultName -Name $keyEncryptionKeyName).Key.kid


$aadAppName = 'Bit Locker Encryption'
$SvcPrincipals = (Get-AzureRmADServicePrincipal -SearchString $aadAppName)
$aadClientID = $SvcPrincipals[0].ApplicationId;
$aadClientID