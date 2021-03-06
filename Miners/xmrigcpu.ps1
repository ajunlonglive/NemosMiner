If (-not (IsLoaded(".\Includes\include.ps1"))) { . .\Includes\include.ps1; RegisterLoaded(".\Includes\include.ps1") }
$Path = ".\Bin\CPU-XMRigv670\xmrig.exe"
$Uri = "https://github.com/Minerx117/miners/releases/download/xmrig/xmrig-6.7.0.7z"
$Commands = [PSCustomObject]@{ 
    "randomxmonero"       = " -a rx/0 --nicehash" #RandomX
    "randomx"             = " -a rx/0 --nicehash" #RandomX 
    "cryptonight-monero"  = " -a rx/0 --nicehash" #Cryptonight-Monero
    "randomsfx"           = " -a rx/sfx --nicehash" #Randomsfx
    "randomwow"           = " -a rx/wow --nicehash" #Randomwow
    "randomarq"           = " -a rx/arq --nicehash" #Randomarq
    "cryptonightv7"       = " -a cn/1 --nicehash" #cryptonightv7
    "cryptonight_heavy"   = " -a cn-heavy/0 --nicehash" #cryptonight_heavyx
    "cryptonight_heavyx"  = " -a cn/double --nicehash" #cryptonight_heavyx
    "cryptonight_saber"   = " -a cn-heavy/0 --nicehash" #cryptonightGPU
    "cryptonight_fast"    = " -a cn/half --nicehash" #cryptonightFast
    "cryptonight_haven"   = " -a cn-heavy/xhv --nicehash" #cryptonightFast
    "chukwa"              = " -a argon2/chukwa --nicehash" #chukwa
    "cryptonight_conceal" = " -a cn/ccx --nicehash" #cryptonight_conceal
}
$ThreadCount = $Variables.ProcessorCount - 1
$Port = $Variables.CPUMinerAPITCPPort
$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Commands | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object { $Algo = Get-Algorithm $_; $_ } | Where-Object { $Pools.$Algo.Host } | ForEach-Object { 
    [PSCustomObject]@{ 
        Type      = "CPU"
        Path      = $Path
        Arguments = "-t $($ThreadCount) -o stratum+tcp://$($Pools.$Algo.Host):$($Pools.$Algo.Port) -u $($Pools.$Algo.User) -p $($Pools.$Algo.Pass)$($Commands.$_) --keepalive --http-port=$($Variables.CPUMinerAPITCPPort) --donate-level 0 --retries=90 --retry-pause=1 --cpu-priority 3"
        HashRates = [PSCustomObject]@{ $Algo = $Stats."$($Name)_$($Algo)_HashRate".Week } #Recompiled 0% fee
        API       = "XMRig"
        Port      = $Variables.CPUMinerAPITCPPort
        Wrap      = $false
        URI       = $Uri    
    }
}
