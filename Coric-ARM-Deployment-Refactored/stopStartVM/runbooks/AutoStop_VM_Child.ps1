<#
.SYNOPSIS  
 Script for deleting the resource groups
.DESCRIPTION  
 Script for deleting the resource groups
.EXAMPLE  
.\AutoStop_VM_Child.ps1 
Version History  
v1.0 - Initial Release  
#>

param ( 
    [object]$WebhookData
)

if ($WebhookData -ne $null) {  
    # Collect properties of WebhookData.
    $WebhookName    =   $WebhookData.WebhookName
    $WebhookBody    =   $WebhookData.RequestBody
    $WebhookHeaders =   $WebhookData.RequestHeader
       
    # Information on the webhook name that called This
    Write-Output "This runbook was started from webhook $WebhookName."
       
    # Obtain the WebhookBody containing the AlertContext
    $WebhookBody = (ConvertFrom-Json -InputObject $WebhookBody)
    Write-Output "`nWEBHOOK BODY"
    Write-Output "============="
    Write-Output $WebhookBody
       
    # Obtain the AlertContext
    $AlertContext = [object]$WebhookBody.context

    # Some selected AlertContext information
    Write-Output "`nALERT CONTEXT DATA"
    Write-Output "==================="
    Write-Output $AlertContext.name
    Write-Output $AlertContext.subscriptionId
    Write-Output $AlertContext.resourceGroupName
    Write-Output $AlertContext.resourceName
    Write-Output $AlertContext.resourceType
    Write-Output $AlertContext.resourceId
    Write-Output $AlertContext.timestamp

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

        	#Flag for CSP subs
            $enableClassicVMs = Get-AutomationVariable -Name 'External_EnableClassicVMs'

            if($enableClassicVMs)
            {    
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

	Write-Output "~Attempted the stop action on the following VM(s):"

    if(($AlertContext.resourceType -eq "microsoft.classiccompute/virtualmachines") -and ($enableClassicVMs))
	{
		$currentVM = Get-AzureVM | where Name -Like $AlertContext.resourceName
		if ($currentVM.Count -ge 1)
		{	
            Write-Output "~$($currentVM.Name)"
			Write-Verbose "Stopping VM $($currentVM.Name) using Classic"
			$Status = Stop-AzureVM -Name $currentVM.Name -ServiceName $currentVM.ServiceName -Force			
		}
	}
    else 
	{
        Write-Output "~$($AlertContext.resourceName)"
		Write-Verbose "Stopping VM $($AlertContext.resourceName) using Resource Manager"
		$Status = Stop-AzureRmVM -Name $AlertContext.resourceName -ResourceGroupName $AlertContext.resourceGroupName -Force
	}
    
    if($Status -eq $null)
    {
        Write-Output "Error occured while stopping the Virtual Machine. $AlertContext.resourceName"
    }
    else
    {
       Write-Output "Successfully stopped the VM $AlertContext.resourceName"
    }
}
else 
{
    Write-Error "This runbook is meant to only be started from a webhook." 
}
