# Update config file to include all new config items
If (-not $Config.ConfigFileVersion -or [System.Version]::Parse($Config.ConfigFileVersion) -lt $Variables.CurrentVersion) { 
    # Changed config items
    $Changed_Config_Items = $Config.Keys | Where-Object { $_ -notin @(@($AllCommandLineParameters.Keys) + @("PoolsConfig")) }
    $Changed_Config_Items | ForEach-Object { 
        Switch ($_) { 
            "ActiveMinergain" { $Config.RunningMinerGainPct = $Config.$_; $Config.Remove($_) }
            "APIKEY" { 
                $Config.MPHAPIKey = $Config.$_
                $Config.ProHashingAPIKey = $Config.$_
                $Config.Remove($_)
            }
            "EnableEarningsTrackerLog" { $Config.EnableBalancesLog = $Config.$_; $Config.Remove($_) }
            "HideMinerWindow" { $Config.Remove($_) }
            "Location" { $Config.Region = $Config.$_; $Config.Remove($_) }
            "NoDualAlgoMining" { $Config.DisableDualAlgoMining = $Config.$_; $Config.Remove($_) }
            "NoSingleAlgoMining" { $Config.DisableSingleAlgoMining = $Config.$_; $Config.Remove($_) }
            "PasswordCurrency" { $Config.PayoutCurrency = $Config.$_; $Config.Remove($_) }
            "ReadPowerUsage" { $Config.CalculatePowerCost = $Config.$_; $Config.Remove($_) }
            "SelGPUCC" { $Config.Remove($_) }
            "SelGPUDSTM" { $Config.Remove($_) }
            "ShowMinerWindow" { $Config.Remove($_) }
            "UserName" { 
                If (-not $Config.MPHUserName) { $Config.MPHUserName = $Config.$_ }
                If (-not $Config.ProHashingUserName) { $Config.ProHashingUserName = $Config.$_ }
                $Config.Remove($_)
            }
            Default { $Config.Remove($_) } # Remove unsupported config item
        }
    }
    Remove-Variable Changed_Config_Items -ErrorAction Ignore

    # Add new config items
    If ($New_Config_Items = $AllCommandLineParameters.Keys | Where-Object { $_ -notin $Config.Keys }) { 
        $New_Config_Items | Sort-Object Name | ForEach-Object { 
            $Value = Get-Variable $_ -ValueOnly -ErrorAction SilentlyContinue
            If ($Value -is [Switch]) { $Value = [Boolean]$Value }
            $Global:Config.$_ = $Value
        }
        Remove-Variable Value -ErrorAction Ignore
    }
    $Config.ConfigFileVersion = $Variables.CurrentVersion.ToString()
    Write-Config $Variables.ConfigFile
    Write-Message -Level Verbose "Updated configuration file '$($Variables.ConfigFile)' to version $($Variables.CurrentVersion.ToString())."
    Remove-Variable New_Config_Items -ErrorAction Ignore
}
