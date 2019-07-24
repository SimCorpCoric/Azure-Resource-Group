<#
.SYNOPSIS  
 Disable AutoSnooze feature
.DESCRIPTION  
 Disable AutoSnooze feature
.EXAMPLE  
.\AutoStop_Disable.ps1 
Version History  
v1.0   - Initial Release  
#>

# ------------------Execution Entry point ---------------------

[string] $FailureMessage = "Failed to execute the command"
[int] $RetryCount = 3 
[int] $TimeoutInSecs = 20
$RetryFlag = $true
$Attempt = 1
do
{
    Write-Output "Logging into Azure subscription using ARM cmdlets..."
    #-----L O G I N - A U T H E N T I C A T I O N-----
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


try
{
    Write-Output "Performing the AutoSnooze Disable..."

    Write-Output "Collecting all the schedule names for AutoSnooze..."

    #---------Read all the input variables---------------
    $SubId = Get-AutomationVariable -Name 'Internal_AzureSubscriptionId'
    $StartResourceGroupNames = Get-AutomationVariable -Name 'External_Start_ResourceGroupNames'
    $StopResourceGroupNames = Get-AutomationVariable -Name 'External_Stop_ResourceGroupNames'
    $automationAccountName = Get-AutomationVariable -Name 'Internal_AutomationAccountName'
    $aroResourceGroupName = Get-AutomationVariable -Name 'Internal_ResourceGroupName'

    $webhookUri = Get-AutomationVariable -Name 'Internal_AutoSnooze_WebhookUri'
    $scheduleNameforCreateAlert = "Schedule_AutoStop_CreateAlert_Parent"

    Write-Output "Disabling the schedules for AutoSnooze..."

    #Disable the schedule for AutoSnooze
    Set-AzureRmAutomationSchedule -automationAccountName $automationAccountName -Name $scheduleNameforCreateAlert -ResourceGroupName $aroResourceGroupName -IsEnabled $false

    Write-Output "Disabling the alerts on all the VM's configured as per asset variable..."

    if($Action -eq "stop")
    {
        [string[]] $VMRGList = $StopResourceGroupNames -split ","
    }
    
    if($Action -eq "start")
    {
        [string[]] $VMRGList = $StartResourceGroupNames -split ","
    }

    $AzureVMListTemp = $null
    $AzureVMList=@()
    ##Getting VM Details based on RG List or Subscription
    if (($VMRGList -ne $null) -and ($VMRGList -ne "*"))
    {
        foreach($Resource in $VMRGList)
        {
            Write-Output "Validating the resource group name ($($Resource.Trim()))" 
            $checkRGname = Get-AzureRmResourceGroup  $Resource.Trim() -ev notPresent -ea 0  
            if ($checkRGname -eq $null)
            {
                Write-Warning "$($Resource) is not a valid Resource Group Name. Please verify your input."
				Write-Output "$($Resource) is not a valid Resource Group Name. Please verify your input."
            }
            else
            {                   
				#Flag check for CSP subs
                if($enableClassicVMs)
                {
                    # Get classic VM resources in group and record target state for each in table
				    $taggedClassicVMs = Get-AzureRmResource -ResourceGroup $Resource -ResourceType "Microsoft.ClassicCompute/virtualMachines"
				    foreach($vmResource in $taggedClassicVMs)
				    {
					    Write-Output "VM classic location $vmResource.Location"
					    if ($vmResource.ResourceGroupName -Like $Resource)
					    {
						    $AzureVMList += @{Name = $vmResource.Name; Location = $vmResource.Location; ResourceGroupName = $vmResource.ResourceGroupName; Type = "Classic"}
					    }
				    }
				}

				# Get resource manager VM resources in group and record target state for each in table
				$taggedRMVMs = Get-AzureRmResource -ResourceGroup $Resource -ResourceType "Microsoft.Compute/virtualMachines"
				foreach($vmResource in $taggedRMVMs)
				{
					if ($vmResource.ResourceGroupName -Like $Resource)
					{
						$AzureVMList += @{Name = $vmResource.Name; Location = $vmResource.Location; ResourceGroupName = $vmResource.ResourceGroupName; Type = "ResourceManager"}
					}
				}
            }
        }
    } 
    else
    {
        Write-Output "Getting all the VM's from the subscription..."  
       $ResourceGroups = Get-AzureRmResourceGroup 
		foreach ($ResourceGroup in $ResourceGroups)
		{    
			#Flag check for CSP subs
            if($enableClassicVMs)
            {
                # Get classic VM resources in group 
			    $taggedClassicVMs = Get-AzureRmResource -ResourceGroup $ResourceGroup.ResourceGroupName -ResourceType "Microsoft.ClassicCompute/virtualMachines"
			    foreach($vmResource in $taggedClassicVMs)
			    {
				    Write-Output "RG : $vmResource.ResourceGroupName , Classic VM $($vmResource.Name)"
				    $AzureVMList += @{Name = $vmResource.Name; Location = $vmResource.Location; ResourceGroupName = $vmResource.ResourceGroupName; Type = "Classic"}
			    }
            }
			
			# Get resource manager VM resources in group and record target state for each in table
			$taggedRMVMs = Get-AzureRmResource -ResourceGroup $ResourceGroup.ResourceGroupName -ResourceType "Microsoft.Compute/virtualMachines"
			foreach($vmResource in $taggedRMVMs)
			{
				Write-Output "RG : $vmResource.ResourceGroupName , ARM VM $($vmResource.Name)"
				$AzureVMList += @{Name = $vmResource.Name; Location = $vmResource.Location; ResourceGroupName = $vmResource.ResourceGroupName; Type = "ResourceManager"}
			}
		}
    }

    Write-Output "Calling child runbook to disable the alert on all the VM's..."    

    foreach($VM in $AzureVMList)
    {
        try
        {
            $params = @{"VMObject"=$VM;"AlertAction"="Disable";"WebhookUri"=$webhookUri}                    
            $runbook = Start-AzureRmAutomationRunbook -automationAccountName $automationAccountName -Name 'AutoStop_CreateAlert_Child' -ResourceGroupName $aroResourceGroupName –Parameters $params
        }
        catch
        {
            Write-Output "Error Occurred on Alert disable..."   
            Write-Output $_.Exception 
        }
    }

    Write-Output "AutoSnooze disable execution completed..."

}
catch
{
    Write-Output "Error Occurred on AutoSnooze Disable Wrapper..."   
    Write-Output $_.Exception
}