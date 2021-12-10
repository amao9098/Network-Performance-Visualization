﻿using namespace Microsoft.Office.Interop

$TextInfo = (Get-Culture).TextInfo
$WorksheetMaxLen = 31
$HeaderRows = 4
$EPS = 0.0001

# Excel uses BGR color values
$ColorPalette = @{
    "LightGreen" = 0x9EF0A1
    "Green"      = 0x135C1E
    "LightRed"   = 0x9EA1FF
    "Red"        = 0x202A80
    "Blue"      = @(0x560000, 0x691511, 0x7C2A22, 0x8F3F33, 0xA25444, 0xB56955, 0xC87E66, 0xDB9377, 0xEEA888) #@(0x633f16, 0x9C6527, 0xD68546, 0xFFB894) # Dark -> Light
    "Orange"    = @(0x0069B0, 0xF74B9, 0x1E7FC2, 0x2D8ACB, 0x3C95D4, 0x4BA0DD, 0x5AABE6, 0x69B6EF, 0x78C1F8) #@(0x005b97, 0x047CCC, 0x19A9FC, 0x5BC6FC)
    "LightGray" = @(0xf5f5f5, 0xd9d9d9)
    "White"     = 0xFFFFFF
}

$ABBREVIATIONS = @{
    "sessions" = "sess."
    "bufferLen" = "bufLen."
    "bufferCount" = "bufCt."
    "protocol" = ""
    "sendMethod" = "sndMthd" 
}

<#
.SYNOPSIS
    Converts an index to an Excel column name.
.NOTES
    Valid for A to ZZ
#>
function Get-ColName($n) {
    if ($n -ge 26) {
        $a = [Int][Math]::floor($n / 26)
        $c1 = [Char]($a + 64)
    }

    $c2 = [Char](($n % 26) + 65)

    return "$c1$c2"
}

##
# Format-RawData
# --------------
# This function formats raw data into tables, one for each dataEntry property. Data samples are
# organized by their sortProp and labeled with the name of the file from which the data sample was extracted.
#
# Parameters
# ----------
# DataObj (HashTable) - Object containing processed data, raw data, and meta data
# TableTitle (String) - Title to be displayed at the top of each table
# 
# Return
# ------
# HashTable[] - Array of HashTable objects which each store a table of formatted raw data
#
##
function Format-RawData {
    param (
        [Parameter(Mandatory=$true)] [PSobject[]] $DataObj,

        [Parameter(Mandatory=$true)] $OPivotKey,

        [Parameter()] [String] $Tool = "",

        [Parameter()] [switch] $NoNewWorksheets
    )

    $legend = @{
        "meta" = @{
            "colLabelDepth" = 1
            "rowLabelDepth" = 1
            "dataWidth"     = 2
            "dataHeight"    = 3 
            "name"          = "legend"
            "numWrites"     = 3 + 3 + 5 
        }
        "rows" = @{
            " "   = 0
            "  "  = 1
            "   " = 2
        }
        "cols" = @{
            "legend" = @{
                " "  = 0
                "  " = 1
            }
        }
        "data" = @{
            "legend" = @{
                " " = @{
                    " " = @{
                        "value" = "Test values are compared against the mean basline value."
                    }
                    "  " = @{
                        "value" = "Test values which show improvement are colored green:"
                    }
                    "   " = @{
                        "value" = "Test values which show regression are colored red:"
                    }
                }
                "  " = @{
                    "  " = @{
                        "value"     = "Improvement"
                        "fontColor" = $ColorPalette.Green
                        "cellColor" = $ColorPalette.LightGreen
                    }
                    "   " = @{
                        "value"     = "Regression"
                        "fontColor" = $ColorPalette.Red
                        "cellColor" = $ColorPalette.LightRed
                    }
                } 
            }
        }
    }

    $meta       = $DataObj.meta
    $innerPivot = $meta.InnerPivot
    $outerPivot = $meta.OuterPivot
    $tables     = @()

    if (-not $NoNewWorksheets) {
        $tables += Get-WorksheetTitle -BaseName "Raw Data" -OuterPivot $outerPivot -OPivotKey $OPivotKey
    }
    if ($meta.comparison) {
        $tables += $legend
    }


    $numBaseline = $DataObj.rawData.baseline.Count
    $numTest = if ($meta.comparison) {$DataObj.rawData.test.Count} else {0}
    $numProps = $dataObj.data.$OPivotKey.Keys.Count
    $numIters = ($numBaseline + $numTest + $meta.outerPivotKeys.Count + ($numProps * ($numBaseline + $numTest)))
    $j = 0
    # Fill single array with all data and sort, label data as baseline/test if necessary
    [Array] $data = @() 
    foreach ($entry in $DataObj.rawData.baseline) {
        if ($meta.comparison) {
            $entry.baseline = $true
        } 
        if ($OPivotKey -in @("", $entry.$outerPivot)) {
            $data += $entry
        }
        
        Write-Progress -Activity "Formatting Tables" -Status "Raw Data Table" -Id 3 -PercentComplete (100 * (($j++) / $numIters))
    }

    if ($meta.comparison) {
        foreach ($entry in $DataObj.rawData.test) {
            if ($OPivotKey -in @("", $entry.$outerPivot)) {
                $data += $entry
            }
            Write-Progress -Activity "Formatting Tables" -Status "Raw Data Table" -Id 3 -PercentComplete (100 * (($j++) / $numIters))
        }
    }

    if ($innerPivot) {
        $data = Sort-ByProp -Objs $data -Prop $innerPivot -Int $true
    }
    
    foreach ($prop in $dataObj.data.$OPivotKey.Keys) { 
        $tableTitle = Get-TableTitle -Tool $Tool -OuterPivot $outerPivot -OPivotKey $OPivotKey

        $table = @{
            "rows" = @{
                $prop = @{}
            }
            "cols" = @{
                $tableTitle = @{
                    $innerPivot = @{}
                }
            }
            "meta" = @{
                "columnFormats" = @()
                "leftAlign"     = [Array] @(2)
                "name"          = "Raw Data"
                "numWrites"     = 1 + 2
            }
            "data"  = @{
                $tableTitle = @{
                    $innerPivot = @{}
                }
            }
        }
        $col = 0
        $row = 0

        foreach ($entry in $data) {
            $iPivotKey = if ($innerPivot) {$entry.$innerPivot} else {""}

            # Add column labels to table
            if (-not ($table.cols.$tableTitle.$innerPivot.Keys -contains $iPivotKey)) {
                if ($meta.comparison) {
                    $table.cols.$tableTitle.$innerPivot.$iPivotKey = @{
                        "baseline" = $col
                        "test"     = $col + 1
                    }
                    $table.meta.columnFormats += @($meta.format.$prop, $meta.format.$prop)
                    $table.meta.numWrites += 3
                    $col += 2
                    $table.data.$tableTitle.$innerPivot.$iPivotKey = @{
                        "baseline" = @{
                            $prop = @{}
                        }
                        "test" = @{
                            $prop = @{}
                        }
                    }
                } 
                else {
                    $table.meta.numWrites += 1
                    $table.meta.columnFormats += $meta.format.$prop
                    $table.cols.$tableTitle.$innerPivot.$iPivotKey = $col
                    $table.data.$tableTitle.$innerPivot.$iPivotKey = @{
                        $prop = @{}
                    }
                    $col += 1
                }
            }

            # Add row labels and fill data in table
            $filename = $entry.fileName.Split('\')[-2] + "\" + $entry.fileName.Split('\')[-1]
            while ($table.rows.$prop.keys -contains $filename) {
                $filename += "*"
            }
            $table.rows.$prop.$filename = $row
            $table.meta.numWrites += 1
            $row += 1
            if ($meta.comparison) {
                if ($entry.baseline) {
                    $table.data.$tableTitle.$innerPivot.$iPivotKey.baseline.$prop.$filename = @{
                        "value" = $entry.$prop
                    }
                }
                else {
                    $table.data.$tableTitle.$innerPivot.$iPivotKey.test.$prop.$filename = @{
                        "value" = $entry.$prop
                    }
                    $params = @{
                        "Cell"    = $table.data.$tableTitle.$innerPivot.$iPivotKey.test.$prop.$filename
                        "TestVal" = $entry.$prop
                        "BaseVal" = $DataObj.data.$OPivotKey.$prop.$iPivotKey.baseline.stats.mean
                        "Goal"    = $meta.goal.$prop
                    }
                    
                    $table.data.$tableTitle.$innerPivot.$iPivotKey.test.$prop.$filename = Set-CellColor @params
                }
            } 
            else {
                $table.data.$tableTitle.$innerPivot.$iPivotKey.$prop.$filename = @{
                    "value" = $entry.$prop
                }
            }
            Write-Progress -Activity "Formatting Tables" -Status "Raw Data Table" -Id 3 -PercentComplete (100 * (($j++) / $numIters))
        }
        $table.meta.numWrites    += $data.Count 
        $table.meta.dataWidth     = Get-TreeWidth $table.cols
        $table.meta.colLabelDepth = Get-TreeDepth $table.cols
        $table.meta.dataHeight    = Get-TreeWidth $table.rows
        $table.meta.rowLabelDepth = Get-TreeDepth $table.rows  
        $tables = $tables + $table 

    }

    foreach ($entry in $data) {
        if ($entry.baseline) {
            $entry.Remove("baseline")
        }
    }
    Write-Progress -Activity "Formatting Tables" -Status "Raw Data Table" -Id 3 -PercentComplete 100 
    return $tables
}


function Sort-ByProp ($Objs, $Prop, $Int) 
{
    $arrs = [Array] @()

    foreach ($obj in $Objs) {
        $arrs += [Array]@($obj)
    }

    while ($arrs.Count > 1) {
        $newArr = @()
        for ($i = 0; $i -lt $arrs.Count - 1; $i += 2) {
            $merged = Merge-Arrays($arrs[$i], $arrs[$i + 1], $Prop, $Int)
            $newArr.Add($merged)
        }
        $arrs = $newArr
    }
    return $arrs
}

function Merge-Arrays ($Arr1, $Arr2, $Prop, $Int) {
    $i = 0
    $j = 0
    $newArr = @()
    while (($i -lt $Arr1.Count) -and ($j -lt $Arr2.Count)) {
        if ($true) {
            if ([Int]($Arr1[$i].$Prop) -le [Int]($Arr2[$j].$Prop)) {
                $newArr += $Arr1[$i]
                $i++
            } else {
                $newArr += $Arr2[$j]
                $j++
            }
        } else {
            if ($Arr1[$i].$Prop -le $Arr2[$j].$Prop) {
                $newArr += $Arr1[$i]
                $i++
            } else {
                $newArr += $Arr2[$j]
                $j++
            }
        }
    }

    while ($i -lt $Arr1.Count) {
        $newArr += $Arr1[$i]
        $i++
    }
    while ($j -lt $arr2.Count) {
        $newArr += $Arr2[$j]
        $j++
    }

    return $newArr
}

function Get-WorksheetTitle ($BaseName, $OuterPivot, $OPivotKey, $InnerPivot, $IPivotKey, $Prop="") {
    if ($OuterPivot -and $InnerPivot) {
        $OAbv = $ABBREVIATIONS[$OuterPivot]
        $IAbv = $ABBREVIATIONS[$InnerPivot]

        $name = "$BaseName - $OPivotKey $OAbv - $IPivotKey $IAbv"

        if ($name.Length -gt $WorksheetMaxLen) {
            $name = "$BaseName - $OPivotKey - $IPivotKey"
        }

        return $name
    } 
    elseif ($OuterPivot) {
        $OAbv = $ABBREVIATIONS[$OuterPivot]
        $name = "$BaseName - $OPivotKey $OAbv"

        if ($name.Length -gt $WorksheetMaxLen) {
            $name = "$BaseName - $OPivotKey"
        }

        return $name
    } 
    elseif ($InnerPivot) {
        $IAbv = $ABBREVIATIONS[$InnerPivot]
        $name = "$BaseName - $IPivotKey $IAbv"

        if ($name.Length -gt $WorksheetMaxLen) {
            $name = "$BaseName - $IPivotKey"
        }

        return $name 
    }
    else {
        if ($Prop) { 
            return "$BaseName $($Prop.Replace("/", " per "))"
        }
        return "$BaseName"
    }
}

function Get-TableTitle ($Tool, $OuterPivot, $OPivotKey, $InnerPivot, $IPivotKey) { 
    if ($OuterPivot -and $InnerPivot) {
        $OAbv = $ABBREVIATIONS[$OuterPivot]
        $IAbv = $ABBREVIATIONS[$InnerPivot]

        return "$Tool - $OPivotKey $OAbv - $IPivotKey $IAbv"
    } 
    elseif ($OuterPivot) {
        $OAbv = $ABBREVIATIONS[$OuterPivot]

        return "$Tool - $OPivotKey $OAbv"
    } 
    elseif ($InnerPivot) {
        $IAbv = $ABBREVIATIONS[$InnerPivot]

        return "$Tool - $IPivotKey $IAbv"
    }
    else {
        return "$Tool"
    }
    
}

##
# Format-Stats
# -------------------
# This function formats statistical metrics (min, mean, max, etc) into a table, one per property.
# When run in comparison mode, the table also displays % change and is color-coded to indicate 
# improvement/regression.
#
# Parameters
# ----------
# DataObj (HashTable) - Object containing processed data, raw data, and meta data
# TableTitle (String) - Title to be displayed at the top of each table
# Metrics (String[]) - Array containing statistical metrics that should be displayed on generated 
#                      tables. All metrics are displayed if this parameter is null. 
#
# Return
# ------
# HashTable[] - Array of HashTable objects which each store a table of formatted statistical data
#
##
function Format-Stats {
    Param (
        [Parameter(Mandatory=$true)]
        [PSObject[]] $DataObj,

        [Parameter(Mandatory=$true)]
        $OPivotKey,

        [Parameter()]
        [String] $Tool = "",

        [Parameter()]
        [Switch] $NoNewWorksheets
    )
    
    $tables = @()
    $data = $DataObj.data
    $meta = $DataObj.meta
    $innerPivot = $meta.InnerPivot
    $outerPivot = $meta.OuterPivot
    $nextRow = $HeaderRows + 1
 
    $numProps = $data.$OPivotKey.keys.Count
    $propEnum = $data.$OPivotKey.keys.GetEnumerator()
    $propEnum.MoveNext()
    $prop = $propEnum.Current 
    $iKeyEnum = $data.$OPivotKey.$prop.keys.GetEnumerator()
    $iKeyEnum.MoveNext()
    $iKey = $iKeyEnum.Current
    $numMetrics = $data.$OPivotKey.$prop.$iKey.baseline.stats.keys.Count
    $numIters =  ($numProps * $meta.innerPivotKeys.Count * $numMetrics)
    $j = 0

    foreach ($prop in $data.$OPivotKey.keys) {
        $tableTitle = Get-TableTitle -Tool $Tool -OuterPivot $outerPivot -OPivotKey $OPivotKey 
        $table = @{
            "rows" = @{
                $prop = @{}
            }
            "cols" = @{
                $tableTitle = @{
                    $innerPivot = @{}
                }
            }
            "meta" = @{
                "columnFormats" = @()
                "name"          = "Stats"  
                "numWrites"     = 1 + 2
            }
            "data" = @{
                $tableTitle = @{
                    $innerPivot = @{}
                }
            }
        }

        $col = 0
        $row = 0
        foreach ($IPivotKey in $data.$OPivotKey.$prop.Keys | Sort) { 

            # Add column labels to table
            if (-not $meta.comparison) {
                $table.cols.$tableTitle.$innerPivot.$IPivotKey  = $col 
                $table.data.$tableTitle.$innerPivot.$IPivotKey  = @{
                    $prop = @{}
                }
                $col += 1
                $table.meta.columnFormats += $meta.format.$prop
                $table.meta.numWrites += 1
            } 
            else {
                $table.cols.$tableTitle.$innerPivot.$IPivotKey = @{
                    "baseline" = $col
                    "% Change" = $col + 1
                    "test"     = $col + 2
                }
                $table.meta.numWrites += 4
                $table.meta.columnFormats += $meta.format.$prop
                $table.meta.columnFormats += "0.0%"
                $table.meta.columnFormats += $meta.format.$prop
                $col += 3
                $table.data.$tableTitle.$innerPivot.$IPivotKey = @{
                    "baseline" = @{
                        $prop = @{}
                    }
                    "% Change" = @{
                        $prop = @{}
                    }
                    "test" = @{
                        $prop = @{}
                    }
                }
            }

            # Add row labels and fill data in table
            $cellRow = $nextRow
            
            if ($data.$OPivotKey.$prop.$IPivotKey.baseline.stats) {$metrics = $data.$OPivotKey.$prop.$IPivotKey.baseline.stats.Keys}
            else {$metrics = $data.$OPivotKey.$prop.$IPivotKey.test.stats.keys}

            foreach ($metric in $Metrics) {
                if ($table.rows.$prop.Keys -notcontains $metric) {
                    $table.rows.$prop.$metric = $row
                    $row += 1
                    $table.meta.numWrites += 1
                }

                if (-not $meta.comparison) {
                    $table.data.$tableTitle.$innerPivot.$IPivotKey.$prop.$metric = @{"value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.stats.$metric}
                } else {
                    if ($data.$OPivotKey.$prop.$IPivotKey.baseline.stats) {
                        $table.data.$tableTitle.$innerPivot.$IPivotKey.baseline.$prop.$metric = @{"value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.stats.$metric}
                    }
                    if ($data.$OPivotKey.$prop.$IPivotKey.test.stats) {
                        $table.data.$tableTitle.$innerPivot.$IPivotKey.test.$prop.$metric     = @{"value" = $data.$OPivotKey.$prop.$IPivotKey.test.stats.$metric}
                    }

                    if ($data.$OPivotKey.$prop.$IPivotKey.baseline.stats -and $data.$OPivotKey.$prop.$IPivotKey.test.stats) {
                        $baseCell = "$(Get-ColName ($col - 1))$cellRow"
                        $testCell = "$(Get-ColName ($col + 1))$cellRow"

                        $table.data.$tableTitle.$innerPivot.$IPivotKey."% change".$prop.$metric = @{"value" = "=IF($baseCell=0, ""--"", ($testCell-$baseCell)/ABS($baseCell))"}
                        
                        $params = @{
                            "Cell"    = $table.data.$tableTitle.$innerPivot.$IPivotKey."% change".$prop.$metric
                            "TestVal" = $data.$OPivotKey.$prop.$IPivotKey.test.stats.$metric
                            "BaseVal" = $data.$OPivotKey.$prop.$IPivotKey.baseline.stats.$metric
                            "Goal"    = $meta.goal.$prop
                        }

                        # Certain statistics always have the same goal.
                        if ($metric -eq "n") {
                            $params.goal = "increase"
                        } elseif ($metric -in @("range", "variance", "std dev", "std err")) {
                            $params.goal = "decrease"
                        } elseif ($metric -in @("skewness", "kurtosis")) {
                            $params.goal = "none"
                        }

                        $table.data.$tableTitle.$innerPivot.$IPivotKey."% change".$prop.$metric = Set-CellColor @params
                    }
                    
                    Write-Progress -Activity "Formatting Tables" -Status "Stats Table" -Id 3 -PercentComplete (100 * (($j++) / $numIters))

                }
                $cellRow += 1
            } # foreach $metric
        }
        $nextRow += $cellRow

        $table.meta.dataWidth     = Get-TreeWidth $table.cols
        $table.meta.colLabelDepth = Get-TreeDepth $table.cols
        $table.meta.dataHeight    = Get-TreeWidth $table.rows
        $table.meta.rowLabelDepth = Get-TreeDepth $table.rows 
        $table.meta.numWrites    += $table.meta.dataHeight * $table.meta.dataWidth 
        $tables += $table
    }

    if (($tables.Count -gt 0) -and (-not $NoNewWorksheets)) {
        $sheetTitle = Get-WorksheetTitle -BaseName "Stats" -OuterPivot $outerPivot -OPivotKey $OPivotKey 
        $tables     = [Array]@($sheetTitle) + $tables 
    }
    Write-Progress -Activity "Formatting Tables" -Status "Stats Table" -Id 3 -PercentComplete 100 
    return $tables
}


##
# Format-Quartiles
# ----------------
# This function formats a table in order to create a chart that displays the quartiles
# of each data subcategory (organized by sortProp), one chart per property.
#
# Parameters
# ----------
# DataObj (HashTable) - Object containing processed data, raw data, and meta data
# TableTitle (String) - Title to be displayed at the top of each table
#
# Return
# ------
# HashTable[] - Array of HashTable objects which each store a table of formatted quartile data
#
##
function Format-Quartiles {
    param (
        [Parameter(Mandatory=$true)] [PSobject[]] $DataObj,

        [Parameter(Mandatory=$true)] $OPivotKey, 

        [Parameter()] [String] $Tool = "",

        [Parameter()] [switch] $NoNewWorksheets
    )
    $tables = @()
    $data = $DataObj.data
    $meta = $DataObj.meta
    $innerPivot = $meta.InnerPivot
    $outerPivot = $meta.OuterPivot


    $numProps = $data.$OPivotKey.keys.Count  
    $numIters =  ($numProps * $meta.innerPivotKeys.Count)
    $j = 0

    foreach ($prop in $data.$OPivotKey.Keys) { 
        $format = $meta.format.$prop
        $tableTitle = Get-TableTitle -Tool $Tool -OuterPivot $outerPivot -OPivotKey $OPivotKey
        $cappedProp = (Get-Culture).TextInfo.ToTitleCase($prop)
        $table = @{
            "rows" = @{
                $prop = @{
                    $innerPivot = @{}
                }
            }
            "cols" = @{
                $tableTitle = @{
                    "min" = 0
                    "Q1"  = 1
                    "Q2"  = 2
                    "Q3"  = 3
                    "Q4"  = 4
                }
            }
            "meta" = @{ 
                "dataWidth" = 5
                "name" = "Quartiles"
                "numWrites" = 2 + 6
            }
            "data" = @{
                $tableTitle = @{
                    "min" = @{
                        $prop = @{
                            $innerPivot = @{}
                        }
                    }
                    "Q1" = @{
                        $prop = @{
                            $innerPivot = @{}
                        }
                    }
                    "Q2" = @{
                        $prop = @{
                            $innerPivot = @{}
                        }
                    }
                    "Q3" = @{
                        $prop = @{
                            $innerPivot = @{}
                        }
                    }
                    "Q4" = @{
                        $prop = @{
                            $innerPivot = @{}
                        }
                    }
                }
            }
            "chartSettings" = @{ 
                "chartType"= [Excel.XlChartType]::xlColumnStacked
                "plotBy"   = [Excel.XlRowCol]::xlColumns
                "xOffset"  = 1
                "YOffset"  = 1
                "title"    = "$cappedProp Quartiles"
                "seriesSettings"= @{
                    1 = @{
                        "hide" = $true
                        "name" = " "
                    }
                    2 = @{ 
                        "color" = $ColorPalette.Blue[3]
                    }
                    3 = @{ 
                        "color" = $ColorPalette.Blue[8]
                    }
                    4 = @{ 
                        "color" = $ColorPalette.blue[0]
                    }
                    5 = @{ 
                        "color" = $ColorPalette.Blue[6]
                    }
                }
                "axisSettings" = @{
                    1 = @{
                        "majorGridlines" = $true
                    }
                    2 = @{
                        "minorGridlines" = $true
                        "minorGridlinesColor" = $ColorPalette.LightGray[0]
                        "majorGridlinesColor" = $ColorPalette.LightGray[1]
                        "title" = $meta.units[$prop]
                    }
                }
            }
        }

        if ($meta.comparison) {
            $table.cols = @{
                $tableTitle = @{
                    "<baseline>min" = 0
                    "<baseline>Q1"  = 1
                    "<baseline>Q2"  = 2
                    "<baseline>Q3"  = 3
                    "<baseline>Q4"  = 4
                    "<test>min" = 5
                    "<test>Q1"  = 6
                    "<test>Q2"  = 7
                    "<test>Q3"  = 8
                    "<test>Q4"  = 9
                }
            }
            $table.data = @{
                $tableTitle = @{
                    "<baseline>min" = @{
                        $prop = @{
                            $innerPivot = @{}
                        }
                    }
                    "<baseline>Q1" = @{
                        $prop = @{
                            $innerPivot = @{}
                        }
                    }
                    "<baseline>Q2" = @{
                        $prop = @{
                            $innerPivot = @{}
                        }
                    }
                    "<baseline>Q3" = @{
                        $prop = @{
                            $innerPivot = @{}
                        }
                    }
                    "<baseline>Q4" = @{
                        $prop = @{
                            $innerPivot = @{}
                        }
                    }
                    "<test>min" = @{
                        $prop = @{
                            $innerPivot = @{}
                        }
                    }
                    "<test>Q1" = @{
                        $prop = @{
                            $innerPivot = @{}
                        }
                    }
                    "<test>Q2" = @{
                        $prop = @{
                            $innerPivot = @{}
                        }
                    }
                    "<test>Q3" = @{
                        $prop = @{
                            $innerPivot = @{}
                        }
                    }
                    "<test>Q4" = @{
                        $prop = @{
                            $innerPivot = @{}
                        }
                    }
                }
            }
            $table.chartSettings.seriesSettings[6] = @{
                "hide" = $true
                "name" = " "
            }
            $table.chartSettings.seriesSettings[7] = @{
                "color" = $ColorPalette.Orange[3]
            }
            $table.chartSettings.seriesSettings[8] = @{
                "color" = $ColorPalette.Orange[8]
            }
            $table.chartSettings.seriesSettings[9] = @{
                "color" = $ColorPalette.orange[0]
            }
            $table.chartSettings.seriesSettings[10] = @{
                "color" = $ColorPalette.Orange[6]
            }
            $table.meta.columnFormats = @($format) * $table.cols.$tableTitle.Count; 
        }
    
        
        # Add row labels and fill data in table
        $row = 0
        foreach ($IPivotKey in $data.$OPivotKey.$prop.Keys | Sort) {
            if (-not $meta.comparison) {
                $table.meta.numWrites += 1
                $table.rows.$prop.$innerPivot.$IPivotKey = $row
                $row += 1
                $table.data.$TableTitle.min.$prop.$innerPivot.$IPivotKey = @{ "value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.stats.min }
                $table.data.$TableTitle.Q1.$prop.$innerPivot.$IPivotKey  = @{ "value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles[25] - $data.$OPivotKey.$prop.$IPivotKey.baseline.stats.min }
                $table.data.$TableTitle.Q2.$prop.$innerPivot.$IPivotKey  = @{ "value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles[50] - $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles[25] } 
                $table.data.$TableTitle.Q3.$prop.$innerPivot.$IPivotKey  = @{ "value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles[75] - $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles[50]}
                $table.data.$TableTitle.Q4.$prop.$innerPivot.$IPivotKey  = @{ "value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.stats.max - $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles[75] }
            } 
            else {
                $table.meta.numWrites += 3
                $table.rows.$prop.$innerPivot.$IPivotKey = @{
                    "baseline" = $row
                    "test"     = $row + 1
                }
                $row += 2

                $table.data.$TableTitle."<baseline>min".$prop.$innerPivot.$IPivotKey = @{
                    "baseline" = @{ "value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.stats.min } 
                }
                $table.data.$TableTitle."<test>min".$prop.$innerPivot.$IPivotKey = @{ 
                    "test"     = @{ "value" = $data.$OPivotKey.$prop.$IPivotKey.test.stats.min}
                }
                $table.data.$TableTitle."<baseline>Q1".$prop.$innerPivot.$IPivotKey = @{
                    "baseline" = @{ "value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles[25] - $data.$OPivotKey.$prop.$IPivotKey.baseline.stats.min }
                }
                $table.data.$TableTitle."<test>Q1".$prop.$innerPivot.$IPivotKey = @{
                    "test"     = @{ "value" = $data.$OPivotKey.$prop.$IPivotKey.test.percentiles[25] - $data.$OPivotKey.$prop.$IPivotKey.test.stats.min }
                }
                $table.data.$TableTitle."<baseline>Q2".$prop.$innerPivot.$IPivotKey = @{
                    "baseline" = @{ "value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles[50] - $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles[25] } 
                }
                $table.data.$TableTitle."<test>Q2".$prop.$innerPivot.$IPivotKey = @{
                    "test"     = @{ "value" = $data.$OPivotKey.$prop.$IPivotKey.test.percentiles[50] - $data.$OPivotKey.$prop.$IPivotKey.test.percentiles[25] } 
                }
                $table.data.$TableTitle."<baseline>Q3".$prop.$innerPivot.$IPivotKey = @{
                    "baseline" = @{ "value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles[75] - $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles[50] } 
                }
                $table.data.$TableTitle."<test>Q3".$prop.$innerPivot.$IPivotKey = @{  
                    "test"     = @{ "value" = $data.$OPivotKey.$prop.$IPivotKey.test.percentiles[75] - $data.$OPivotKey.$prop.$IPivotKey.test.percentiles[50] }
                }
                $table.data.$TableTitle."<baseline>Q4".$prop.$innerPivot.$IPivotKey = @{
                    "baseline" = @{ "value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.stats.max - $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles[75] }
                }
                $table.data.$TableTitle."<test>Q4".$prop.$innerPivot.$IPivotKey = @{
                    "test"     = @{ "value" = $data.$OPivotKey.$prop.$IPivotKey.test.stats.max - $data.$OPivotKey.$prop.$IPivotKey.test.percentiles[75] }
                }
            }
            Write-Progress -Activity "Formatting Tables" -Status "Quartiles Table" -Id 3 -PercentComplete (100 * (($j++) / $numIters))

        }

        $table.meta.dataWidth     = Get-TreeWidth $table.cols
        $table.meta.colLabelDepth = Get-TreeDepth $table.cols
        $table.meta.dataHeight    = Get-TreeWidth $table.rows
        $table.meta.rowLabelDepth = Get-TreeDepth $table.rows  
        $table.meta.numWrites    += $table.meta.dataHeight * $table.meta.dataWidth
        
         
        $tables = $tables + $table
    }

    if (($tables.Count -gt 0) -and (-not $NoNewWorksheets)) {
        $sheetTitle = Get-WorksheetTitle -BaseName "Quartiles" -OuterPivot $outerPivot -OPivotKey $OPivotKey
        $tables = @($sheetTitle) + $tables
    }
    Write-Progress -Activity "Formatting Tables" -Status "Quartiles Table" -Id 3 -PercentComplete 100


    return $tables
}


##
# Format-MinMaxChart
# ----------------
# This function formats a table that displays min, mean, and max of each data subcategory, 
# one table per property. This table primarily serves to generate a line chart for the
# visualization of this data.
#
# Parameters
# ----------
# DataObj (HashTable) - Object containing processed data, raw data, and meta data
# TableTitle (String) - Title to be displayed at the top of each table
#
# Return
# ------
# HashTable[] - Array of HashTable objects which each store a table of formatted data
#
##
function Format-MinMaxChart {
    Param (
        [Parameter(Mandatory=$true)] [PSobject[]] $DataObj,

        [Parameter(Mandatory=$true)] $OPivotKey, 

        [Parameter()] [String] $Tool = "",

        [Parameter()] [switch] $NoNewWorksheets
    )
    
    $tables     = @()
    $data       = $DataObj.data
    $meta       = $DataObj.meta
    $innerPivot = $meta.InnerPivot
    $outerPivot = $meta.OuterPivot
    $metrics = @("min", "mean", "max")

    $numProps = $data.$OPivotKey.keys.Count  
    $numIters =  ($numProps * $meta.innerPivotKeys.Count * $metrics.Count)
    $j = 0
    foreach ($prop in $data.$OPivotKey.keys) {
        $cappedProp = (Get-Culture).TextInfo.ToTitleCase($prop) 
        $tableTitle = Get-TableTitle -Tool $Tool -OuterPivot $outerPivot -OPivotKey $OPivotKey
        $table = @{
            "rows" = @{
                $prop = @{}
            }
            "cols" = @{
                $tableTitle = @{
                    $innerPivot = @{}
                }
            }
            "meta" = @{
                "columnFormats" = @()
                "name"          = "MinMaxCharts"
                "numWrites"     = 1 + 2
            }
            "data" = @{
                $tableTitle = @{
                    $innerPivot = @{}
                }
            }
            "chartSettings" = @{
                "chartType"    = [Excel.XlChartType]::xlLineMarkers
                "plotBy"       = [Excel.XlRowCol]::xlRows
                "title"        = $cappedProp
                "xOffset"      = 1
                "yOffset"      = 2
                "dataTable"    = $true
                "hideLegend"   = $true
                "axisSettings" = @{
                    1 = @{
                        "majorGridlines" = $true
                    }
                    2 = @{
                        "minorGridlines" = $true
                        "minorGridlinesColor" = $ColorPalette.LightGray[0]
                        "majorGridlinesColor" = $ColorPalette.LightGray[1]
                        "title" = $meta.units.$prop
                    }
                }
            }
        }
        if ($meta.comparison) {
            $table.chartSettings.seriesSettings = @{
                1 = @{
                    "color"       = $ColorPalette.Blue[8]
                    "markerColor" = $ColorPalette.Blue[8]
                    "markerStyle" = [Excel.XlMarkerStyle]::xlMarkerStyleCircle
                    "lineWeight"  = 3
                    "markerSize"  = 5
                }
                2 = @{
                    "color"       = $ColorPalette.Orange[8]
                    "markerColor" = $ColorPalette.Orange[8]
                    "markerStyle" = [Excel.XlMarkerStyle]::xlMarkerStyleCircle
                    "lineWeight"  = 3
                    "markerSize"  = 5
                }
                3 = @{
                    "color"       = $ColorPalette.Blue[6]
                    "markerColor" = $ColorPalette.Blue[6]
                    "markerStyle" = [Excel.XlMarkerStyle]::xlMarkerStyleCircle
                    "lineWeight"  = 3
                    "markerSize"  = 5
                }
                4 = @{
                    "color"       = $ColorPalette.Orange[6]
                    "markerColor" = $ColorPalette.Orange[6]
                    "markerStyle" = [Excel.XlMarkerStyle]::xlMarkerStyleCircle
                    "lineWeight"  = 3
                    "markerSize"  = 5
                }
                5 = @{
                    "color"       = $ColorPalette.Blue[3]
                    "markerColor" = $ColorPalette.Blue[3]
                    "markerStyle" = [Excel.XlMarkerStyle]::xlMarkerStyleCircle
                    "lineWeight"  = 3
                    "markerSize"  = 5
                }
                6 = @{
                    "color"       = $ColorPalette.Orange[3]
                    "markerColor" = $ColorPalette.Orange[3]
                    "markerStyle" = [Excel.XlMarkerStyle]::xlMarkerStyleCircle
                    "lineWeight"  = 3
                    "markerSize"  = 5
                }
            }
        } 
        else {
            $table.chartSettings.seriesSettings = @{
                1 = @{
                    "color"       = $ColorPalette.Blue[8]
                    "markerColor" = $ColorPalette.Blue[8]
                    "markerStyle" = [Excel.XlMarkerStyle]::xlMarkerStyleCircle
                    "lineWeight"  = 3
                    "markerSize"  = 5
                }
                2 = @{
                    "color"       = $ColorPalette.Blue[6]
                    "markerColor" = $ColorPalette.Blue[6]
                    "markerStyle" = [Excel.XlMarkerStyle]::xlMarkerStyleCircle
                    "lineWeight"  = 3
                    "markerSize"  = 5
                }
                3 = @{
                    "color"       = $ColorPalette.Blue[3]
                    "markerColor" = $ColorPalette.Blue[3]
                    "markerStyle" = [Excel.XlMarkerStyle]::xlMarkerStyleCircle
                    "lineWeight"  = 3
                    "markerSize"  = 5
                }
            }
        }

        if (-not $innerPivot) {
            $table.chartSettings.yOffset = 3
        }

        $col = 0
        $row = 0
        foreach ($IPivotKey in $data.$OPivotKey.$prop.Keys | Sort) {
            # Add column labels to table
            $table.cols.$tableTitle.$innerPivot.$IPivotKey = $col
            $table.meta.numWrites += 1
            $table.data.$tableTitle.$innerPivot.$IPivotKey = @{
                $prop = @{}
            }
            $table.meta.columnFormats += $meta.format.$prop
            $col += 1
        
            # Add row labels and fill data in table
            foreach ($metric in $metrics) {
                if (-not ($table.rows.$prop.Keys -contains $metric)) { 
                    if (-not $meta.comparison) {
                        $table.rows.$prop.$metric = $row
                        $row += 1
                        $table.meta.numWrites += 1
                    } 
                    else {
                        $table.meta.numWrites += 3
                        $table.rows.$prop.$metric = @{
                            "baseline" = $row
                            "test"     = $row + 1
                        } 
                        $row += 2
                    }
                }
                if (-not ($table.data.$tableTitle.$innerPivot.$IPivotKey.$prop.Keys -contains $metric)) {
                    $table.data.$tableTitle.$innerPivot.$IPivotKey.$prop.$metric = @{}
                }

                if (-not $meta.comparison) {
                    $table.data.$tableTitle.$innerPivot.$IPivotKey.$prop.$metric = @{"value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.stats.$metric}
                } 
                else {
                    $table.data.$tableTitle.$innerPivot.$IPivotKey.$prop.$metric.baseline = @{"value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.stats.$metric}
                    $table.data.$tableTitle.$innerPivot.$IPivotKey.$prop.$metric.test     = @{"value" = $data.$OPivotKey.$prop.$IPivotKey.test.stats.$metric}
                }
                Write-Progress -Activity "Formatting Tables" -Status "MinMeanMax Table" -Id 3 -PercentComplete (100 * (($j++) / $numIters))

            }

        }
        $table.meta.dataWidth     = Get-TreeWidth $table.cols
        $table.meta.colLabelDepth = Get-TreeDepth $table.cols
        $table.meta.dataHeight    = Get-TreeWidth $table.rows
        $table.meta.rowLabelDepth = Get-TreeDepth $table.rows
        $table.meta.numWrites    += $table.meta.dataHeight * $table.meta.dataWidth 
        $tables = $tables + $table
    }

    if (($tables.Count -gt 0) -and (-not $NoNewWorksheets)) {
        $sheetTitle = Get-WorksheetTitle -BaseName "MinMeanMax" -OuterPivot $outerPivot -OPivotKey $OPivotKey
        $tables = @($sheetTitle) + $tables
    }
    Write-Progress -Activity "Formatting Tables" -Status "MinMeanMax Table" -Id 3 -PercentComplete 100

    return $tables
}


##
# Format-Percentiles
# ----------------
# This function formats a table displaying percentiles of each data subcategory, one
# table per property + sortProp combo. When in comparison mode, percent change is also
# plotted and is color-coded to indicate improvement/regression. A chart is also formatted
# with each table.  
#
# Parameters
# ----------
# DataObj (HashTable) - Object containing processed data, raw data, and meta data
# TableTitle (String) - Title to be displayed at the top of each table
#
# Return
# ------
# HashTable[] - Array of HashTable objects which each store a table of formatted percentile data
#
##
function Format-Percentiles {
    Param (
        [Parameter(Mandatory=$true)] [PSobject[]] $DataObj,

        [Parameter(Mandatory=$true)] $OPivotKey,

        [Parameter()] [String] $Tool = "",

        [Parameter()] [switch] $NoNewWorksheets
    )

    $tables     = @()
    $data       = $DataObj.data
    $meta       = $DataObj.meta
    $innerPivot = $meta.InnerPivot
    $outerPivot = $meta.OuterPivot
    $nextRow = $HeaderRows
  
    
    $numIters = 0
    $propEnum = $data.$OPivotKey.keys.GetEnumerator()
    while ($propEnum.MoveNext()) {
        $prop = $propEnum.Current
        $iKeyEnum = $data.$OPivotKey.$prop.keys.GetEnumerator()
        while ($iKeyEnum.MoveNext()) {
            $iKey = $iKeyEnum.Current
            if ($data.$OPivotKey.$prop.$iKey.baseline.percentiles) {
                $numIters += $data.$OPivotKey.$prop.$iKey.baseline.percentiles.keys.Count
            } elseif ($data.$OPivotKey.$prop.$iKey.test.percentiles) { 
                $numIters += $data.$OPivotKey.$prop.$iKey.test.percentiles.keys.Count
            }
        }
    }
    $j = 0


    foreach ($prop in $data.$OPivotKey.Keys) {
        foreach ($IPivotKey in $data.$OPivotKey.$prop.Keys | Sort) { 

            if ($innerPivot) { 
                $chartTitle = (Get-Culture).TextInfo.ToTitleCase("$prop Percentiles - $IPivotKey $innerPivot") 
                $tableTitle = Get-TableTitle -Tool $Tool -OuterPivot $outerPivot -OPivotKey $OPivotKey -InnerPivot $innerPivot -IPivotKey $IPivotKey
            } 
            else {
                $chartTitle = (Get-Culture).TextInfo.ToTitleCase("$prop Percentiles")  
                $tableTitle = Get-TableTitle -Tool $Tool -OuterPivot $outerPivot -OPivotKey $OPivotKey -InnerPivot $innerPivot -IPivotKey $IPivotKey
            }
            
            $table = @{
                "rows" = @{
                    "percentiles" = @{}
                }
                "cols" = @{
                    $tableTitle = @{
                        $prop = 0
                    }
                }
                "meta" = @{
                    "columnFormats" = @($meta.format.$prop)
                    "rightAlign"    = [Array] @(2)
                    "name"          = "Percentiles"
                    "numWrites"     = 1 + 2
                }
                "data" = @{
                    $tableTitle = @{
                        $prop = @{
                            "percentiles" = @{}
                        }
                    }
                }
                "chartSettings" = @{
                    "title"     = $chartTitle
                    "yOffset"   = 1
                    "xOffset"   = 1
                    "chartType" = [Excel.XlChartType]::xlXYScatterLinesNoMarkers
                    "seriesSettings" = @{
                        1 = @{ 
                            "color"      = $ColorPalette.Blue[6]
                            "lineWeight" = 3
                        }
                    }
                    "axisSettings" = @{
                        1 = @{
                            "max"            = 100
                            "title"          = "Percentiles"
                            "minorGridlines" = $true
                        }
                        2 = @{
                            "title" = $meta.units[$prop]
                        }
                    }
                }
            }

            $table.chartSettings.axisSettings[2].logarithmic = Set-Logarithmic -Data $data -OPivotKey $OPivotKey -Prop $prop -IPivotKey $IPivotKey -Meta $meta 

            if ($meta.comparison) {
                $table.meta.numWrites += 3
                $table.cols.$tableTitle.$prop = @{
                    "baseline" = 0
                    "% change" = 1
                    "test"     = 2
                }
                $table.data.$tableTitle.$prop = @{
                    "baseline" = @{
                        "percentiles" = @{}
                    }
                    "% change" = @{
                        "percentiles" = @{}
                    }
                    "test" = @{
                        "percentiles" = @{}
                    }
                }
                $table.chartSettings.seriesSettings[2] = @{
                    "delete" = $true
                }
                $table.chartSettings.seriesSettings[3] = @{
                    "color"      = $ColorPalette.Orange[6]
                    "lineWeight" = 3
                }
                $table.meta.columnFormats = @($meta.format.$prop, "0.0%", $meta.format.$prop)
            }
            $row = 0

            $keys = @()
            if ($data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles.Keys.Count -gt 0) {
                $keys = $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles.Keys
            } 
            else {
                $keys = $data.$OPivotKey.$prop.$IPivotKey.test.percentiles.Keys
            }

            # Add row labels and fill data in table
            foreach ($percentile in $keys | Sort) {
                $table.rows.percentiles.$percentile = $row
                $table.meta.numWrites += 1
                if ($meta.comparison) {
                    $baseCell = "C$nextRow"
                    $testCell = "E$nextRow" 
                    if ($data.$OPivotKey.$prop.$IPivotKey.ContainsKey("baseline")) {
                        $table.data.$tableTitle.$prop.baseline.percentiles[$percentile]   = @{"value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles.$percentile}
                    }
                    if ($data.$OPivotKey.$prop.$IPivotKey.ContainsKey("test")) {
                        $table.data.$tableTitle.$prop.test.percentiles[$percentile]       = @{"value" = $data.$OPivotKey.$prop.$IPivotKey.test.percentiles.$percentile}
                    }
                    if ($data.$OPivotKey.$prop.$IPivotKey.ContainsKey("baseline") -and $data.$OPivotKey.$prop.$IPivotKey.ContainsKey("test")) {
                        $table.data.$tableTitle.$prop."% change".percentiles[$percentile] = @{"value" = "=IF($baseCell=0, ""--"", ($testCell-$baseCell)/ABS($baseCell))"}
                        $params = @{
                            "Cell"    = $table.data.$tableTitle.$prop."% change".percentiles[$percentile]
                            "TestVal" = $data.$OPivotKey.$prop.$IPivotKey.test.percentiles[$percentile]
                            "BaseVal" = $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles[$percentile]
                            "Goal"    = $meta.goal.$prop
                        }
                        $table.data.$tableTitle.$prop."% change".percentiles[$percentile] = Set-CellColor @params
                    } 
                } 
                else {
                    $table.data.$tableTitle.$prop.percentiles[$percentile] = @{"value" = $data.$OPivotKey.$prop.$IPivotKey.baseline.percentiles.$percentile}
                }
                $row += 1
                $nextRow += 1
                Write-Progress -Activity "Formatting Tables" -Status "Percentiles Table" -Id 3 -PercentComplete (100 * (($j++) / $numIters))

            }
            $nextRow += $HeaderRows

            $table.meta.dataWidth     = Get-TreeWidth $table.cols
            $table.meta.colLabelDepth = Get-TreeDepth $table.cols
            $table.meta.dataHeight    = Get-TreeWidth $table.rows
            $table.meta.rowLabelDepth = Get-TreeDepth $table.rows 
            $table.meta.numWrites    += $table.meta.dataHeight * $table.meta.dataWidth  
            $tables = $tables + $table
        }
    }

    if (($tables.Count -gt 0) -and (-not $NoNewWorksheets)) {
        $sheetTitle = Get-WorksheetTitle -BaseName "Percentiles" -OuterPivot $outerPivot -OPivotKey $OPivotKey
        $tables     = @($sheetTitle) + $tables 
    }
    Write-Progress -Activity "Formatting Tables" -Status "Done" -Id 3 -PercentComplete 100

    return $tables  
}

function Set-Logarithmic ($Data, $OPivotKey, $Prop, $IPivotKey, $Meta) {
    if ($data.$OPivotKey.$Prop.$IPivotKey.baseline.stats) {
        if ($data.$OPivotKey.$Prop.$IPivotKey.baseline.stats.min -le 0) {
            return $false
        }
        if ($Meta.comparison) {
            if ($data.$OPivotKey.$Prop.$IPivotKey.test.stats.min -le 0) {
                return $false
            }
        }
        if (($data.$OPivotKey.$Prop.$IPivotKey.baseline.stats.max / ($data.$OPivotKey.$Prop.$IPivotKey.baseline.stats.min + $EPS)) -gt 10) {
            return $true
        }

        if ($Meta.comparison) {
            if (($data.$OPivotKey.$Prop.$IPivotKey.test.stats.max / ($data.$OPivotKey.$Prop.$IPivotKey.test.stats.min + $EPS)) -gt 10) {
                return $true
            }
            if (($data.$OPivotKey.$Prop.$IPivotKey.test.stats.max / ($data.$OPivotKey.$Prop.$IPivotKey.baseline.stats.min + $EPS)) -gt 10) {
                return $true
            }
            if (($data.$OPivotKey.$Prop.$IPivotKey.baseline.stats.max / ($data.$OPivotKey.$Prop.$IPivotKey.test.stats.min + $EPS)) -gt 10) {
                return $true
            }
        }
    }
    return $false
}

<#
.SYNOPSIS
    Returns a template for Format-Histogram
#>
function Get-HistogramTemplate {
    param(
        [PSObject[]] $DataObj,
        [String] $TableTitle,
        [String] $Property,
        [String] $IPivotKey
    )

    $meta = $DataObj.meta

    $chartTitle = if ($IPivotKey) {
        "$Property Histogram - $IPivotKey $($meta.InnerPivot)"
    } else {
        "$Property Histogram"
    }

    $table = @{
        "rows" = @{
            "histogram buckets" = @{}
        }
        "cols" = @{
            $TableTitle = @{
                $Property = 0
            }
        }
        "meta" = @{
            "rightAlign" = [Array] @(2)
            "columnFormats" = @("0.0%")
            "name"          = "Histogram"
            "numWrites"     = 1 + 2
        }
        "data" = @{
            $TableTitle = @{
                $Property = @{
                    "histogram buckets" = @{}
                }
            }
        }
        "chartSettings"= @{
            "title"   = $TextInfo.ToTitleCase($chartTitle)
            "yOffset" = 1
            "xOffset" = 1
            "seriesSettings" = @{
                1 = @{ 
                    "color" = $ColorPalette.Blue[6]
                    "lineWeight" = 1
                    "name" = "Frequency"
                }
            }
            "axisSettings" = @{
                1 = @{
                    "title" = "$Property ($($meta.units[$Property]))"
                    "tickLabelSpacing" = 5
                }
                2 = @{
                    "title" = "Frequency"
                }
            }
        } # chartSettings
    }

    # Support base/test comparison mode
    if ($meta.comparison) {
        $table.cols.$TableTitle.$Property = @{
            "baseline" = 0
            "% change" = 1
            "test"     = 2
        }
        
        $table.meta.numWrites += 3
        $table.data.$TableTitle.$Property = @{
            "baseline" = @{
                "histogram buckets" = @{}
            }
            "% change" = @{
                "histogram buckets" = @{}
            }
            "test" = @{
                "histogram buckets" = @{}
            }
        }

        $table.chartSettings.seriesSettings[1].name = "Baseline"
        $table.chartSettings.seriesSettings[2] = @{
            "delete" = $true # don't plot % change
        }
        $table.chartSettings.seriesSettings[3] = @{
            "color"      = $ColorPalette.Blue[6]
            "name"       = "Test"
            "lineWeight" = 3
        }

        $table.meta.columnFormats = @("0.0%", "0.0%", "0.0%")
    }

    return $table
} # Get-HistogramTemplate

<#
.SYNOPSIS
    Outputs a table with a histogram and chart.
#>
function Format-Histogram {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject[]] $DataObj,

        [Parameter(Mandatory=$true)]
        $OPivotKey,

        [Parameter(Mandatory=$true)]
        [String] $Tool
    )

    $tables = @()
    $meta = $DataObj.meta

    foreach ($prop in $DataObj.data.$OPivotKey.Keys) {
        foreach ($iPivotKey in $DataObj.data.$OPivotKey.$prop.Keys | sort) {
            $data = $DataObj.data.$OPivotKey.$prop.$iPivotKey

            if (-not $data.baseline.histogram -and -not $data.test.histogram) {
                continue
            }

            $tableTitle = Get-TableTitle -Tool $Tool -OuterPivot $meta.OuterPivot -OPivotKey $OPivotKey -InnerPivot $meta.InnerPivot -IPivotKey $iPivotKey
            $table = Get-HistogramTemplate -DataObj $DataObj -TableTitle $tableTitle -Property $prop -IPivotKey $iPivotKey

            if ($data.baseline.histogram) {
                $baseSum = ($data.baseline.histogram.Values | measure -Sum).Sum
            }
            
            if ($data.test.histogram) {
                $testSum = ($data.test.histogram.Values | measure -Sum).Sum
            }

            # Add row labels and fill data in table
            $row = 0
            $buckets = if ($data.baseline.histogram.Keys.Count -gt 0) {$data.baseline.histogram.Keys} else {$data.test.histogram.Keys}
            foreach ($bucket in ($buckets | sort)) {
                $table.rows."histogram buckets".$bucket = $row
                $table.meta.numWrites += 1
                
                

                if (-not $meta.comparison) {
                    $baseVal = $data.baseline.histogram.$bucket / $baseSum
                    $table.data.$tableTitle.$prop."histogram buckets"[$bucket] = @{"value" = $baseVal}
                } else {
                    if ($data.baseline.histogram) {
                        $baseVal = $data.baseline.histogram.$bucket / $baseSum
                        $table.data.$tableTitle.$prop.baseline."histogram buckets"[$bucket]   = @{"value" = $baseVal}
                    }
                    if ($data.test.histogram) { 
                        $testVal = $data.test.histogram.$bucket / $testSum
                        $table.data.$tableTitle.$prop.test."histogram buckets"[$bucket]       = @{"value" = $testVal}
                    }
                    if ($data.baseline.histogram -and $data.test.histogram) {
                        $baseCell = "C$($row + $HeaderRows)"
                        $testCell = "E$($row + $HeaderRows)"
                        $table.data.$tableTitle.$prop."% change"."histogram buckets"[$bucket] = @{"value" = "=IF($baseCell=0, ""--"", ($testCell-$baseCell)/ABS($baseCell))"}
                        $table.data.$tableTitle.$prop."% change"."histogram buckets"[$bucket] = Set-CellColor -Cell $table.data.$tableTitle.$prop."% change"."histogram buckets"[$bucket] -BaseVal $baseVal -TestVal $testVal -Goal "increase"
                    }
                }

                $row += 1
            }

            $table.meta.dataWidth     = Get-TreeWidth $table.cols
            $table.meta.colLabelDepth = Get-TreeDepth $table.cols
            $table.meta.dataHeight    = Get-TreeWidth $table.rows
            $table.meta.rowLabelDepth = Get-TreeDepth $table.rows
            
            $table.meta.numWrites += $table.meta.dataHeight * $table.meta.dataWidth  
            $tables = $tables + $table
        }
    }

    if ($table.Count -gt 0) {
        $worksheetTitle = Get-WorksheetTitle -BaseName "Histogram" -OuterPivot $meta.OuterPivot -OPivotKey $OPivotKey
        $tables = @($worksheetTitle) + $tables
    }

    return $tables
}


##
# Format-Distribution
# -------------------
# This function formats a table in order to create a chart that displays the the
# distribution of data over time.
#
# Parameters
# ----------
# DataObj (HashTable) - Object containing processed data, raw data, and meta data
# TableTitle (String) - Title to be displayed at the top of each table
# Prop (String) - The name of the property for which a table should be created (raw data must be in array form)
# SubSampleRate (int) - How many time samples should be grouped together for a single data point on the chart
#
# Return
# ------
# HashTable[] - Array of HashTable objects which each store a table of formatted distribution data
#
##
function Format-Distribution {
    Param (
        [Parameter(Mandatory=$true)] [PSobject[]] $DataObj,

        [Parameter()] [string] $OPivotKey,

        [Parameter()] [String] $Tool = "",

        [Parameter()] [String] $Prop,

        [Parameter()] [Int] $SubSampleRate = -1,

        [Parameter()] [switch] $NoNewWorksheets
        
    )

    $DEFALT_SEGMENTS_TARGET = 200

    $meta  = $DataObj.meta 
    $modes = if ($meta.comparison) { @("baseline", "test") } else { @(,"baseline") } 
    $tables     = @()
    $innerPivot = $meta.InnerPivot
    $outerPivot = $meta.OuterPivot

    $NumSamples = Calculate-MaxNumSamples -RawData $DataObj.rawData -Modes $modes -Prop $Prop
    if ($SubSampleRate -eq -1) {
        $SubSampleRate = [Int] ($NumSamples/$DEFALT_SEGMENTS_TARGET)
    } 
    $numIters = Calculate-NumIterations -Distribution -DataObj $dataObj -Prop $Prop -SubSampleRate $SubSampleRate
    $j = 0

    foreach ($IPivotKey in $DataObj.data.$OPivotKey.$Prop.Keys) { 
        foreach ($mode in $modes) { 
            if (-Not $DataObj.data.$OPivotKey.$Prop.$IPivotKey.$mode.stats) {
                continue
            } 

            
            $logarithmic = Set-Logarithmic -Data $dataObj.data -OPivotKey $OPivotKey -Prop $Prop -IPivotKey $IPivotKey `
                                            -Meta $meta
            $tableTitle = Get-TableTitle -Tool $Tool -OuterPivot $outerPivot -OPivotKey $OPivotKey -InnerPivot $innerPivot -IPivotKey $IPivotKey
            $data       = $dataObj.rawData.$mode 
            $table = @{
                "meta" = @{
                    "name" = "Distribution"
                    "numWrites" = 1 + 3
                }
                "rows" = @{
                    "Data Point" = @{}
                }
                "cols" = @{
                    $tableTitle = @{
                        "Time Segment" = 0
                        $Prop          = 1
                    }
                }
                "data" = @{
                    $tableTitle = @{
                        "Time Segment" = @{
                            "Data Point" = @{}
                        }
                        $Prop = @{
                            "Data Point" = @{}
                        }
                    }
                }
                "chartSettings" = @{
                    "chartType" = [Excel.XlChartType]::xlXYScatter
                    "yOffset"   = 2
                    "xOffset"   = 2
                    "title"     = "Temporal $prop Distribution"
                    "axisSettings" = @{
                        1 = @{
                            "title"          = "Time Series"
                            "minorGridlines" = $true
                            "majorGridlines" = $true
                            "max"            = $NumSamples
                        }
                        2 = @{
                            "title"       = $meta.units.$Prop
                            "logarithmic" = $logarithmic
                            "min"         = 10
                        }
                    }
                }
            }

            if ($mode -eq "baseline") {
                $table.chartSettings.seriesSettings = @{
                    1 = @{
                            "markerStyle"           = [Excel.XlMarkerStyle]::xlMarkerStyleCircle
                            "markerBackgroundColor" = $ColorPalette.Blue[8]
                            "markerForegroundColor" = $ColorPalette.Blue[6]
                            "name"                  = "$Prop Sample" 
                        }
                }
            } else {
                $table.chartSettings.seriesSettings = @{
                    1 = @{
                            "markerStyle"           = [Excel.XlMarkerStyle]::xlMarkerStyleCircle
                            "markerBackgroundColor" = $ColorPalette.Blue[8]
                            "markerForegroundColor" = $ColorPalette.Blue[6]
                            "name"                  = "$Prop Sample"
                        }
                }
            }

            # Add row labels and fill data in table
            $i   = 0
            $row = 0

            if ($SubSampleRate -gt 0) { 
                $finished = $false
                while (-Not $finished) {
                    [Array]$segmentData = @()
                    foreach ($entry in $data) {
                        if ($entry.$Prop.GetType().Name -ne "Object[]") {
                            continue
                        }
                        if (((-not $innerPivot) -or ($entry.$innerPivot -eq $IPivotKey)) -and `
                                ((-not $outerPivot) -or ($entry.$outerPivot -eq $OPivotKey)) -and `
                                    ($i * $SubSampleRate -lt $entry.$Prop.Count)) {
                            $finalIdx = (($i + 1) * $SubSampleRate) - 1
                            if (((($i + 1) * $SubSampleRate) - 1) -ge $entry.$Prop.Count) {
                                $finalIdx = $entry.$Prop.Count - 1
                            }
                            $segmentData += $entry.$Prop[($i * $SubSampleRate) .. $finalIdx]
                        }
                    }
                    $segmentData = $segmentData | Sort
                    $time        = $i * $subSampleRate
                    if ($segmentData.Count -ge 5) {
                        $table.rows."Data Point".$row       = $row
                        $table.rows."Data Point".($row + 1) = $row + 1
                        $table.rows."Data Point".($row + 2) = $row + 2
                        $table.rows."Data Point".($row + 3) = $row + 3
                        $table.rows."Data Point".($row + 4) = $row + 4
                        $table.data.$tableTitle."Time Segment"."Data Point".$row       = @{"value" = $time}
                        $table.data.$tableTitle."Time Segment"."Data Point".($row + 1) = @{"value" = $time}
                        $table.data.$tableTitle."Time Segment"."Data Point".($row + 2) = @{"value" = $time}
                        $table.data.$tableTitle."Time Segment"."Data Point".($row + 3) = @{"value" = $time}
                        $table.data.$tableTitle."Time Segment"."Data Point".($row + 4) = @{"value" = $time}
                        $table.data.$tableTitle.$Prop."Data Point".$row = @{"value"       = $segmentData[0]}
                        $table.data.$tableTitle.$Prop."Data Point".($row + 1) = @{"value" = $segmentData[[int]($segmentData.Count / 4)]}
                        $table.data.$tableTitle.$Prop."Data Point".($row + 2) = @{"value" = $segmentData[[int]($segmentData.Count / 2)]}
                        $table.data.$tableTitle.$Prop."Data Point".($row + 3) = @{"value" = $segmentData[[int]((3 * $segmentData.Count) / 4)]}
                        $table.data.$tableTitle.$Prop."Data Point".($row + 4) = @{"value" = $segmentData[-1]}
                        $row += 5
                        $table.meta.numWrites += 5
                    } 
                    elseif ($segmentData.Count -ge 1){
                        foreach ($sample in $segmentData) {
                            $table.rows."Data Point".$row = $row
                            $table.data.$tableTitle."Time Segment"."Data Point".$row = @{"value" = $time}
                            $table.data.$tableTitle.$Prop."Data Point".$row          = @{"value" = $sample}
                            $row++
                            $table.meta.numWrites += 1
                        }
                    } else {
                        $finished = $true
                    }
                    $i++

                    Write-Progress -Activity "Formatting Tables" -Status "Distribution Table" -Id 3 -PercentComplete (100 * (($j++) / $numIters))

                }
            } else {
                $finished = $false
                while (-not $finished) { 
                    [Array]$segmentData = @()
                    foreach ($entry in $data) {
                        if ($entry.$prop.GetType().Name -ne "Object[]") {
                            continue
                        }
                        if (((-not $innerPivot) -or ($entry.$innerPivot -eq $IPivotKey)) -and ((-not $outerPivot) -or ($entry.$outerPivot -eq $OPivotKey))) {
                            if ($null -eq $entry[$Prop][$i]) {
                                continue
                            } 
                            $segmentData += $entry[$Prop][$i]
                        }
                    }
                    
                    $finished = ($segmentData.Count -eq 0) 
                    foreach ($sample in $segmentData) {
                        $table.rows."Data Point".$row = $row
                        $table.data.$tableTitle."Time Segment"."Data Point".$row = @{"value" = $i}
                        $table.data.$tableTitle.$Prop."Data Point".$row          = @{"value" = $sample}
                        $row++
                        $table.meta.numWrites += 1
                    }
                    $i++
                    Write-Progress -Activity "Formatting Tables" -Status "Distribution Table" -Id 3 -PercentComplete (100 * (($j++) / $numIters))

                }
            }
            $table.meta.dataWidth     = Get-TreeWidth $table.cols
            $table.meta.colLabelDepth = Get-TreeDepth $table.cols
            $table.meta.dataHeight    = Get-TreeWidth $table.rows
            $table.meta.rowLabelDepth = Get-TreeDepth $table.rows
            $table.meta.numWrites += $table.meta.dataHeight * $table.meta.dataWidth 
            if (-not $NoNewWorksheets) {
                if ($modes.Count -gt 1) {
                    if ($mode -eq "baseline") {
                        $worksheetName = Get-WorksheetTitle -BaseName "Base Distr." -OuterPivot $outerPivot -OPivotKey $OPivotKey -InnerPivot $innerPivot -IPivotKey $IPivotKey -Prop $Prop
                    } 
                    else {
                        $worksheetName = Get-WorksheetTitle -BaseName "Test Distr." -OuterPivot $outerPivot -OPivotKey $OPivotKey -InnerPivot $innerPivot -IPivotKey $IPivotKey -Prop $Prop
                    } 
                } 
                else {
                    $worksheetName = Get-WorksheetTitle -BaseName "Distr." -OuterPivot $outerPivot -OPivotKey $OPivotKey -InnerPivot $innerPivot -IPivotKey $IPivotKey -Prop $Prop
                } 
                $tables += $worksheetName
            }

            $tables += $table
        }
    }
    
    Write-Progress -Activity "Formatting Tables" -Status "Distribution Table" -Id 3 -PercentComplete 100

    return $tables
}

##
# Format-Distribution2
# -------------------
# This function formats a table in order to create a chart that displays the the
# distribution of data over time.
#
# Parameters
# ----------
# DataObj (HashTable) - Object containing processed data, raw data, and meta data
# TableTitle (String) - Title to be displayed at the top of each table
# Prop (String) - The name of the property for which a table should be created (raw data must be in array form)
# SubSampleRate (int) - How many time samples should be grouped together for a single data point on the chart
#
# Return
# ------
# HashTable[] - Array of HashTable objects which each store a table of formatted distribution data
#
##
function Format-Distribution2 {
    Param (
        [Parameter(Mandatory=$true)] [PSobject[]] $DataObj,

        [Parameter()] [string] $OPivotKey,

        [Parameter()] [String] $Tool = "",

        [Parameter()] [String] $Prop,

        [Parameter()] [Int] $SubSampleRate = -1,

        [Parameter()] [switch] $NoNewWorksheets
        
    )

    $DEFALT_SEGMENTS_TARGET = 200

    $meta  = $DataObj.meta 
    $modes = if ($meta.comparison) { @("baseline", "test") } else { @(,"baseline") } 
    $tables     = @()
    $innerPivot = $meta.InnerPivot
    $outerPivot = $meta.OuterPivot

    $NumSamples = Calculate-MaxNumSamples -RawData $DataObj.rawData -Modes $modes -Prop $Prop
    if ($SubSampleRate -eq -1) {
        $SubSampleRate = [Int] ($NumSamples/$DEFALT_SEGMENTS_TARGET)
    } 
    $numIters = Calculate-NumIterations -Distribution -DataObj $dataObj -Prop $Prop -SubSampleRate $SubSampleRate
    $j = 0

    foreach ($IPivotKey in $DataObj.data.$OPivotKey.$Prop.Keys) { 
        foreach ($mode in $modes) { 
            if (-Not $DataObj.data.$OPivotKey.$Prop.$IPivotKey.$mode.stats) {
                continue
            } 

            
            $logarithmic = Set-Logarithmic -Data $dataObj.data -OPivotKey $OPivotKey -Prop $Prop -IPivotKey $IPivotKey `
                                            -Meta $meta
            $tableTitle = Get-TableTitle -Tool $Tool -OuterPivot $outerPivot -OPivotKey $OPivotKey -InnerPivot $innerPivot -IPivotKey $IPivotKey
            $data       = $dataObj.rawData.$mode 
            $table = @{
                "meta" = @{
                    "name" = "Distribution"
                    "numWrites" = 1 + 3
                }
                "rows" = @{
                    "Data Point" = @{}
                }
                "cols" = @{
                    $tableTitle = @{
                        "" = @{
                            "Time Segment" = 0
                        }
                        $Prop = @{
                            "max" = 1
                            "p999" = 2
                            "p99" = 3
                            "p90" = 4
                            "p75" = 5
                            "p50" = 6
                            "p25" = 7
                            "p10" = 8
                            "min" = 9
                        }
                    }
                }
                "data" = @{
                    $tableTitle = @{
                        "" = @{
                            "Time Segment" = @{
                                "Data Point" = @{}
                            }
                        }
                        $Prop = @{
                            "max" = @{
                                "Data Point" = @{}
                            }
                            "p999" = @{
                                "Data Point" = @{}
                            }
                            "p99" = @{
                                "Data Point" = @{}
                            }
                            "p90" = @{
                                "Data Point" = @{}
                            }
                            "p75" = @{
                                "Data Point" = @{}
                            }
                            "p50" = @{
                                "Data Point" = @{}
                            }
                            "p25" = @{
                                "Data Point" = @{}
                            }
                            "p10" = @{
                                "Data Point" = @{}
                            }
                            "min" = @{
                                "Data Point" = @{}
                            }
                        }
                    }
                }
                "chartSettings" = @{
                    "chartType" = [Excel.XlChartType]::xlArea
                    "yOffset"   = 2
                    "xOffset"   = 2
                    "title"     = "Temporal $prop Distribution"
                    "axisSettings" = @{
                        1 = @{
                            "title"          = "Time Series"
                            "minorGridlines" = $true
                            "majorGridlines" = $true
                            "max"            = $NumSamples
                        }
                        2 = @{
                            "title"       = $meta.units.$Prop
                            "logarithmic" = $logarithmic
                            "min"         = 10
                        }
                    }
                }
            }

            if ($mode -eq "baseline") {
                $table.chartSettings.seriesSettings = @{
                    1 = @{ 
                            "markerBackgroundColor" = $ColorPalette.Blue[0]
                            "markerForegroundColor" = $ColorPalette.Blue[0]  
                        }
                    2 = @{ 
                            "markerBackgroundColor" = $ColorPalette.Blue[1]
                            "markerForegroundColor" = $ColorPalette.Blue[1]  
                        }
                    3 = @{ 
                            "markerBackgroundColor" = $ColorPalette.Blue[2]
                            "markerForegroundColor" = $ColorPalette.Blue[2]  
                        }
                    4 = @{ 
                            "markerBackgroundColor" = $ColorPalette.Blue[3]
                            "markerForegroundColor" = $ColorPalette.Blue[3]  
                        }
                    5 = @{ 
                            "markerBackgroundColor" = $ColorPalette.Blue[4]
                            "markerForegroundColor" = $ColorPalette.Blue[4]  
                        }
                    6 = @{ 
                            "markerBackgroundColor" = $ColorPalette.Blue[5]
                            "markerForegroundColor" = $ColorPalette.Blue[5]  
                        }
                    7 = @{ 
                            "markerBackgroundColor" = $ColorPalette.Blue[6]
                            "markerForegroundColor" = $ColorPalette.Blue[6]  
                        }
                    8 = @{ 
                            "markerBackgroundColor" = $ColorPalette.Blue[7]
                            "markerForegroundColor" = $ColorPalette.Blue[7]  
                        }
                    9 = @{ 
                            "markerBackgroundColor" = $ColorPalette.White
                            "markerForegroundColor" = $ColorPalette.White
                            "name" = "" 
                        }
                }
            } else {
                $table.chartSettings.seriesSettings = @{
                    1 = @{
                            "markerStyle"           = [Excel.XlMarkerStyle]::xlMarkerStyleCircle
                            "markerBackgroundColor" = $ColorPalette.Blue[8]
                            "markerForegroundColor" = $ColorPalette.Blue[6]
                            "name"                  = "$Prop Sample"
                        }
                }
            }

            # Add row labels and fill data in table
            $i   = 0
            $row = 0

            if ($SubSampleRate -gt 0) { 
                $finished = $false
                while (-Not $finished) {
                    [Array]$segmentData = @()
                    foreach ($entry in $data) {
                        if ($entry.$Prop.GetType().Name -ne "Object[]") {
                            continue
                        }
                        if (((-not $innerPivot) -or ($entry.$innerPivot -eq $IPivotKey)) -and `
                                ((-not $outerPivot) -or ($entry.$outerPivot -eq $OPivotKey)) -and `
                                    ($i * $SubSampleRate -lt $entry.$Prop.Count)) {
                            $finalIdx = (($i + 1) * $SubSampleRate) - 1
                            if (((($i + 1) * $SubSampleRate) - 1) -ge $entry.$Prop.Count) {
                                $finalIdx = $entry.$Prop.Count - 1
                            }
                            $segmentData += $entry.$Prop[($i * $SubSampleRate) .. $finalIdx]
                        }
                    }
                    $segmentData = $segmentData | Sort
                    $time        = $i * $subSampleRate
                    
                    if($segmentData.COunt -eq 0) {
                        $finished = $true
                        continue
                    }

                    $table.rows."Data Point".$row = $row 
                    $table.data.$tableTitle.""."Time Segment"."Data Point".$row       = @{"value" = $time}
                    $table.data.$tableTitle.$Prop."max"."Data Point".$row = @{"value" = $segmentData[-1]}
                    $table.data.$tableTitle.$Prop."p999"."Data Point".$row = @{"value" = $segmentData[[int](0.999 * ($segmentData.Count - 1))]}
                    $table.data.$tableTitle.$Prop."p99"."Data Point".$row = @{"value" = $segmentData[[int](0.99 * ($segmentData.Count - 1))]}
                    $table.data.$tableTitle.$Prop."p90"."Data Point".$row = @{"value" = $segmentData[[int](0.90 * ($segmentData.Count - 1))]}
                    $table.data.$tableTitle.$Prop."p75"."Data Point".$row = @{"value" = $segmentData[[int](0.75 * ($segmentData.Count - 1))]}
                    $table.data.$tableTitle.$Prop."p50"."Data Point".$row = @{"value" = $segmentData[[int](0.50 * ($segmentData.Count - 1))]}
                    $table.data.$tableTitle.$Prop."p25"."Data Point".$row = @{"value" = $segmentData[[int](0.25 * ($segmentData.Count - 1))]}
                    $table.data.$tableTitle.$Prop."p10"."Data Point".$row = @{"value" = $segmentData[[int](0.1 * ($segmentData.Count - 1))]}
                    $table.data.$tableTitle.$Prop."min"."Data Point".$row = @{"value" = $segmentData[0]}
                    $i++
                    $row++

                    Write-Progress -Activity "Formatting Tables" -Status "Distribution Table" -Id 3 -PercentComplete (100 * (($j++) / $numIters))

                }
            } else {
                $finished = $false
                while (-not $finished) { 
                    [Array]$segmentData = @()
                    foreach ($entry in $data) {
                        if ($entry.$prop.GetType().Name -ne "Object[]") {
                            continue
                        }
                        if (((-not $innerPivot) -or ($entry.$innerPivot -eq $IPivotKey)) -and ((-not $outerPivot) -or ($entry.$outerPivot -eq $OPivotKey))) {
                            if ($null -eq $entry[$Prop][$i]) {
                                continue
                            } 
                            $segmentData += $entry[$Prop][$i]
                        }
                    }
                    
                    $finished = ($segmentData.Count -eq 0) 
                    foreach ($sample in $segmentData) {
                        $table.rows."Data Point".$row = $row
                        $table.data.$tableTitle."Time Segment"."Data Point".$row = @{"value" = $i}
                        $table.data.$tableTitle.$Prop."Data Point".$row          = @{"value" = $sample}
                        $row++
                        $table.meta.numWrites += 1
                    }
                    $i++
                    Write-Progress -Activity "Formatting Tables" -Status "Distribution Table" -Id 3 -PercentComplete (100 * (($j++) / $numIters))

                }
            }
            $table.meta.dataWidth     = Get-TreeWidth $table.cols
            $table.meta.colLabelDepth = Get-TreeDepth $table.cols
            $table.meta.dataHeight    = Get-TreeWidth $table.rows
            $table.meta.rowLabelDepth = Get-TreeDepth $table.rows
            $table.meta.numWrites += $table.meta.dataHeight * $table.meta.dataWidth 
            if (-not $NoNewWorksheets) {
                if ($modes.Count -gt 1) {
                    if ($mode -eq "baseline") {
                        $worksheetName = Get-WorksheetTitle -BaseName "Base Distr." -OuterPivot $outerPivot -OPivotKey $OPivotKey -InnerPivot $innerPivot -IPivotKey $IPivotKey -Prop $Prop
                    } 
                    else {
                        $worksheetName = Get-WorksheetTitle -BaseName "Test Distr." -OuterPivot $outerPivot -OPivotKey $OPivotKey -InnerPivot $innerPivot -IPivotKey $IPivotKey -Prop $Prop
                    } 
                } 
                else {
                    $worksheetName = Get-WorksheetTitle -BaseName "Distr." -OuterPivot $outerPivot -OPivotKey $OPivotKey -InnerPivot $innerPivot -IPivotKey $IPivotKey -Prop $Prop
                } 
                $tables += $worksheetName
            }

            $tables += $table
        }
    }
    
    Write-Progress -Activity "Formatting Tables" -Status "Distribution Table" -Id 3 -PercentComplete 100

    return $tables
}

<#
.SYNOPSIS 
    Calculates the maximum numer of samples of a given property provided
    by a single data file
#>
function Calculate-MaxNumSamples ($RawData, $Modes, $Prop) {
    $max = 0
    foreach ($mode in $Modes) {
        foreach ($fileEntry in $RawData.$mode) {
            if ($fileEntry.$Prop.Count -gt $max) {
                $max = $fileEntry.$Prop.Count
            }
        } 
    }
    $max
}
function Calculate-NumIterations {
    param (
        [Parameter(Mandatory=$true, ParameterSetName="distribution")]
        [Switch] $Distribution,

        [Parameter(Mandatory=$true)]
        $DataObj, 

        [Parameter(Mandatory=$true, ParameterSetName = "distribution")]
        [String] $Prop, 

        [Parameter(Mandatory=$true, ParameterSetName = "distribution")]
        [Int] $SubSampleRate

         
    )

    if ($Distribution) { 
        $innerLoopIters = 0
        $maxSamples = Calculate-MaxNumSamples -RawData $DataObj.rawData -Modes @("baseline") -Prop $Prop
        if ($SubsampleRate -gt 0) { 
            $innerLoopIters += 1 + [Int]( ($maxSamples / $SubsampleRate) + 0.5) 
        } else {
            $innerLoopIters += $maxSamples
        }

        
        if ($dataObj.meta.comparison) {
            $maxSamples = Calculate-MaxNumSamples -RawData $DataObj.rawData -Modes @("test") -Prop $Prop
            if ($SubsampleRate -gt 0) {  
                $innerLoopIters += 1 + [Int](($maxSamples/ $SubSampleRate) + 0.5) 
            } else {
                $innerLoopIters += $maxSamples + 1
            }
        } 
        return $DataObj.meta.innerPivotKeys.Count * $innerLoopIters
    }
}


<#
.SYNOPSIS
    Sets the colors of a cell, indicating whether a test value shows
    an improvement when compared to a baseline value. Improvement is
    defined by the goal (increase/decrease) for the given value.
.PARAMETER Cell
    Object containg a cell's value and other settings.
.PARAMETER TestVal
    Test metric value.
.PARAMETER BaseVal
    Baseline metric value.
.PARAMETER Goal
    Defines metric improvement direction. "increase", "decrease", or "none".
#>
function Set-CellColor ($Cell, [Decimal] $TestVal, [Decimal] $BaseVal, $Goal) {
    if (($Goal -ne "none") -and ($TestVal -ne $BaseVal)) {
        if (($Goal -eq "increase") -eq ($TestVal -gt $BaseVal)) {
            $Cell["fontColor"] = $ColorPalette.Green
            $Cell["cellColor"] = $ColorPalette.LightGreen
        } else {
            $Cell["fontColor"] = $ColorPalette.Red
            $Cell["cellColor"] = $ColorPalette.LightRed
        }
    }

    return $Cell
}

##
# Get-TreeWidth
# -------------
# Calculates the width of a tree structure
#
# Parameters 
# ----------
# Tree (HashTable) - Object with a heirarchical tree structure
#
# Return
# ------
# int - Width of Tree
#
##
function Get-TreeWidth ($Tree) {
    if ($Tree.GetType().Name -eq "Int32") {
        return 1
    }
    $width = 0
    foreach ($key in $Tree.Keys) {
        $width += [int](Get-TreeWidth -Tree $Tree[$key])
    }
    return $width
}

##
# Get-TreeWidth
# -------------
# Calculates the depth of a tree structure
#
# Parameters 
# ----------
# Tree (HashTable) - Object with a heirarchical tree structure
#
# Return
# ------
# int - Depth of Tree
#
##
function Get-TreeDepth ($Tree) {
    if ($Tree.GetType().Name -eq "Int32") {
        return 0
    }
    $depths = @()
    foreach ($key in $Tree.Keys) {
        $depths = $depths + [int](Get-TreeDepth -Tree $Tree[$key])
    }
    return ($depths | Measure -Maximum).Maximum + 1
}
