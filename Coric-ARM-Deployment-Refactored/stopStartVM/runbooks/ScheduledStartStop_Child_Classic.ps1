<#
.SYNOPSIS  
 Wrapper script for start & stop Classic VM's
.DESCRIPTION  
 Wrapper script for start & stop Classic VM's
.EXAMPLE  
.\ScheduledStartStop_Child_Classic.ps1 -VMName "Value1" -Action "Value2" -ResourceGroupName "Value3" 
Version History  
v1.0   - Initial Release  
#>
param(
[string]$VMName = $(throw "Value for VMName is missing"),
[String]$Action = $(throw "Value for Action is missing"),
[String]$ResourceGroupName = $(throw "Value for ResourceGroupName is missing")
)

[string] $FailureMessage = "Failed to execute the command"
[int] $RetryCount = 3 
[int] $TimeoutInSecs = 20
$RetryFlag = $true
$Attempt = 1
do
{
    #----------------------------------------------------------------------------------
    #---------------------LOGIN TO AZURE AND SELECT THE SUBSCRIPTION-------------------
    #----------------------------------------------------------------------------------

    Write-Output "Logging into Azure subscription using ARM cmdlets..."    
    $connectionName = "AzureRunAsConnection"
    try
    {
        # Get the connection "AzureRunAsConnection "
        $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

        Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
        
        Write-Output "Successfully logged into Azure subscription using ARM cmdlets..."

        
        Write-Output "Logging into Azure subscription using Classic cmdlets..."
        #----- Initialize the Azure subscription we will be working against for Classic Azure resources-----
        Write-Output "Authenticating Classic RunAs account"
        $ConnectionAssetName = "AzureClassicRunAsConnection"
        $connection = Get-AutomationConnection -Name $connectionAssetName        
        Write-Output "Get connection asset: $ConnectionAssetName" -Verbose
        $Conn = Get-AutomationConnection -Name $ConnectionAssetName
        if ($Conn -eq $null)
        {
            throw "Could not retrieve connection asset: $ConnectionAssetName. Make sure that this asset exists in the Automation account."
        }
        $CertificateAssetName = $Conn.CertificateAssetName
        Write-Output "Getting the certificate: $CertificateAssetName" -Verbose
        $AzureCert = Get-AutomationCertificate -Name $CertificateAssetName
        if ($AzureCert -eq $null)
        {
            throw "Could not retrieve certificate asset: $CertificateAssetName. Make sure that this asset exists in the Automation account."
        }
        Write-Output "Authenticating to Azure with certificate." -Verbose
        Set-AzureSubscription -SubscriptionName $Conn.SubscriptionName -SubscriptionId $Conn.SubscriptionID -Certificate $AzureCert 
        Select-AzureSubscription -SubscriptionId $Conn.SubscriptionID

        Write-Output "Successfully logged into Azure subscription using Classic cmdlets..."

        Write-Output "VM action is : $($Action)"
    
        if ($Action.Trim().ToLower() -eq "stop")
        {
            Write-Output "Stopping VM $($VMName) using Classic"

            $Status = Stop-AzureVM -Name $VMName -ServiceName $ResourceGroupName -Force

            if ($Status.OperationStatus -ne 'Succeeded') 
            { 
                # The VM failed to stop, so send notice 
                Write-Output ($VMName + " failed to stop") 
            } 
            else 
            { 
                # The VM stopped, so send notice 
                Write-Output ($VMName + " has been stopped") 
            } 
        }
        elseif($Action.Trim().ToLower() -eq "start")
        {
            Write-Output "Starting VM $($VMName) using Classic"

            $Status = Start-AzureVM -Name $VMName -ServiceName $ResourceGroupName

            if ($Status.OperationStatus -ne 'Succeeded') 
            { 
                # The VM failed to start, so send notice 
                Write-Output ($VMName + " failed to start") 
            } 
            else 
            { 
                # The VM started, so send notice 
                Write-Output ($VMName + " has been started") 
            } 
        }

        $RetryFlag = $false
    }
    catch 
    {
        if (!$servicePrincipalConnection)
        {
            $ErrorMessage = "Connection $connectionName not found."

            $RetryFlag = $false

            throw $ErrorMessage
        }

        if ($Attempt -gt $RetryCount) 
        {
            Write-Output "$FailureMessage! Total retry attempts: $RetryCount"

            Write-Output "[Error Message] $($_.exception.message) `n"

            $RetryFlag = $false
        }
        else 
        {
            Write-Output "[$Attempt/$RetryCount] $FailureMessage. Retrying in $TimeoutInSecs seconds..."

            Start-Sleep -Seconds $TimeoutInSecs

            $Attempt = $Attempt + 1
        }   
    }
}
while($RetryFlag)
