using module ..\Includes\Include.psm1

$Path = ".\Bin\NVIDIA-miniZ160v2\miniZ.exe"
$Uri = "https://github.com/Minerx117/miner-binaries/releases/download/v16.0v2/miniZ_v1.6v2_cuda10_win-x64.7z"
$Commands = [PSCustomObject]@{ 
    "equihash144"  = " --par=144,5 --pers auto --ocX" #Equihash144
    "equihash125"  = " --par=125,4 --pers auto --ocX" #Equihash125
    "zhash"        = " --par=144,5 --pers auto --ocX" #Zhash
    "beamv2"       = " --par=beam --pers auto --ocX" #Beamv2
    "beamv3"       = " --par=144,5s --pers auto --ocX" #Beamv3
    "beam"         = " --par=150,5 --pers auto --ocX" #Beam
    "equihash192"  = " --par=192,7 --pers auto --ocX" #Equihash192
    #"equihash96"   = " --par=96,5 --pers auto" #equihash96
    "equihash-btg" = " --par=144,5 --pers BgoldPoW --ocX" # Equihash-btg MPH
    "equihash-zcl" = " --par=192,7 --pers ZcashPoW --ocX" # Equihash-ZCL MPH
}
$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Commands | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object { $Algo = Get-Algorithm $_; $_ } | Where-Object { $Pools.$Algo.Host } | ForEach-Object { 
    [PSCustomObject]@{ 
        Type      = "NVIDIA"
        Path      = $Path
        Arguments = "--cleanjobs --jobtimeout=900 --retries=99 --retrydelay=1 --stat-int 10 --latency --nocolor --extra --tempunits C -cd $($Config.SelGPUDSTM) --telemetry $($Variables.NVIDIAMinerAPITCPPort) --url $($Pools.$Algo.User)@$($Pools.$Algo.Host):$($Pools.$Algo.Port) --pass $($Pools.$Algo.Pass)$($Commands.$_)" #--oc1 --oc2 --f11=0
        Algorithm = $Algo
        API       = "miniZ"
        Port      = $Variables.NVIDIAMinerAPITCPPort
        Wrap      = $false
        URI       = $Uri
        Fee       = 0.02 #Dev fee
    }
}
