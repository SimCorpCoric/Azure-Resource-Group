<#
.SYNOPSIS  
	This runbook used to perform action start or stop in classic VM group by Cloud Services
.DESCRIPTION  
	This runbook used to perform action start or stop in classic VM group by Cloud Services	
	This runbook requires the Azure Automation Run-As (Service Principle) account, which must be added when creating the Azure Automation account.
 .EXAMPLE  
    .\ScheduledStartStop_Base_Classic.ps1 -CloudServiceName "Value1" -Action "Value2" -VMList "VM1,VM2,VM3" 	

#>

Param(
[Parameter(Mandatory=$true,HelpMessage="Enter the value for CloudService.")][String]$CloudServiceName,
[Parameter(Mandatory=$true,HelpMessage="Enter the value for Action. Values can be either start or stop")][String]$Action,
[Parameter(Mandatory=$false,HelpMessage="Enter the VMs separated by comma(,)")][string]$VMList
)

function ScheduleSnoozeClassicAction ([string]$CloudServiceName,[string]$VMName,[string]$Action)
{
    
    if($Action.ToLower() -eq 'start')
    {
        $params = @{"VMName"="$($VMName)";"Action"="start";"ResourceGroupName"="$($CloudServiceName)"}   
    }    
    elseif($Action.ToLower() -eq 'stop')
    {
        $params = @{"VMName"="$($VMName)";"Action"="stop";"ResourceGroupName"="$($CloudServiceName)"}                    
    }    
   
   	Write-Output "Performing the schedule $($Action) for the VM : $($VMName) using Classic"

	$runbookName = 'ScheduledStartStop_Child_Classic'
	
	$job = Start-AzureRmAutomationRunbook -automationAccountName $automationAccountName -Name $runbookName -ResourceGroupName $aroResourceGroupName -Parameters $params

    return $job
   
}

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
    Write-Output "Runbook Execution Started..."

    $automationAccountName = Get-AutomationVariable -Name 'Internal_AutomationAccountName'
    $aroResourceGroupName = Get-AutomationVariable -Name 'Internal_ResourceGroupName'

    [string[]] $AzVMList = $VMList -split "," 

    Write-Output "Performing the action $($Action) against the classic VM list $($VMList) in the cloud service $($CloudServiceName)..." 

    foreach($VM in $AzVMList)
    {
        Write-Output "Processing the classic VM $($VM)"

        $job = ScheduleSnoozeClassicAction -CloudServiceName $CloudServiceName -VMName $VM -Action $Action

        Write-Output "Checking the job status..."

        $jobInfo = Get-AzureRmAutomationJob -Id $job.JobId -ResourceGroupName $aroResourceGroupName -AutomationAccountName $automationAccountName
        $isJobCompleted = $false

        While($isJobCompleted -ne $true)
        {
            $isJobCompleted = $true
            if($jobInfo.Status.ToLower() -ne "completed")
            {
                $isJobCompleted = $false
                $jobInfo = Get-AzureRmAutomationJob -Id $job.JobId -ResourceGroupName $aroResourceGroupName -AutomationAccountName $automationAccountName
                Write-Output "Job is currently in progress..."
                Start-Sleep -Seconds 10
            }
            else
            {
                Write-Output "Job is completed for the VM $($VM)..."
                break
            }                
        }
    }

    Write-Output "Runbook Execution Completed..."       
}
catch
{
    $ex = $_.Exception
    Write-Output $_.Exception
}
