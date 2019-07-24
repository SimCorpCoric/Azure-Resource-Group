<#
.SYNOPSIS  
	This runbook used to perform sequenced start or stop Azure RM/Classic VM
.DESCRIPTION  
	This runbook used to perform sequenced start or stop Azure RM/Classic VM.
	Create a tag called “sequencestart” on each VM that you want to sequence start activity for.Create a tag called “sequencestop” on each VM that you want to sequence stop activity for. The value of the tag should be an integer (1,2,3) that corresponds to the order you want to start\stop. For both action, the order goes ascending (1,2,3) . WhatIf behaves the same as in other runbooks. 
	Upon completion of the runbook, an option to email results of the started VM can be sent via SendGrid account. 
	
	This runbook requires the Azure Automation Run-As (Service Principle) account, which must be added when creating the Azure Automation account.
 .PARAMETER  
    Parameters are read in from Azure Automation variables.  
    Variables (editable):
    -  External_Start_ResourceGroupNames    :  ResourceGroup that contains VMs to be started. Must be in the same subscription that the Azure Automation Run-As account has permission to manage.
    -  External_Stop_ResourceGroupNames     :  ResourceGroup that contains VMs to be stopped. Must be in the same subscription that the Azure Automation Run-As account has permission to manage.
    -  External_ExcludeVMNames              :  VM names to be excluded from being started.
.EXAMPLE  
	.\SequencedStartStop_Parent.ps1 -Action "Value1" 

#>

Param(
[Parameter(Mandatory=$true,HelpMessage="Enter the value for Action. Values can be either stop or start")][String]$Action,
[Parameter(Mandatory=$false,HelpMessage="Enter the value for WhatIf. Values can be either true or false")][bool]$WhatIf = $false,
[Parameter(Mandatory=$false,HelpMessage="Enter the value for ContinueOnError. Values can be either true or false")][bool]$ContinueOnError = $false,
[Parameter(Mandatory=$false,HelpMessage="Enter the VMs separated by comma(,)")][string]$VMList
)

function PerformActionOnSequencedTaggedVMAll($Sequences, [string]$Action, $TagName, $ExcludeList)
{
    foreach($seq in $Sequences)
    {
        Write-Output "Getting all the VM's from the subscription..."  
        $ResourceGroups = Get-AzureRmResourceGroup

        $AzureVMList=@()
        $AzureVMListTemp=@()

        if($WhatIf -eq $false)
        {
            Write-Output "Performing the $($Action) action against VM's where the tag $($TagName) is $($seq)."
			foreach($rg in $ResourceGroups)
			{
                $AzureVMList += Get-AzureRmResource -TagValue $seq | Where-Object {($_.ResourceType -eq “Microsoft.Compute/virtualMachines”) -and ($_.ResourceGroupName -eq $rg.ResourceGroupName)} | Select Name, ResourceGroupName
            }
            
            foreach($VM in $AzureVMList)
            {
                $FilterTagVMs = Get-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name

                $CaseSensitiveTagName = $FilterTagVMs.Tags.Keys | Where-Object -FilterScript {$_ -eq $TagName}
                
                if($CaseSensitiveTagName -ne $null)
                {
                    if($FilterTagVMs.Tags[$CaseSensitiveTagName] -eq $seq)
                    {
                        $AzureVMListTemp+=$FilterTagVMs | Select Name,ResourceGroupName
                    }
                }
            }
            $AzureVMList = $AzureVMListTemp

            ##Remove Excluded VMs
            $ActualAzureVMList=@()
            $ExAzureVMList=@()
            if(($ExcludeList -ne $null) -and ($ExcludeList -ne "none"))
            {
                foreach($filtervm in $ExcludeList) 
                {
		            $currentVM = Get-AzureRmVM | where Name -Like $filtervm.Trim()  -ErrorAction SilentlyContinue
		            if ($currentVM.Count -ge 1)
		            {
			            $ExAzureVMList+=$currentVM.Name
		            }
                }
            }

            if(($ExcludeList -ne $null) -and ($ExcludeList -ne "none"))
            {
                foreach($VM in $AzureVMList)
                {  
                    ##Checking Vm in excluded list                         
                    if($ExAzureVMList -notcontains ($($VM.Name)))
                    {
                        $ActualAzureVMList+=$VM
                    }
                }
            }
            else
            {
                $ActualAzureVMList = $AzureVMList
            }
            
            $ActualVMListOutput=@()
            
            foreach($vmObj in $ActualAzureVMList)
            {   
                $ActualVMListOutput = $ActualVMListOutput + $vmObj.Name + " "
                Write-Output "Executing runbook ScheduledStartStop_Child to perform the $($Action) action on VM: $($vmobj.Name)"
                $params = @{"VMName"="$($vmObj.Name)";"Action"=$Action;"ResourceGroupName"="$($vmObj.ResourceGroupName)"}                    
                Start-AzureRmAutomationRunbook -automationAccountName $automationAccountName -Name 'ScheduledStartStop_Child' -ResourceGroupName $aroResourceGroupName –Parameters $params                   
            }

            if($ActualVMListOutput -ne $null)
            {
                Write-Output "~Attempted the $($Action) action on the following VMs in sequence $($seq): $($ActualVMListOutput)"
            }
            
            Write-Output "Completed the sequenced $($Action) against VM's where the tag $($TagName) is $($seq)." 

            if(($Action -eq 'stop' -and $seq -ne $Sequences.Count) -or ($Action -eq 'start' -and $seq -ne [int]$Sequences.Count - ([int]$Sequences.Count-1)))
            {
                Write-Output "Validating the status before processing the next sequence..."
            }        

            foreach($vmObjStatus in $ActualAzureVMList)
            {
                [int]$SleepCount = 0 
                $CheckVMStatus = CheckVMState -VMObject $vmObjStatus -Action $Action
                While($CheckVMStatus -eq $false)
                {                
                    Write-Output "Checking the VM Status in 10 seconds..."
                    Start-Sleep -Seconds 10
                    $SleepCount+=10
                    if($SleepCount -gt $maxWaitTimeForVMRetryInSeconds -and $ContinueOnError -eq $false)
                    {
                        Write-Output "Unable to $($Action) the VM $($vmObjStatus.Name). ContinueOnError is set to False, hence terminating the sequenced $($Action)..."
                        Write-Output "Completed the sequenced $($Action)..."
                        exit
                    }
                    elseif($SleepCount -gt $maxWaitTimeForVMRetryInSeconds -and $ContinueOnError -eq $true)
                    {
                        Write-Output "Unable to $($Action) the VM $($vmObjStatus.Name). ContinueOnError is set to True, hence moving to the next resource..."
                        break
                    }
                    $CheckVMStatus = CheckVMState -VMObject $vmObjStatus -Action $Action
                }
            }
        }
        elseif($WhatIf -eq $true)
        {
            Write-Output "WhatIf parameter is set to True..."
            Write-Output "When 'WhatIf' is set to TRUE, runbook provides a list of Azure Resources (e.g. VMs), that will be impacted if you choose to deploy this runbook."
            Write-Output "No action will be taken at this time. These are the resources where the tag $($TagName) is $($seq)..."
            foreach($rg in $ResourceGroups)
			{
                $AzureVMList += Get-AzureRmResource -TagValue $seq | Where-Object {($_.ResourceType -eq “Microsoft.Compute/virtualMachines”) -and ($_.ResourceGroupName -eq $rg.ResourceGroupName)} | Select Name, ResourceGroupName
            }
            
            foreach($VM in $AzureVMList)
            {
                $FilterTagVMs = Get-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name  

                $CaseSensitiveTagName = $FilterTagVMs.Tags.Keys | Where-Object -FilterScript {$_ -eq $TagName}

                if($CaseSensitiveTagName -ne $null)
                {
                    if($FilterTagVMs.Tags[$CaseSensitiveTagName] -eq $seq)
                    {
                        $AzureVMListTemp+=$FilterTagVMs | Select Name,ResourceGroupName
                    }
                }
            }
            $AzureVMList = $AzureVMListTemp

            ##Remove Excluded VMs
            $ActualAzureVMList=@()
            $ExAzureVMList=@()
            if(($ExcludeList -ne $null) -and ($ExcludeList -ne "none"))
            {
                foreach($filtervm in $ExcludeList) 
                {
		            $currentVM = Get-AzureRmVM | where Name -Like $filtervm.Trim()  -ErrorAction SilentlyContinue
		            if ($currentVM.Count -ge 1)
		            {
			            $ExAzureVMList+=$currentVM.Name
		            }
                }
            }

            if(($ExcludeList -ne $null) -and ($ExcludeList -ne "none"))
            {
                foreach($VM in $AzureVMList)
                {  
                    ##Checking Vm in excluded list                         
                    if($ExAzureVMList -notcontains ($($VM.Name)))
                    {
                        $ActualAzureVMList+=$VM
                    }
                }
            }
            else
            {
                $ActualAzureVMList = $AzureVMList
            }
            
            Write-Output $($ActualAzureVMList)
            Write-Output "End of resources where tag $($TagName) is $($seq)..."
        }
    }
}

function PerformActionOnSequencedTaggedVMRGs($Sequences, [string]$Action, $TagName, [string[]]$VMRGList, $ExcludeList)
{
    foreach($seq in $Sequences)
    {
        $AzureVMList=@()
        $AzureVMListTemp=@()

        if($WhatIf -eq $false)
        {
            Write-Output "Performing the $($Action) action against VM's where the tag $($TagName) is $($seq)."
			foreach($rg in $VMRGList)
			{
                $AzureVMList += Get-AzureRmResource -TagValue $seq | Where-Object {($_.ResourceType -eq “Microsoft.Compute/virtualMachines”) -and ($_.ResourceGroupName -eq $rg.Trim())} | Select Name, ResourceGroupName
            }
            
            foreach($VM in $AzureVMList)
            {
                $FilterTagVMs = Get-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name   
                
                $CaseSensitiveTagName = $FilterTagVMs.Tags.Keys | Where-Object -FilterScript {$_ -eq $TagName}               

                if($CaseSensitiveTagName -ne $null)
                {             
                    if($FilterTagVMs.Tags[$CaseSensitiveTagName] -eq $seq)
                    {
                        $AzureVMListTemp+=$FilterTagVMs | Select Name,ResourceGroupName
                    }
                }
            }
            $AzureVMList = $AzureVMListTemp

            ##Remove Excluded VMs
            $ActualAzureVMList=@()
            $ExAzureVMList=@()
            if(($ExcludeList -ne $null) -and ($ExcludeList -ne "none"))
            {
                foreach($filtervm in $ExcludeList) 
                {
		            $currentVM = Get-AzureRmVM | where Name -Like $filtervm.Trim()  -ErrorAction SilentlyContinue
		            if ($currentVM.Count -ge 1)
		            {
			            $ExAzureVMList+=$currentVM.Name
		            }
                }
            }

            if(($ExcludeList -ne $null) -and ($ExcludeList -ne "none"))
            {
                foreach($VM in $AzureVMList)
                {  
                    ##Checking Vm in excluded list                         
                    if($ExAzureVMList -notcontains ($($VM.Name)))
                    {
                        $ActualAzureVMList+=$VM
                    }
                }
            }
            else
            {
                $ActualAzureVMList = $AzureVMList
            }
            
            $ActualVMListOutput=@()
            
            foreach($vmObj in $ActualAzureVMList)
            {   
                $ActualVMListOutput = $ActualVMListOutput + $vmObj.Name + " "
                Write-Output "Executing runbook ScheduledStartStop_Child to perform the $($Action) action on VM: $($vmobj.Name)"
                $params = @{"VMName"="$($vmObj.Name)";"Action"=$Action;"ResourceGroupName"="$($vmObj.ResourceGroupName)"}                    
                Start-AzureRmAutomationRunbook -automationAccountName $automationAccountName -Name 'ScheduledStartStop_Child' -ResourceGroupName $aroResourceGroupName –Parameters $params                   
            }

            if($ActualVMListOutput -ne $null)
            {
                Write-Output "~Attempted the $($Action) action on the following VMs in sequence $($seq): $($ActualVMListOutput)"
            }
            
            Write-Output "Completed the sequenced $($Action) against VM's where the tag $($TagName) is $($seq)." 

            if(($Action -eq 'stop' -and $seq -ne $Sequences.Count) -or ($Action -eq 'start' -and $seq -ne [int]$Sequences.Count - ([int]$Sequences.Count-1)))
            {
                Write-Output "Validating the status before processing the next sequence..."
            }        

            foreach($vmObjStatus in $ActualAzureVMList)
            {
                [int]$SleepCount = 0 
                $CheckVMStatus = CheckVMState -VMObject $vmObjStatus -Action $Action
                While($CheckVMStatus -eq $false)
                {                
                    Write-Output "Checking the VM Status in 10 seconds..."
                    Start-Sleep -Seconds 10
                    $SleepCount+=10
                    if($SleepCount -gt $maxWaitTimeForVMRetryInSeconds -and $ContinueOnError -eq $false)
                    {
                        Write-Output "Unable to $($Action) the VM $($vmObjStatus.Name). ContinueOnError is set to False, hence terminating the sequenced $($Action)..."
                        Write-Output "Completed the sequenced $($Action)..."
                        exit
                    }
                    elseif($SleepCount -gt $maxWaitTimeForVMRetryInSeconds -and $ContinueOnError -eq $true)
                    {
                        Write-Output "Unable to $($Action) the VM $($vmObjStatus.Name). ContinueOnError is set to True, hence moving to the next resource..."
                        break
                    }
                    $CheckVMStatus = CheckVMState -VMObject $vmObjStatus -Action $Action
                }
            }
        }
        elseif($WhatIf -eq $true)
        {
            Write-Output "WhatIf parameter is set to True..."
            Write-Output "When 'WhatIf' is set to TRUE, runbook provides a list of Azure Resources (e.g. VMs), that will be impacted if you choose to deploy this runbook."
            Write-Output "No action will be taken at this time. These are the resources where the tag $($TagName) is $($seq)..."
            foreach($rg in $VMRGList)
			{
                $AzureVMList += Get-AzureRmResource -TagValue $seq | Where-Object {($_.ResourceType -eq “Microsoft.Compute/virtualMachines”) -and ($_.ResourceGroupName -eq $rg.Trim())} | Select Name, ResourceGroupName
            }
            
            foreach($VM in $AzureVMList)
            {
                $FilterTagVMs = Get-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name      

                $CaseSensitiveTagName = $FilterTagVMs.Tags.Keys | Where-Object -FilterScript {$_ -eq $TagName}

                if($CaseSensitiveTagName -ne $null)
                {
                    if($FilterTagVMs.Tags[$CaseSensitiveTagName] -eq $seq)
                    {
                        $AzureVMListTemp+=$FilterTagVMs | Select Name,ResourceGroupName
                    }
                }
            }
            $AzureVMList = $AzureVMListTemp

            ##Remove Excluded VMs
            $ActualAzureVMList=@()
            $ExAzureVMList=@()
            if(($ExcludeList -ne $null) -and ($ExcludeList -ne "none"))
            {
                foreach($filtervm in $ExcludeList) 
                {
		            $currentVM = Get-AzureRmVM | where Name -Like $filtervm.Trim()  -ErrorAction SilentlyContinue
		            if ($currentVM.Count -ge 1)
		            {
			            $ExAzureVMList+=$currentVM.Name
		            }
                }
            }

            if(($ExcludeList -ne $null) -and ($ExcludeList -ne "none"))
            {
                foreach($VM in $AzureVMList)
                {  
                    ##Checking Vm in excluded list                         
                    if($ExAzureVMList -notcontains ($($VM.Name)))
                    {
                        $ActualAzureVMList+=$VM
                    }
                }
            }
            else
            {
                $ActualAzureVMList = $AzureVMList
            }
            
            Write-Output $($ActualAzureVMList)
            Write-Output "End of resources where tag $($TagName) is $($seq)..."
        }
    }
}

function PerformActionOnSequencedTaggedVMList($Sequences, [string]$Action, $TagName, [string[]]$AzVMList)
{
    foreach($seq in $Sequences)
    {
        $AzureVMList=@()
        $AzureVMListTemp=@()

        if($WhatIf -eq $false)
        {
            Write-Output "Performing the $($Action) action against VM's where the tag $($TagName) is $($seq)."
			foreach($vm in $AzVMList)
			{
                $AzureVMList += Get-AzureRmResource -TagValue $seq | Where-Object {($_.ResourceType -eq “Microsoft.Compute/virtualMachines”) -and ($_.Name -eq $vm.Trim())} | Select Name, ResourceGroupName
            }
            
            foreach($VM in $AzureVMList)
            {
                $FilterTagVMs = Get-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name 
                
                $CaseSensitiveTagName = $FilterTagVMs.Tags.Keys | Where-Object -FilterScript {$_ -eq $TagName}               

                if($CaseSensitiveTagName -ne $null)
                {               
                    if($FilterTagVMs.Tags[$CaseSensitiveTagName] -eq $seq)
                    {
                        $AzureVMListTemp+=$FilterTagVMs | Select Name,ResourceGroupName
                    }
                }
            }
            $AzureVMList = $AzureVMListTemp

            $ActualVMListOutput=@()

            foreach($vmObj in $AzureVMList)
            {   
                $ActualVMListOutput = $ActualVMListOutput + $vmObj.Name + " "
                Write-Output "Executing runbook ScheduledStartStop_Child to perform the $($Action) action on VM: $($vmobj.Name)"
                $params = @{"VMName"="$($vmObj.Name)";"Action"=$Action;"ResourceGroupName"="$($vmObj.ResourceGroupName)"}                    
                Start-AzureRmAutomationRunbook -automationAccountName $automationAccountName -Name 'ScheduledStartStop_Child' -ResourceGroupName $aroResourceGroupName –Parameters $params
            }

            if($ActualVMListOutput -ne $null)
            {
                Write-Output "~Attempted the $($Action) action on the following VMs in sequence $($seq): $($ActualVMListOutput)"
            }
            
            Write-Output "Completed the sequenced $($Action) against VM's where the tag $($TagName) is $($seq)." 

            if(($Action -eq 'stop' -and $seq -ne $Sequences.Count) -or ($Action -eq 'start' -and $seq -ne [int]$Sequences.Count - ([int]$Sequences.Count-1)))
            {
                Write-Output "Validating the status before processing the next sequence..."
            }        

            foreach($vmObjStatus in $AzureVMList)
            {
                [int]$SleepCount = 0 
                $CheckVMStatus = CheckVMState -VMObject $vmObjStatus -Action $Action
                While($CheckVMStatus -eq $false)
                {                
                    Write-Output "Checking the VM Status in 10 seconds..."
                    Start-Sleep -Seconds 10
                    $SleepCount+=10
                    if($SleepCount -gt $maxWaitTimeForVMRetryInSeconds -and $ContinueOnError -eq $false)
                    {
                        Write-Output "Unable to $($Action) the VM $($vmObjStatus.Name). ContinueOnError is set to False, hence terminating the sequenced $($Action)..."
                        Write-Output "Completed the sequenced $($Action)..."
                        exit
                    }
                    elseif($SleepCount -gt $maxWaitTimeForVMRetryInSeconds -and $ContinueOnError -eq $true)
                    {
                        Write-Output "Unable to $($Action) the VM $($vmObjStatus.Name). ContinueOnError is set to True, hence moving to the next resource..."
                        break
                    }
                    $CheckVMStatus = CheckVMState -VMObject $vmObjStatus -Action $Action
                }
            }
        }
        elseif($WhatIf -eq $true)
        {
            Write-Output "WhatIf parameter is set to True..."
            Write-Output "When 'WhatIf' is set to TRUE, runbook provides a list of Azure Resources (e.g. VMs), that will be impacted if you choose to deploy this runbook."
            Write-Output "No action will be taken at this time. These are the resources where the tag $($TagName) is $($seq)..."
            foreach($vm in $AzVMList)
			{
                $AzureVMList += Get-AzureRmResource -TagValue $seq | Where-Object {($_.ResourceType -eq “Microsoft.Compute/virtualMachines”) -and ($_.Name -eq $vm)} | Select Name, ResourceGroupName
            }
            
            foreach($VM in $AzureVMList)
            {
                $FilterTagVMs = Get-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name                
                
                $CaseSensitiveTagName = $FilterTagVMs.Tags.Keys | Where-Object -FilterScript {$_ -eq $TagName}

                if($CaseSensitiveTagName -ne $null)
                {
                    if($FilterTagVMs.Tags[$CaseSensitiveTagName] -eq $seq)
                    {
                        $AzureVMListTemp+=$FilterTagVMs | Select Name,ResourceGroupName
                    }
                }
            }

            $ActualAzureVMList = $AzureVMListTemp                      
            
            Write-Output $($ActualAzureVMList)
            Write-Output "End of resources where tag $($TagName) is $($seq)..."
        }
    }
}
function CheckVMState ($VMObject,[string]$Action)
{
    [bool]$IsValid = $false
    
    $CheckVMState = (Get-AzureRmVM -ResourceGroupName $VMObject.ResourceGroupName -Name $VMObject.Name -Status -ErrorAction SilentlyContinue).Statuses.Code[1]
    if($Action.ToLower() -eq 'start' -and $CheckVMState -eq 'PowerState/running')
    {
        $IsValid = $true
    }    
    elseif($Action.ToLower() -eq 'stop' -and $CheckVMState -eq 'PowerState/deallocated')
    {
            $IsValid = $true
    }    
    return $IsValid
}


function CheckValidAzureVM ($FilterVMList)
{
    [string[]] $invalidvm=@()
    $VMListARM=@()
    
    $VMListARM = Get-AzureRmResource -ResourceType Microsoft.Compute/virtualMachines  
          
    foreach($filtervm in $FilterVMList) 
    {
        $VMARMTemp = $VMListARM | where name -Like $filtervm.Trim()

        if($VMARMTemp -eq $null)
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
$automationAccountName = Get-AutomationVariable -Name 'Internal_AutomationAccountName'
$aroResourceGroupName = Get-AutomationVariable -Name 'Internal_ResourceGroupName'
$maxWaitTimeForVMRetryInSeconds = Get-AutomationVariable -Name 'External_WaitTimeForVMRetryInSeconds'
$StartResourceGroupNames = Get-AutomationVariable -Name 'External_Start_ResourceGroupNames'
$StopResourceGroupNames = Get-AutomationVariable -Name 'External_Stop_ResourceGroupNames'
$ExcludeVMNames = Get-AutomationVariable -Name 'External_ExcludeVMNames'

try
{
    $Action = $Action.Trim().ToLower()

    if(!($Action -eq "start" -or $Action -eq "stop"))
    {
        Write-Output "`$Action parameter value is : $($Action). Value should be either start or stop."
        Write-Output "Completed the runbook execution..."
        exit
    }

    #If user gives the VM list with comma seperated....
    [string[]] $AzVMList = $VMList -split ","        

    #Validate the Exclude List VM's and stop the execution if the list contains any invalid VM
    if (([string]::IsNullOrEmpty($ExcludeVMNames) -ne $true) -and ($ExcludeVMNames -ne "none"))
    {   
        Write-Output "Values exist on the VM's Exclude list. Checking resources against this list..."
        [string[]] $VMfilterList = $ExcludeVMNames -split ","
        $ExAzureVMList = CheckValidAzureVM -FilterVMList $VMfilterList
    }

    if($Action -eq "stop")
    {
        [string[]] $VMRGList = $StopResourceGroupNames -split ","
    }
    if($Action -eq "start")
    {
        [string[]] $VMRGList = $StartResourceGroupNames -split ","
    }
     
    Write-Output "Executing the Sequenced $($Action)..."   
    Write-Output "Input parameter values..."
    Write-Output "`$Action : $($Action)"
    Write-Output "`$WhatIf : $($WhatIf)"
    Write-Output "`$ContinueOnError : $($ContinueOnError)"
    Write-Output "Filtering the tags across all the VM's..."
    
    $startTagValue = "sequencestart"  
	$stopTagValue = "sequencestop"  	
    $startTagKeys = Get-AzureRmVM | Where-Object {$_.Tags.Keys -eq $startTagValue.ToLower()} | Select Tags
	$stopTagKeys = Get-AzureRmVM | Where-Object {$_.Tags.Keys -eq $stopTagValue.ToLower()} | Select Tags
	$startSequences=[System.Collections.ArrayList]@()
	$stopSequences=[System.Collections.ArrayList]@()
	
    foreach($tag in $startTagKeys.Tags)
    {
		foreach($key in $($tag.keys)){
            if ($key.ToLower() -eq $startTagValue.ToLower())
            {
                [void]$startSequences.add([int]$tag[$key])
            }
        }
	}
	
	foreach($tag in $stopTagKeys.Tags)
    {
		foreach($key in $($tag.keys)){
            if ($key.ToLower() -eq $stopTagValue.ToLower())
            {
                [void]$stopSequences.add([int]$tag[$key])
            }
        }
    }

    $startSequences = $startSequences | Sort-Object -Unique
	$stopSequences = $stopSequences | Sort-Object -Unique
	
	if ($Action -eq 'start') 
	{
        if($AzVMList -ne $null)
        {
            $AzureVMList = CheckValidAzureVM -FilterVMList $AzVMList
            PerformActionOnSequencedTaggedVMList -Sequences $startSequences -Action $Action -TagName $startTagValue -AzVMList $AzVMList
        }
        else
        {
            if (($VMRGList -ne $null) -and ($VMRGList -ne "*"))
            {
		        PerformActionOnSequencedTaggedVMRGs -Sequences $startSequences -Action $Action -TagName $startTagValue -VMRGList $VMRGList -ExcludeList $VMfilterList
            }
            else
            {
                PerformActionOnSequencedTaggedVMAll -Sequences $startSequences -Action $Action -TagName $startTagValue -ExcludeList $VMfilterList
            }
	    }
    }
	
	if ($Action -eq 'stop')
	{
        if($AzVMList -ne $null)
        {
            $AzureVMList = CheckValidAzureVM -FilterVMList $AzVMList
            PerformActionOnSequencedTaggedVMList -Sequences $stopSequences -Action $Action -TagName $stopTagValue -AzVMList $AzVMList        
        }
        else
        {
            if (($VMRGList -ne $null) -and ($VMRGList -ne "*"))
            {
		        PerformActionOnSequencedTaggedVMRGs -Sequences $stopSequences -Action $Action -TagName $stopTagValue -VMRGList $VMRGList -ExcludeList $VMfilterList
            }
            else
            {
                PerformActionOnSequencedTaggedVMAll -Sequences $stopSequences -Action $Action -TagName $stopTagValue -ExcludeList $VMfilterList
            }
	    }
    }
	
   
    Write-Output "Completed the sequenced $($Action)..."
}
catch
{
    Write-Output "Error Occurred in the sequence $($Action) runbook..."   
    Write-Output $_.Exception
}