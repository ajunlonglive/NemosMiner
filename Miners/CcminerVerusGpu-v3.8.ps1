using module ..\Includes\Include.psm1

$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Path = ".\Bin\$($Name)\ccminer.exe"
$Uri = "https://github.com/Minerx117/miner-binaries/releases/download/v3.8/ccminerGPU38.7z"
$DeviceEnumerator = "Type_Vendor_Index"

$Commands = [PSCustomObject]@{ 
    "VerusHash" = " --algo verus --intensity 21"
    #"VerusHash" = " --algo verus --intensity 21"
}

$Devices | Where-Object Type -EQ "NVIDIA" | Select-Object Model -Unique | Sort-Object $DeviceEnumerator | ForEach-Object { 
    If ($Miner_Devices = @($Devices | Where-Object Model -EQ $_.Model)) { 
        $MinerAPIPort = [UInt16]($Config.APIPort + ($Miner_Devices | Sort-Object Id | Select-Object -First 1 -ExpandProperty Id) + 1)
        $Miner_Name = (@($Name) + @($Miner_Devices.Model | Sort-Object -Unique | ForEach-Object { $Model = $_; "$(@($Miner_Devices | Where-Object Model -eq $Model).Count)x$Model" }) | Select-Object) -join '-'

        $Commands | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Where-Object { $Pools.$_.Host } | Where-Object { -not $Pools.$_.SSL } | ForEach-Object {

            #Get commands for active miner devices
            #$Commands.$_ = Get-CommandPerDevice -Command $Commands.$_ -ExcludeParameters @("algo") -DeviceIDs $Miner_Devices.$DeviceEnumerator

            [PSCustomObject]@{ 
                Name       = $Miner_Name
                DeviceName = $Miner_Devices.Name
                Path      = $Path
                Arguments = ("$($Commands.$_) --url stratum+tcp://$($Pools.$_.Host):$($Pools.$_.Port) --user $($Pools.$_.User) --pass $($Pools.$_.Pass) --statsavg 2 --retry-pause 1 --api-bind $MinerAPIPort --devices $(($Miner_Devices | ForEach-Object { '{0:x}' -f ($_.$DeviceEnumerator) }) -join ',')" -replace "\s+", " ").trim()
                Algorithm = $_
                API       = "Ccminer"
                Port      = $MinerAPIPort
                URI       = $Uri
            }
        }
    }
}