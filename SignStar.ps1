<#
.SYNOPSIS
    Windows 10 driver signing script

.DESCRIPTION
    This script generates a new certificate for driver signing,
    copies the certificate to the appropiate certificate stores and
    signs all drivers in a specific folder and its subfolders.

.NOTES
    File Name: SignStar.ps1

.EXAMPLE
    SignStar
    Will create a new certificate and sign all drivers inside the given folder and its subfolders when no standard settings are configured.
    If a standard setting is configured this will be used.
    If no standard certificate is set then a new one gets created. If no standard folder is set the current directory will be used.

.EXAMPLE
    SignStar "foobar CA"
    Will check if certificate "foobar CA" is installed and sign everything inside the current folder and its subfolders if no standard folder is set.
    If the "foobar CA" certificate is not found create a certificate "foobar CA" and sign all drivers inside the scripts folder and its subfolders if no standard folder is set.

.EXAMPLE
    SignStar "foobar CA" "C:\foobar"
    Will check if certificate "foobar CA" is installed and sign everything inside given folder and its subfolders. Overrides standard folder.
    If the "foobar CA" certificate is not found create a certificate "foobar CA" and sign all drivers inside the given folder and its subfolders.
    Overrides standard folder in every case.

.LINK
    http://www.win-raid.com/new.php?thread=1087

.INPUTTYPE
    Takes two names of type [string]

.RETURNVALUE
    Output [string]

.PARAMETER certName
    Name of the certificate that gets created and used for signing. Not mandotory.

.PARAMETER driver
    Name of the folder that holds the drive that should be signed. Not mandotory.
#>

param(
        [parameter(Mandatory=$False, Position = 0, ValueFromPipeline = $True, HelpMessage = "Certificate Name.")]
        [alias("cn")]
        # set the standard certificate name
        [string]$certName = $null
        ,       
        [Parameter(Mandatory = $False, Position = 1, ValueFromPipeline = $True, HelpMessage = "Driver Folder.")]
        [alias("df")]
        # set the standard folder name
        [string]$driver = $null
        ,
        [Parameter(Mandatory = $False, Position = 2, ValueFromPipeline = $True, HelpMessage = "Use GUI?")]
        [alias("ug")]
        # use GUI where possible
        $useGUI = $true
)

if($args[0]) { [string]$certName = $args[0]
    if($args[1]) { [string]$driver = $args[1] }
}

function Add-Cert ($certName) {

    Write-Host Creating certificate $certName. Certificate will be placed in Root certificate store of the Local Machine...
    .\makecert.exe -r -n "CN=$certName" -ss Root -sr LocalMachine
    
    Write-Host `r`nCopying $certName into Trusted Publishers certificate store...
    $SourceStore = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Store -ArgumentList Root,LocalMachine
    $SourceStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
    $cert = $SourceStore.Certificates | Where-Object  -FilterScript { $_.subject -like "*$certName*" }
    $DestStore = New-Object  -TypeName System.Security.Cryptography.X509Certificates.X509Store -ArgumentList TrustedPublisher,LocalMachine
    $DestStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $DestStore.Add($cert)
    $SourceStore.Close()
    $DestStore.Close()
}

function Sign-Driver ($certName, $driver) {

    Write-Host "[*] Generating catalog file(s) for driver(s) in $driver..."
    .\Inf2Cat.exe /drv:""$driver"" /os:7_X64,Server2008R2_X64,8_X64,Server8_X64,6_3_X64,Server6_3_X64,10_X64,Server10_X64

    $certificates = gci *.cat -R
    if(!$certificates) {
        ForEach ($certificate in $certificates)  
        {
            Write-Host "[*] Signing $certificate..."
            $command = ".\signtool.exe sign /s Root /n ""$certName"" /t http://timestamp.verisign.com/scripts/timstamp.dll /a ""$certificate"""
            iex $command
        }
    }
    else { Write-Information "[*] Nothing to sign. No cataloges found." }    
}

if ($certName -eq $null) { # script w/o parameter, no standard certificate given: new cert + sign
    [string]$certName = Read-Host "New certificate name: "    
    if ($certName -ne $null) {
        Add-Cert ($certName)
        if ($useGUI) {
            Add-Type -AssemblyName System.Windows.Forms
            $driver = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
                Description = "Driver Folder for Signing"
                SelectedPath = $pwd
                ShowNewFolderButton = $false
                }
            if ($driver.ShowDialog() -eq "OK") { [string]$driver = $driver.SelectedPath }
            else { $driver = $pwd }
        }
        else { [string]$driverFolder = Read-Host "Driver Folder for Signing: " }
    }
    else { Throw "No name. No signing. Abort." }    
}

elseif ($certName -ne $args[0]) { # script w/o parameter, standard certificate given: sign
    Sign-Driver ($certName, $driver)
}

elseif ($certname -eq $args[0]) { # script w/ parameter: if present: sign, if not: new cert + sign
    while (!(gci cert:\LocalMachine\Root | sls "$certName")) {
        Write-Host "[*] Certificate not found. Creating $certName..."
        Add-Cert($certName)
    } # check if cert is present or create one if not present

    if ($args[1]) {
        [string]$driver = $args[1]
        Write-Host "[*] Folder given. Overriding standard folder if set."
        Sign-Driver($certName, $driver)
    } # if folder parameter is present: use it

    elseif (!$args[1] -and !$driver) {
        [string]$driver = $pwd
        Write-Host "[*] No folder given. Using current directory: $pwd"
        Sign-Driver($certName, $driver)
    } # if no folder parameter is present and no standard folder is set: use $pwd

    elseif (!$args[1] -and $driver) {
        Write-Host "[*] Standard folder set. Using directory: $driver"
        Sign-Driver($certName, $driver)
    } # if no folder parameter is present and standard folder is set: use standard folder

    else { Throw "You shouldn't be here!" }
}

else { Throw "You shouldn't be here!" }