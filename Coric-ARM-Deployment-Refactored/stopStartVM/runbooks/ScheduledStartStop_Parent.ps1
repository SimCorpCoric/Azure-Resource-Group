<#
.SYNOPSIS  
	 Wrapper script for get all the VM's in all RG's or subscription level and then call the Start or Stop runbook
.DESCRIPTION  
	 This runbook is intended to start/stop VMs (both classic and ARM based VMs) that resides in a given list of Azure resource group(s).If the resource group list is empty, then the script gets all the VMs in the current subscription.
	 Upon completion of the runbook, an option to email results of the started VM can be sent via SendGrid account. 
		
	 This runbook requires the Azure Automation Run-As (Service Principle) account, which must be added when creating the Azure Automation account.
.EXAMPLE  
	.\ScheduledStartStop_Parent.ps1 -Action "Value1" -WhatIf "False"

.PARAMETER  
    Parameters are read in from Azure Automation variables.  
    Variables (editable):
    -  External_Start_ResourceGroupNames    :  ResourceGroup that contains VMs to be started. Must be in the same subscription that the Azure Automation Run-As account has permission to manage.
    -  External_Stop_ResourceGroupNames     :  ResourceGroup that contains VMs to be stopped. Must be in the same subscription that the Azure Automation Run-As account has permission to manage.
    -  External_ExcludeVMNames              :  VM names to be excluded from being started.
   
#>

Param(
[Parameter(Mandatory=$true,HelpMessage="Enter the value for Action. Values can be either stop or start")][String]$Action,
[Parameter(Mandatory=$false,HelpMessage="Enter the value for WhatIf. Values can be either true or false")][bool]$WhatIf = $false,
[Parameter(Mandatory=$false,HelpMessage="Enter the VMs separated by comma(,)")][string]$VMList
)

function ScheduleSnoozeAction ($VMObject,[string]$Action)
{
    
    Write-Output "Calling the ScheduledStartStop_Child wrapper (Action = $($Action))..."
	
    if($Action.ToLower() -eq 'start')
    {
        $params = @{"VMName"="$($VMObject.Name)";"Action"="start";"ResourceGroupName"="$($VMObject.ResourceGroupName)"}   
    }    
    elseif($Action.ToLower() -eq 'stop')
    {
        $params = @{"VMName"="$($VMObject.Name)";"Action"="stop";"ResourceGroupName"="$($VMObject.ResourceGroupName)"}                    
    }    
   
   	if ($VMObject.Type -eq "Classic")
	{
		Write-Output "Performing the schedule $($Action) for the VM : $($VMObject.Name) using Classic"
		$currentVM = Get-AzureVM | where Name -Like $VMObject.Name
		if ($currentVM.Count -ge 1)
		{
			$runbookName = 'ScheduledStartStop_Child_Classic'
		}
		else
		{
			Write-Error "Error: No VM instance with name $($VMObject.Name) found"
		}
	
	}
	elseif ($VMObject.Type -eq "ResourceManager")
	{
		Write-Output "Performing the schedule $($Action) for the VM : $($VMObject.Name) using AzureRM"
		$runbookName = 'ScheduledStartStop_Child'
	}
	
	 $runbook = Start-AzureRmAutomationRunbook -automationAccountName $automationAccountName -Name $runbookName -ResourceGroupName $aroResourceGroupName -Parameters $params
}

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
                    $ExAzureVMList += @{Name = $nvm.Name; ResourceGroupName = $nvm.ResourceGroupName; Type = "ResourceManager"}
                }
            }
            
            if($EnableClassicVMs)
            {
                $NewVm = $VMListCS | where name -Like $vm

                if($NewVM -ne $null)
                {
                    foreach($nvm in $NewVM)
                    {
                        $ExAzureVMList += @{Name = $nvm.Name; ResourceGroupName = $nvm.ResourceGroupName; Type = "Classic"}
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
$StartResourceGroupNames = Get-AutomationVariable -Name 'External_Start_ResourceGroupNames'
$StopResourceGroupNames = Get-AutomationVariable -Name 'External_Stop_ResourceGroupNames'
$ExcludeVMNames = Get-AutomationVariable -Name 'External_ExcludeVMNames'
$automationAccountName = Get-AutomationVariable -Name 'Internal_AutomationAccountName'
$aroResourceGroupName = Get-AutomationVariable -Name 'Internal_ResourceGroupName'

try
    {  
        $Action = $Action.Trim().ToLower()

        if(!($Action -eq "start" -or $Action -eq "stop"))
        {
            Write-Output "`$Action parameter value is : $($Action). Value should be either start or stop."
            Write-Output "Completed the runbook execution..."
            exit
        }            
        Write-Output "Runbook Execution Started..."
        [string[]] $VMfilterList = $ExcludeVMNames -split ","
        #If user gives the VM list with comma seperated....
        [string[]] $AzVMList = $VMList -split ","        

        if($Action -eq "stop")
        {
            [string[]] $VMRGList = $StopResourceGroupNames -split ","
        }
        
        if($Action -eq "start")
        {
            [string[]] $VMRGList = $StartResourceGroupNames -split ","
        }

        #Validate the Exclude List VM's and stop the execution if the list contains any invalid VM
        if (([string]::IsNullOrEmpty($ExcludeVMNames) -ne $true) -and ($ExcludeVMNames -ne "none"))
        {
            Write-Output "Values exist on the VM's Exclude list. Checking resources against this list..."
            $ExAzureVMList = CheckValidAzureVM -FilterVMList $VMfilterList -EnableClassicVMs $enableClassicVMs
        } 
        $AzureVMListTemp = $null
        $AzureVMList=@()

        if ($AzVMList -ne $null)
		{
			##Action to be taken based on VM List and not on Resource group.
			##Validating the VM List.
			Write-Output "VM List is given to take action (Exclude list will be ignored)..."
			$AzureVMList = CheckValidAzureVM -FilterVMList $AzVMList -EnableClassicVMs $enableClassicVMs
		} 
		else
		{

            ##Getting VM Details based on RG List or Subscription
            if (($VMRGList -ne $null) -and ($VMRGList -ne "*"))
            {
                foreach($Resource in $VMRGList)
                {
				    Write-Output "Validating the resource group name ($($Resource.Trim()))" 
                    $checkRGname = Get-AzureRmResourceGroup -Name $Resource.Trim() -ev notPresent -ea 0  
                    if ($checkRGname -eq $null)
                    {
                        Write-Warning "$($Resource) is not a valid ResourceGroup Name. Please verify your input!"
                        Write-Output "$($Resource) is not a valid ResourceGroup Name. Please verify your input!"
                        exit
                    }
                    else
                    {    
					    #Flag check for CSP subs
                        if($enableClassicVMs)
                        {
                            # Get classic VM resources in group and record target state for each in table
                            Write-Output "Getting all the Classic VMs from Resource Group : $($Resource.Trim())"

					        $taggedClassicVMs = Get-AzureRmResource -ResourceGroupName $Resource -ResourceType "Microsoft.ClassicCompute/virtualMachines"

                            foreach($vmResource in $taggedClassicVMs)
					        {
						        if ($vmResource.ResourceGroupName -Like $Resource)
						        {
							        $AzureVMList += @{Name = $vmResource.Name; ResourceGroupName = $vmResource.ResourceGroupName; Type = "Classic"}
						        }
					        }
					    }

					    # Get resource manager VM resources in group and record target state for each in table
                        Write-Output "Getting all the ARM VMs from Resource Group : $($Resource.Trim())"

					    $taggedRMVMs = Get-AzureRmResource -ResourceGroupName $Resource -ResourceType "Microsoft.Compute/virtualMachines"
                        foreach($vmResource in $taggedRMVMs)
					    {
						    if ($vmResource.ResourceGroupName -Like $Resource)
						    {
							    $AzureVMList += @{Name = $vmResource.Name; ResourceGroupName = $vmResource.ResourceGroupName; Type = "ResourceManager"}                                
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
                        # Get classic VM resources in group and record target state for each in table
                        Write-Output "Getting all the Classic VMs from Resource Group : $($ResourceGroup.ResourceGroupName)"

				        $taggedClassicVMs = Get-AzureRmResource -ResourceGroupName $ResourceGroup.ResourceGroupName -ResourceType "Microsoft.ClassicCompute/virtualMachines"

				        foreach($vmResource in $taggedClassicVMs)
				        {
				            Write-Output "ResourceGroup : $($vmResource.ResourceGroupName) : Classic VM : $($vmResource.Name)"
					        $AzureVMList += @{Name = $vmResource.Name; ResourceGroupName = $vmResource.ResourceGroupName; Type = "Classic"}
				        }
                    }				

				    # Get resource manager VM resources in group and record target state for each in table
                    Write-Output "Getting all the ARM VMs from Resource Group : $($ResourceGroup.ResourceGroupName)"

				    $taggedRMVMs = Get-AzureRmResource -ResourceGroupName $ResourceGroup.ResourceGroupName -ResourceType "Microsoft.Compute/virtualMachines"

				    foreach($vmResource in $taggedRMVMs)
				    {
					    Write-Output "ResourceGroup : $($vmResource.ResourceGroupName) : ARM VM : $($vmResource.Name)"
					    $AzureVMList += @{Name = $vmResource.Name; ResourceGroupName = $vmResource.ResourceGroupName; Type = "ResourceManager"}
				    }
			    }
			
            }
        }

        $ActualAzureVMList=@()

        if($AzVMList -ne $null)
        {
            $ActualAzureVMList = $AzureVMList
        }
        #Check if exclude vm list has wildcard       
        elseif(($VMfilterList -ne $null) -and ($VMfilterList -ne "none"))
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

        Write-Output "Performing the $($Action) action..."

        $ActualVMListOutput=@()
        
        if($WhatIf -eq $false)
        {   
            $AzureVMListARM=@()
            $AzureVMListClassic=@() 

            # Store the ARM and Classic VM's seperately
            $AzureVMListARM = $ActualAzureVMList | Where-Object {$_.Type -eq "ResourceManager"}
            $AzureVMListClassic = $ActualAzureVMList | Where-Object {$_.Type -eq "Classic"} 

            # process the ARM VM's
            if($AzureVMListARM -ne $null)
            {
                foreach($VM in $AzureVMListARM)
                {  
                    $ActualVMListOutput = $ActualVMListOutput + $VM.Name + " "
                    ScheduleSnoozeAction -VMObject $VM -Action $Action
                }
                Write-Output "~Attempted the $($Action) action on the following ARM VMs : $($ActualVMListOutput)"
            }

            # process the Classic VM's
            if(($AzureVMListClassic -ne $null) -and ($enableClassicVMs))
            {
                $hashtbl = [ordered]@{}
                # build the hash table to store the cloud service and its VM list
                foreach($vmObj in $AzureVMListClassic)
                {
                    $currentVM = Get-AzureVM | where Name -EQ $vmObj.Name  -ErrorAction SilentlyContinue

                    if($hashtbl.Keys -notcontains $currentVM.ServiceName)
                    {
                        $hashtbl.add($currentVM.ServiceName,$vmObj.Name)
                    }
                    else
                    {
                        $hashtbl[$currentVM.ServiceName] = $hashtbl[$currentVM.ServiceName] + "," + $vmObj.Name
                    }                        
                }

                # process the hash table for each cloud service with its VM list
                $ActualVMListOutput=@()
                foreach($cs in $hashtbl.Keys)
                {
                    $params = @{"CloudServiceName"="$($cs)";"Action"="$($Action)";"VMList"="$($hashtbl.$cs)"}
                    $runbookName = 'ScheduledStartStop_Base_Classic'  
                    $runbook = Start-AzureRmAutomationRunbook -automationAccountName $automationAccountName -Name $runbookName -ResourceGroupName $aroResourceGroupName -Parameters $params
                    $ActualVMListOutput = $ActualVMListOutput + $hashtbl.$cs + " "
                }
                Write-Output "~Attempted the $($Action) action on the following Classic VMs : $($ActualVMListOutput)"
            }
        }
        elseif($WhatIf -eq $true)
        {
            Write-Output "WhatIf parameter is set to True..."
            Write-Output "When 'WhatIf' is set to TRUE, runbook provides a list of Azure Resources (e.g. VMs), that will be impacted if you choose to deploy this runbook."
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
