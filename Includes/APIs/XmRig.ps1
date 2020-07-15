﻿using module ..\Include.psm1

class XmRig : Miner { 
    [String]GetCommandLineParameters() { 
        If ($this.Arguments -match "^{.+}$") { 
            Return ($this.Arguments | ConvertFrom-Json -ErrorAction SilentlyContinue).Commands
        }
        Else { 
            Return $this.Arguments
        }
    }

    CreateConfigFiles() { 
        $Parameters = $this.Arguments | ConvertFrom-Json -ErrorAction SilentlyContinue

        Try { 
            $ConfigFile = "$(Split-Path $this.Path)\$($Parameters.ConfigFile.FileName)"

            $ThreadsConfig = [PSCustomObject]@{ }
            $ThreadsConfigFile = "$(Split-Path $this.Path)\$($Parameters.ThreadsConfigFileName)"

            If ($Parameters.ConfigFile.Content.threads) { 
                #Write full config file, ignore possible hw change
                $Parameters.ConfigFile.Content | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile -ErrorAction SilentlyContinue -Force
            }
            else { 
                #Check If we have a valid hw file for all installed hardware. If hardware / device order has changed we need to re-create the config files. 
                $ThreadsConfig = Get-Content $ThreadsConfigFile -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
                If ($ThreadsConfig.Count -lt 1) { 
                    If (Test-Path "$(Split-Path $this.Path)\$($this.Algorithm | Select-Object -Index 0)-*.json" -PathType Leaf) { 
                        #Remove old config files, thread info is no longer valid
                        Write-Message -Level Warn "Hardware change detected. Deleting existing configuration files for miner '$($this.Info)'."
                        Remove-Item "$(Split-Path $this.Path)\ThreadsConfig-$($this.Algorithm | Select-Object -Index 0)-*.json" -Force -ErrorAction SilentlyContinue
                    }
                    #Temporarily start miner with pre-config file (without threads config). Miner will then update hw config file with threads info
                    $Parameters.ConfigFile.Content | ConvertTo-Json -Depth 10 | Set-Content $ThreadsConfigFile -Force
                    If ((Test-Path ".\CreateProcess.cs" -PathType Leaf) -and ($this.API -ne "Wrapper")) { 
                        $this.Process = Start-SubProcessWithoutStealingFocus -FilePath $this.Path -ArgumentList $Parameters.HwDetectCommands -WorkingDirectory (Split-Path $this.Path) -Priority ($this.DeviceName | ForEach-Object { If ($_ -like "CPU#*") { -2 } else { -1 } } | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum) -EnvBlock $this.Environment
                    }
                    Else { 
                        $EnvCmd = ($this.Environment | ForEach-Object { "```$env:$($_)" }) -join "; "
                        $this.Process = Start-Job ([ScriptBlock]::Create("Start-Process $(@{ desktop = "powershell"; core = "pwsh" }.$Global:PSEdition) `"-command $EnvCmd```$Process = (Start-Process '$($this.Path)' '$($Parameters.HwDetectCommands)' -WorkingDirectory '$(Split-Path $this.Path)' -WindowStyle Minimized -PassThru).Id; Wait-Process -Id `$PID; Stop-Process -Id ```$Process`" -WindowStyle Hidden -Wait"))
                    }
                    If ($this.Process | Get-Job -ErrorAction SilentlyContinue) { 
                        For ($WaitForPID = 0; $WaitForPID -le 20; $WaitForPID++) { 
                            If ($this.ProcessId = (Get-CIMInstance CIM_Process | Where-Object { $_.ExecutablePath -eq $this.Path -and $_.CommandLine -like "*$($this.Path)*$($Parameters.HwDetectCommands)*" }).ProcessId) { 
                                Break
                            }
                            Start-Sleep -Milliseconds 100
                        }
                        For ($WaitForThreadsConfig = 0; $WaitForThreadsConfig -le 60; $WaitForThreadsConfig++) { 
                            If ($ThreadsConfig = @(Get-Content $ThreadsConfigFile -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue).threads) { 
                                If ($this.DeviceName -like "GPU*") { 
                                    ConvertTo-Json -InputObject @($ThreadsConfig | Sort-Object -Property Index -Unique) -Depth 10 | Set-Content $ThreadsConfigFile -ErrorAction SilentlyContinue -Force
                                }
                                Else { 
                                    ConvertTo-Json -InputObject @($ThreadsConfig | Select-Object -Unique) -Depth 10 | Set-Content $ThreadsConfigFile -ErrorAction SilentlyContinue -Force
                                }
                                Break
                            }
                            Start-Sleep -Milliseconds 500
                        }
                        $this.StopMining()
                    }
                    Else { 
                        Write-Message -Level Error "Running temporary miner failed - cannot create threads config files for '$($this.Info)' [Error: '$($Error | Select-Object -Index 0)']."
                        Return
                    }
                }

                If (-not ((Get-Content $ConfigFile -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue).threads)) { 
                    #Threads config in config file is invalid, retrieve from threads config file
                    $ThreadsConfig = Get-Content $ThreadsConfigFile | ConvertFrom-Json
                    If ($ThreadsConfig.Count -ge 1) { 
                        #Write config files. Overwrite because we need to add thread info
                        If ($this.DeviceName -like "GPU*") { 
                            $Parameters.ConfigFile.Content | Add-Member threads ([Array](($ThreadsConfig | Where-Object { $Parameters.Devices -contains $_.index })) * $Parameters.Threads) -Force
                        }
                        Else { 
                            #CPU thread config does not contain index information
                            $Parameters.ConfigFile.Content | Add-Member threads ([Array]($ThreadsConfig * $Parameters.Threads)) -Force
                        }
                        $Parameters.ConfigFile.Content | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile -Force
                    }
                    Else { 
                        Write-Message -Level Error "Error parsing threads config file - cannot create miner config files for '$($this.Info)' [Error: '$($Error | Select-Object -Index 0)']."
                        Return
                    }
                }
            }
        }
        Catch { 
            Write-Message -Level Error "Creating miner config files for '$($this.Info)' failed [Error: '$($Error | Select-Object -Index 0)']."
            Return
        }
    }

    [String]GetMinerUri () { 
        Return "http://localhost:$($this.Port)/api.json"
    }

    [Object]UpdateMinerData () { 
        $Timeout = 5 #seconds
        $Data = [PSCustomObject]@{ }
        $PowerUsage = [Double]0
        $Sample = [PSCustomObject]@{ }

        $Request = $this.MinerUri
        $Response = ""

        Try { 
            If ($Global:PSVersionTable.PSVersion -ge [System.Version]("6.2.0")) { 
                $Response = Invoke-WebRequest $Request -TimeoutSec $Timeout -DisableKeepAlive -MaximumRetryCount 3 -RetryIntervalSec 1 -ErrorAction Stop
            }
            Else { 
                $Response = Invoke-WebRequest $Request -UseBasicParsing -TimeoutSec $Timeout -DisableKeepAlive -ErrorAction Stop
            }
            $Data = $Response | ConvertFrom-Json -ErrorAction Stop
        }
        Catch { 
            Return $null
        }

        $HashRate = [PSCustomObject]@{ }
        $Shares = [PSCustomObject]@{ }

        $HashRate_Name = [String]$this.Algorithm[0]
        $HashRate_Value = [Double]$Data.hashrate.total[0]
        If (-not $HashRate_Value) { $HashRate_Value = [Double]$Data.hashrate.total[1] } #fix
        If (-not $HashRate_Value) { $HashRate_Value = [Double]$Data.hashrate.total[2] } #fix

        $Shares_Accepted = [Int64]0
        $Shares_Rejected = [Int64]0

        If ($this.AllowedBadShareRatio) { 
            $Shares_Accepted = [Int64]$Data.results.shares_good
            $Shares_Rejected = [Int64]($Data.results.shares_total - $Data.results.shares_good)
            If ((-not $Shares_Accepted -and $Shares_Rejected -ge 3) -or ($Shares_Accepted -and ($Shares_Rejected * $this.AllowedBadShareRatio -gt $Shares_Accepted))) { 
                $this.SetStatus([MinerStatus]::Failed)
            }
            $Shares | Add-Member @{ $HashRate_Name = @($Shares_Accepted, $Shares_Rejected, $($Shares_Accepted + $Shares_Rejected)) }
        }

        If ($HashRate_Name) { 
            $HashRate | Add-Member @{ $HashRate_Name = [Double]$HashRate_Value }
        }

        If ($this.ReadPowerusage) { 
            $PowerUsage = $this.GetPowerUsage()
        }

        If ($HashRate.PSObject.Properties.Value -gt 0) { 
            $Sample = [PSCustomObject]@{ 
                Date       = (Get-Date).ToUniversalTime()
                HashRate   = $HashRate
                PowerUsage = $PowerUsage
                Shares     = $Shares
            }
            Return $Sample
        }
        Return $null
    }
}