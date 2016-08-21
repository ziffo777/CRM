Configuration CRM
{
	param
	(
		[Parameter(Mandatory=$true)]
		[string]$configuration,
		
		[Parameter(Mandatory=$true)]
		[PSCredential]$adminCredential
	)

	Import-DscResource -ModuleName PSDesiredStateConfiguration
	
	Node localhost
	{
		LocalConfigurationManager
		{
			RebootNodeIfNeeded             = $true
			ConfigurationModeFrequencyMins = 15
			ConfigurationMode              = 'ApplyOnly'
			ActionAfterReboot              = 'ContinueConfiguration'
		}
    	
		Script ExtractCRM
		{
			GetScript = {
				@{ Result = "CRM" }
			}
			TestScript = {
				Test-Path "C:\CRM2016_FULL\SetupServer.exe"
			}
		    SetScript = {
                $process="C:\CRM2016\CRM2016-Server-ENU-amd64.exe"
                $args="/passive /quiet /log:c:\CRM2016\crm.extract.log /extract:C:\CRM2016_FULL"
 
                Start-Process $process -ArgumentList $args -Wait
            }
	    }

		File ConfigureCRM
        {
            Ensure          = "Present" 
            Type            = "File" 
            Recurse         = $false 
            Contents        = $configuration
            DestinationPath = "C:\CRM2016\crm.configuration.xml"
        }

		Script IgnoreRestart
		{
			GetScript = {
				@{ Result = "CRM" }
			}
			TestScript = {
				return ((Test-Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce) -eq $false)
			}
			SetScript = {
				Remove-Item HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce -Force
            }
			DependsOn = "[Script]ExtractCRM"
	    }

        Package InstallCRM
		{
			Ensure          = "Present"
			Name            = "CRM 2016"
			Path            = "C:\CRM2016_FULL\SetupServer.exe"
			ProductId       = '0C524D55-1409-0080-BD7E-530E52560E52'
			Arguments       = '/Q /config "c:\CRM2016\crm.configuration.xml" /LV "c:\CRM2016\crm.setup.log" ' # args for silent mode
            
			DependsOn       = "[Script]ExtractCRM", "[File]ConfigureCRM", "[Script]IgnoreRestart"

            PsDscRunAsCredential = $adminCredential
         
		}
	}
} 

