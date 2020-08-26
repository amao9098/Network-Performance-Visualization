﻿$MBTOGB = 1 / 1000
$BTOGB = 1 / (1024 * 1024 * 1024) 


##
# Parse-Files
# -----------
# This function iterates through the files of a specified directory, parsing each file and 
# exctracting relevant data from each file. Data is then packaged into an array of objects,
# one object per file, and returned along with some meta data.
#
# Parameters
# ----------
# DirName (String) - Path to the directory whose files are to be parsed
# Tool (String) - Name of the tool whose data is being parsed (NTTTCP, LATTE, CTStraffic, etc.)
#
# Return
# ------
# HashTable - Object containing an array of dataEntry objects and meta data
#
##
function Parse-Files {
    param (
        [Parameter(Mandatory=$true)] [string]$DirName, 
        [Parameter()] [string] $Tool
    )

    try {
        $files = Get-ChildItem $DirName
    } 
    catch {
        Write-Warning "Error at Parse-Files: failed to open directory at path: $DirName"
        Write-Error $_.Exception.Message
    }

    if ($Tool -eq "NTTTCP") {
        [Array] $dataEntries = @()
        foreach ($file in $files) {
            $fileName = $file.FullName
            try {
                $dataEntry = Parse-NTTTCP -FileName $fileName
            } 
            catch {
                Write-Warning "Error at Parse-NTTTCP: failed to parse file $fileName"
                Write-Error $_.Exception.Message
            }

            $dataEntries += ,$dataEntry
        }

        $rawData = @{
            "meta" = @{
                "units" = @{
                    "cycles"     = "cycles/byte"
                    "throughput" = "Gb/s"
                }
                "goal" = @{
                    "throughput" = "increase"
                    "cycles"     = "decrease"
                }
                "format" = @{
                    "throughput" = "0.00"
                    "cycles"     = "0.00"
                    "% change"   = "+#.0%;-#.0%;0.0%"
                }
                "noTable"  = [Array] @("filename")
                "sortProp" = "sessions"
            }
            "data" = $dataEntries
        }

        return $rawData
    } 
    elseif ($Tool -eq "LATTE RAW") {
        [Array] $dataEntries = @() 
        foreach ($file in $files) {
            $fileName = $file.FullName
            try {
                $dataEntry = Parse-LATTE -FileName $fileName
            } 
            catch {
                Write-Warning "Error at Parse-LATTE: failed to parse file $fileName"
                Write-Error $_.Exception.Message
            }
            if ($dataEntry) {
                $dataEntries += ,$dataEntry
            }
        }

        $rawData = @{
            "meta" = @{
                "units" = @{
                    "latency"  = "us"
                }
                "goal" = @{
                    "latency"  = "decrease"
                }
                "format" = @{
                    "latency"  = "#.0"
                    "% change" = "+#.0%;-#.0%;0.0%"
                }
                "noTable" = [Array]@("filename")
            }
            "data" = $dataEntries
        }

        return $rawData
    } 
    elseif ($Tool -eq "LATTE") {
        [Array] $dataEntries = @() 
        foreach ($file in $files) {
            $fileName = $file.FullName
            try {
                $dataEntry = Parse-LATTE-Summary -FileName $fileName
            } 
            catch {
                Write-Warning "Error at Parse-LATTE: failed to parse file $fileName"
                Write-Error $_.Exception.Message
            }

            $dataEntries += ,$dataEntry
        }

        $rawData = @{
            "meta" = @{
                "units" = @{
                    "latency"  = "us"
                }
                "goal" = @{
                    "latency"  = "decrease"
                }
                "format" = @{
                    "latency"  = "#.0"
                    "% change" = "+#.0%;-#.0%;0.0%"
                }
                "sortProp" = "protocol"
                "noTable"  = [Array]@("filename", "sendMethod")
            }
            "data" = $dataEntries
        }

        return $rawData
    }
    elseif ($Tool -eq "CTStraffic") {
        [Array] $dataEntries = @() 
        foreach ($file in $files) {
            $fileName = $file.FullName
            try {
                $ErrorActionPreference = "Stop"

                $dataEntry = Parse-CTStraffic -FileName $fileName
            } 
            catch {
                Write-Warning "Error at Parse-CTStraffic: failed to parse file $fileName"
                Write-Error $_.Exception.Message
            }

            $dataEntries += ,$dataEntry
        }

        $rawData = @{
            "meta" = @{
                "units" = @{
                    "throughput" = "Gb"
                }
                "goal" = @{
                    "throughput" = "increase"
                }
                "format" = @{
                    "throughput" = "0.00"
                    "% change"   = "+#.0%;-#.0%;0.0%"
                }
                "sortProp" = "sessions"
                "noTable"  = [Array]@("filename")
            }
            "data" = [Array]$dataEntries
        }

        return $rawData
    }
}


##
# Parse-NTTTCP
# ------------
# This function parses a single file containing NTTTCP data in an XML format. Relevant data
# is then extracted, packaged into a dataEntry object, and returned.
#
# Parameters
# ----------
# Filename (String) - Path of file to be parsed
#
# Return
# ------
# HashTable - Object containing extracted data
#
## 
function Parse-NTTTCP ([string] $FileName) {
    [XML]$file = Get-Content $FileName

    [decimal] $cycles = $file.ChildNodes.cycles.'#text'
    [decimal] $throughput = $MBTOGB * [decimal]$file.ChildNodes.throughput[1].'#text'
    [int] $sessions = $file.ChildNodes.parameters.max_active_threads

    $dataEntry = @{
        "sessions"   = $sessions
        "throughput" = $throughput
        "cycles"     = $cycles
        "filename"   = $FileName
    }

    return $dataEntry
}


##
# Parse-CTStraffic
# ----------------
# This function parses a single file containing CTStraffic data in an CSV format. 
# Relevant data is then extracted, packaged into a dataEntry object, and returned.
#
# Parameters
# ----------
# Filename (String) - Path of file to be parsed
#
# Return
# ------
# HashTable - Object containing extracted data
#
##
function Parse-CTStraffic ([string] $Filename) {
    $file = Get-Content $Filename

    $firstLine = $true
    $idxs = @{}
    [Array] $throughputs = @()
    [Array] $sessions = @()

    foreach ($line in $file) {
        if ($firstLine) {
            $firstLine = $false
            $splitLine = $line.Split(',')
            $col       = 0
            foreach($token in $splitLine) {
                if (@("SendBps", "In-Flight") -contains $token) {
                    $idxs[$token] = $col
                }
                $col++
            }
        } 
        else {
            $splitLine = $line.Split(',')

            $throughputs += ($BTOGB * [decimal]$splitLine[$idxs["SendBps"]])
            $sessions    += $splitLine[$idxs["In-Flight"]]
        }
    }

    $dataEntry = @{
        "sessions"   = [int]($sessions | Measure -Maximum).Maximum
        "throughput" = [decimal]($throughputs | Measure -Average).Average
        "filename"   = $Filename
    }

    return $dataEntry
}


##
# Parse-LATTE
# ----------
# This function parses a single file containing LATTE data. Each line containing
# a latency sample is then extracted into an array, packaged into a dataEntry 
# object, and returned.
#
# Parameters
# ----------
# Filename (String) - Path of file to be parsed
#
# Return
# ------
# HashTable - Object containing extracted data
#
##
function Parse-LATTE ([string] $FileName) {
    $file = Get-Content $FileName

    [Array] $latency = @()
    foreach ($line in $file) {
        $latency += ,[int]$line
    }

    $dataEntry = @{
        "latency"  = $latency
        "filename" = $FileName
    }

    return $dataEntry
}


function Parse-LATTE-Summary ([string] $FileName) {
    $file = Get-Content $FileName

    $dataEntry = @{
        "filename" = $FileName
    }

    $histogram = $false

    foreach ($line in $file) {
        $splitLine = Remove-EmptyStrings -Arr $line.split(' ')

        if ($splitLine.Count -eq 0) {
            continue
        }

        if ($splitLine[0] -eq "Protocol") {
            $dataEntry.protocol = $splitLine[-1]
        }
        if ($splitLine[0] -eq "SendMethod") {
            $dataEntry.sendMethod = $splitLine[-1]
        }
        if ($splitLine[0] -eq "MsgSize") {
            $dataEntry.msgSize = $splitLine[-1] 
        }

        if ($splitLine[0] -eq "Interval(usec)") {
            $dataEntry.latency = [HashTable] @{} 
            $histogram = $true
            continue
        }

        if ($histogram) {
            $dataEntry.latency.([Int32] $splitLine[0]) = [Int32] $splitLine[-1]
        }
    }

    if (-not $histogram) {
        Write-Warning "No histogram in file $filename"
        return
    }

    return $dataEntry
}

function Remove-EmptyStrings ($Arr) {
    $newArr = [Array] @()
    foreach ($val in $arr) {
        if ($val -ne "") {
            $newArr += $val.Trim()
        }
    }
    return $newArr
}