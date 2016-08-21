Configuration CRM
{
	param
	(
		[Parameter(Mandatory=$true)]
		[PSCredential]$adminCredential
	)

	Import-DscResource -ModuleName PSDesiredStateConfiguration
	Import-DscResource -ModuleName xSQLServer
	
    $systemCredential = New-Object System.Management.Automation.PSCredential ("SYSTEM", $adminCredential.Password)
    $networkServiceCredential = New-Object System.Management.Automation.PSCredential ("NT AUTHORITY\NetworkService", $adminCredential.Password)

	$sqlFeatures = "SQLENGINE,RS,FULLTEXT"
	$sqlInstance = "MSSQLSERVER"
    $sqlServer = "localhost"

	Node localhost
	{
		LocalConfigurationManager
		{
			RebootNodeIfNeeded             = $true
			ConfigurationModeFrequencyMins = 15
			ConfigurationMode              = 'ApplyOnly'
			ActionAfterReboot              = 'ContinueConfiguration'
		}
    
        
		xSqlServerSetup SqlServerSetup
        {
               
            SourcePath = "C:\SQL2014\"
            SourceFolder = ""
            SetupCredential = $adminCredential
            InstanceName = $sqlInstance
            Features = $sqlFeatures

			SQLSysAdminAccounts = "NT AUTHORITY\SYSTEM"

            InstallSharedDir = "C:\Program Files\Microsoft SQL Server"
            InstallSharedWOWDir = "C:\Program Files (x86)\Microsoft SQL Server"
            InstanceDir = "C:\Program Files\Microsoft SQL Server"
            InstallSQLDataDir = "C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Data"
            SQLUserDBDir = "C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Data"
            SQLUserDBLogDir = "C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Data"
            SQLTempDBDir = "C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Data"
            SQLTempDBLogDir = "C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Data"
            SQLBackupDir = "C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Data"
			
            SQLSvcAccount = $systemCredential
            RSSvcAccount =  $systemCredential
            FTSvcAccount =  $systemCredential

			ForceReboot = $true
        }
         
        xSqlServerFirewall SqlFirewall
        {
               
            SourcePath = "C:\SQL2014\"
			SourceFolder = ""
            InstanceName =$sqlInstance
            Features = $sqlFeatures
			DependsOn = "[xSqlServerSetup]SqlServerSetup"
        }

        xSQLServerPowerPlan SqlPowerPlan
        {
            Ensure = "Present"
            DependsOn = "[xSqlServerSetup]SqlServerSetup"
        }

        xSQLServerMemory SqlServerMemory
        {
               
            Ensure = "Present"
            DynamicAlloc = $false
            MinMemory = "256"
            MaxMemory ="1024"
			SQLServer = $sqlServer
			SQLInstanceName = $sqlInstance
			DependsOn = "[xSqlServerSetup]SqlServerSetup"
        }

        xSQLServerMaxDop SqlServerMaxDop
        {
               
            Ensure = "Present"
            DynamicAlloc = $true
			SQLServer = $sqlServer
			SQLInstanceName = $sqlInstance
		    DependsOn = "[xSqlServerSetup]SqlServerSetup"
			   
        }

        Script ReportServer
		{
			GetScript = {
				@{
					Result = "ReportServer"
				}
			}
			TestScript = {
				$ns = "root\Microsoft\SqlServer\ReportServer\RS_MSSQLSERVER\v12\Admin"
                $RSObject = Get-WmiObject -class "MSReportServer_ConfigurationSetting" -namespace "$ns"
                return $RSObject.WindowsServiceIdentityActual -eq "LocalSystem"

			}
			SetScript ={
				$ns = "root\Microsoft\SqlServer\ReportServer\RS_MSSQLSERVER\v12\Admin"
                $RSObject = Get-WmiObject -class "MSReportServer_ConfigurationSetting" -namespace "$ns"
                # Set service account
                $builtInServiceAccount = "Builtin\LocalSystem"
                $useBuiltInServiceAccount = $true
                $RSObject.SetWindowsServiceIdentity($useBuiltInServiceAccount, $builtInServiceAccount, "") | out-null
                # Set virtual directory URLs
                $HTTPport = 80
                $RSObject.RemoveURL("ReportServerWebService", "http://+:$HTTPport", 1033) | out-null
                $RSObject.RemoveURL("ReportManager", "http://+:$HTTPport", 1033) | out-null
                $RSObject.SetVirtualDirectory("ReportServerWebService", "ReportServer", 1033) | out-null
                $RSObject.SetVirtualDirectory("ReportManager", "Reports", 1033) | out-null
                $RSObject.ReserveURL("ReportServerWebService", "http://+:$HTTPport", 1033) | out-null
                $RSObject.ReserveURL("ReportManager", "http://+:$HTTPport", 1033) | out-null
                # Restart service
                $serviceName = $RSObject.ServiceName
                Restart-Service -Name $serviceName -Force
			}
            DependsON = "[xSqlServerSetup]SqlServerSetup"
		}

		xSQLServerRSConfig ReportServerConfiguration
		{
            InstanceName = $sqlInstance
            RSSQLServer = $sqlServer
            RSSQLInstanceName = $sqlInstance
            SQLAdminCredential = $adminCredential

			DependsOn = "[Script]ReportServer"      
        }
	}
} 

