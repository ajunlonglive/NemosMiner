if (!(IsLoaded(".\Include.ps1"))) {. .\Include.ps1;RegisterLoaded(".\Include.ps1")}

$Threads = 2

$Path = ".\Bin\Excavator2\excavator.exe"
$Uri = "https://github.com/nicehash/excavator/releases/download/v1.4.4a/excavator_v1.4.4a_NVIDIA_Win64.zip"

$Commands = [PSCustomObject]@{
    #"blake2s" = @() #Blake2s(alexis78 faster)
    #"decred" = @() #Decred
    #"daggerhashimoto" = @() #Ethash(claymore faster)
    #"equihash" = @() #Equihash(dstm faster)
    #"lbry" = @() #Lbry
    "lyra2rev2" = @() #Lyra2RE2(fastest)
    #"neoscrypt" = @() #NeoScrypt(fastest)
    #"nist5" = @() #nist5(alexis78 faster)
    #"pascal" = @() #Pascal
}

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName
$Port = $Variables.NVIDIAMinerAPITCPPort

$Commands | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {
    try {
        if ((Get-Algorithm $_) -ne "Decred" -and (Get-Algorithm $_) -ne "Sia") {
            if ((Test-Path (Split-Path $Path)) -and $Pools.$(Get-Algorithm $_).Host) {
                [PSCustomObject]@{time = 0; commands = @([PSCustomObject]@{id = 1; method = "algorithm.add"; params = @("$_", "$([Net.DNS]::Resolve($Pools.$(Get-Algorithm $_).Host).AddressList.IPAddressToString | Select-Object -First 1):$($Pools.$(Get-Algorithm $_).Port)", "$($Pools.$(Get-Algorithm $_).User):$($Pools.$(Get-Algorithm $_).Pass)")})},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "0") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "1") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "2") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "3") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "4") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "5") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "6") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "7") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "8") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "9") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "10") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "11") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "12") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "13") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "14") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "15") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "16") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "17") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "18") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "19") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 10; loop = 10; commands = @([PSCustomObject]@{id = 1; method = "algorithm.print.speeds"; params = @("0")})} | ConvertTo-Json -Depth 10 | Set-Content "$(Split-Path $Path)\$($Pools.$(Get-Algorithm $_).Name)_$(Get-Algorithm $_)_$($Pools.$(Get-Algorithm $_).User)_$($Threads)_Nvidia.json" -Force -ErrorAction Stop
            }

            [PSCustomObject]@{
                Type = "NVIDIA"
                Path = $Path
                Arguments = "-p $Port -c $($Pools.$(Get-Algorithm $_).Name)_$(Get-Algorithm $_)_$($Pools.$(Get-Algorithm $_).User)_$($Threads)_Nvidia.json -na"
                HashRates = [PSCustomObject]@{$(Get-Algorithm $_) = $Stats."$($Name)_$(Get-Algorithm $_)_HashRate".Week}
                API = "NiceHash"
                Port = $Port
                URI = $Uri
				User = $Pools.(Get-Algorithm($_)).User
                PrerequisitePath = "$env:SystemRoot\System32\msvcr120.dll"
                PrerequisiteURI = "http://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe"
            }
        }
        else {
            if ((Test-Path (Split-Path $Path)) -and $Pools."$(Get-Algorithm $_)NiceHash".Host) {
                [PSCustomObject]@{time = 0; commands = @([PSCustomObject]@{id = 1; method = "algorithm.add"; params = @("$_", "$([Net.DNS]::Resolve($Pools."$(Get-Algorithm $_)NiceHash".Host).AddressList.IPAddressToString | Select-Object -First 1):$($Pools."$(Get-Algorithm $_)NiceHash".Port)", "$($Pools."$(Get-Algorithm $_)NiceHash".User):$($Pools."$(Get-Algorithm $_)NiceHash".Pass)")})},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "0") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "1") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "2") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "3") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "4") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "5") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "6") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "7") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "8") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "9") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "10") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "11") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "12") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "13") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "14") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "15") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "16") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "17") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "18") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 3; commands = @([PSCustomObject]@{id = 1; method = "worker.add"; params = @("0", "19") + $Commands.$_}) * $Threads},
                [PSCustomObject]@{time = 10; loop = 10; commands = @([PSCustomObject]@{id = 1; method = "algorithm.print.speeds"; params = @("0")})} | ConvertTo-Json -Depth 10 | Set-Content "$(Split-Path $Path)\$($Pools."$(Get-Algorithm $_)NiceHash".Name)_$(Get-Algorithm $_)_$($Pools."$(Get-Algorithm $_)NiceHash".User)_$($Threads)_Nvidia.json" -Force -ErrorAction Stop
            }

            [PSCustomObject]@{
                Type = "NVIDIA"
                Path = $Path
                Arguments = "-p $Port -c $($Pools."$(Get-Algorithm $_)NiceHash".Name)_$(Get-Algorithm $_)_$($Pools."$(Get-Algorithm $_)NiceHash".User)_$($Threads)_Nvidia.json -na"
                HashRates = [PSCustomObject]@{"$(Get-Algorithm $_)NiceHash" = $Stats."$($Name)_$(Get-Algorithm $_)NiceHash_HashRate".Week}
                API = "NiceHash"
                Port = $Port
                URI = $Uri
				User = $Pools.(Get-Algorithm($_)).User
                PrerequisitePath = "$env:SystemRoot\System32\msvcr120.dll"
                PrerequisiteURI = "http://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe"
            }
        }
    }
    catch {
    }
}
