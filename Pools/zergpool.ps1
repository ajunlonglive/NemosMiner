using module ..\Includes\Include.psm1

Try { 
    $Request = Get-Content ((Split-Path -parent (Get-Item $script:MyInvocation.MyCommand.Path).Directory) + "\Brains\zergpool\zergpool.json") | ConvertFrom-Json
}
Catch { return }

If (-not $Request) { return }

$Name = (Get-Item $script:MyInvocation.MyCommand.Path).BaseName
$HostSuffix = ".mine.zergpool.com"
$PriceField = "Plus_Price"
# $PriceField = "actual_last24h"
# $PriceField = "estimate_current"
$DivisorMultiplier = 1000000

$Location = "US"

# Placed here for Perf (Disk reads)
$ConfName = If ($Config.PoolsConfig.$Name) { $Name } Else { "default" }
$PoolConf = $Config.PoolsConfig.$ConfName

$Request | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object { 
    $PoolHost = "$($_)$($HostSuffix)"
    $PoolPort = $Request.$_.port
    $PoolAlgorithm = Get-Algorithm $Request.$_.name

    $Divisor = $DivisorMultiplier * [Double]$Request.$_.mbtc_mh_factor

    $Stat = Set-Stat -Name "$($Name)_$($PoolAlgorithm)_Profit" -Value ([Double]$Request.$_.$PriceField / $Divisor * (1 - ($Request.$_.fees / 100)))

    $PwdCurr = If ($PoolConf.PwdCurrency) { $PoolConf.PwdCurrency } Else { $Config.Passwordcurrency }
    $WorkerName = If ($PoolConf.WorkerName -like "ID=*") { $PoolConf.WorkerName } Else { "ID=$($PoolConf.WorkerName)" }

    If ($PoolConf.Wallet) { 
        [PSCustomObject]@{ 
            Algorithm     = [String]$PoolAlgorithm
            Price         = [Double]($Stat.Live * $PoolConf.PricePenaltyFactor)
            StablePrice   = [Double]$Stat.Week
            MarginOfError = [Double]$Stat.Week_Fluctuation
            Protocol      = "stratum+tcp"
            Host          = [String]$PoolHost
            Port          = [Int]$PoolPort
            User          = $PoolConf.Wallet
            Pass          = "$($WorkerName),c=$($PwdCurr)"
            Location      = [String]$Location
            SSL           = [Bool]$false
            Fee           = [Decimal]($Request.$_.Fees / 100)
        }
    }
}
