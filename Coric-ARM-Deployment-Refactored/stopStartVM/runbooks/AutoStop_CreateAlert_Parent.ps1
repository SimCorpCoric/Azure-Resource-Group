<#
.SYNOPSIS  
 Runbook for shutdown the Azure VM based on CPU usage
.DESCRIPTION  
 Runbook for shutdown the Azure VM based on CPU usage
.EXAMPLE  
.\AutoStop_CreateAlert_Parent.ps1 -WhatIf $false -VMList "vm1,vm2"
Version History  
v1.0   - Initial Release  
v2.0   - Added classic support
#>

Param(
[Parameter(Mandatory=$false,HelpMessage="Enter the value for WhatIf. Values can be either true or false")][bool]$WhatIf = $false,
[Parameter(Mandatory=$false,HelpMessage="Enter the VMs separated by comma(,) if you want to create alerts for VMs")][string]$VMList
)

function CheckValidAzureVM ($FilterVMList,$EnableClassicVMs)
{
    [boolean] $ISexists = $false
    [string[]] $invalidvm=@()
    $VMListARM=@()
    
    #Flag check for CSP subs
    if($EnableClassicVMs)
    {
        $VMListCS=@()
        $VMListCS = Get-AzureRmResource -ResourceType Microsoft.ClassicCompute/virtualMachines
    }
    
    $VMListARM = Get-AzureRmResource -ResourceType Microsoft.Compute/virtualMachines    
    
    foreach($filtervm in $FilterVMList) 
    {
        $ISexists = $false
        
        if($EnableClassicVMs)
        {
            $VMCSTemp = $VMListCS | where name -Like $filtervm.Trim()

            if($VMCSTemp -eq $null)
            {
                $ISexists = $false
            }
            else
            {
                $ISexists = $true
            }            
        }
        
        $VMARMTemp = $VMListARM | where name -Like $filtervm.Trim()

        if($VMARMTemp -ne $null)
        {
            $ISexists = $true
        }
        elseif($ISexists -eq $false)
        {
            $invalidvm = $invalidvm+$filtervm      
        }
    }
    
    if($invalidvm -ne $null)
    {
        Write-Output "Runbook Execution Stopped! Invalid VM Name(s) in the list: $($invalidvm) "
        Write-Warning "Runbook Execution Stopped! Invalid VM Name(s) in the list: $($invalidvm) "
        exit
    }
    else
    {
        $ExAzureVMList=@()

        foreach($vm in $FilterVMList)
        {
            $NewVM = $VMListARM | where name -Like $vm

            if($NewVM -ne $null)
            {
                foreach($nvm in $NewVM)
                {
                    $ExAzureVMList += @{Name = $nvm.Name; Location = $nvm.Location; ResourceGroupName = $nvm.ResourceGroupName; Type = "ResourceManager"}
                }
            }
            
            if($EnableClassicVMs)
            {
                $NewVm = $VMListCS | where name -Like $vm

                if($NewVM -ne $null)
                {
                    foreach($nvm in $NewVM)
                    {
                        $ExAzureVMList += @{Name = $nvm.Name; Location = $nvm.Location; ResourceGroupName = $nvm.ResourceGroupName; Type = "Classic"}
                    }
                }                
            }
        }

        return $ExAzureVMList                
    }    
}

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

#---------Read all the input variables---------------
$SubId = Get-AutomationVariable -Name 'Internal_AzureSubscriptionId'
$StopResourceGroupNames = Get-AutomationVariable -Name 'External_Stop_ResourceGroupNames'
$ExcludeVMNames = Get-AutomationVariable -Name 'External_ExcludeVMNames'
$automationAccountName = Get-AutomationVariable -Name 'Internal_AutomationAccountName'
$aroResourceGroupName = Get-AutomationVariable -Name 'Internal_ResourceGroupName'

#-----Prepare the inputs for alert attributes-----
$webhookUri = Get-AutomationVariable -Name 'Internal_AutoSnooze_WebhookUri'

try
    {  
        Write-Output "Runbook execution started..."
        [string[]] $VMfilterList = $ExcludeVMNames -split ","
        [string[]] $VMAlertList = $VMList -split ","        
        [string[]] $VMRGList = $StopResourceGroupNames -split ","
        
        #Validate the Exclude List VM's and stop the execution if the list contains any invalid VM
        if (([string]::IsNullOrEmpty($ExcludeVMNames) -ne $true) -and ($ExcludeVMNames -ne "none"))
        {
            Write-Output "Values exist on the VM's Exclude list. Checking resources against this list..."            
            $ExAzureVMList = CheckValidAzureVM -FilterVMList $VMfilterList -EnableClassicVMs $enableClassicVMs
        } 

        if ($ExAzureVMList -ne $null -and $WhatIf -eq $false)
        {
            foreach($VM in $ExAzureVMList)
            {
                try
                {
                        Write-Output "Disabling the alert rules for VM : $($VM.Name)" 
                        $params = @{"VMObject"=$VM;"AlertAction"="Disable";"WebhookUri"=$webhookUri}                    
                        $runbook = Start-AzureRmAutomationRunbook -automationAccountName $automationAccountName -Name 'AutoStop_CreateAlert_Child' -ResourceGroupName $aroResourceGroupName –Parameters $params
                }
                catch
                {
                    $ex = $_.Exception
                    Write-Output $_.Exception 
                }
            }
        }
        elseif($ExAzureVMList -ne $null -and $WhatIf -eq $true)
        {
            Write-Output "WhatIf parameter is set to True..."
            Write-Output "What if: Performing the alert rules disable for the Exclude VM's..."
            Write-Output $ExcludeVMNames
        }

        $AzureVMListTemp = $null
        $AzureVMList=@()
		
		
		if ($VMAlertList -ne $null)
		{
			##Alerts are created based on VM List not on Resource group.
			##Validating the VM List.
			Write-Output "VM List is given to create Alerts.."
			$AzureVMList = CheckValidAzureVM -FilterVMList $VMAlertList -EnableClassicVMs $enableClassicVMs
		} 
		else
		{
            ##Getting VM Details based on RG List or Subscription
            if (($VMRGList -ne $null) -and ($VMRGList -ne "*"))
            {
			    Write-Output "Resource Group List is given to create Alerts.."
                foreach($Resource in $VMRGList)
                {
                    Write-Output "Validating the resource group name ($($Resource.Trim()))" 
                    $checkRGname = Get-AzureRmResourceGroup  $Resource.Trim() -ev notPresent -ea 0  
                    if ($checkRGname -eq $null)
                    {
                        Write-Output "$($Resource) is not a valid Resource Group Name. Please verify your input."
                        Write-Warning "$($Resource) is not a valid Resource Group Name. Please verify your input."
                        exit
                    }
                    else
                    {                   
                   	    #Flag check for CSP subs
                        if($enableClassicVMs)
                        {	
                            #Get classic VM resources in group and record target state for each in table
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
        }
		
        $ActualAzureVMList=@()
        if($VMfilterList -ne $null)
        {
            foreach($VM in $AzureVMList)
            {  
                ##Checking Vm in excluded list                         
                if($ExAzureVMList.Name -notcontains ($($VM.Name)))
                {
                    $ActualAzureVMList+=$VM
                }
            }
        }
        else
        {
            $ActualAzureVMList = $AzureVMList
        }

        if($WhatIf -eq $false)
        {    
            foreach($VM in $ActualAzureVMList)
            {  
                    Write-Output "Creating alert rules for the VM : $($VM.Name)"
                    $params = @{"VMObject"=$VM;"AlertAction"="Create";"WebhookUri"=$webhookUri}                    
                    $runbook = Start-AzureRmAutomationRunbook -automationAccountName $automationAccountName -Name 'AutoStop_CreateAlert_Child' -ResourceGroupName $aroResourceGroupName –Parameters $params
            }
            Write-Output "Note: All the alert rules creation are processed in parallel. Please check the child runbook (AutoStop_CreateAlert_Child) job status..."
        }
        elseif($WhatIf -eq $true)
        {
            Write-Output "WhatIf parameter is set to True..."
            Write-Output "When 'WhatIf' is set to TRUE, runbook provides a list of Azure Resources (e.g. VM's), that will be impacted if you choose to deploy this runbook."
            Write-Output "No action will be taken at this time..."
            Write-Output $($ActualAzureVMList) 
        }
        Write-Output "Runbook Execution Completed..."
    }
    catch
    {
        $ex = $_.Exception
        Write-Output $_.Exception
    }
