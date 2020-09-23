using module .\Include.psm1

Function Start-Cycle { 
    $Variables.CycleTime = Measure-Command -Expression {
        Write-Message "Started new cycle."

        #Set master timer
        $Variables.Timer = (Get-Date).ToUniversalTime()
        $Variables.StatStart = If ($Variables.StatEnd) { $Variables.StatEnd } Else { $Variables.Timer }
        $Variables.StatEnd = $Variables.Timer.AddSeconds($Config.Interval)
        $Variables.StatSpan = New-TimeSpan $Variables.StatStart $Variables.StatEnd
        $Variables.WatchdogInterval = ($Variables.Strikes + 1) * $Variables.StatSpan.TotalSeconds
        $Variables.WatchdogReset = ($Variables.Strikes + 1) * $Variables.Strikes * $Variables.StatSpan.TotalSeconds

        $Variables.EndLoopTime = ((Get-Date).AddSeconds($Config.Interval))
        $Variables.DecayExponent = [Int](($Variables.Timer - $Variables.DecayStart).TotalSeconds / $Variables.DecayPeriod)

        #Expire watchdog timers
        $Variables.WatchdogTimers = @($Variables.WatchdogTimers | Where-Object Kicked -GE $Variables.Timer.AddSeconds( - $Variables.WatchdogReset))

        #To trigger an eventual miner restart
        $Variables.OldShowMinerWindows = $Config.ShowMinerWindows
        $Variables.OldCalculatePowerCost = $Config.CalculatePowerCost

        #Always get the latest config
        Read-Config

        $PoolNames = $Config.PoolName
        $PoolsConfig = $Config.PoolsConfig

        #Activate or deactivate donation
        If (($Variables.DonateStart).DayOfYear -ne (Get-Date).DayOfYear) { 
            #Re-Randomize donation start once per day
            $Variables.DonateStart = (Get-Date).AddMinutes((Get-Random -Minimum $Config.Donate -Maximum (1440 - $Config.Donate - (Get-Date).TimeOfDay.TotalMinutes)))
            $Variables.DonateEnd = $Variables.DonateStart
        }

        If ($Config.Donate) { 
            If ((Get-Date) -ge $Variables.DonateStart) { 
                If ($Variables.DonateEnd -eq $Variables.DonateStart) { 
                    #We get here only once per donation period
                    $Variables.DonateStart = (Get-Date)
                    $Variables.DonateEnd = $Variables.DonateStart.AddMinutes($Config.Donate)
                    $Variables.EndLoopTime = $Variables.DonateEnd

                    # Get donation addresses randomly from agreed developers list
                    # This will fairly distribute donations to developers
                    # Developers list and wallets is publicly available at: https://nemosminer.com/data/devlist.json & https://raw.githubusercontent.com/Minerx117/UpDateData/master/devlist.json
                    Try { 
                        $DonationData = Invoke-WebRequest "https://raw.githubusercontent.com/Minerx117/UpDateData/master/devlist.json" -TimeoutSec 15 -UseBasicParsing -Headers @{ "Cache-Control" = "no-cache" } | ConvertFrom-Json
                    }
                    Catch { 
                        $DonationData = @(
                            [PSCustomObject]@{ Name = "MrPlus";      Wallet = "134bw4oTorEJUUVFhokDQDfNqTs7rBMNYy"; UserName = "MrPlus"; PayoutCurrency = "BTC" }, 
                            [PSCustomObject]@{ Name = "Nemo";        Wallet = "1QGADhdMRpp9Pk5u5zG1TrHKRrdK5R81TE"; UserName = "nemo"; PayoutCurrency = "BTC" }, 
                            [PSCustomObject]@{ Name = "aaronsace";   Wallet = "1Q24z7gHPDbedkaWDTFqhMF8g7iHMehsCb"; UserName = "aaronsace"; PayoutCurrency = "BTC" }, 
                            [PSCustomObject]@{ Name = "grantemsley"; Wallet = "16Qf1mEk5x2WjJ1HhfnvPnqQEi2fvCeity"; UserName = "grantemsley"; PayoutCurrency = "BTC" },
                            [PSCustomObject]@{ Name = "uselessguru"; Wallet = "1GPSq8txFnyrYdXL8t6S94mYdF8cGqVQJF"; UserName = "uselessguru"; PayoutCurrency = "BTC" }
                        )
                    }
                    $Variables.DonateRandom = $DonationData | Get-Random #Use same donation data for the entire donation period to reduce switching

                    #Add pool config to config (in-memory only)
                    $Variables.DonatePoolNames = @($Config.PoolName -replace "24hr$" -replace "Coins$" | Where-Object { $_ -notlike "ProHashing*" }) #No all devs have a known ProHashing account
                    $Variables.DonatePoolsConfig = [Ordered]@{ }
                    $Variables.DonatePoolNames | ForEach-Object { 
                        $PoolConfig = [PSCustomObject]@{ }
                        $PoolConfig | Add-Member PricePenaltyFactor 1
                        $PoolConfig | Add-Member WorkerName "NemosMiner-$($Variables.CurrentVersion.ToString())-donate$($Config.Donate)" -Force
                        Switch -Regex ($_) { 
                            "MPH" { 
                                $PoolConfig | Add-Member UserName $Variables.DonateRandom.UserName
                            }
                            "NiceHash" { 
                                $PoolConfig | Add-Member Wallet $Variables.DonateRandom.Wallet
                            }
                            # "ProHashing*" { 
                            #     $PoolConfig | Add-Member PayoutCurrency $Variables.DonateRandom.PayoutCurrency
                            #     $PoolConfig | Add-Member UserName $Variables.DonateRandom.ProHashingUserName
                            # }
                            Default { 
                                $PoolConfig | Add-Member PayoutCurrency $Variables.DonateRandom.PayoutCurrency
                                $PoolConfig | Add-Member Wallet $Variables.DonateRandom.Wallet
                            }
                        }
                        $Variables.DonatePoolsConfig.$_ = $PoolConfig
                    }
                }
                If ((Get-Date) -lt $Variables.DonateEnd) { 
                    $PoolNames = $Variables.DonatePoolNames
                    $PoolsConfig = $Variables.DonatePoolsConfig
                    Write-Message "Donation run: Mining for '$($Variables.DonateRandom.Name)' for the next $(If (($Config.Donate - ((Get-Date) - $Variables.DonateStart).Minutes) -gt 1) { "$($Config.Donate - ((Get-Date) - $Variables.DonateStart).Minutes) minutes" } Else { "minute" })."
                }
                ElseIf ($Variables.DonatePoolsConfig) { 
                    $Variables.DonatePoolNames = $null
                    $Variables.DonatePoolsConfig = $null
                    Write-Message "Donation run complete. Mining for you."
                }
            }
        }

        #Stop BrainJobs for deconfigured pools
        Stop-BrainJob @($Variables.BrainJobs.Keys | Where-Object { $_ -notin $Config.PoolName })

        #Start Brain jobs (will pick up all newly added pools)
        Start-BrainJob

        Write-Message "Loading currency exchange rates from 'min-api.cryptocompare.com'..."
        Get-Rate

        #Power cost preparations
        If ($Config.CalculatePowerCost) { 
            If (($Variables.Devices).Count -lt 1) { 
                Write-Message -Level Warn "No configured miner devices. Cannot read power usage info - disabling power usage calculations."
                $Variables.CalculatePowerCost = $false
            }
            Else { 
                #$Variables.CalculatePowerCost is an operational variable and not identical to $Config.CalculatePowerCost
                $Variables.CalculatePowerCost = $true

                #HWiNFO64 verification
                $RegKey = "HKCU:\Software\HWiNFO64\VSB"
                If ($RegistryValue = Get-ItemProperty -Path $RegKey -ErrorAction SilentlyContinue) { 
                    If ([String]$Variables.HWInfo64RegistryValue -eq [String]$RegistryValue) { 
                        Write-Message -Level Warn "Power usage info in registry has not been updated [HWiNFO64 not running???] - power cost calculation is not available. "
                        $Variables.CalculatePowerCost = $false
                    }
                    Else { 
                        $Hashtable = @{ }
                        $Device = ""
                        $RegistryValue.PSObject.Properties | Where-Object { $_.Name -match "^Label[0-9]+$" -and (Compare-Object @($_.Value -split ' ' | Select-Object) @(($Variables.Devices).Name | Select-Object) -IncludeEqual -ExcludeDifferent) } | ForEach-Object { 
                            $Device = ($_.Value -split ' ') | Select-Object -last 1
                            Try { 
                                $Hashtable.Add($Device, $RegistryValue.($_.Name -replace "Label", "Value"))
                            }
                            Catch { 
                                Write-Message -Level Warn "HWiNFO64 sensor naming is invalid [duplicate sensor for $Device] - disabling power usage calculations."
                                $Variables.CalculatePowerCost = $false
                            }
                        }
                        If ($Variables.Devices | Where-Object State -EQ "Enabled" | Where-Object { $null -eq $Hashtable.($_.Name) }) { 
                            Write-Message -Level Warn "HWiNFO64 sensor naming is invalid [missing sensor config for $((($Variables.Devices).Name | Where-Object { $null -eq $Hashtable.$_ }) -join ', ')] - disabling power usage calculations."
                            $Variables.CalculatePowerCost = $false
                        }
                        Remove-Variable Device
                        Remove-Variable HashTable
                    }
                    $Variables.HWInfo64RegistryValue = [String]$RegistryValue
                }
                Else { 
                    Write-Message -Level Warn "Cannot read power usage info from registry [Key '$($RegKey)' does not exist - HWiNFO64 not running???] - disabling power usage calculations."
                    $Variables.CalculatePowerCost = $false
                }
            }
            If ($Config.CalculatePowerCost -and -not ($Variables.CalculatePowerCost)) { 
                Write-Message -Level Warn "Realtime power usage cannot be read from system. Will display static values where available."
            }
        }

        #Power price
        If (-not ($Config.PowerPricekWh | Sort-Object | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name)) { 
            $Config.PowerPricekWh = [PSCustomObject]@{ "00:00" = 0 }
        }
        If ($null -eq $Config.PowerPricekWh."00:00") { 
            #00:00h power price is the same as the latest price of the previous day
            $Config.PowerPricekWh | Add-Member "00:00" ($Config.PowerPricekWh.($Config.PowerPricekWh | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Sort-Object | Select-Object -Last 1))
        }
        $Variables.PowerPricekWh = [Double]($Config.PowerPricekWh.($Config.PowerPricekWh | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Sort-Object | Where-Object { $_ -lt (Get-Date -Format HH:mm).ToString() } | Select-Object -Last 1))
        $Variables.PowerCostBTCperW = [Double](1 / 1000 * 24 * $Variables.PowerPricekWh / $Variables.Rates."BTC".($Config.Currency | Select-Object -Index 0))
        $Variables.BasePowerCost = [Double]($Config.IdlePowerUsageW / 1000 * 24 * $Variables.PowerPricekWh / $Variables.Rates."BTC".($Config.Currency | Select-Object -Index 0))

        #Clear pools if pools config has changed to avoid double pools with different wallets/usernames
        If (($Config.PoolsConfig | ConvertTo-Json -Compress) -ne ($Variables.PoolsConfigCached | ConvertTo-Json -Compress)) { 
            $Variables.Pools = [Miner]::Pools
        }

        #Load unprofitable algorithms
        If (Test-Path ".\Includes\UnprofitableAlgorithms.txt" -PathType Leaf -ErrorAction Ignore) { 
            $Variables.UnprofitableAlgorithms = [String[]](Get-Content ".\Includes\UnprofitableAlgorithms.txt" | ConvertFrom-Json -ErrorAction SilentlyContinue | Sort-Object -Unique)
            Write-Message "Loaded list of unprofitable algorithms ($($Variables.UnprofitableAlgorithms.Count) entrie$(If ($Variables.UnprofitableAlgorithms.Count -ne 1) { "s" }))."
        }
        Else {
            $Variables.UnprofitableAlgorithms = $null
        }

        #Load information about the pools
        $Variables.NewPools_Jobs = @()
        If ((Test-Path ".\Pools" -PathType Container -ErrorAction Ignore) -and ($PoolNames)) { 
            Write-Message "Requesting pool data ($(@($PoolNames) -join ', ')) - this usually takes less than $($Config.PoolTimeout) second$(If ($Config.PoolTimeout -ne 1) { "s" } )..."
            $Variables.NewPools_Jobs = @(
                $PoolNames | ForEach-Object { 
                    Get-ChildItemContent ".\Pools\$($_).*" -Parameters @{ PoolConfig = $PoolsConfig.($_ -replace "24hr$" -replace "Coins$") } -Threaded -Priority $(If ($Variables.Miners | Where-Object Status -EQ "Running" | Where-Object Type -EQ "CPU") { "Normal" })
                }
            )
        
            #Retrieve collected pool data
            $Variables.NewPools_Jobs | ForEach-Object $_.Job | Wait-Job -Timeout ([Int]$Config.PoolTimeout) | Out-Null
            [Pool[]]$NewPools = $Variables.NewPools_Jobs | ForEach-Object { $_.EndInvoke($_.Job) | ForEach-Object { If (-not $_.Content.Name) { $_.Content | Add-Member Name $_.Name -Force }; $_.Content } }
            $Variables.NewPools_Jobs | ForEach-Object { $_.Dispose() }
            $Variables.Remove("NewPools_Jobs")
        }
        Else { 
            Write-Message -Level WARN "No configured pools - retrying in 10 seconds..."
            Start-Sleep -Seconds 10
            Continue
        }

        #Remove de-configured pools
        [Pool[]]$Variables.Pools = $Variables.Pools | Where-Object Name -in $Config.PoolName

        #Find new pools
        [Pool[]]$ComparePools = Compare-Object -PassThru @($Variables.Pools | Select-Object) @($NewPools | Select-Object) -Property Name, Algorithm, CoinName, Currency, Protocol, Host, Port, User, Pass, SSL | Where-Object SideIndicator -EQ "=>" | Select-Object -Property * -ExcludeProperty SideIndicator
        
        [Pool[]]$Variables.CommparePools = $ComparePools
        $Variables.PoolsCount = $Variables.Pools.Count

        #Add new pools
        If ($ComparePools) { 
            [Pool[]]$Variables.Pools += ($ComparePools | Select-Object)
        }

        #Update existing pools
        $Variables.Pools | ForEach-Object { 
            [Pool]$Pool = $null

            $_.Available = $true
            $_.Best = $false
            $_.Reason = $null

            $Pool = $NewPools | 
            Where-Object Name -eq $_.Name | 
            Where-Object Algorithm -eq $_.Algorithm | 
            Where-Object CoinName -eq $_.CoinName | 
            Where-Object Currency -eq $_.Currency | 
            Where-Object Protocol -eq $_.Protocol | 
            Where-Object Host -eq $_.Host | 
            Where-Object Port -eq $_.Port | 
            Where-Object User -eq $_.User | 
            Where-Object Pass -eq $_.Pass | 
            Where-Object SSL -eq $_.SSL | 
            Select-Object -First 1

            If ($Pool) { 
                If (-not $Config.EstimateCorrection -or $Pool.EstimateFactor -lt 0 -or $Pool.EstimateFactor -gt 1) { $_.EstimateFactor = [Double]1 } Else { $_.EstimateFactor = [Double]($Pool.EstimateFactor) }
                If ($Config.IgnorePoolFee -or $Pool.Fee -lt 0 -or $PoolFee -gt 1) { $_.Fee = 0 } Else { $_.Fee = $Pool.Fee }
                If ($Pool.PricePenaltyFactor -lt 0 -or $Pool.PricePenaltyFactor -gt 1) { $_.PricePenaltyFactor = [Double]1 } Else { $_.PricePenaltyFactor = [Double]($Pool.PricePenaltyFactor) }
                $_.Price = $Pool.Price * $_.EstimateFactor * $_.PricePenaltyFactor * (1 - $_.Fee)
                $_.Price_Bias = $_.Price * (1 - $Pool.MarginOfError * [Math]::Pow($Variables.DecayBase, $Variables.DecayExponent))
                $_.StablePrice = $Pool.StablePrice * $_.EstimateFactor * $_.PricePenaltyFactor * (1 - $_.Fee)
                $_.MarginOfError = $Pool.MarginOfError
                $_.Updated = $Pool.Updated
            }
        }
        Remove-Variable Pool

        # Filter Algo based on Per Pool Config
        $PoolsConfig = $Config.PoolsConfig #much faster
        $Variables.Pools | Where-Object Disabled -EQ $true | ForEach-Object { $_.Available = $false; $_.Reason += "Disabled (by Stat file)" }
        If ($Config.SSL -ne "Preferred") { $Variables.Pools | Where-Object { $_.SSL -ne [Boolean]$Config.SSL } | ForEach-Object { $_.Available = $false; $_.Reason += "Config item SSL -ne $([Boolean]$Config.SSL)" } }
        $Variables.Pools | Where-Object MarginOfError -gt (1 - $Config.MinAccuracy) | ForEach-Object { $_.Available = $false; $_.Reason += "MinAccuracy ($($Config.MinAccuracy * 100)%) exceeded" }
        $Variables.Pools | Where-Object { "*:$($_.Algorithm)" -in $Variables.UnprofitableAlgorithms } | ForEach-Object { $_.Available = $false; $_.Reason += "Unprofitable Algorithm" }
        $Variables.Pools | Where-Object { "1:$($_.Algorithm)" -in $Variables.UnprofitableAlgorithms } | ForEach-Object { $_.Reason += "Unprofitable Primary Algorithm" } #Keep available
        $Variables.Pools | Where-Object { "2:$($_.Algorithm)" -in $Variables.UnprofitableAlgorithms } | ForEach-Object { $_.Reason += "Unprofitable Secondary Algorithm" } #Keep available
        $Variables.Pools | Where-Object { $_.Name -notin $Config.PoolName } | ForEach-Object { $_.Available = $false; $_.Reason += "Pool not configured" }
        $Variables.Pools | Where-Object Price -EQ 0 | ForEach-Object { $_.Available = $false; $_.Reason += "Price -eq 0" }
        $Variables.Pools | Where-Object Price -EQ [Double]::NaN | ForEach-Object { $_.Available = $false; $_.Reason += "No price data" }
        If ($Config.EstimateCorrection -eq $true ) { $Variables.Pools | Where-Object EstimateFactor -lt 0.5 | ForEach-Object { $_.Available = $false; $_.Reason += "EstimateFactor -lt 50%" } }

        $Variables.Pools | Where-Object { "-$($_.Algorithm)" -in $Config.Algorithm } | ForEach-Object { $_.Available = $false; $_.Reason += "Algorithm disabled (-$($_.Algorithm)) in generic config" }
        $Variables.Pools | Where-Object { "-$($_.Algorithm)" -in $PoolsConfig.($_.Name).Algorithm } | ForEach-Object { $_.Available = $false; $_.Reason += "Algorithm disabled (-$($_.Algorithm)) in $($_.Name) pool config" }
        $Variables.Pools | Where-Object { "-$($_.Algorithm)" -in $PoolsConfig.Default.Algorithm } | ForEach-Object { $_.Available = $false; $_.Reason += "Algorithm disabled (-$($_.Algorithm)) in default pool config)" }
        If ($Config.Algorithm -like "+*") { $Variables.Pools | Where-Object { "+$($_.Algorithm)" -notin $Config.Algorithm } | ForEach-Object { $_.Available = $false; $_.Reason += "Algorithm not enabled in generic config" } }
        $Variables.Pools | Where-Object { $PoolsConfig.($_.Name).Algorithm -like "+*" } | Where-Object { "+$($_.Algorithm)" -notin $PoolsConfig.($_.Name).Algorithm } | ForEach-Object { $_.Available = $false; $_.Reason += "Algorithm not enabled in $($_.Name) pool config" }
        If ($PoolsConfig.Default.Algorithm -like "+*") { $Variables.Pools | Where-Object { "+$($_.Algorithm)" -notin $PoolsConfig.Default.Algorithm } | ForEach-Object { $_.Available = $false; $_.Reason += "Algorithm not enabled in default pool config" } }

        $Variables.Pools | Where-Object { $Config.Pools.$($_.Name).ExcludeRegion -and (Compare-Object @($Config.Pools.$($_.Name).ExcludeRegion | Select-Object) @($_.Region) -IncludeEqual -ExcludeDifferent) } | ForEach-Object { $_.Available = $false; $_.Reason += "Region excluded in $($_.Name) pool config" } 

        # Use region as preference and not the only one
        [Pool[]]$ThisRegionPools = $Variables.Pools | Where-Object { $_.Region -eq $Config.Region }
        $Variables.Pools = $ThisRegionPools + ($Variables.Pools | Where-Object { $_ -notin $ThisRegionPools })
        Remove-Variable ThisRegionPools

        Write-Message -Level VERBOSE "Had $($Variables.PoolsCount) pool$( If ($Variables.PoolsCount -ne 1) { "s" }), found $($ComparePools.Count) new pool$( If ($ComparePools.Count -ne 1) { "s" }). $(@($Variables.Pools | Where-Object Available -EQ $true).Count) pool$(If (@($Variables.Pools | Where-Object Available -EQ $true).Count -ne 1) { "s" }) remain$(If (@($Variables.Pools | Where-Object Available -EQ $true).Count -eq 1) { "s" }) (filtered out $(@($Variables.Pools | Where-Object Available -NE $true).Count) pool$(If (@($Variables.Pools | Where-Object Available -NE $true).Count -ne 1) { "s" }))."
        Remove-Variable ComparePools

        #If not all the live pool prices represent the same period of time then use historic pricing for the same period
        If (($Variables.Pools | Where-Object Available -EQ $true | Where-Object Price_Bias | Select-Object -ExpandProperty Name -Unique | ForEach-Object { $Variables.Pools | Where-Object Name -EQ $_ | Measure-Object Updated -Maximum | Select-Object -ExpandProperty Maximum } | Select-Object -Unique | Measure-Object -Minimum -Maximum | ForEach-Object { $_.Maximum - $_.Minimum }).TotalMinutes -gt $Config.SyncWindow) { 
            Write-Message -Level Warn "Pool prices are out of sync ($([Int]($Variables.Pools | Where-Object Price_Bias | Select-Object -ExpandProperty Name -Unique | ForEach-Object { $Variables.Pools | Where-Object Name -EQ $_ | Measure-Object Updated -Maximum | Select-Object -ExpandProperty Maximum} | Select-Object -Unique | Measure-Object -Minimum -Maximum | ForEach-Object { $_.Maximum - $_.Minimum }).TotalMinutes) minutes). "
            $Variables.Pools | Where-Object Price_Bias | ForEach-Object { $_.Price_Bias = $_.StablePrice }
        }

        If ($Config.Watchdog) { 
            #Apply watchdog to pools
            $Variables.Pools | Where-Object { ($Variables.WatchdogTimers | Where-Object PoolName -EQ $_.Name | Where-Object Kicked -LT $Variables.Timer.AddSeconds( - $Variables.WatchdogInterval) | Where-Object Algorithm -EQ $_.Algorithm).Count -ge $Config.WatchdogPoolAlgorithmCount } | ForEach-Object { $_.Available = $false; $_.Price = $_.Price_Bias = $_.StablePrice = $_.MarginOfError = [Double]::NaN; $_.Reason += "Algorithm suspended by watchdog" }
            $Variables.Pools | Where-Object { ($Variables.WatchdogTimers | Where-Object PoolName -EQ $_.Name | Where-Object Kicked -LT $Variables.Timer.AddSeconds( - $Variables.WatchdogInterval)).Count -ge $Config.WatchdogPoolCount } | ForEach-Object { $_.Available = $false; $_.Price = $_.Price_Bias = $_.StablePrice = $_.MarginOfError = [Double]::NaN; $_.Reason += "Pool suspended by watchdog" }
        }

        #Pre-sort all pools
        [Pool[]]$Variables.Pools = $Variables.Pools | Sort-Object -Descending { -not $_.Available }, { $_.StablePrice * (1 - $_.MarginOfError) }, { $_.Region -eq $Config.Region }, { $_.SSL -eq $Config.SSL }

        # Ensure we get the hashrate for running miners prior looking for best miner
        $Variables.Miners | Where-Object Best | ForEach-Object { 
            $Miner = $_
            If ($Miner.DataReaderJob.HasMoreData) { 
                $Miner.Data += @($Miner.DataReaderJob | Receive-Job | Select-Object -Property Date, HashRate, Shares, PowerUsage)
            }
            If ($Miner.Status -eq [MinerStatus]::Running -and $Miner.GetStatus() -ne [MinerStatus]::Running) { 
                Write-Message -Level ERROR "Miner '$($Miner.Info)' exited unexpectedly." 
                $Miner.SetStatus([MinerStatus]::Failed)
                $Miner.StatusMessage = "Exited unexpectedly."
            }
            If (($Miner.Data).Count) { 
                $Miner.Speed_Live = [Double[]]@()
                $PowerUsage = 0
                #Collect hashrate from miner
                $Miner_Speeds = [Hashtable]@{}
                $Miner.Algorithm | ForEach-Object { 
                    $Miner.Speed_Live += [Double]($Miner.CollectHashRate($_, $false))
                    $Miner_Speeds.$_ = ([Double]($Miner.CollectHashRate($_, ($Miner.New -and ($Miner.Data).Count -lt ($Miner.MinDataSamples)))))
                }
                If ($Variables.CalculatePowerCost) {
                    #Collect power usage from miner
                    $Miner.PowerUsage_Live = ([Double]($Miner.CollectPowerUsage($false)))
                    $PowerUsage = [Double]($Miner.CollectPowerUsage($Miner.New -and ($Miner.Data).Count -lt ($Miner.MinDataSamples)))
                }
                #Reduce data to MinDataSamples * 5
                If (($Miner.Data).Count -gt ($Miner.MinDataSamples * 5)) { 
                    Write-Message -Level VERBOSE "Reducing data samples for miner ($($Miner.Name)). Keeping the latest $($Miner.MinDataSamples * 5) samples."
                    $Miner.Data = $Miner.Data | Select-Object -Last ($Miner.MinDataSamples * 5)
                }
            }

            #We don't want to store hashrates if we have less than $MinDataSamples
            If (($Miner.GetStatus() -eq [MinerStatus]::Running -and ($Miner.Data).Count -ge $Miner.MinDataSamples) -or ($Miner.New -and $Miner.Activated -ge 3)) { 
                $Miner.StatEnd = (Get-Date).ToUniversalTime()
                $Miner.Intervals += $Stat_Span = [TimeSpan]($Miner.StatEnd - $Miner.StatStart)

                $Miner.Workers | ForEach-Object { 
                    $Worker =  $_
                    $Algorithm = $Worker.Pool.Algorithm
                    $Stat_Name = "$($Miner.Name)_$($Algorithm)_HashRate"
                    If ($Miner.Activated -gt 0 -or (Get-Stat $Stat_Name)) { #Do not save data if stat just got removed
                        $Stat = Set-Stat -Name $Stat_Name -Value $Miner_Speeds.$Algorithm -Duration $Stat_Span -FaultDetection (($Miner.Data).Count -ge $Miner.MinDataSamples)
                        If ($Stat.Updated -gt $Variables.StatStart) { 
                            Write-Message "Saved hash rate ($($Stat_Name): $(($Miner_Speeds.$Algorithm | ConvertTo-Hash) -replace ' '))$(If ($Stat.Duration -eq $Stat_Span) { " [Benchmark done]" })."
                            #Update watchdog timer
                            $WatchdogTimer = $Variables.WatchdogTimers | Where-Object MinerName -EQ $Miner.Name | Where-Object PoolName -EQ $Worker.Pool.Name | Where-Object Algorithm -EQ $Worker.Pool.Algorithm | Where-Object DeviceName -EQ $Miner.DeviceName | Sort-Object Kicked | Select-Object -Last 1
                            If ($WatchdogTimer -and $Stat.Updated -gt $WatchdogTimer.Kicked) { 
                                $WatchdogTimer.Kicked = $Stat.Updated
                            }
                            $Miner.StatStart = $Miner.StatEnd
                        }
                    }
                }

                If ($Variables.CalculatePowerCost -and $Variables.OldCalculatePowerCost -eq $Variables.CalculatePowerCost) {
                    $Stat_Name = "$($Miner.Name)$(If ($Miner.Algorithm.Count -eq 1) { "_$($Miner.Algorithm | Select-Object -Index 0)" })_PowerUsage"
                    If ($Miner.Activated -gt 0 -or $Stats.$Stat_Name) { #Do not save data if stat just got removed
                        $Stat = Set-Stat -Name $Stat_Name -Value $PowerUsage -Duration $Stat_Span -FaultDetection (($Miner.Data).Count -gt $Miner.MinDataSamples)
                        If ($Stat.Updated -gt $Variables.StatStart) { 
                            Write-Message "Saved power usage ($($Stat_Name): $(([Double]$PowerUsage).ToString("N2"))W)$(If ($Stat.Duration -eq $Stat_Span) { " [Power usage measurement done]" })."
                        }
                    }
                }
                Remove-Variable Stat_Name
                Remove-Variable Stat_Span
                $Miner.New = $false
                Remove-Variable Stat -ErrorAction Ignore
            }
        }

        If ((Test-Path .\Miners -PathType Container) -and (Test-Path ".\Config\MinersHash.json" -PathType Leaf)) { 
            Write-Message "Looking for miner files changes..."
            $Variables.MinersHash = Get-Content ".\Config\MinersHash.json" | ConvertFrom-Json
            Compare-Object @($Variables.MinersHash | Select-Object) @(Get-ChildItem .\Miners\ -filter "*.ps1" | Get-FileHash | Select-Object) -Property "Hash", "Path" | Sort-Object "Path" -Unique | ForEach-Object { 
                If (Test-Path $_.Path -PathType Leaf) { 
                    Write-Message "Miner Updated: $($_.Path)"
                    $UpdatedMiner = &$_.path
                    $UpdatedMiner.Name = (Get-Item $_.Path).BaseName
                    $Variables.Miners | Where-Object { $_.Path -eq (Resolve-Path $UpdatedMiner.Path) } | ForEach-Object { 
                        $Miner = $_
                        If ($Miner.Status -eq [MinerStatus]::Running -and $Miner.GetStatus() -ne [MinerStatus]::Running) { 
                            Write-Message -Level ERROR "Miner '$Miner.Info' exited unexpectedly." 
                            $Miner.SetStatus([MinerStatus]::Failed)
                        }
                        Else { 
                            Write-Message "Stopping miner '$Miner.Info' for update..."
                            $Miner.SetStatus([MinerStatus]::Idle)
                        }

                        #Remove all watchdog timer(s) for this miner
                        $Miner.Workers | ForEach-Object { 
                            $Worker = $_
                            $WatchdogTimer = $Variables.WatchdogTimers | Where-Object MinerName -EQ $Miner.Name | Where-Object PoolName -EQ $Worker.Pool.Name | Where-Object Algorithm -EQ $Worker.Pool.Algorithm | Where-Object DeviceName -EQ $Miner.DeviceName
                            If ($WatchdogTimer) { 
                                $Variables.WatchdogTimers = @($Variables.WatchdogTimers | Where-Object MinerName -NE $Miner.Name | Where-Object Algorithm -NE $Worker.Pool.Algorithm | Where-Object DeviceName -NE $Miner.DeviceName)
                            }
                        }
                    }
                    #Remove old binaries
                    Remove-Item -Force -Recurse (Split-Path $UpdatedMiner.Path)
                    #Trigger benchmark
                    Get-ChildItem -path ".\Stats\" -filter "$($UpdatedMiner.Name)_*.txt" | ForEach-Object { Remove-Stat ($_ -replace ".txt") } 
                }
                $Variables.MinersHash = Get-ChildItem .\Miners\ -filter "*.ps1" | Get-FileHash
                $Variables.MinersHash | ConvertTo-Json | Out-File ".\Config\MinersHash.json"
            }
        }

        #Get new miners
        Write-Message -Verbose "Loading miners..."
        $AllPools = [PSCustomObject]@{ }
        $PoolsPrimaryAlgorithm =  [PSCustomObject]@{ }
        $PoolsSecondaryAlgorithm =  [PSCustomObject]@{ }
        #For leagacy miners
        $Variables.Pools | Select-Object -ExpandProperty Algorithm -Unique | ForEach-Object { $_.ToLower() } | Select-Object -Unique | ForEach-Object { 
            $Variables.Pools | Where-Object Available -EQ $true | Where-Object Algorithm -EQ $_ | Select-Object -First 1 | ForEach-Object {  
                $_.Best = $true
                $AllPools | Add-Member $_.Algorithm $_
            }
        }
        $Variables.Pools | Sort-Object Algorithm | Where-Object Best -EQ $true | ForEach-Object { 
            If ($_.Reason -ne "Unprofitable Primary Algorithm") { $PoolsPrimaryAlgorithm | Add-Member $_.Algorithm $_ } #Allow unprofitable algos for primary algorithm
            If ($_.Reason -ne "Unprofitable Secondary Algorithm") { $PoolsSecondaryAlgorithm | Add-Member $_.Algorithm $_ } #Allow unprofitable algos for secondary algorithm
        }

        #Prepare devices
        $EnabledDevices = $Variables.Devices | Where-Object { $_.State -EQ [DeviceState]::Enabled } | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        #For GPUs set type AMD or NVIDIA
        $EnabledDevices | Where-Object Type -EQ "GPU" | ForEach-Object { $_.Type = $_.Vendor }
        If (-not $Config.MinerInstancePerDeviceModel) { $EnabledDevices | ForEach-Object { $_.Model = $_.Vendor } } #Remove Model information from devices -> will create only one miner instance

        #Load miners
        If (Test-Path ".\Miners" -PathType Container -ErrorAction Ignore) { 
            $Variables.NewMiners_Jobs = @(
                If ($Config.IncludeRegularMiners -and (Test-Path ".\Miners" -PathType Container)) { Get-ChildItemContent ".\Miners" -Parameters @{ Pools = $PoolsPrimaryAlgorithm; PoolsSecondaryAlgorithm = $PoolsSecondaryAlgorithm; Config = $Config; Devices = $EnabledDevices } -Threaded -Priority $(If ($Variables.Miners | Where-Object Status -EQ "Running" | Where-Object Type -EQ "CPU") { "Normal" }) }
                If ($Config.IncludeOptionalMiners -and (Test-Path ".\OptionalMiners" -PathType Container)) { Get-ChildItemContent ".\OptionalMiners" -Parameters @{ Pools = $PoolsPrimaryAlgorithm; PoolsSecondaryAlgorithm = $PoolsSecondaryAlgorithm; Config = $Config; Devices = $EnabledDevices } -Threaded -Priority $(If ($Variables.Miners | Where-Object Status -EQ "Running" | Where-Object { $_.DeviceName -like "CPU#*" }) { "Normal" }) }
                If (Test-Path ".\CustomMiners" -PathType Container) { Get-ChildItemContent ".\CustomMiners" -Parameters @{ Pools = $PoolsPrimaryAlgorithm; PoolsSecondaryAlgorithm = $PoolsSecondaryAlgorithm; Config = $Config; Devices = $EnabledDevices } -Threaded -Priority $(If ($Variables.Miners | Where-Object Status -EQ "Running" | Where-Object { $_.DeviceName -like "CPU#*" }) { "Normal" }) }
            )

            #Retrieve collected miner data
            $Variables.NewMiners_Jobs | ForEach-Object $_.Job | Wait-Job -Timeout 30 | Out-Null
            $NewMiners = $Variables.NewMiners_Jobs | ForEach-Object { 
                $_.EndInvoke($_.Job) | Where-Object { $_.Content.API } | ForEach-Object { 
                    If ($Config.IgnoreMinerFee) { $Miner_Fees = @($_.Content.HashRates.Count * @(0)) } Else { $Miner_Fees = @($_.Content.Fee) }

                    [Worker[]]$Workers = @()
                    $_.Content.Algorithm | ForEach-Object { 
                        $Workers += @{ 
                            Pool = [Pool]$AllPools.$_
                            Fee = [Double]($Miner_Fees | Select-Object -Index $Workers.Count)
                        }
                    }

                    [PSCustomObject]@{ 
                        Name             = [String]$_.Content.Name
                        BaseName         = [String]($_.Content.Name -split '-' | Select-Object -Index 0)
                        Version          = [String]($_.Content.Name -split '-' | Select-Object -Index 1)
                        Path             = [String]$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($_.Content.Path)
                        Algorithm        = [String[]]$_.Content.Algorithm
                        Workers          = [Worker[]]$Workers
                        Arguments        = $(If ($_.Content.Arguments -isnot [String]) { [String]($_.Content.Arguments | ConvertTo-Json -Depth 10 -Compress) } Else { [String]$_.Content.Arguments })
                        DeviceName       = [String[]]$_.Content.DeviceName
                        Devices          = [Device[]]($Variables.Devices | Where-Object Name -in $_.Content.DeviceName)
                        Type             = [String]$_.Content.Type
                        Port             = [UInt16]$_.Content.Port
                        URI              = [String]$_.Content.URI
                        PrerequisitePath = [String]$_.Content.PrerequisitePath
                        WarmupTime       = $(If ($_.Content.WarmupTime -lt $Config.WarmupTime) { [Int]$Config.WarmupTime } Else { [Int]$_.Content.WarmupTime })
                        MinerUri         = [String]$_.Content.MinerUri
                        PowerUsageInAPI  = [Boolean]$_.PowerUsageInAPI
                    } -as "$($_.Content.API)"
                }
            }

            $Variables.NewMiners_Jobs | ForEach-Object { $_.Dispose() }
            $Variables.Remove("NewMiners_Jobs")
        }
        Remove-Variable PoolsPrimaryAlgorithm -ErrorAction Ignore
        Remove-Variable PoolsSecondaryAlgorithm -ErrorAction Ignore

        $CompareMiners = Compare-Object -PassThru @($Variables.Miners | Select-Object) @($NewMiners | Select-Object) -Property Name, Type, Path, Algorithm -IncludeEqual

        #Stop runing miners where miner file is gone
        $Variables.Miners | Where-Object { $_.SideIndicator -EQ "<=" -and $_.GetStatus() -eq [MinerStatus]::Running } | ForEach-Object { 
            Write-Message "Stopped miner '$($_.Info)'."
            $_.SetStatus([MinerStatus]::Idle)
        }

        #Remove gone miners
        [Miner[]]$Variables.Miners = $Variables.Miners | Where-Object SideIndicator -EQ "=="

        [Miner[]]$Variables.Miners | Select-Object | ForEach-Object { 
            $_.CachedBenchmark = $_.Benchmark
            $_.CachedMeasurePowerUsage = $_.MeasurePowerusage
            $_.Reason = $null
        }

        #Add new miners
        [Miner[]]$Variables.Miners += $CompareMiners | Where-Object SideIndicator -EQ "=>"
        Remove-Variable CompareMiners -ErrorAction Ignore

        #Update existing miners
        $Variables.Miners | Select-Object | ForEach-Object { 
            If ($Miner = Compare-Object -PassThru ($NewMiners | Where-Object Name -EQ $_.Name | Where-Object Path -EQ $_.Path | Where-Object Type -EQ $_.Type | Select-Object) $_ -Property Algorithm -ExcludeDifferent -IncludeEqual) { 
                $_.Restart = [Boolean]($_.Arguments -ne $Miner.Arguments -or $_.Port -ne $Miner.Port -or $_.PowerUsageInAPI -ne $Miner.PowerUsageInAPI)
                $_.Arguments = $Miner.Arguments
                $_.Workers = $Miner.Workers
                $_.Port = $Miner.Port
                $_.WarmupTime = $Miner.WarmupTime
                $_.PowerUsageInAPI = $Miner.PowerUsageInAPI
            }
            $_.AllowedBadShareRatio = $Config.AllowedBadShareRatio
            $_.CalculatePowerCost = $Variables.CalculatePowerCost
            $_.Refresh($Variables.PowerCostBTCperW)
            $_.MinDataSamples = $Config.MinDataSamples * (1, @($_.Algorithm | ForEach-Object { $Config.MinDataSamplesAlgoMultiplier.$_ }) | Measure-Object -Maximum).maximum
            $_.MeasurePowerUsage = [Boolean]($Variables.CalculatePowerCost -eq $true -and [Double]::IsNaN($_.PowerUsage))
            $_.ShowMinerWindows = $Config.ShowMinerWindows
        }
        Remove-Variable Miner -ErrorAction Ignore
        Remove-Variable NewMiners -ErrorAction Ignore

        $Variables.Miners | Select-Object | Where-Object Disabled -EQ $true | ForEach-Object { $_.Available = $false; $_.Reason += "0H/s Stat file" }
        $Variables.Miners | Select-Object | Where-Object { $Config.ExcludeMinerName.Count -and (Compare-Object @($Config.ExcludeMinerName | Select-Object) @($_.BaseName, "$($_.BaseName)_$($_.Version)", $_.Name | Select-Object -Unique) -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0 } | ForEach-Object { $_.Available = $false; $_.Reason += "ExcludeMinerName: ($($Config.ExcludeMinerName -Join '; '))" }
        $Variables.Miners | Select-Object | Where-Object { $Config.ExcludeDeviceName.Count -and (Compare-Object @($Config.ExcludeDeviceName | Select-Object) @($_.DeviceName | Select-Object)-IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0 } | ForEach-Object { $_.Available = $false; $_.Reason += "ExcludeDeviceName: ($($Config.ExcludeDeviceName -Join '; '))" }
        $Variables.Miners | Select-Object | Where-Object Disabled -NE $true | Where-Object Earning -EQ 0 | ForEach-Object { $_.Available = $false; $_.Reason += "Earning -eq 0" }
        $Variables.Miners | Select-Object | Where-Object { ($Config.Algorithm | Select-Object | Where-Object { $_.StartsWith("+") }) -and (Compare-Object (($Config.Algorithm | Select-Object | Where-Object { $_.StartsWith("+") }).Replace("+", "")) $_.Algorithm -IncludeEqual -ExcludeDifferent | Measure-Object).Count -eq 0 } | ForEach-Object { $_.Available = $false; $_.Reason += "Config.ExcludeAlgorithm ($($_.Algorithm -join " & "))" }
        $Variables.Miners | Select-Object | Where-Object { $Config.DisableMinersWithFees -and $_.Fee -gt 0 } | ForEach-Object { $_.Available = $false; $_.Reason += "Config.DisableMinersWithFees" }
        $Variables.Miners | Select-Object | Where-Object { $Config.NoSingleAlgoMining -and $_.Workers.Count -eq 1 } | ForEach-Object { $_.Available = $false; $_.Reason += "Config.NoSingleAlgoMining" }
        $Variables.Miners | Select-Object | Where-Object { $Config.NoDualAlgoMining -and $_.Workers.Count -eq 2 } | ForEach-Object { $_.Available = $false; $_.Reason += "Config.NoDualAlgoMining" }

        $Variables.MinersNeedingBenchmark = $Variables.Miners | Where-Object Benchmark -EQ $true
        $Variables.MinersNeedingPowerUsageMeasurement = $Variables.Miners | Where-Object Enabled -EQ $true | Where-Object MeasurePowerUsage -EQ $true

        If (-not ($Variables.MinersNeedingBenchmark -or $Variables.MinersNeedingPowerUsageMeasurement)) { 
            #Detect miners with unreal earning (> 3x higher than the next best 10% miners, error in data provided by pool?)
            $Variables.Miners | Select-Object | Group-Object -Property { $_.DeviceName } | ForEach-Object {
                $ReasonableEarning = [Double]($_.Group | Sort-Object -Descending Earning | Select-Object -Skip 1 -First ([Int]($VMiners.Count / 10 )) | Measure-Object Earning -Average).Average * 3
                $_.Group | Where-Object { $ReasonableEarning -gt 0 -and $_.Earning -le $ReasonableEarning } | Foreach-Object { $_.Available = $false; $_.Reason += "Unreal profit data (-gt 3x higher)"}
            }
            Remove-Variable ReasonableEarning -ErrorAction Ignore
        }

        $Variables.Miners | Where-Object Available -EQ $true | Where-Object { -not (Test-Path $_.Path -Type Leaf -ErrorAction Ignore) } | ForEach-Object { $_.Available = $false; $_.Reason += "Binary missing" }
        $Variables.Miners | Where-Object Available -EQ $true | Where-Object PrerequisitePath | Where-Object { -not (Test-Path $_.PrerequisitePath -PathType Leaf -ErrorAction Ignore) } | ForEach-Object { $_.Available = $false; $_.Reason += "PreRequisite missing" }

        $Variables.MinersMissingBinary = $Variables.Miners | Where-Object Reason -contains "Binary missing"
        $Variables.MinersMissingPreRequisite = $Variables.Miners | Where-Object Reason -contains "PreRequisite missing"

        Get-Job | Where-Object { $_.State -eq "Completed" } | Remove-Job
        If ($Variables.MinersMissingBinary -or $Variables.MinersMissingPreRequisite) { 
            #Download miner binaries
            If ($Variables.Downloader.State -ne "Running") { 
                Write-Message "Some miners binaries are missing, starting downloader..."
                $Downloader_Parameters = @{
                    Logfile = $Variables.Logfile
                    DownloadList = @($Variables.MinersMissingPreRequisite | Select-Object @{ Name = "URI"; Expression = { $_.PrerequisiteURI } }, @{ Name = "Path"; Expression = { $_.PrerequisitePath } }, @{ Name = "Searchable"; Expression = { $false } }) + @($Variables.MinersMissingBinary | Select-Object URI, Path, @{ Name = "Searchable"; Expression = { $Miner = $_; ($Variables.Miners | Where-Object { (Split-Path $_.Path -Leaf) -eq (Split-Path $Miner.Path -Leaf) }).Count -eq 0 } }) | Select-Object * -Unique
                }
                $Variables.Downloader = Start-Job -Name Downloader -InitializationScript ([scriptblock]::Create("Set-Location '$($Variables.MainPath)'")) -ArgumentList $Downloader_Parameters -FilePath ".\Includes\Downloader.ps1"
                Remove-Variable Downloader_Parameters
            }
            ElseIf (-not ($Variables.Miners | Where-Object Available -EQ $true)) { 
                Write-Message "Waiting 30 seconds for downloader to install binaries..."
            }
        }

        If ($Config.WatchDog) { 
            #Apply watchdog to miners
            $Variables.Miners | Select-Object | Where-Object { ($Variables.WatchdogTimers | Where-Object MinerName -EQ $_.Name | Where-Object DeviceName -EQ $_.DeviceName | Measure-Object | Select-Object -ExpandProperty Count) -ge $Config.WatchdogMinerCount } | ForEach-Object { $_.Available = $false; $_.Data = @(); $_.Reason += "Miner (all algorithms) suspended by watchdog" }
            $Variables.Miners | Select-Object | Where-Object { ($Variables.WatchdogTimers | Where-Object MinerName -EQ $_.Name | Where-Object DeviceName -EQ $_.DeviceName | Where-Object Algorithm -EQ $_.Algorithm | Measure-Object | Select-Object -ExpandProperty Count) -ge $Config.WatchdogMinerAlgorithmCount } | ForEach-Object { $_.Available = $false; $_.Data = @(); $_.Reason += "Miner {$($_.Algorithm)} suspended by watchdog" }
        }

        Write-Message "Found $(($Variables.Miners).Count) miner$(If (($Variables.Miners).Count -ne 1) { "s" }), $(($Variables.Miners | Where-Object Available -EQ $true).Count) miner$(If (($Variables.Miners | Where-Object Available -EQ $true).Count -ne 1) { "s" }) remain$(If (($Variables.Miners | Where-Object Available -EQ $true).Count -eq 1) { "s" }) (filtered out $(($Variables.Miners | Where-Object Available -NE $true).Count) miner$(If (($Variables.Miners | Where-Object Available -NE $true).Count -ne 1) { "s" }))."

        If ($Config.OpenFirewallPorts) { 
            #Open firewall ports for all miners
            #temp fix, needs removing from loop as it requires admin rights
            If (Get-Command "Get-MpPreference" -ErrorAction Ignore) { 
                $ProgressPreferenceBackup = $ProgressPreference
                $ProgressPreference = "SilentlyContinue"
                If ((Get-Command "Get-MpComputerStatus" -ErrorAction Ignore) -and (Get-MpComputerStatus -ErrorAction Ignore)) { 
                    If (Get-Command "Get-NetFirewallRule" -ErrorAction Ignore) { 
                        $MinerFirewalls = Get-NetFirewallApplicationFilter | Select-Object -ExpandProperty Program
                        If (@($Variables.Miners | Select-Object -ExpandProperty Path -Unique) | Compare-Object @($MinerFirewalls) | Where-Object SideIndicator -EQ "=>") { 
                            Start-Process (@{desktop = "powershell"; core = "pwsh" }.$PSEdition) ("-Command Import-Module '$env:Windir\System32\WindowsPowerShell\v1.0\Modules\NetSecurity\NetSecurity.psd1'; ('$(@($Variables.Miners | Select-Object -ExpandProperty Path -Unique) | Compare-Object @($MinerFirewalls) | Where-Object SideIndicator -EQ '=>' | Select-Object -ExpandProperty InputObject | ConvertTo-Json -Compress)' | ConvertFrom-Json) | ForEach-Object {New-NetFirewallRule -DisplayName (Split-Path `$_ -leaf) -Program `$_ -Description 'Inbound rule added by NemosMiner $($Variables.CurrentVersion) on $((Get-Date).ToString())' -Group 'Cryptocurrency Miner'}" -replace '"', '\"') -Verb runAs
                        }
                        Remove-Variable MinerFirewalls
                    }
                }
                $ProgressPreference = $ProgressPreferenceBackup
            }
        }

        Write-Message "Calculating earning$(If ($Variables.PowerPricekWh) { " and profit" }) for each miner$(If ($Variables.PowerPricekWh) { " (power cost $($Config.Currency | Select-Object -Index 0) $($Variables.PowerPricekWh)/kW⋅h)"})..."

        #Don't penalize active miners, add RunningMiner bonus
        $Variables.Miners | Select-Object | Where-Object { $_.GetStatus() -eq [MinerStatus]::Running } | ForEach-Object { 
            $_.Earning_Bias = $_.Earning * (1 + ($Config.RunningMinerGainPct / 100))
            $_.Profit_Bias = $_.Profit * (1 + ($Config.RunningMinerGainPct / 100))
        }

        #Hack: temporarily make all earnings & Earnings positive, BestMiners_Combos(_Comparison) produces wrong sort order when earnings or Earnings are negative
        $SmallestEarningBias = [Double][Math]::Abs((($Variables.Miners | Where-Object Available -EQ $true | Where-Object { -not [Double]::IsNaN($_.Earning_Bias) }).Earning_Bias | Measure-Object -Minimum).minimum) * 2
        $SmallestProfitBias = [Double][Math]::Abs((($Variables.Miners | Where-Object Available -EQ $true | Where-Object { -not [Double]::IsNaN($_.Profit_Bias) }).Profit_Bias | Measure-Object -Minimum).minimum) * 2
        $Variables.Miners | Where-Object Available -EQ $true | ForEach-Object { $_.Earning_Bias += $SmallestEarningBias; $_.Profit_Bias += $SmallestProfitBias }

        If (-not ($Variables.Miners | Where-Object Available -EQ $true)) { 
            Write-Message -Level Warn "No miners available. Waiting for next cycle."
            $Variables.EndLoop = $true
            $Variables.EndLoopTime = (Get-Date).AddSeconds(10)
        }
        ElseIf ($Variables.Miners.Count -eq 1) { 
            $BestMiners_Combo = $BestMiners = $FastestMiners = $Variables.Miners
        }
        Else { 
            #Get most profitable miner combination i.e. AMD+NVIDIA+CPU
            If ($Variables.CalculatePowerCost -and (-not $Config.IgnorePowerCost)) { $SortBy = "Profit" } Else { $SortBy = "Earning" }
            $SortedMiners = $Variables.Miners | Where-Object Available -EQ $true | Sort-Object -Descending { $_.Benchmark -eq $true }, { $_.MeasurePowerUsage -eq $true }, { $_."$($SortBy)_Bias" }, { $_.Data.Count }, { $_.MinDataSamples } #pre-sort
            $FastestMiners = $SortedMiners | Select-Object DeviceName, Algorithm -Unique | ForEach-Object { $Miner = $_; ($SortedMiners | Where-Object { -not (Compare-Object $Miner $_ -Property DeviceName, Algorithm) } | Select-Object -First 1) } #use a smaller subset of miners
            $BestMiners = @($FastestMiners | Select-Object DeviceName -Unique | ForEach-Object { $Miner = $_; ($FastestMiners | Where-Object { (Compare-Object $Miner.DeviceName $_.DeviceName | Measure-Object).Count -eq 0 } | Select-Object -First 1) })

            $Miners_Device_Combos = @(Get-Combination ($BestMiners | Select-Object DeviceName -Unique) | Where-Object { (Compare-Object ($_.Combination | Select-Object -ExpandProperty DeviceName -Unique) ($_.Combination | Select-Object -ExpandProperty DeviceName) | Measure-Object).Count -eq 0 })

            $BestMiners_Combos = @(
                $Miners_Device_Combos | ForEach-Object { 
                    $Miner_Device_Combo = $_.Combination
                    [PSCustomObject]@{ 
                        Combination = $Miner_Device_Combo | ForEach-Object { 
                            $Miner_Device_Count = $_.DeviceName.Count
                            [Regex]$Miner_Device_Regex = "^(" + (($_.DeviceName | ForEach-Object { [Regex]::Escape($_) }) -join '|') + ")$"
                            $BestMiners | Where-Object { ([Array]$_.DeviceName -notmatch $Miner_Device_Regex).Count -eq 0 -and ([Array]$_.DeviceName -match $Miner_Device_Regex).Count -eq $Miner_Device_Count }
                        }
                    }
                }
            )

            $BestMiners_Combo = @($BestMiners_Combos | Sort-Object -Descending { ($_.Combination | Where-Object { $_."$($Sortby)" -Like ([Double]::NaN) } | Measure-Object).Count }, { ($_.Combination | Measure-Object "$($SortBy)_Bias" -Sum).Sum }, { ($_.Combination | Where-Object { $_.SortBy -ne 0 } | Measure-Object).Count } | Select-Object -Index 0 | Select-Object -ExpandProperty Combination)
            Remove-Variable Miner_Device_Combo
            Remove-Variable Miners_Device_Combos
            Remove-Variable BestMiners
            Remove-Variable SortBy
        }
        #Hack part 2: reverse temporarily forced positive earnings & Earnings
        $Variables.Miners | Where-Object Available -EQ $true | ForEach-Object { $_.Earning_Bias -= $SmallestEarningBias; $_.Profit_Bias -= $SmallestProfitBias }
        Remove-Variable SmallestEarningBias
        Remove-Variable SmallestProfitBias

        # No CPU mining if GPU miner prevents it
        If ($BestMiners_Combo.PreventCPUMining -contains $true) { 
            $BestMiners_Combo = $BestMiners_Combo | Where-Object { $_.Type -ne "CPU" }
            Write-Message "Miner prevents CPU mining"
        }

        #Don't penalize active miners
        $Variables.Miners | Select-Object | Where-Object { $_.GetStatus() -eq [MinerStatus]::Running } | ForEach-Object { 
            $_.Earning_Bias = $_.Earning
            $_.Profit_Bias = $_.Profit
        }

        $Variables.MiningProfit = [Double]($BestMiners_Combo | Measure-Object Profit -Sum).Sum
        $Variables.MiningEarning = [Double]($BestMiners_Combo | Measure-Object Earning -Sum).Sum
        $Variables.MiningPowerCost = [Double]($BestMiners_Combo | Measure-Object PowerCost -Sum).Sum

        $FastestMiners | Select-Object | ForEach-Object { $_.Fastest =  $true }

        #ProfitabilityThreshold check - OK to run miners?
        If ((-not $Variables.Rates."BTC") -or [Double]::IsNaN($Variables.MiningPowerCost) -or ($Variables.MiningEarning - $Variables.MiningPowerCost) -ge ($Config.ProfitabilityThreshold / $Variables.Rates."BTC".($Config.Currency | Select-Object -Index 0)) -or $Variables.MinersNeedingBenchmark -or $Variables.MinersNeedingPowerUsageMeasurement) { 
            $BestMiners_Combo | Select-Object | ForEach-Object { $_.Best = $true }
        }
        Else { 
            Write-Message "Mining profit ($($Config.Currency | Select-Object -Index 0) $(ConvertTo-LocalCurrency -Value [Double]($Variables.MiningEarning - $Variables.MiningPowerCost) -BTCRate ($Variables.Rates."BTC".($Config.Currency | Select-Object -Index 0)) -Offset 1)) is below the configured threshold of $($Config.Currency | Select-Object -Index 0) $($Config.ProfitabilityThreshold.ToString("N$((Get-Culture).NumberFormat.CurrencyDecimalDigits)"))/day; mining is suspended until threshold is reached."
        }

        $Variables.Summary = ""
        If ($Variables.Rates."BTC") { 
            If (-not [Double]::IsNaN($Variables.MiningEarning)) { 
                $Variables.Summary = "Estimated Earning/day: {0:N} $($Config.Currency | Select-Object -Index 0)" -f ($Variables.MiningEarning * ($Variables.Rates."BTC".($Config.Currency | Select-Object -Index 0)))
                If (-not [Double]::IsNaN($Variables.MiningPowerCost)) { 
                    $Variables.Summary += "&ensp;&ensp;&ensp;&ensp;&ensp;&ensp;Profit/day: {0:N} $($Config.Currency | Select-Object -Index 0)" -f ($Variables.MiningProfit * ($Variables.Rates."BTC".($Config.Currency | Select-Object -Index 0)))
                }
                $Variables.Summary +=  "&ensp;&ensp;&ensp;&ensp;"
            }
            (@("BTC") + @($Config.PoolsConfig.Keys | ForEach-Object { $Config.PoolsConfig.$_.PayoutCurrency }) + @($Config.Currency | ForEach-Object { $_ -replace "^m" } )) | Sort-Object -Unique | Where-object { $_ -ne ($Config.Currency | Select-Object -Index 0) } | ForEach-Object { 
                $Variables.Summary += "&ensp;&ensp;1 $_={0:N} $($Config.Currency | Select-Object -Index 0)" -f ($Variables.Rates.$_.($Config.Currency | Select-Object -Index 0))
            }
        }

        #Also restart running miners (stop & start)
        # Is currently best miner AND
        # has been active before OR
        # Data collector has died OR
        # Benchmark state changed 
        # MeasurePowerUsage state changed
        # CalculatePowerCost -> true -> done (to change data poll interval)
        $BestMiners_Combo | Select-Object | ForEach-Object { 
            If ($_.Activated -EQ -1) { #Re-benchmark triggered in Web GUI
                $_.Restart = $true
                $_.Data = @()
                $_.Activated = 0
            }
            ElseIf ($_.MeasurePowerUsage -and (-not $_.PowerUsageInAPI) -and $_.DataReaderJob.State -ne $_.GetStatus()) { $_.Restart = $true }
            ElseIf ($_.Benchmark -ne $_.CachedBenchmark) { $_.Restart = $true }
            ElseIf ($_.MeasurePowerUsage -ne $_.CachedMeasurePowerUsage) { $_.Restart = $true }
            ElseIf ($_.CalculatePowerCost -eq $false -and -$Variables.CalculatePowerCost) { $_.Restart = $true }
            ElseIf ($Config.ShowMinerWindows -ne $Variables.OldShowMinerWindows) { $_.Restart = $true } 
            ElseIf ($Config.CalculatePowerCost -ne $Variables.OldCalculatePowerCost) { $_.Restart = $true }
        }

        #Stop running miners
        $Variables.Miners | Where-Object Status -EQ "Running" | Where-Object { $_.Best -eq $false -or $_.Restart -eq $true } | ForEach-Object { 
            $Miner = $_
            $Miner_Info = $Miner.Info
            If ($Miner.Status -eq [MinerStatus]::Running -and $Miner.GetStatus() -ne [MinerStatus]::Running) { 
                Write-Message -Level ERROR "Miner '$($Miner.Info)' exited unexpectedly." 
                $Miner.SetStatus([MinerStatus]::Failed)
                $Miner.StatusMessage = "Exited unexpectedly."
            }
            Else { 
                Write-Message "Stopped miner '$($Miner_Info)'."
                $Miner.SetStatus([MinerStatus]::Idle)
                If ($Miner.ProcessId) { Stop-Process -Id $Miner.ProcessId -Force -ErrorAction Ignore }

                $Miner.Workers | ForEach-Object { 
                    $Worker = $_
                    $WatchdogTimer = $Variables.WatchdogTimers | Where-Object MinerName -EQ $Miner.Name | Where-Object Algorithm -EQ $Worker.Pool.Algorithm | Where-Object DeviceName -EQ $Miner.DeviceName
                    If ($WatchdogTimer) { 
                        If ($WatchdogTimer.Kicked -lt $Variables.Timer.AddSeconds( - $Variables.WatchdogInterval)) { 
                            If ($Miner.StatusMessage -ne " suspended by watchdog") { 
                                Write-Message -Level Warn "Watchdog: Miner '$($Miner_Info)' suspended by watchdog."
                                $Miner.StatusMessage = " suspended by watchdog"
                            }
                        }
                        Else { 
                            #Remove watchdog timer(s)
                            $Variables.WatchdogTimers = @($Variables.WatchdogTimers | Where-Object MinerName -NE $Miner.Name | Where-Object Algorithm -NE $Worker.Pool.Algorithm | Where-Object DeviceName -NE $Miner.DeviceName)
                        }
                    }
                }
            }
        }

        #Kill stray miners
        Get-CIMInstance CIM_Process | Where-Object ExecutablePath | Where-Object { [String[]]($Variables.Miners.Path | Sort-Object -Unique) -contains $_.ExecutablePath } | Where-Object { ($Variables.Miners).ProcessID -notcontains $_.ProcessID } | Select-Object -ExpandProperty ProcessID | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction Ignore }

        #Put here in case the port range has changed
        Initialize-API

        #Optional delay to avoid blue screens
        Start-Sleep -Seconds $Config.Delay -ErrorAction Ignore

        $Variables.Miners | Where-Object Best -EQ $true | ForEach-Object { 
            $Miner = $_
            If ($Miner.GetStatus() -ne [MinerStatus]::Running) { 
                # Launch prerun if exists
                If ($Miner.Type -eq "AMD" -and (Test-Path ".\Utils\Prerun\AMDPrerun.bat" -PathType Leaf)) { 
                    Start-Process ".\Utils\Prerun\AMDPrerun.bat" -WorkingDirectory ".\Utils\Prerun" -WindowStyle hidden
                }
                If ($Miner.Type -eq "NVIDIA" -and (Test-Path ".\Utils\Prerun\NVIDIAPrerun.bat" -PathType Leaf)) { 
                    Start-Process ".\Utils\Prerun\NVIDIAPrerun.bat" -WorkingDirectory ".\Utils\Prerun" -WindowStyle hidden
                }
                If ($Miner.Type -eq "CPU" -and (Test-Path ".\Utils\Prerun\CPUPrerun.bat" -PathType Leaf)) { 
                    Start-Process ".\Utils\Prerun\CPUPrerun.bat" -WorkingDirectory ".\Utils\Prerun" -WindowStyle hidden
                }
                If ($Miner.Type -ne "CPU") { 
                    $PrerunName = ".\Utils\Prerun\$($Miner.Algorithm).bat"
                    $DefaultPrerunName = ".\Utils\Prerun\default.bat"
                    If (Test-Path $PrerunName -PathType Leaf) { 
                        Write-Message "Launching Prerun: $PrerunName"
                        Start-Process $PrerunName -WorkingDirectory ".\Utils\Prerun" -WindowStyle hidden
                        Start-Sleep -Seconds 2
                    }
                    ElseIf (Test-Path $DefaultPrerunName -PathType Leaf) { 
                        Write-Message "Launching Prerun: $DefaultPrerunName"
                        Start-Process $DefaultPrerunName -WorkingDirectory ".\Utils\Prerun" -WindowStyle hidden
                        Start-Sleep -Seconds 2
                    }
                }
                $Miner.SetStatus([MinerStatus]::Running)
                Write-Message "Started miner '$($Miner.Info)'."
                Write-Message -Level Verbose $Miner.GetCommandLine().Replace("$(Convert-Path '.\')\", "")

                # Log switching information to .\Logs\switching.log
                [PSCustomObject]@{ Date = (Get-Date); "Type" = $($Miner.Type -join " & "); "Miner" = $Miner.Info; "Account" = (($Miner.Workers.Pool.User | ForEach-Object { $_ -split '\.' | Select-Object -Index 0 } | Select-Object -Unique) -join '; '); "CommandLine" = $Miner.GetCommandLine() } | Export-Csv .\Logs\switching.log -Append -NoTypeInformation
                [PSCustomObject]@{ Date = [String](Get-Date -Format s); "Device" = $(($Miner.Devices.Name | Sort-Object)-join "; "); "Miner" = $Miner.Info; "Account" = (($Miner.Workers.Pool.User | ForEach-Object { $_ -split '\.' | Select-Object -Index 0 } | Select-Object -Unique) -join '; '); "Earning" = ($_.Earning); "Profit" = ($_.Profit); "CommandLine" = $Miner.GetCommandLine().Replace("$(Convert-Path '.\')\", "") } | Export-Csv .\Logs\switching2.log -Append -NoTypeInformation

                #Add watchdog timer
                If ($Config.Watchdog) { 
                    $Miner.Workers | ForEach-Object { 
                        $Worker = $_
                        $Variables.WatchdogTimers += [PSCustomObject]@{ 
                            MinerName  = $Miner.Name
                            PoolName   = $Worker.Pool.Name
                            Algorithm  = $Worker.Pool.Algorithm
                            DeviceName = $Miner.DeviceName
                            Kicked     = $Variables.Timer
                        }
                    }
                }
            }
        }

        $Variables.Miners | Where-Object Best -EQ $true | ForEach-Object { 
            $Message = ""
            If ($_.Benchmark -eq $true) { $Message = "Benchmark " }
            If ($_.Benchmark -eq $true -and $_.MeasurePowerUsage -eq $true) { $Message = "$($Message)and "}
            If ($_.MeasurePowerUsage -eq $true) { $Message = "$($Message)Power usage measurement " }
            If ($Message) { Write-Message -Level Verbose "$($Message)for miner '$($_.Info)' in progress [Attempt $($_.Activated)/3]..." }
        }

        $Variables.Miners | Where-Object Available -EQ $true | Group-Object -Property { $_.DeviceName } | ForEach-Object { 
            $MinersDeviceGroup = $_.Group
            $MinersDeviceGroupNeedingBenchmark = $MinersDeviceGroup | Where-Object { $_.Benchmark -eq $true }
            $MinersDeviceGroupNeedingPowerUsageMeasurement = $MinersDeviceGroup | Where-Object { $_.MeasurePowerUsage -eq $true }

            #Display benchmarking progress
            If ($MinersDeviceGroupNeedingBenchmark) { 
                Write-Message -Level  Verbose "Benchmarking for device$(If (($MinersDeviceGroup.DeviceName | Select-Object -Unique).Count -gt 1) { " group" } ) ($(($MinersDeviceGroup.DeviceName | Select-Object -Unique ) -join '; ')) in progress: $($MinersDeviceGroupNeedingBenchmark.Count) miner$(If ($MinersDeviceGroupNeedingBenchmark.Count -gt 1){ 's' }) left to complete benchmark."
            }
            #Display power usage measurement progress
            If ($MinersDeviceGroupNeedingPowerUsageMeasurement) { 
                Write-Message -Level  Verbose "Power usage measurement for device$(If (($MinersDeviceGroup.DeviceName | Select-Object -Unique).Count -gt 1) { " group" } ) ($(($MinersDeviceGroup.DeviceName | Select-Object -Unique ) -join '; ')) in progress: $($MinersDeviceGroupNeedingPowerUsageMeasurement.Count) miner$(If ($MinersDeviceGroupNeedingPowerUsageMeasurement.Count -gt 1) { 's' }) left to complete measuring."
            }
        }

        $Error.Clear()

        Get-Job | Where-Object State -EQ "Completed" | Remove-Job

        If ($Variables.Miners | Where-Object Status -EQ "Running") { Write-Message "Collecting miner data while waiting for next cycle..." }

        #Cache pools config for next cycle
        $Variables.PoolsConfigCached = $Config.PoolsConfig

        # Mostly used for debug. Will execute code found in .\EndLoopCode.ps1 if exists.
        If (Test-Path ".\EndLoopCode.ps1" -PathType Leaf) { Invoke-Expression (Get-Content ".\EndLoopCode.ps1" -Raw) }
    }

    $Variables.StatusText = "Waiting $($Variables.TimeToSleep) seconds... | Next refresh: $((Get-Date).AddSeconds($Variables.TimeToSleep).ToString('g'))"
    $Variables.EndLoop = $true
    TimerUITick
}

$ProgressPreference = "SilentlyContinue"

If (Test-Path ".\Includes\APIs" -PathType Container -ErrorAction Ignore) { Get-ChildItem ".\Includes\APIs" -File | ForEach-Object { . $_.FullName } }

While ($true) { 
    If ($Variables.MiningStatus -eq "Paused") { 
        # Run a dummy cycle to keep the UI updating.
        $Variables.EndLoopTime = ((Get-Date).AddSeconds($Config.Interval))

        # Keep updating exchange rate
        Get-Rate
        (@("BTC") + @($Config.PoolsConfig.Keys | ForEach-Object { $Config.PoolsConfig.$_.PayoutCurrency }) + @($Config.Currency | ForEach-Object { $_ -replace "^m" } )) | Sort-Object -Unique | Where-object { $_ -ne ($Config.Currency | Select-Object -Index 0) } | ForEach-Object { 
            $Variables.Summary = "1 $_={0:N} $($Config.Currency | Select-Object -Index 0)" -f ($Variables.Rates.$_.($Config.Currency | Select-Object -Index 0))
        }

        # Update the UI every 30 seconds, and the Last 1/6/24hr and text window every 2 minutes
        For ($i = 0; $i -lt 4; $i++) { 
            If ($i -eq 3) { 
                $Variables.EndLoop = $true
                Update-Monitoring
            }
            Else { 
                $Variables.EndLoop = $false
            }

            $Variables.StatusText = "Mining paused"
            Start-Sleep -Seconds 30
        }
    }
    Else { 
        # Purge logs more than 10 days
        Get-ChildItem ".\Logs\CoreCyle-*.log" | Sort-Object LastWriteTime | Select-Object -Skip 10 | Remove-Item -Force -Recurse

        Start-Cycle
        Update-Monitoring

        $Variables.RefreshNeeded = $true
        TimerUITick

        #End loop when
        # - a miner crashed (and no other miners are benchmarking)
        # - all benchmarking miners have collected enough samples
        # - warmuptime is up
        # - timeout is reached (no readout from miner)
        $InitialActiveMiners = $ActiveMiners = $Variables.Miners | Where-Object Best -EQ $true | Sort-Object -Descending { $_.Benchmark }, { $_.MeasurePowerUsage }
        $BenchmarkingOrMeasuringMiners = @($ActiveMiners | Where-Object { $_.Benchmark -eq $true -or $_.MeasurePowerUsage -eq $true })
        If ($BenchmarkingOrMeasuringMiners) { $Interval = 2 } Else { $Interval = 5 }

        While ((Get-Date) -le $Variables.EndLoopTime -or ($BenchmarkingOrMeasuringMiners | Where-Object Activated -GT 0)) {
            $NextLoop = (Get-Date).AddSeconds($Interval)
            $ActiveMiners | ForEach-Object { 
                $Miner = $_
                If ($Miner.DataReaderJob.HasMoreData) { 
                    $Miner.Data += $Samples = @($Miner.DataReaderJob | Receive-Job | Select-Object) 
                    $Sample = @($Samples) | Select-Object -Last 1
                    If ($Sample) { 
                        Write-Message -Level Verbose "$($Miner.Name) data sample retrieved: [$(($Miner.Algorithm | ForEach-Object { "$_ = $(($Sample.Hashrate.$_ | ConvertTo-Hash) -replace ' ')$(If ($Miner.AllowedBadShareRatio) { " / Shares Total = $($Sample.Shares.$_[2]), Rejected = $($Sample.Shares.$_[1])" })" }) -join ' & ')$(If ($Sample.PowerUsage) { " / Power = $($Sample.PowerUsage.ToString("N2"))W" })] ($(($Miner.Data).Count) sample$(If (($Miner.Data).Count -ne 1) { "s"} ))"
                        If ($Miner.AllowedBadShareRatio) { 
                            $Miner.Algorithm | ForEach-Object { 
                                If ((-not $Sample.Shares.$_[0] -and $Sample.Shares.$_[1] -ge 3) -or ($Sample.Shares.$_[0] -and ($Sample.Shares.$_[1] * $Miner.AllowedBadShareRatio -gt $Sample.Shares.$_[0]))) { 
                                    Write-Message -Level ERROR "Miner '$($Miner.Info)' stopped. Reason: Too many bad shares (Shares Total = $($Sample.Shares.$_[2]), Rejected = $($Sample.Shares.$_[1]))." 
                                    $Miner.SetStatus([MinerStatus]::Failed)
                                    $Miner.StatusMessage = "too many bad shares."
                                    Break
                                }
                            }
                        }
                    }
                }
                If ($Miner.GetStatus() -ne [MinerStatus]::Running) { 
                    #Miner crashed
                    Write-Message -Level ERROR "Miner '$($Miner.Info)' exited unexpectedly." 
                    $Miner.SetStatus([MinerStatus]::Failed)
                    $Miner.StatusMessage = "Exited unexpectedly."
                }
                ElseIf ($Miner.DataReaderJob.State -ne [MinerStatus]::Running) { 
                    #Miner data reader process failed
                    Write-Message -Level ERROR "Miner data reader '$($Miner.Info)' exited unexpectedly." 
                    $Miner.SetStatus([MinerStatus]::Failed)
                    $Miner.StatusMessage = "Miner data reader exited unexpectedly."
                }
                ElseIf (((Get-Date) - $Miner.Process.StartTime).TotalSeconds -gt $Miner.WarmupTime -and ($Miner.Data.Date | Select-Object -Last 1) -lt (Get-Date).AddSeconds( -$Miner.WarmupTime).ToUniversalTime()) { 
                    #Miner is stuck - no data for > $WarmupTime seconds
                    Write-Message -Level ERROR "Miner '$($Miner.Info)' got stopped because it has not updated data for $($Miner.WarmupTime) seconds."
                    $Miner.SetStatus([MinerStatus]::Failed)
                    $Miner.StatusMessage = "Has not updated data for $($Miner.WarmupTime) seconds"
                }
            }

            $FailedMiners = $ActiveMiners | Where-Object { $_.GetStatus() -ne [MinerStatus]::Running }
            $ActiveMiners = $ActiveMiners | Where-Object { $_.GetStatus() -eq [MinerStatus]::Running }
            $BenchmarkingOrMeasuringMiners = @($BenchmarkingOrMeasuringMiners | Where-Object { $_.GetStatus() -eq [MinerStatus]::Running })

            If ($FailedMiners -and -not $BenchmarkingOrMeasuringMiners) { 
                #A miner crashed and we're not benchmarking, end the loop now
                $Variables.EndLoop = $true
                $Message = "Miner failed. "
                Break
            }
            ElseIf ($BenchmarkingOrMeasuringMiners -and (-not ($BenchmarkingOrMeasuringMiners | Where-Object { ($_.Data).Count -lt ($Config.MinDataSamples) }))) { 
                #Enough samples collected for this loop, exit loop immediately
                $Message = "All$(If ($BenchmarkingOrMeasuringMiners | Where-Object Benchmark -EQ $true) { " benchmarking" })$(If ($BenchmarkingOrMeasuringMiners | Where-Object { $_.Benchmark -eq $true -and $_.MeasurePowerUsage -eq $true }) { " and" } )$(If ($BenchmarkingOrMeasuringMiners | Where-Object MeasurePowerUsage -EQ $true) { " power usage measuring" }) miners have collected enough samples for this cycle. "
                Break
            }
            ElseIf ($InitialActiveMiners -and (-not $ActiveMiners)) { 
                #No more running miners, end the loop now
                $Variables.EndLoop = $true
                $Message = "No more running miners. "
                Break
            }

            While ((Get-Date) -le $NextLoop) { Start-Sleep -Milliseconds 100 }
        }
        Write-Message "$($Message)Ending cycle."
        Remove-Variable Message -ErrorAction SilentlyContinue
        Remove-Variable ActiveMiners -ErrorAction SilentlyContinue
        Remove-Variable InitialActiveMiners -ErrorAction SilentlyContinue
        Remove-Variable FailedMiners -ErrorAction SilentlyContinue
        Remove-Variable BenchmarkingMiners -ErrorAction SilentlyContinue
        Update-Monitoring
    }
}
