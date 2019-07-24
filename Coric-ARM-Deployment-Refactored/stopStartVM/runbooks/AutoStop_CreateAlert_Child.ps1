    param(
        $VMObject,
        [string]$AlertAction,
        [string]$WebhookUri
    )


#-----Function to generate unique alert name-----
function Generate-AlertName 
{
    param ([string] $OldAlertName , 
     [string] $VMName)
         
    [string[]] $AlertSplit = $OldAlertName -split "-"
    [int] $Number =$AlertSplit[$AlertSplit.Length-1]
    $Number++
    $Newalertname = "Alert-$($VMName)-$Number"
    return $Newalertname
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

#-----Prepare the inputs for alert attributes-----
$threshold = Get-AutomationVariable -Name 'External_AutoStop_Threshold'
$metricName = Get-AutomationVariable -Name 'External_AutoStop_MetricName'
$timeWindow = Get-AutomationVariable -Name 'External_AutoStop_TimeWindow'
$condition = Get-AutomationVariable -Name 'External_AutoStop_Condition' # Other valid values are LessThanOrEqual, GreaterThan, GreaterThanOrEqual
$description = Get-AutomationVariable -Name 'External_AutoStop_Description'
$timeAggregationOperator = Get-AutomationVariable -Name 'External_AutoStop_TimeAggregationOperator'
$webhookUri = Get-AutomationVariable -Name 'Internal_AutoSnooze_WebhookUri'


try
{
	Write-Output "Runbook execution started..." 
    $ResourceGroupName =$VMObject.ResourceGroupName
    $Location = $VMObject.Location
	Write-Output "Location...$($VMObject.Location)" 
	Write-Output "getting status..." 
	if (($VMObject.Type -eq "Classic") -and ($enableClassicVMs))
	{
		$currentVM = Get-AzureVM | where Name -Like $VMObject.Name
		$VMState = $currentVM.InstanceStatus
		
		$resourceId = "/subscriptions/$($SubId)/resourceGroups/$ResourceGroupName/providers/Microsoft.ClassicCompute/virtualMachines/$($VMObject.Name.Trim())"
	}
	else
	{
		$VMState = (Get-AzureRmVM -ResourceGroupName $VMObject.ResourceGroupName -Name $VMObject.Name -Status -ErrorAction SilentlyContinue).Statuses.Code[1] 
		
		$resourceId = "/subscriptions/$($SubId)/resourceGroups/$ResourceGroupName/providers/Microsoft.Compute/virtualMachines/$($VMObject.Name.Trim())"
	}
    Write-Output "Processing VM ($($VMObject.Name))"
    Write-Output "Current VM state is ($($VMState))"
    $actionWebhook = New-AzureRmAlertRuleWebhook -ServiceUri $WebhookUri
    
    $NewAlertName ="Alert-$($VMObject.Name)-1"
                                                 
    if($AlertAction -eq "Disable")
    {
        $ExVMAlerts = Get-AzureRmAlertRule -ResourceGroup $VMObject.ResourceGroupName -DetailedOutput -ErrorAction SilentlyContinue
                 if($ExVMAlerts -ne $null)
                    {
                        Write-Output "Checking for any previous alert(s)..." 
                        #Alerts exists so disable alert
                        foreach($Alert in $ExVMAlerts)
                        {
                                                
                            if($Alert.Name.ToLower().Contains($($VMObject.Name.ToLower().Trim())))
                            {
                                Write-Output "Previous alert ($($Alert.Name)) found and disabling now..." 
                                 Add-AzureRmMetricAlertRule  -Name  $Alert.Name `
                                        -Location  $Alert.Location `
                                        -ResourceGroup $ResourceGroupName `
                                        -TargetResourceId $resourceId `
                                        -MetricName $metricName `
                                        -Operator  $condition `
                                        -Threshold $threshold `
                                        -WindowSize  $timeWindow `
                                        -TimeAggregationOperator $timeAggregationOperator `
                                        -Action $actionWebhook `
                                        -Description $description -DisableRule 

                                        Write-Output "Alert ($($Alert.Name)) Disabled for VM $($VMObject.Name)"
                                    
                            }
                        }
                           
                    }
    }
    elseif($AlertAction -eq "Create")
    {
        #Getting ResourcegroupName and Location based on VM  
                    
                        if (($VMState -eq 'PowerState/running') -or ($VMState -eq 'ReadyRole'))
                        {                     
                            try
                            {
								Write-Output "Creating alerts..." 
                                $VMAlerts = Get-AzureRmAlertRule -ResourceGroup $ResourceGroupName -DetailedOutput -ErrorAction SilentlyContinue

                                #Check if alerts exists and take action
                                if($VMAlerts -ne $null)
                                {
                                    Write-Output "Checking for any previous alert(s)..." 
                                    #Alerts exists so delete and re-create the new alert
                                    foreach($Alert in $VMAlerts)
                                    {
                                                
                                        if($Alert.Name.ToLower().Contains($($VMObject.Name.ToLower().Trim())))
                                        {
                                            Write-Output "Previous alert ($($Alert.Name)) found and deleting now..." 
                                            #Remove the old alert
                                            Remove-AzureRmAlertRule -Name $Alert.Name -ResourceGroup $ResourceGroupName
                                   
                                            #Wait for few seconds to make sure it processed 
                                            Do
                                            {
                                               #Start-Sleep 10    
                                               $GetAlert=Get-AzureRmAlertRule -ResourceGroup $ResourceGroupName -Name $Alert.Name -DetailedOutput -ErrorAction SilentlyContinue                                       
                                                        
                                            }
                                            while($GetAlert -ne $null)
                                   
                                            Write-Output "Generating a new alert with unique name..."
                                            #Now generate new unique alert name
                                            $NewAlertName = Generate-AlertName -OldAlertName $Alert.Name -VMName $VMObject.Name               
                                    
                                        }
                                     }
                           
                                }
                                 #Alert does not exist, so create new alert
                                 Write-Output $NewAlertName                
                                 
                                 Write-Output "Adding a new alert to the VM..."
                                 
                                 Add-AzureRmMetricAlertRule  -Name  $NewAlertName `
                                        -Location  $location `
                                        -ResourceGroup $ResourceGroupName `
                                        -TargetResourceId $resourceId `
                                        -MetricName $metricName `
                                        -Operator  $condition `
                                        -Threshold $threshold `
                                        -WindowSize  $timeWindow `
                                        -TimeAggregationOperator $timeAggregationOperator `
                                        -Action $actionWebhook `
                                        -Description $description               
                               
                                           
                               Write-Output  "Alert Created for VM $($VMObject.Name.Trim())"    
                            }
                            catch
                            {
                             Write-Output "Error Occurred"   
                             Write-Output $_.Exception
                            }
                    
                         }
                         else
                         {
                            Write-Output " $($VM.Name) is De-allocated"
                         }
    }
  }
  catch
  {
    Write-Output "Error Occurred"   
    Write-Output $_.Exception
  }  

