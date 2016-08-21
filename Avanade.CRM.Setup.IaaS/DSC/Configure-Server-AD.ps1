Configuration CRM
{
	param
	(
		[Parameter(Mandatory=$true)]
		[PSCredential]$adminCredential
	)

	Import-DscResource -ModuleName PSDesiredStateConfiguration
	Import-DscResource -ModuleName xActiveDirectory 
	
	$domainUserName = "AVANADE\\" + $adminCredential.UserName
	$domainCredential = New-Object System.Management.Automation.PSCredential ($domainUserName, $adminCredential.Password)

    Node localhost
	{
		LocalConfigurationManager
		{
			RebootNodeIfNeeded             = $true
			ConfigurationModeFrequencyMins = 15
			ConfigurationMode              = 'ApplyOnly'
			ActionAfterReboot              = 'ContinueConfiguration'
		}
    
		
   
        WindowsFeature ADDSInstall             
        {             
            Ensure = "Present"             
            Name = "AD-Domain-Services"             
        }            
            
        # Optional GUI tools            
        WindowsFeature ADDSTools            
        {             
            Ensure = "Present"             
            Name = "RSAT-ADDS"             
        }            

	    File NTDS
        {            
            DestinationPath = 'C:\NTDS'            
            Type = 'Directory'            
            Ensure = 'Present'            
        }            		
	
		
        # No slash at end of folder paths            
        xADDomain ADDomain             
        {             
            DomainName = "avanade.com"             
            DomainAdministratorCredential = $domainCredential
            SafemodeAdministratorPassword = $adminCredential
            DatabasePath = 'C:\NTDS\DB'            
            LogPath = 'C:\NTDS\Log'            
            SysvolPath = 'C:\NTDS\SysVol'
            DependsOn = "[WindowsFeature]ADDSInstall","[File]NTDS"            
        }   

		xADOrganizationalUnit OU
        {
           Ensure = 'Present'
           Name = "CRM"
           Path = "dc=avanade,dc=com"
           ProtectedFromAccidentalDeletion = $true
           DependsOn = "[xADDomain]ADDomain"

		   PsDscRunAsCredential = $adminCredential
        }

		
	}
} 

