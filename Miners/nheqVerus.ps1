using module ..\Includes\Include.psm1

$Path = ".\Bin\CPU-nheqVerus082\nheqminer.exe"
$Uri = "https://github.com/Minerx117/miner-binaries/releases/download/0.8.2/nheqminer082.7z"
$Commands = [PSCustomObject]@{ 
    "verus"     = "" #Verus
    "verushash" = "" #Verushash
}
$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Commands | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object { $Algo = Get-Algorithm $_; $_ } | Where-Object { $Pools.$Algo.Host } | ForEach-Object { 
    switch ($_) { 
        "hodl" { $ThreadCount = $Variables.ProcessorCount }
        default { $ThreadCount = $Variables.ProcessorCount - 1 }
    }
    [PSCustomObject]@{ 
        Type      = "CPU"
        Path      = $Path
        Arguments = "-t $($ThreadCount) -a $($Variables.CPUMinerAPITCPPort) -v -l $($Pools.$Algo.Host):$($Pools.$Algo.Port) -u $($Pools.$Algo.User) -p $($Pools.$Algo.Pass)$($Commands.$_)"
        Algorithm = $Algo
        API       = "nheq"
        Port      = $Variables.CPUMinerAPITCPPort
        Wrap      = $false
        URI       = $Uri
    }
}
