Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName PresentationFramework

$wshell = New-Object -ComObject Wscript.Shell

function Unzip
{
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

function Load-Xaml {
	[xml]$xaml = Get-Content -Path $PSScriptRoot\uevutil.xaml
	$manager = New-Object System.Xml.XmlNamespaceManager -ArgumentList $xaml.NameTable
	$manager.AddNamespace("x", "http://schemas.microsoft.com/winfx/2006/xaml");
	$xamlReader = New-Object System.Xml.XmlNodeReader $xaml
	[Windows.Markup.XamlReader]::Load($xamlReader)
}
$window = Load-Xaml

# WPF controls
$packagelist = $window.FindName("packagelist")
$registrylist = $window.FindName("registrylist")
$filelist = $window.FindName("filelist")
$restorebtn = $window.FindName("restorebtn")
$clearbtn = $window.FindName("clearbtn")
$enabledisable = $window.FindName("enabledisable")
$reloadtemplates = $window.FindName("reloadtemplates")
$localpkgcache = $window.FindName("localpkgcache")
$loadsettings = $window.FindName("loadsettings")
$importsettings = $window.FindName("importsettings")
$networkpackagepath = $window.FindName("networkpackagepath")
$pkgxfilename = $window.FindName("pkgxfilename")
$uevstatus = $window.FindName("uevstatus")
# $ = $window.FindName("")

function clear-localuevcache() {
    # $packagefolder = (Get-ItemProperty -path registry::hkcu\software\microsoft\uev\agent\configuration -name settingsstoragepath).settingsstoragepath
	$localcache = $env:localappdata + "\Microsoft\UEV"
	# Get-ChildItem $localcache\* -Recurse | Remove-Item
}

function clear-settingspackages() {
	$packagefolder = $configuration.SettingsStoragePath
    # $packagefolder = (Get-ItemProperty -path registry::hkcu\software\microsoft\uev\agent\configuration -name settingsstoragepath).settingsstoragepath
	# Get-ChildItem $packagefolder\settingspackages\* -Recurse | Remove-Item
}

function get-uevpackages() {
    # $packagefolder = (Get-ItemProperty -path registry::hkcu\software\microsoft\uev\agent\configuration -name settingsstoragepath).settingsstoragepath
    # get each folder in settingspackages
	$packages = get-childitem $packagefolder -Directory
	$packagelist.ItemsSource = $packages
	$packagelist.DisplayMemberPath = 'Name'
	$packagelist.SelectedIndex = 0
	# return $packagelist
}

function get-uevtemplates() {
    return (Get-UevTemplate | select templateid, templatename, templatetype)
}

function restore-uevpackage ($filename) {
	$basepath = $filename.replace($filename.split("\")[-1],"")
    # this function gets the contents of a specified pkgx file and restores the files and registry keys stored in it
    [xml]$settings = export-uevpackage $filename
    $registry = $settings.settingsdocument.registry.setting | select-object -property type, name, '#text'
    $files = $settings.settingsdocument.file.setting | select-object -property type, name, '#text'
    foreach ($reg in $registry) {
        $type = $reg.type.replace("VT_", "")
        $path = $reg.name.replace("registry://", "registry::")
        $value = $reg.'#text'
		$name = $path.split("\")[-1]
		$baseregpath = $path.replace("\$name", "")
		$baseregname = $baseregpath.split("\")[-1]
		$baseregfolder = $baseregpath.replace("\$baseregname", "")
		$test = Test-Path $baseregpath
		if ($test -eq $false) { # create registry path if it doesn't exist
			New-Item -Path $baseregfolder -name $baseregname -Force
		}
		if ($type -eq "MULTI_STRING") { $type = "multistring" }
		if ($type -eq "BINARY") {
			$value = [System.Convert]::FromBase64String($value)
		}
		New-ItemProperty -Path $baseregpath -Name $name -PropertyType $type -value $value -Force
        # Set-ItemProperty -Path HKCU:\Environment -Name Path -Value $newpath
    }
	# unzip the pkgx to grab any small files.
	$tmp = $env:TEMP + "\" + $filename.split("\")[-1]
	unzip $filename $tmp

    foreach ($file in $files) {
		if ($file.'#text' -ne $null) {
			$path = [System.Environment]::ExpandEnvironmentVariables($file.name.replace("file://", ""))
			$pkgdat = $file.'#text'
			$pkgdat = $basepath+$pkgdat
			if (Test-Path $pkgdat) {
				copy-item -path $pkgdat -destination $path -Force
			} else {
				if (test-path $tmp\files\$file.'#text') {
					copy-item -path $tmp\files\$file.'#text' -destination $path -Force
				}
			}
		}
	}
	# remove temp folder used in restore
	Remove-Item $tmp -recurse -force
	$wshell.Popup("Restore Completed",0,"Done",0x0)
}

function load-uevpackage ($filename) {
	# Write-Host $filename
	$registrylist.Items.Clear();
	$filelist.Items.Clear();
    # this function gets the contents of a specified pkgx file and restores the files and registry keys stored in it
    [xml]$settings = export-uevpackage $filename
    $registry = $settings.settingsdocument.registry.setting | select-object -property type, name, '#text'
    $files = $settings.settingsdocument.file.setting | select-object -property type, name, '#text'
    foreach ($reg in $registry) {
        $type = $reg.type.replace("VT_", "")
        $path = $reg.name.replace("registry://", "")
        $value = $reg.'#text'
		$row = [PSCustomObject]@{type = $type;path = $path;value = $value}
		$registrylist.AddChild($row)
        # write-output $type, $path, $value
    }
    foreach ($file in $files) {
		if ($file.'#text' -ne $null) {
			$path = [System.Environment]::ExpandEnvironmentVariables($file.name.replace("file://", ""))
			$pkgdatname = $file.'#text'
			$row = [PSCustomObject]@{path = $path;pkgdatname = $pkgdatname}
			$filelist.AddChild($row)
		}
    }
}


Function Get-FileName() {
    param(
        [Parameter(Mandatory=$false)][string]$initialDirectory
    )
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = "All files (*.pkgx)| *.pkgx"
    $OpenFileDialog.ShowDialog() | Out-Null
	$packagename = $OpenFileDialog.filename
	if ($packagename -ne "") {
		$pkgxfilename.text = $packagename
		load-uevpackage $packagename
	}
}

function refresh-templates() {
	Unregister-UevTemplate -All
	# verify the templates are valid
	$templates = Get-ChildItem ($configuration.settingstemplatecatalogpath + "\*.xml")
	foreach ($template in $templates) {
		if ((Test-UevTemplate $template).status -ne "Valid") {
			$wshell.Popup("Error in template $template",0,"error",0x0)
		} else {
			Register-UevTemplate $template
		}
	}
	$wshell.Popup("Templates refreshed from template catalog",0,"Done",0x0)
}

#
# button bindings
#
$restorebtn.Add_click({
	$packagename = $pkgxfilename.text
	restore-uevpackage $packagename
})

$reloadtemplates.Add_click({
	refresh-templates
})

$clearbtn.Add_click({
	# clear cache function
})

$loadsettings.Add_click({
	$packagename = $configuration.SettingsStoragePath + "\settingspackages\" + $packagelist.SelectedValue + "\" + $packagelist.SelectedValue + ".pkgx"
	$pkgxfilename.text = $packagename
	load-uevpackage $packagename
})

$importsettings.Add_click({
	Get-FileName
})

$enabledisable.Add_click({
	$isenabled = (get-uevstatus).uevenabled
	if ($isenabled -eq $true) {
		Disable-Uev
	} else {
		Enable-Uev
	}
	$isenabled = (get-uevstatus).uevenabled
	if ($isenabled -eq $true) {
		$uevstatus.Content = "UE-V Enabled"
		$enabledisable.content = "Disable UE-V"
	} else {
		$uevstatus.Content = "UE-V Disabled"
		$enabledisable.content = "Enable UE-V"
	}
})

# sanity checks

# ue-v powershell cmdlets are present
try {
	$configuration = Get-UevConfiguration
} catch {
	Write-Host "Could not get configuration via powershell cmdlets"
	exit
}

# settingspackages path exists
$test = Test-Path $configuration.settingsstoragepath
if ($test -eq $false) {
	Write-Host "Settings packages path doesn't exist"
	exit
}

# template repo exists
$test = Test-Path $configuration.settingstemplatecatalogpath
if ($test -eq $false) {
	Write-Host "Templates catalog path doesn't exist"
	exit
}

# os version, win10 only.
$osversion = (gwmi Win32_OperatingSystem).version

# test elevation.  cannot perform some tasks without it.
$elevated = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")
if ($elevated -eq $false) {
	$enabledisable.isenabled = $false
	$enabledisable.ToolTip = "run in elevated mode for this function"
	$reloadtemplates.isenabled = $false
	$reloadtemplates.tooltip = "run in elevated mode for this function"
}

# initialization

$configuration = Get-UevConfiguration
$uevstatus.content = $isenabled
$packagefolder = $configuration.SettingsStoragePath + "\settingspackages"
$networkpackagepath.text = $packagefolder
$localpkgcache.text = $env:localappdata + "\Microsoft\UEV"

$isenabled = (get-uevstatus).uevenabled
if ($isenabled -eq $true) {
	$uevstatus.Content = "UE-V Enabled"
	$enabledisable.content = "Disable UE-V"
} else {
	$uevstatus.Content = "UE-V Disabled"
	$enabledisable.content = "Enable UE-V"
}
get-uevpackages
$templates = get-uevtemplates

$window.ShowDialog() > $null