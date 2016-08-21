Configuration CRM
{
	param
	(
		[Parameter(Mandatory=$true)]
		[string]$configuration,
		
		[Parameter(Mandatory=$true)]
		[PSCredential]$installCredential,

		[Parameter(Mandatory=$true)]
		[PSCredential]$adminCredential
	)

	Import-DscResource -ModuleName PSDesiredStateConfiguration
	Import-DscResource -ModuleName cChoco 
	Import-DscResource -ModuleName xSystemSecurity 
	Import-DscResource -ModuleName xActiveDirectory 
	Import-DscResource -ModuleName xStorage
	Import-DscResource -ModuleName xSQLServer
	Import-DscResource -ModuleName xWebAdministration
	Import-DscResource -ModuleName xPendingReboot
	
	$domainUserName = "AVANADE\\" + $adminCredential.UserName
	$domainCredential = New-Object System.Management.Automation.PSCredential ($domainUserName, $adminCredential.Password)

    $systemCredential = New-Object System.Management.Automation.PSCredential ("SYSTEM", $adminCredential.Password)
    $networkServiceCredential = New-Object System.Management.Automation.PSCredential ("NT AUTHORITY\NetworkService", $adminCredential.Password)

	$sqlFeatures = "SQLENGINE,RS,FULLTEXT"
	$sqlInstance = "MSSQLSERVER"
    $sqlServer = "localhost"

	$storageAccountName = $installCredential.UserName
	$storageAccountKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($installCredential.Password))

	Node localhost
	{
		xPendingReboot RebootCRM
        {
            Name = "RebootCRM"
        }

		LocalConfigurationManager
		{
			#DebugMode                      = 'ForceModuleImport'
			RebootNodeIfNeeded             = $true
			ConfigurationModeFrequencyMins = 15
			ConfigurationMode              = 'ApplyOnly'
			ActionAfterReboot              = 'ContinueConfiguration'
		}
    
        Script DisableFirewall 
        {
            GetScript = {
                @{
                    GetScript = $GetScript
                    SetScript = $SetScript
                    TestScript = $TestScript
                    Result = -not('True' -in (Get-NetFirewallProfile -All).Enabled)
                }
            }

            SetScript = {
                Set-NetFirewallProfile -All -Enabled False -Verbose
            }

            TestScript = {
                $Status = -not('True' -in (Get-NetFirewallProfile -All).Enabled)
                $Status -eq $True
            }
        }

		xUAC UAC
		{
			Setting = "NeverNotifyAndDisableAll"
		}
		
		xIEEsc IEAdministrators
		{
			UserRole = "Administrators"
			IsEnabled = $false
		}

		xIEEsc IEUsers
		{
			UserRole = "Users"
			IsEnabled = $false
		}

        Script EnableCredSSP
        {

            GetScript = {
                @{
                
                    Result = "CredSSP"
                }
            }

            TestScript = {
                return $false
            }
            SetScript = {
                Enable-WSManCredSSP -Role Server -Force
                Enable-WSManCredSSP -Role Client -DelegateComputer "*" -Force
            }
        }

        Registry AllowFreshCredentials
        {
            Ensure = "Present"  # You can also set Ensure to "Absent"
            Key = "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation"
            ValueName = "AllowFreshCredentials"
            ValueData = "1"
            ValueType = "Dword"
        }

        Registry AllowFreshCredentialsValue
        {
            Ensure = "Present"  # You can also set Ensure to "Absent"
            Key = "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentials"
            ValueName = "1"
            ValueData = "*"
        }

        Registry AllowFreshCredentialsWhenNTLMOnly
        {
            Ensure = "Present"  # You can also set Ensure to "Absent"
            Key = "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation"
            ValueName = "AllowFreshCredentialsWhenNTLMOnly"
            ValueData = "1"
            ValueType = "Dword"
        }

        Registry AllowFreshCredentialsWhenNTLMOnlyValue
        {
            Ensure = "Present"  # You can also set Ensure to "Absent"
            Key = "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly"
            ValueName = "1"
            ValueData = "*"
        }

		File NTDS
        {            
            DestinationPath = 'C:\NTDS'            
            Type = 'Directory'            
            Ensure = 'Present'            
        }            		
		
		File ConfigureCRM
        {
            Ensure          = "Present" 
            Type            = "File" 
            Recurse         = $false 
            Contents        = $configuration
            DestinationPath = "C:\CRM.xml"
        }

		File SourceCRMDirectory
        {
            Ensure          = "Present" 
            Type            = "Directory" 
            Recurse         = $false 
            DestinationPath = "C:\CRM2016"    
        }

        File ExtractCRMDirectory
        {
            Ensure          = "Present" 
            Type            = "Directory" 
            Recurse         = $false 
            DestinationPath = "C:\CRM2016_FULL"    
        }

        Script MapInstall
		{
			GetScript = {
				@{
					Result = "Install"
				}
			}
			TestScript = {
				Test-Path "I:\"
			}
			SetScript ={
                $a = $using:StorageAccountName
                $k = $using:StorageAccountKey
                
                $fqdn = "$a.file.core.windows.net"
                $shareUrl = "\\$fqdn\install"

                "net use I: $shareUrl /u:$a $k" | Out-File c:\install.bat -Encoding ascii
				
                $vaultType = [Windows.Security.Credentials.PasswordVault,Windows.Security.Credentials,ContentType=WindowsRuntime]
                $vault	  = new-object Windows.Security.Credentials.PasswordVault 

				$credential = new-object Windows.Security.Credentials.PasswordCredential $fqdn,$a,$k
				$vault.Add($credential)

				$vaults = $vault.RetrieveAll()
				$vaults | %{
                    Write-Verbose "vault record:"
					Write-Verbose $_.Resource
					Write-Verbose $_.UserName
                }
                
                Start-Process c:\install.bat -wait -verbose 
			}
		}

		File CopyCRM
        {
            Ensure = 'Present'
            SourcePath = 'I:\CRM2016-Server-ENU-amd64.exe'
            DestinationPath = 'C:\CRM2016\CRM2016-Server-ENU-amd64.exe'
            Recurse = $false
            Type = 'File'
        }

		File SQLDirectory
        {
            Ensure          = "Present" 
            Type            = "Directory" 
            Recurse         = $false 
            DestinationPath = "C:\SQL2014"    
        }

		
		xMountImage SqlISO
        {
			Name = "SQL Disk"
			ImagePath = "I:\en_sql_server_2014_developer_edition_with_service_pack_2_x64_dvd_8967821.iso"
			DriveLetter = "S:"
            DependsOn = '[Script]MapInstall', '[File]SQLDirectory'
        }

        Script SqlISOWait
        {
            GetScript = {
				@{
					Result = "Drive"
				}
			}
			TestScript = {
				(Get-PSDrive | ?{ $_.Root -eq 'S:\'}) -ne $null

			}
			SetScript ={
				   
                $RetryIntervalSec = 10
                $RetryCount = 60

                $driveFound = $false
                Write-Verbose -Message "Checking for drive..."

                for ($count = 0; $count -lt $RetryCount; $count++)
                {
                    $drive = (Get-PSDrive | ?{ $_.Root -eq 'S:\'})
                    if ($drive -ne $null)
                    {
                        Write-Verbose -Message "Found drive 'S:\'."
                        $driveFound = $true
                        break;
                    }
                    else
                    {
                        Write-Verbose -Message "Drive 'S:\' NOT found."
                        Write-Verbose -Message "Retrying in $RetryIntervalSec seconds ..."
                        Start-Sleep -Seconds $RetryIntervalSec
                    }
                }

                if (!$driveFound)
                {
                    throw "Drive 'S:\' NOT found after $RetryCount attempts."
                }
			}
            DependsOn = "[xMountImage]SqlISO"
        }

		File CopySQL
        {
            Ensure = 'Present'
            SourcePath = 'S:\'
            DestinationPath = 'C:\SQL2014\'
            Recurse = $true
            Type = 'Directory'
			DependsOn ='[Script]SqlISOWait'
        }

		File RemoveInstall
        {
            Ensure          = "Absent" 
            Type            = "File" 
            Recurse         = $false 
            DestinationPath = "C:\Install.bat"
			Force           = $true
			DependsOn       = '[File]CopySQL', '[File]CopyCRM'
        }

		WindowsFeature ApplicationServer
		{
		  Ensure = "Present"
		  Name = "Application-Server"
		}
    
		WindowsFeature SearchService
		{
		  Ensure = "Present"
		  Name = "Search-Service"
		}

		WindowsFeature WindowsIdentityFoundation
		{
		  Ensure = "Present"
		  Name = "Windows-Identity-Foundation"
		}

		WindowsFeature IIS
		{
		  Ensure = "Present"
		  Name = "Web-Server"
		}

		WindowsFeature AspNet
		{
		  Ensure = "Present"
		  Name = "Web-Asp-Net45"
		  DependsOn = "[WindowsFeature]IIS"
		}

		WindowsFeature WebServerManagementConsole
		{
			Name = "Web-Mgmt-Console"
			Ensure = "Present"
			DependsOn = "[WindowsFeature]AspNet"
		}

		WindowsFeature HttpActivation
		{
			Name="AS-HTTP-Activation"
			Ensure="Present"
			DependsOn = "[WindowsFeature]IIS"
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

		cChocoInstaller choco 
        { 
            InstallDir = "C:\choco" 
        }

        cChocoPackageInstaller net35
        {            
			Ensure = 'Present'
            Name = "dogtail.dotnet3.5sp1" 
			DependsOn = "[cChocoInstaller]choco"
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

			DependsOn =  '[cChocoPackageInstaller]net35', '[File]CopySQL'
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
                $args="/passive /quiet /log:c:\extract.log /extract:C:\CRM2016_FULL"
 
                Start-Process $process -ArgumentList $args -Wait
            }
            DependsON = '[File]ExtractCRMDirectory', '[Script]MapInstall', '[File]CopyCRM', '[xSQLServerRSConfig]ReportServerConfiguration'
	    }

		Script RebootCRM
		{
			GetScript = { 
				return @{result = 'RebootCRM'}}
			TestScript = {
				return (Test-Path HKLM:\SOFTWARE\Avanade.CRM\CRM.RebootKey)
			}
			SetScript = {
				New-Item -Path HKLM:\SOFTWARE\Avanade.CRM\CRM.RebootKey -Force
				# Setting the global:DSCMachineStatus = 1 tells DSC that a reboot is required
                $global:DSCMachineStatus = 1
        	}
			
			DependsOn = '[Script]ExtractCRM'
		}    

        Package InstallCRM
		{
			Ensure          = "Present"
			Name            = "CRM 2016"
			Path            = "C:\CRM2016_FULL\SetupServer.exe"
			ProductId       = '0C524D55-1409-0080-BD7E-530E52560E52'
			Arguments       = '/Q /config "c:\CRM.xml" /LV "c:\crm.log" ' # args for silent mode
            
			DependsOn       = "[File]ConfigureCRM", "[Script]ExtractCRM", "[Script]ReportServer", '[xSQLServerRSConfig]ReportServerConfiguration', '[Script]RebootCRM'

            PsDscRunAsCredential = $adminCredential
         
		}
	}
} 

