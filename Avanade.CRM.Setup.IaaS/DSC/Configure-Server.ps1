Configuration CRM
{
	param
	(
		[Parameter(Mandatory=$true)]
		[PSCredential]$installCredential
	)

	Import-DscResource -ModuleName PSDesiredStateConfiguration
	Import-DscResource -ModuleName xSystemSecurity 
	Import-DscResource -ModuleName xStorage
	Import-DscResource -ModuleName cChoco 

	
	$storageAccountName = $installCredential.UserName
	$storageAccountKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($installCredential.Password))

	Node localhost
	{
		LocalConfigurationManager
		{
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

		cChocoPackageInstaller vcredist2010
        {            
			Ensure = 'Present'
            Name = "vcredist2010" 
			DependsOn = "[cChocoInstaller]choco"
        } 

		cChocoPackageInstaller vcredist2012
        {            
			Ensure = 'Present'
            Name = "vcredist2012" 
			DependsOn = "[cChocoInstaller]choco"
        } 

		cChocoPackageInstaller vcredist2013
        {            
			Ensure = 'Present'
            Name = "vcredist2013" 
			DependsOn = "[cChocoInstaller]choco"
        } 

		cChocoPackageInstaller vcredist2015
        {            
			Ensure = 'Present'
            Name = "vcredist2015" 
			DependsOn = "[cChocoInstaller]choco"
        } 

		cChocoPackageInstaller sql2012.clrtypes
        {            
			Ensure = 'Present'
            Name = "sql2012.clrtypes" 
			DependsOn = "[cChocoInstaller]choco"
        } 

		cChocoPackageInstaller sql2008r2.nativeclient
        {            
			Ensure = 'Present'
            Name = "sql2008r2.nativeclient" 
			DependsOn = "[cChocoInstaller]choco"
        } 

		cChocoPackageInstaller sql2012.smo
        {            
			Ensure = 'Present'
            Name = "sql2012.smo" 
			DependsOn = "[cChocoInstaller]choco"
        } 

		cChocoPackageInstaller reportviewer2010sp1
        {            
			Ensure = 'Present'
            Name = "reportviewer2010sp1" 
			DependsOn = "[cChocoInstaller]choco"
        } 
		
	}
} 

