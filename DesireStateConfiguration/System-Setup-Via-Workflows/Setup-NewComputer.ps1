﻿#requires -version 4

<#
.SYNOPSIS
This PowerShell Script will setup a blank using via PowerShell Workflows and DSC. 

.DESCRIPTION
Version - 1.0.0

This PowerShell Script will setup a blank using via PowerShell Workflows and DSC. The Script will do the following
*Rename the Computer
*Define a DNS Server
*Join the Computer to a Domain
*Enable RDP
*Set TimeZone to Central Time Zone
*Disable UAC
*Moves CD-ROM drive to Z: drive
*Format and Mounts all Drives
*Configure a Computer PowerShell LCM to use a Pull Server

.EXAMPLE
.\Setup-NewComputer-Workflow.ps1 -computer_ip 1.2.3.4 -new_name "server-1" -local_user "administrator" -local_password "password1234" -domain_user "sharepoint\administrator" -domain_password "password1234"

.PARAMETER computer_ip
Specifies the computer to setup. Mandatory parameter

.PARAMETER new_name
Specifies the new name of the computer. Mandatory parameter

.PARAMETER local_user
Specifies an administrator on the computer to setup. Default Value = 'administrator'

.PARAMETER local_password
Specifies the password of the local_user.

.PARAMETER domain
Specifies the domain to join. Default Value = 'sharepoint.test'

.PARAMETER domain_user
Specifies an account that can join the computer to the domain. Must be in the format of "domain\user"

.PARAMETER domain_password
Specifies the domain user's password

.PARAMETER windows_key
Specifies the Windows Key.  Mandatory parameter

.PARAMETER node
Specifies a node's GUID for DSC.  If empty, the script will generate a new GUID. DSC Parameter Set

.PARAMETER pull_server
Specifies the DSC Pull server. Default Value = 'dsc.sharepoint.test'. DSC Parameter Set

.PARAMETER certificate_pfx_path
Specifies the path of the certificate for DSC Pull server credentials. DSC Parameter Set

.PARAMETER certificate_pfx_password
Specifies the password of the certificate for DSC Pull server credentials. DSC Parameter Set

.NOTES


#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)] [string] $computer_ip,
    [Parameter(Mandatory=$true)] [string] $new_name,
    [Parameter(Mandatory=$true)] [string] $domain                                = "sharepoint.test",
    [Parameter(Mandatory=$false)][string] $local_user                            = "administrator",
    [Parameter(Mandatory=$true)] [string] $local_password,
    [Parameter(Mandatory=$true)] [string] $windows_key,

    [ValidatePattern("(\w+)\\(\w+)")]
    [Parameter(Mandatory=$true)][string] $domain_user,
    [Parameter(Mandatory=$true)][string] $domain_password, 

    [Parameter(ParameterSetName="DSC",Mandatory=$false)][string] $pull_server              = "dsc.sharepoint.test",
    [ValidateScript({Test-Path $_})]
    [Parameter(ParameterSetName="DSC",Mandatory=$false)][string] $certificate_pfx_path     = [string]::empty,
    [Parameter(ParameterSetName="DSC",Mandatory=$false)][string] $certificate_pfx_password = [string]::empty,
    [Parameter(ParameterSetName="DSC",Mandatory=$false)][string] $node                     = [string]::empty
)

. (Join-Path $PWD.Path "Modules\Setup-Workflow.ps1")
. (Join-Path $PWD.Path "Modules\Server-DSC-Template.ps1") -Nodeid $node 

Set-Variable -Name domain_creds -value (New-Object System.Management.Automation.PSCredential ($domain_user, (ConvertTo-SecureString $domain_password -AsPlainText -Force)))
Set-Variable -Name local_creds  -value (New-Object System.Management.Automation.PSCredential ($local_user,  (ConvertTo-SecureString $local_password  -AsPlainText -Force)))
Set-Variable -Name dsc_path -Value "C:\Program Files\WindowsPowerShell\DscService\Configuration\" -Option Constant

Set-Item -Path 'WSMan:\localhost\Client\TrustedHosts' -Value $computer_ip

#Workflow to Setup Machine
$options = @{ 
    new_name             = $new_name
    domain               = $domain
    pull_server          = $pull_server
    guid                 = $node
    cred                 = $domain_creds
    windows_key          = $windows_key
    pfx_path             = $certificate_pfx_path
    pfx_password         = $certificate_pfx_password
}
Setup-NewComputer @options -PSPersist $true -PSComputerName $computer_ip -PSCredential $local_creds -Verbose

#DSC To Configure
switch ($PsCmdlet.ParameterSetName)
{ 
    "DSC" {
        if( [string]::IsNullOrEmpty($node) ) { 
            Set-Variable -Name node -Value ([guid]::NewGuid() | Select -Expand Guid)
        }

        Write-Output ("Using Guid - {0} for {1}. Please save. Value will also be saved on the root of the C: parition on {1}." -f $node, $computer_ip)
        ServerSetup

        $mof_path = Join-Path -Path $PWD.Path -ChildPath "ServerSetup"
        New-DscCheckSum -ConfigurationPath $mof_path -OutPath $dsc_path -Verbose -Force
    }
}