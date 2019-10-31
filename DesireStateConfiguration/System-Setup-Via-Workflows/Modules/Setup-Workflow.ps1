﻿workflow Setup-NewComputer { 
    param (
        [string] $new_name,
        [string] $domain,
        [string] $pull_server,
        [string] $guid,
        [string] $dns               = "10.2.1.5",
        [string] $pfx_path,
        [string] $pfx_password,
        [string] $windows_key,
        [System.Management.Automation.PSCredential] $cred
    )

    sequence {
        Set-ExecutionPolicy -ExecutionPolicy Unrestricted
        Set-NetFirewallProfile -Enabled false

        Rename-Computer -NewName $new_name
        Restart-Computer -Wait -For PowerShell -Timeout 90 -Force
        
        inlinescript {
            Set-Variable -Name interface -Value "Ethernet0" -Option Constant
            Set-Variable -Name dns -Value $using:dns -Option Constant
            Set-DnsClientServerAddress -InterfaceAlias $using:interface -ServerAddresses $using:dns
            Add-Computer -DomainName $using:domain -Credential $using:cred -Force 
        }
        Restart-Computer -Wait -For PowerShell -Timeout 90 -Force

        parallel {
            inlinescript {
                Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0 -Force -ErrorAction Stop  
                Set-NetFirewallRule -DisplayGroup "Remote Desktop" -Enabled:True -ErrorAction Stop
            }

           inlinescript {
                tzutil.exe /s "Central Standard Time" 
            }
 
            inlinescript {
                Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 00000000
            }

            inlinescript {
                slmgr -ipk $using:windows_key
            }

            inlinescript {
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"  -Name "AUOptions" -Value 4
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"  -Name "CachedAUOptions" -Value 4
            }

            inlinescript {
                Enable-PSRemoting -Force -Confirm:$false
                Enable-WSManCredSSP -DelegateComputer * -Force -Role Client
                Enable-WSManCredSSP -Force -Role Server
            }
        }

        inlinescript {
            function Get-NextDriveLetter {
                param ([string] $current_drive )
                return ( [char][byte]([byte][char]$current_drive - 1) )
            }

            Set-Variable -Name new_drive_letter -Value "Z"
            Set-Variable -Name cdrom_drives -Value @(Get-Volume | Where DriveType -eq "CD-ROM")

            foreach( $drive in $cdrom_drives ) {
                $cd_drive = Get-WmiObject Win32_Volume | Where DriveLetter -imatch $drive.DriveLetter
                $cd_drive.DriveLetter = "$new_drive_letter`:"
                $cd_drive.put()
                $new_drive_letter = Get-NextDriveLetter -current_drive $new_drive_letter
            }

            Get-Disk | Where { $_.PartitionStyle -eq "RAW" } | Initialize-Disk -PartitionStyle MBR 
            Get-Disk | Where { $_.NumberOfPartitions -eq 0 } |   
                New-Partition -AssignDriveLetter -UseMaximumSize |
                Format-Volume -FileSystem NTFS -Force -Confirm:$false
        }

        inlinescript {
            configuration Configure_DSCPullServer {                param ($NodeId, $PullServer, $ThumbPrint)    
                LocalConfigurationManager                {                    AllowModuleOverwrite = 'True'                    ConfigurationID = $NodeId                    ConfigurationModeFrequencyMins = 30                     ConfigurationMode = 'ApplyAndAutoCorrect'                    RebootNodeIfNeeded = 'True'                    RefreshMode = 'PULL'                     CertificateId = $ThumbPrint                    DownloadManagerName = 'WebDownloadManager'                    DownloadManagerCustomData = (@{ServerUrl = "https://$PullServer/psdscpullserver.svc"})                }            }

            $pfx = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2    
		    $secure_pfx_pass = ConvertTo-SecureString -String $using:pfx_password -AsPlainText -Force
   
            $pfx.import($using:pfx_path,$secure_pfx_pass,"Exportable,PersistKeySet")    
   
 	        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My","LocalMachine")    
 	        $store.open("MaxAllowed")    
 	        $store.add($pfx)    
 	        $store.close()    

            if( $using:guid -ne [string]::empty ) {
                Configure_DSCPullServer -NodeId $using:guid -PullServer $using:pull_server -ThumbPrint $pfx.Thumbprint                Set-DscLocalConfigurationManager -path Configure_DSCPullServer
                $using:guid | Add-Content -Encoding Ascii ( Join-Path "C:" $using:guid )
            }
        }

        Restart-Computer -Wait -For PowerShell -Timeout 90 -Force
        Set-NetFirewallProfile -Enabled true 
    }

}