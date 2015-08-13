﻿<#
.SYNOPSIS

Install the LANSA IDE.
Creates a SQL Server Database then installs from the DVD image

Requires the environment that a LANSA Cake provides, particularly an AMI license.

# N.B. It is vital that the user id and password supplied pass the password rules. 
E.g. The password is sufficiently complex and the userid is not duplicated in the password. 
i.e. UID=PCXUSER and PWD=PCXUSER@#$%^&* is invalid as the password starts with the entire user id "PCXUSER".

.EXAMPLE


#>
param(
[String]$server_name=$env:COMPUTERNAME,
[String]$dbname='LANSA',
[String]$dbuser = 'administrator',
[String]$dbpassword = 'password',
[String]$webuser = 'PCXUSER2',
[String]$webpassword = 'PCXUSER@122',
[String]$f32bit = 'true',
[String]$SUDB = '1',
[String]$UPGD = 'false',
[String]$maxconnections = '20',
[String]$wait
)

# Put first output on a new line in cfn_init log file
Write-Output ("`r`n")

$trusted=$true

Write-Debug ("Server_name = $server_name")
Write-Debug ("dbname = $dbname")
Write-Debug ("dbuser = $dbuser")
Write-Debug ("webuser = $webuser")
Write-Debug ("32bit = $f32bit")
Write-Debug ("SUDB = $SUDB")
Write-Debug ("UPGD = $UPGD")

try
{
    if ( $f32bit -eq 'true' -or $f32bit -eq '1')
    {
        $f32bit_bool = $true
    }
    else
    {
        $f32bit_bool = $false
    }

    if ( $UPGD -eq 'true' -or $UPGD -eq '1')
    {
        $UPGD_bool = $true
    }
    else
    {
        $UPGD_bool = $false
    }

    Write-Debug ("UPGD_bool = $UPGD_bool" )

    $x_err = (Join-Path -Path $ENV:TEMP -ChildPath 'x_err.log')
    Remove-Item $x_err -Force -ErrorAction SilentlyContinue

    # On initial install disable TCP Offloading

    if ( -not $UPGD_bool )
    {
        Disable-TcpOffloading
    }

    ######################################
    # Require MS C runtime to be installed
    ######################################

    # Ensure SQL Server Powershell module is loaded

    Import-Module “sqlps”

    if ( $SUDB -eq '1' -and -not $UPGD_bool)
    {
        Create-SqlServerDatabase $server_name $dbname
    }

    # Enable Named Pipes on database

    Change-SQLProtocolStatus -server $server_name -instance "MSSQLSERVER" -protocol "NP" -enable $true

    $service = get-service "MSSQLSERVER"  
    restart-service $service.name -force #Restart SQL Services 

    if ( -not $UPGD_bool )
    {
        Start-WebAppPool -Name "DefaultAppPool"
    }

    # Speed up the start of the VL IDE
    # Switch off looking for software license keys

    [Environment]::SetEnvironmentVariable('LSFORCEHOST', 'NO-NET', 'Machine')

    Write-Output ("Installing the application")

    if ($f32bit_bool)
    {
        $APPA = "${ENV:ProgramFiles(x86)}\LANSA"
    }
    else
    {
        $APPA = "${ENV:ProgramFiles}\LANSA"
    }

    # Pull down DVD image 
    &aws "s3 sync  s3://lansa/releasedbuilds/v13/LanDVDcut_L4W13200_4088_Latest $Script:DvdDir `
        --exclude *ibmi/* `
        --exclude *AS400/* `
        --exclude *linux/* `
        --exclude *setup/Installs/MSSQLEXP/* `
        --delete" | Write-Output

    Install-VisualLansa

    Install-Integrator 

    Write-Output "IDE Installation completed"

    #####################################################################################
    # Test if post install x_run processing had any fatal errors
    #####################################################################################

    if ( (Test-Path -Path $x_err) )
    {
        Write-Verbose ("Signal to caller that the installation has failed")

        $errorRecord = New-ErrorRecord System.Configuration.Install.InstallException RegionDoesNotExist `
            NotInstalled $region -Message "$x_err exists and indicates an installation error has occurred."
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

	Write-output ("Remap licenses to new instance Guid and set permissions so that webuser may access them" )

	Map-LicenseToUser "LANSA Scalable License" "ScalableLicensePrivateKey" $webuser
	Map-LicenseToUser "LANSA Integrator License" "IntegratorLicensePrivateKey" $webuser
	Map-LicenseToUser "LANSA Development License" "DevelopmentLicensePrivateKey" $webuser

	Write-output ("Allow webuser to create directory in c:\windows\temp so that LOB and BLOB processing works" )
    
    Set-AccessControl $webuser "C:\Windows\Temp" "Modify" "ContainerInherit, ObjectInherit"

    Write-Output ("Installation completed successfully")
}
catch
{
	$_
    Write-Error ("Installation error")
    throw
}
finally
{
    Write-Output ("See $install_log and other files in $ENV:TEMP for more details.")
    Write-Output ("Also see C:\cfn\cfn-init\data\metadata.json for the CloudFormation template with all parameters expanded.")
}

# Successful completion so set Last Exit Code to 0
cmd /c exit 0