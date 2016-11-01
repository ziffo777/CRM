#Requires -Version 3.0
#Requires -Module AzureRM.Resources
#Requires -Module Azure.Storage

Param(

	[Parameter()]
	[ValidateNotNullOrEmpty()]
	[string] 
	$ResourceGroupName = "msalmcrm",
        
	[Parameter()]
	[ValidateNotNullOrEmpty()]
	[string] 
	$ResourceGroupLocation = "West Europe",
    
	[switch] 
	$UploadArtifacts,
    
	[Parameter()]
	[ValidateNotNullOrEmpty()]
	[string] 
	$StorageAccountName = "msalmcrm",
    
	[Parameter()]
	[ValidateNotNullOrEmpty()]
	[string] 
	$StorageContainerName = $ResourceGroupName.ToLowerInvariant() + '-stageartifacts',
    
	[Parameter()]
	[string]
	$ProjectName = "Avanade.CRM.Setup.IaaS",

	[Parameter()]
	[ValidateNotNullOrEmpty()]
	[string] 
	$TemplateFile = '..\Templates\azuredeploy.json',
    
	[Parameter()]
	[ValidateNotNullOrEmpty()]
	[string] 
	$TemplateParametersFile = '..\Templates\azuredeploy.parameters.json',
    
	[Parameter()]
	[ValidateNotNullOrEmpty()]
	[string] 
	$ArtifactStagingDirectory = "..\..\$ProjectName\",
    
	[Parameter()]
	[ValidateNotNullOrEmpty()]
	[string] 
	$DSCSourceFolder = '..\DSC',

	[Parameter()]
	[ValidateNotNullOrEmpty()]
	[string] 
	$vmName = 'msalmcrm',

	[Parameter()]
	[ValidateNotNullOrEmpty()]
	[string] 
	$AdminUserName = "crm",

	[Parameter(Mandatory=$true)]
	[ValidateNotNullOrEmpty()]
	[securestring] 
	$AdminPassword


)

Import-Module Azure -ErrorAction SilentlyContinue

try {
    [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent("VSAzureTools-$UI$($host.name)".replace(" ","_"), "2.9")
} catch { }

Set-StrictMode -Version 3

$configurationPath = Join-Path $PSScriptRoot "Configuration.xml"
[string]$configuration = Get-Content $configurationPath


$storageAccount = Get-AzureRmStorageAccount | Where-Object{$_.StorageAccountName -eq $StorageAccountName}
if ($storageAccount -eq $null)
{
	throw "Storage account $StorageAccountName not found."
}

$storageResourceGroupName = $storageAccount.ResourceGroupName
$storageKeyDetails = Get-AzureRMStorageAccountKey -ResourceGroupName $storageResourceGroupName -Name $storageAccountName -ErrorAction Stop
$storageAccountKey = ConvertTo-SecureString $storageKeyDetails[0].Value -AsPlainText -Force

$OptionalParameters = New-Object -TypeName Hashtable
$OptionalParameters.Add("storageAccountName",$storageAccountName)
$OptionalParameters.Add("storageAccountKey",$storageAccountKey)
$OptionalParameters.Add("configuration",$configuration)
$OptionalParameters.Add("vmName",$vmName)
$OptionalParameters.Add("adminUserName", $AdminUserName)
$OptionalParameters.Add("adminPassword", $AdminPassword)


$TemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $TemplateFile))
$TemplateParametersFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $TemplateParametersFile))

if ($UploadArtifacts) {
    # Convert relative paths to absolute paths if needed
    $ArtifactStagingDirectory = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $ArtifactStagingDirectory))
    $DSCSourceFolder = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCSourceFolder))

	Write-Verbose -Verbose -Message "DCS MODULES INSTALLATION START"

	. (Join-Path $PSScriptRoot 'Install-DscModules.ps1') -DscDirectory $DSCSourceFolder

	Write-Verbose -Verbose -Message "DCS MODULES INSTALLED"

    Set-Variable ArtifactsLocationName '_artifactsLocation' -Option ReadOnly -Force
    Set-Variable ArtifactsLocationSasTokenName '_artifactsLocationSasToken' -Option ReadOnly -Force

    $OptionalParameters.Add($ArtifactsLocationName, $null)
    $OptionalParameters.Add($ArtifactsLocationSasTokenName, $null)

    # Parse the parameter file and update the values of artifacts location and artifacts location SAS token if they are present
    $JsonContent = Get-Content $TemplateParametersFile -Raw | ConvertFrom-Json
    $JsonParameters = $JsonContent | Get-Member -Type NoteProperty | Where-Object {$_.Name -eq "parameters"}

    if ($JsonParameters -eq $null) {
        $JsonParameters = $JsonContent
    }
    else {
        $JsonParameters = $JsonContent.parameters
    }

    $JsonParameters | Get-Member -Type NoteProperty | ForEach-Object {
        $ParameterValue = $JsonParameters | Select-Object -ExpandProperty $_.Name

        if ($_.Name -eq $ArtifactsLocationName -or $_.Name -eq $ArtifactsLocationSasTokenName) {
            $OptionalParameters[$_.Name] = $ParameterValue.value
        }
    }

    $StorageAccountContext = $storageAccount.Context
	
    # Generate the value for artifacts location if it is not provided in the parameter file
    $ArtifactsLocation = $OptionalParameters[$ArtifactsLocationName]
    if ($ArtifactsLocation -eq $null) {
        $ArtifactsLocation = $StorageAccountContext.BlobEndPoint + $StorageContainerName
        $OptionalParameters[$ArtifactsLocationName] = $ArtifactsLocation
    }

    # Copy files from the local storage staging location to the storage account container
    New-AzureStorageContainer -Name $StorageContainerName -Context $StorageAccountContext -Permission Container -ErrorAction SilentlyContinue *>&1

    $ArtifactFilePaths = Get-ChildItem $ArtifactStagingDirectory -Recurse -File | ForEach-Object -Process {$_.FullName}
    foreach ($SourcePath in $ArtifactFilePaths) {
        $BlobName = $ProjectName + '\' + $SourcePath.Replace($ArtifactStagingDirectory, "").Trim('\')
        Set-AzureStorageBlobContent -File $SourcePath -Blob $BlobName -Container $StorageContainerName -Context $StorageAccountContext -Force
    }

    # Generate the value for artifacts location SAS token if it is not provided in the parameter file
    $ArtifactsLocationSasToken = $OptionalParameters[$ArtifactsLocationSasTokenName]
    if ($ArtifactsLocationSasToken -eq $null) {
        # Create a SAS token for the storage container - this gives temporary read-only access to the container
        $ArtifactsLocationSasToken = New-AzureStorageContainerSASToken -Container $StorageContainerName -Context $StorageAccountContext -Permission r -ExpiryTime (Get-Date).AddHours(4)
        $ArtifactsLocationSasToken = ConvertTo-SecureString $ArtifactsLocationSasToken -AsPlainText -Force
        $OptionalParameters[$ArtifactsLocationSasTokenName] = $ArtifactsLocationSasToken
    }

	$dscResourceGroupName = $storageAccount.ResourceGroupName


	Write-Verbose -Verbose -Message "DscFolder: $DSCSourceFolder"
	
	Get-ChildItem -Path $DSCSourceFolder *.ps1 |%{
		$sourceFilePath = $_.FullName
		$targetFileName = $_.Name + ".zip"
		$targetFilePath = Join-Path $ArtifactStagingDirectory $targetFileName

		Write-Verbose -Verbose -Message "Publishing $sourceFilePath to $targetFilePath"
		Publish-AzureRmVMDscConfiguration -ConfigurationPath $sourceFilePath -OutputArchivePath $targetFilePath -Force
		Set-AzureStorageBlobContent -File $targetFilePath -Blob ($ProjectName + '\' +$targetFileName) -Container $StorageContainerName -Context $StorageAccountContext -Force
	}
}



# Create or update the resource group using the specified template file and template parameters file
New-AzureRmResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Verbose -Force -ErrorAction Stop 

New-AzureRmResourceGroupDeployment -Name ((Get-ChildItem $TemplateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
                                   -ResourceGroupName $ResourceGroupName `
                                   -TemplateFile $TemplateFile `
                                   -TemplateParameterFile $TemplateParametersFile `
                                   @OptionalParameters `
                                   -Force -Verbose