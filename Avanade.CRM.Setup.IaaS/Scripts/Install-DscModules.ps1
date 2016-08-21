

param
(
    [ValidateNotNullOrEmpty()]
    [string] 
    $DscDirectory = (Join-Path $PSScriptRoot "..\DSC"),

    [string]
    [ValidateNotNullOrEmpty()]
    $Pattern = "-ModuleName (?<value>\w*)"
)


$packageProvider = Get-PackageProvider -Name Nuget
if ($packageProvider -eq $null)
{
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}

Set-PSRepository -Name PSGallery -SourceLocation https://www.powershellgallery.com/api/v2/ -InstallationPolicy Trusted


Get-Module -ListAvailable | ?{ $_.RepositorySourceLocation -ne $null } | Uninstall-Module

$modules = Get-ChildItem $DscDirectory -Filter *.* | %{ Select-String -Path $_.FullName -Pattern $Pattern | %{ $_.Matches | %{ $_.Groups["value"].Value }}} | Select -Unique
Write-Output "DSC Modules:"
$modules

Write-Output ""
$modules | ?{ $_ -ne "PSDesiredStateConfiguration" } | %{ 

	Write-Output "Installing module $_"
	Find-Module -Name $_ | Install-Module 
} 
