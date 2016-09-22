param(
    [string]$DomainLDAP,
    [string]$EnvironmentAcronym = 'P'
)

Set-CoricOUStructure -DomainLDAPName $DomainLDAP -EnvironmentAcronym $EnvironmentAcronym

<#
.Synopsis
   Creates an OU
.DESCRIPTION
   Creates an OU in the given domain underneath a given OU path
.EXAMPLE
   New-OU -DomainLDAPName 'DC=Coric,DC=Hosted' -Name 'Parent'

   Creates an OU called "Parent" in the root of the Coric.Hosted domain
.EXAMPLE
   New-OU -DomainLDAPName 'DC=Coric,DC=Hosted' -Parent 'Parent' -Name 'Child'

   Creates an OU called "Child" in the "Parent" OU of the Coric.Hosted domain
#>
function New-OU
{
    [CmdletBinding()]
    [alias("eqCreateOU")]
    Param
    (
        [Parameter(Mandatory=$true,
                    HelpMessage="Fully Qualified LDAP-format domain name. i.e. DC=mydomain,DC=local")]
        [ValidateNotNullOrEmpty()]
        [alias("ParentContainer")]
        [string] $DomainLDAPName,

        [Parameter(Mandatory=$false,
                    HelpMessage="Parent OU to place new OU into")]
        [ValidateNotNullOrEmpty()]
        [alias("OU")]
        [string] $Parent,

        [Parameter(Mandatory=$true,
                    HelpMessage="OU name to create")]
        [string] $Name
    )
	if ($OU -eq '')
		{
		$Path = 'OU=' + $Name + ',' + $DomainLDAPName
		}
	else
		{
		$Path = 'OU=' + $Name + ',OU=' + $Parent + ',' + $DomainLDAPName
		}

	if ([adsi]::Exists('LDAP://' + $Path) -eq $False)
	{
		$Command = 'DSADD OU "' + $Path + '"'
		Invoke-Expression -Command $Command
	}
}



<#
.Synopsis
   Creates all required Coric OUs for the given environment
.DESCRIPTION
   Creates all Coric OUs required for an Azure-hosted system.
   Note: Only one environment is created at a time, so this should be called for each environment created (i.e. Prod, UAT, Dev)
.EXAMPLE
   Set-CoricOUStructure -DomainLDAPName 'DC=Coric,DC=Hosted'

   This would create all Coric OUs for the default Production environment for a domain called Coric.Hosted
.EXAMPLE
   Set-CoricOUStructure -DomainLDAPName 'DC=My,DC=Local' -EnvironmentAcronym 'U'

   This would create all Coric OUs for the UAT environment for a domain called My.Local
#>
function Set-CoricOUStructure
{
    [CmdletBinding()]
    [Alias("eqCreateOrganisationalUnits")]
    Param
    (
        [Parameter(Mandatory=$true,
                    HelpMessage="Fully Qualified LDAP-format domain name. i.e. DC=mydomain,DC=local")]
        [ValidateNotNullOrEmpty()]
        $DomainLDAPName,

        [Parameter(Mandatory=$false,
                    HelpMessage="Name for the parent OU which will contain all server role sub-OUs")]
        [ValidateNotNullOrEmpty()]
        $OUServerRole = 'Coric Server Roles',

        [Parameter(Mandatory=$false,
                    HelpMessage="Name for the parent OU which will contain all user sub-OUs")]
        [ValidateNotNullOrEmpty()]
        $OUCoricAccount = 'Coric Accounts',

        [Parameter(Mandatory=$false,
                    HelpMessage="Name of the Document Warehouse parent OU and sub-OU prefix")]
        [ValidateNotNullOrEmpty()]
        $OUDocumentWarehouse = 'Document Warehouse',

        [Parameter(Mandatory=$false,
                   HelpMessage="Environment acronym to create environment-specific Warehouse user access OUs for")]
        [ValidateNotNullOrEmpty()]
        [string]$EnvironmentAcronym = "P"
    )

	Write-Output 'Creating OUs'

	# server roles
	New-OU -DomainLDAPName $DomainLDAPName -Name $OUServerRole
	New-OU -DomainLDAPName $DomainLDAPName -Parent $OUServerRole -Name 'SQL'
	New-OU -DomainLDAPName $DomainLDAPName -Parent $OUServerRole -Name 'Drone'
	New-OU -DomainLDAPName $DomainLDAPName -Parent $OUServerRole -Name 'Desktop'
	New-OU -DomainLDAPName $DomainLDAPName -Parent $OUServerRole -Name 'IIS'
	New-OU -DomainLDAPName $DomainLDAPName -Parent $OUServerRole -Name 'RDG'
	New-OU -DomainLDAPName $DomainLDAPName -Parent $OUServerRole -Name 'FTP'
	New-OU -DomainLDAPName $DomainLDAPName -Parent $OUServerRole -Name 'PushPull'

	# accounts
	New-OU -DomainLDAPName $DomainLDAPName -Name $OUCoricAccount
	New-OU -DomainLDAPName $DomainLDAPName -Parent $OUCoricAccount -Name 'Service Accounts'

	# Warehouse sub-OUs
	New-OU -DomainLDAPName $DomainLDAPName -Parent $OUCoricAccount -Name $OUDocumentWarehouse
	New-OU -DomainLDAPName $DomainLDAPName -Parent ($OUDocumentWarehouse + ',OU=' + $OUCoricAccount) -Name ($OUDocumentWarehouse + ' ' + $EnvironmentAcronym.ToLower())

	New-OU -DomainLDAPName $DomainLDAPName -Parent $OUCoricAccount -Name 'Document Warehouse Access'
	New-OU -DomainLDAPName $DomainLDAPName -Parent $OUCoricAccount -Name 'Client User'
	New-OU -DomainLDAPName $DomainLDAPName -Parent $OUCoricAccount -Name 'Support'
	New-OU -DomainLDAPName $DomainLDAPName -Parent $OUCoricAccount -Name 'Groups'
}