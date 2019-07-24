<#
.SYNOPSIS  
 Wrapper script for start & stop AzureRM VM's
.DESCRIPTION  
 Wrapper script for start & stop AzureRM VM's
.EXAMPLE  
.\ScheduledStartStop_Child.ps1 -VMName "Value1" -Action "Value2" -ResourceGroupName "Value3" 
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

        Write-Output "VM action is : $($Action)"
            
        if ($Action.Trim().ToLower() -eq "stop")
        {
            Write-Output "Stopping the VM : $($VMName)"

            $Status = Stop-AzureRmVM -Name $VMName -ResourceGroupName $ResourceGroupName -Force

            if($Status -eq $null)
            {
                Write-Output "Error occured while stopping the Virtual Machine $($VMName)"
            }
            else
            {
            Write-Output "Successfully stopped the VM $VMName"
            }
        }
        elseif($Action.Trim().ToLower() -eq "start")
        {
            Write-Output "Starting the VM : $($VMName)"

            $Status = Start-AzureRmVM -Name $VMName -ResourceGroupName $ResourceGroupName

            if($Status -eq $null)
            {
                Write-Output "Error occured while starting the Virtual Machine $($VMName)"
            }
            else
            {
                Write-Output "Successfully started the VM $($VMName)"
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
