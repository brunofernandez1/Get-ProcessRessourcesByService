<#

    .SYNOPSIS
    This script checks the consumed memory and CPU utilisation of a subprocess for an service.

    .DESCRIPTION
    This powershell script reads the performance data from the WMI of a given Process and compares it with the given thresholds.
    The exit codes are equivalent to the nagios exit codes

    .PARAMETER Mem
    The Mem parameter is only a switch to enable the two parameters MemWarn and MemCritical

    .PARAMETER MemWarn
    The MemWarn parameter is the threshold in Megabytes to throw a "WARNING" error in memory consumption

    .PARAMETER MemCritical
    The MemCritical parameter is the threshold in Megabytes to throw a "CRITICAL" error in memory consumption

    .PARAMETER CPU
    The CPU parameter is only a switch to enable the two parameters CPUWarn and CPUCritical

    .PARAMETER CPUWarn
    The CPUWarn parameter is the threshold in percent to throw a "WARNING" error in CPU consumption

    .PARAMETER CPUCritical
    The CPUCritical parameter is the threshold in percent to throw a "CRITICAL" error in CPU consumption

    .INPUTS
    None

    .OUTPUTS
    Log file stored in C:\temp\Get-ProcessRessourcesbyService.log
    Can be changed in the Write-Log function

    .NOTES
    Copyright 2016 RealStuff Informatik AG

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; version 2
    of the License.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.


    Version:        1.0
    Author:         Bruno Fernandez, RealStuff Informatik AG, CH
    Creation Date:  20162209 intial script
                    20162210 Final

    .EXAMPLE
    .\Get-ProcessRessources.ps1 -Service servicename -Mem -MemWarn 1024 -MemCritical 2048
  
    With this command you set the warn level of memory consumption to 1024MB and critical level to 2048MB

    .EXAMPLE
    .\Get-ProcessRessources.ps1 -Service servicename -CPU -CPUWarn 15 -CPUCritical 25

    With this command you set the warn level of CPU consumption to 15% and the critical level to 25%

    .EXAMPLE
    .\Get-ProcessRessources.ps1 -Service servicename -Mem -MemWarn 1024 -MemCritical 2048 -CPU -CPUWarn 10 -CPUCritical 25

    With this command you set the warn level for CPU and memory at the same time
#>


#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Requires -Version 2.0

param (
    [Parameter(Mandatory=$true)][string]$Service,
    [string]$Process,
    [switch]$Mem,
    [UInt64]$MemWarn,
    [UInt64]$MemCritical,
    [switch]$CPU,
    [Int]$CPUWarn,
    [Int]$CPUCritical
)


#----------------------------------------------------------[Declarations]----------------------------------------------------------


#Global Vars
$global:ProcessList = $null
$global:ServiceList = $null
$global:FilteredService = $null
$global:FilteredProcessList = $null
$global:FilteredProcessListwithParent = $null
$global:CPUInUse = $null
$global:ProcessListwithParent = $null
[UInt64]$global:MemoryInuse = $null


#Nagios exit codes
$ExitCodes = 
@{
    "UNKNOWN"    = 3;
    "CRITICAL"   = 2;
    "WARNING"    = 1;
    "OK"         = 0
}

#-----------------------------------------------------------[Functions]------------------------------------------------------------

#Write-Log function by @wasserja
#https://gallery.technet.microsoft.com/scriptcenter/Write-Log-PowerShell-999c32d0
#Customized by Bruno Fernandez, RealStuff Informatik AG, CH
function Write-Log 
{ 
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, 
                   ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()] 
        [Alias("LogContent")] 
        [string]$Message, 
 
        [Parameter(Mandatory=$false)] 
        [Alias('LogPath')] 
        [string]$Path='C:\temp\Get-ProcessRessourcesbyService.log', 
         
        [Parameter(Mandatory=$false)] 
        [ValidateSet("Error","Warn","Info")] 
        [string]$Level="Info", 
         
        [Parameter(Mandatory=$false)] 
        [switch]$NoClobber 
    ) 
 
    Begin 
    { 
        # Set VerbosePreference to Continue or SilentlyContinue so that verbose messages are displayed or hidden. 
        $VerbosePreference = 'SilentlyContinue'

        # Set WarningPreference to Continue or SilentlyContinue so that verbose messages are displayed or hidden.
        $WarningPreference = 'SilentlyContinue'
        
        # Set ErrorActionPreference to Continue or SilentlyContinue so that verbose messages are displayed or hidden.
        $ErrorActionPreference = "SilentlyContinue"
    } 
    Process 
    { 
         
        # If the file already exists and NoClobber was specified, do not write to the log. 
        if ((Test-Path $Path) -AND $NoClobber) { 
            Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name." 
            Return 
            } 
 
        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path. 
        elseif (!(Test-Path $Path)) { 
            Write-Verbose "Creating $Path." 
            $NewLogFile = New-Item $Path -Force -ItemType File 
            } 
 
        else { 
            # Nothing to see here yet. 
            } 
 
        # Format Date for our Log File 
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss" 
 
        # Write message to error, warning, or verbose pipeline and specify $LevelText 
        switch ($Level) { 
            'Error' { 
                Write-Error $Message 
                $LevelText = 'ERROR:' 
                } 
            'Warn' { 
                Write-Warning $Message 
                $LevelText = 'WARNING:' 
                } 
            'Info' { 
                Write-Verbose $Message 
                $LevelText = 'INFO:' 
                } 
            } 
         
        # Write log entry to $Path 
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append 
    } 
    End 
    { 
    } 
}

#This function creates an ArrayList of all  services on the system by querying the WMI
Function Get-Services {

    $global:ServiceList = Get-WmiObject -Class Win32_Service
    if (!$global:ServiceList){
        #Write-Log -Level Warn -Message "No services found"
        Write-Host -NoNewline ("UNKNOWN - servicelist not found")
        exit $ExitCodes["UNKNOWN"]
        }
    else {
        #Write-Log -Level Info -Message "service list has content"
    }
}

#This function creates an Arraylist of all processes on the system by querying the WMI
Function Get-Processes {
    #Get the process list with performance data
    $global:ProcessList = Get-WmiObject Win32_PerfFormattedData_PerfProc_Process
    #Get the process list with parent process id information
    $global:ProcessListwithParent = Get-WmiObject Win32_Process
    
    if (!$global:ProcessListwithParent -or !$global:ProcessList){
        #Write-Log -Level Warn -Message "No processes found"
        Write-Host -NoNewline ("UNKNOWN - Process or Service " + $Process + " not found")
        exit $ExitCodes["UNKNOWN"]
        }
    else {
        #Write-Log -Level Info -Message "Process List has content"
    }
}

#This function filters the arrays 
Function Filter-Processes($global:ServiceList, $global:ProcessList, $global:FilteredProcessListwithParent, $global:ProcessListwithParent){


  #Write-Log -Level Info -Message "Filtering servicelist for Service"    
  $global:FilteredService = @($global:ServiceList | ?{$_.Name -match "$Service"})
  
  #Check if the service pid has childs
  $global:FilteredService.ForEach({
    
    $temppid = $_.ProcessId
    
    #Write-Log -Level Info -Message "temppid is filled up with $temppid"
    #Write-Log -Level Info -Message "Filtering filtered ServiceList for $_.Name and $_.ProcessId"
    
    $global:ProcessListWithParent | ForEach-Object {

        $tempparentpid = $_.ParentProcessId
        #Write-Log -Level Info -Message "Tempparentpid is filled up with $tempparentpid"
        #Write-Log -Level Info -Message "Does $tempparentpid match with $temppid ?"
        
        #Each process that is child, is added to to the FilteredProcessListwithParent
        if ($tempparentpid -eq $temppid){
            #Write-Log -Level Info -Message "Adding Process $_ to filtered List"
            $global:FilteredProcessListwithParent += @($_)
            }
        }

  })
    
    #Check if FilteredProcessListwithParent is empty, if yes, stop the script
    if ($global:FilteredProcessListwithParent.Count -eq 0 ){
        #Write-Log -Level Warn -Message "Could not find any service with the process name $Service"
        #Write-Log -Level Warn -Message ("Script ended with exit code " + $ExitCodes["UNKNOWN"])
        Write-Host -NoNewline ("UNKNOWN - Service " + $Service + " has no childs or is not available")
        exit $ExitCodes["UNKNOWN"]
    }
    if ($global:FilteredProcessListwithParent.Count -ge 1){
        #Write-Log -Level Info -Message ("Found " + $global:FilteredProcessListwithParent.Count + " process(es)")
    }

  #Getting performance information from the child processes
  $global:FilteredProcessListwithParent.ForEach({
       $temppid = $_.ProcessId
       #Write-Log -Level Info -Message "Creating list with Performance counter"
       
       $global:ProcessList.ForEach({
            $temppid2 = $_.IDProcess
            if($temppid2 -eq $temppid){
                #Write-Log -Level Info -Message "Adding $_"
                $global:FilteredProcessList += @($_)
                }
       })
       #Write-Log -Level Info -Message "Counting content of Process List:  ($global:FilteredProcessList).count"

            
    })

    if ($global:FilteredProcessList.Count -eq 0 ){
        Write-Host -NoNewline ("UNKNOWN - Something went wrong by getting performance information")
        exit $ExitCodes["UNKNOWN"]
        }
  #If no service is found, the script will end here with a warning in the log and exit code UNKNOWN

}


#This function counts the memory consumption in MB of the process and child processes
Function Count-MemoryUtilization($global:FilteredProcessList){
    #Write-Log -Level Info -Message "Counting the Memory utilization for all processes"
    #Write-Log -Level Info -Message "Counten of global:FilteredProcessList: $global:FilteredProcessList"
    Foreach ($SingleProcess in $global:FilteredProcessList){
        $global:MemoryInuse += $SingleProcess.WorkingSetPrivate/1024/1024
        #Write-Log -Level Info -Message ( "$global:MemoryInuse MB of memory is in use")
    }
    #Write-Log -Level Info -Message ("We have a total of " + $global:MemoryInuse + " MB of memory in use")
}

#This function counts the CPU consumption in % of the process and child processes
Function Count-CPUUitlization($global:FilteredProcessList){
    #Write-Log -Level Info -Message "Counting the CPU utilization for all processes"
    Foreach ($SingleProcess in $global:FilteredProcessList){
        $global:CPUInUse += $SingleProcess.PercentProcessorTime
        #Write-Log -Level Info -Message ( "$global:CPUInUse % of CPU is in use")
    }
    #Write-Log -Level Info -Message ("We have a total of " + $global:CPUInUse + " % of CPU is in use")
}

#This function compares the effective consumption with the given thresholds
Function Check-Thresholds { 
    #Write-Log -Level Info -Message "Checking Thresholds"
    #Check only memory threshold if memory switch is set
    if ($Mem -and !$CPU){
        #Write-Log -Level Info -Message "Mem switch was set but CPU not"
        #Write-Log -Level Info -Message "Checking if Mem thresholds are exceeded"
        
        if($global:MemoryInuse -ge $MemWarn){
            #Write-Log -Level Warn -Message "Memory thresholds are exeeded...Checking if critical or warning"
            if($global:MemoryInuse -ge $MemCritical){
                #Write-Log -Level Warn -Message ("Script ended with exit code " + $ExitCodes["CRITICAL"])
                Write-Host -NoNewline ("CRITICAL - Used Mem " + $global:MemoryInuse + " MB | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCritical + " cpu=0;0;0")
                exit $ExitCodes["CRITICAL"]
            }
            #Write-Log -Level Warn -Message ("Script ended with exit code " + $ExitCodes["WARNING"])
            Write-Host -NoNewline ("WARNING - Used Mem " + $global:MemoryInuse + " MB | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCritical + " cpu=0;0;0")
            exit $ExitCodes["WARNING"]
        }
        #Write-Log -Level Info -Message "Memory thresholds are not exeeded"
        #Write-Log -Level Info -Message ("Script ended with exit code " + $ExitCodes["OK"])
        Write-Host -NoNewline ("OK - Used Mem " + $global:MemoryInuse + " MB | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCritical + " cpu=0;0;0")
        exit $ExitCodes["OK"]
    }
    #Check only cpu threshold if cpu switch is set
    if ($CPU -and !$Mem){
        #Write-Log -Level Info -Message "CPU switch was set but Mem not"
        #Write-Log -Level Info -Message "Checking if CPU thresholds are exceeded"
        if($global:CPUInUse -ge $CPUWarn){
            #Write-Log -Level Warn -Message "CPU threshold are exeeded...Checking if critical or warning"
            if($global:CPUInuse -ge $CPUCritical){
                #Write-Log -Level Warn -Message ("Script ended with exit code " + $ExitCodes["CRITICAL"])
                Write-Host -NoNewline ("CRITICAL - Used CPU " +$global:CPUInUse + " % | mem=0;0;0 cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCritical)
                exit $ExitCodes["CRITICAL"]
            }
            #Write-Log -Level Warn -Message ("Script ended with exit code " + $ExitCodes["WARNING"])
            Write-Host -NoNewline ("WARNING - Used CPU " +$global:CPUInUse + " % | mem=0;0;0 cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCritical)
            exit $ExitCodes["WARNING"]
        }
        #Write-Log -Level Info -Message "CPU thresholds are not exeeded"
        #Write-Log -Level Info -Message ("Script ended with exit code " + $ExitCodes["OK"])
        Write-Host -NoNewline ("OK - Used CPU " +$global:CPUInUse + " % | mem=0;0;0 cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCritical)
        exit $ExitCodes["OK"]
    }
    #Check memory and cpu thresholds if both switches are set
    if ($CPU -and $Mem){
        #Write-Log -Level Info -Message "CPU  and Mem switches were set"
        #Write-Log -Level Info -Message "Checking if CPU or Memory thresholds are exceeded"
        if($global:CPUInUse -ge $CPUCritical){
            #Write-Log -Level Warn -Message "CPU critical threshold is exeeded"
            $CPUTempExitCode = $ExitCodes["CRITICAL"]
        }
        elseif($global:CPUInUse -ge $CPUWarn){
            #Write-Log -Level Warn -Message "CPU warning threshold is exeeded"
            $CPUTempExitCode = $ExitCodes["WARNING"]
        }
        elseif($global:CPUInUse -lt $CPUWarn){
            #Write-Log -Level Info -Message "CPU warning threshold is NOT exeeded"
            $CPUTempExitCode = $ExitCodes["OK"]
        }
        if($global:MemoryInUse -ge $MemCritical){
            #Write-Log -Level Warn -Message "Memory critical threshold is exeeded"
            $MemTempExitCode = $ExitCodes["CRITICAL"]
        }
        elseif($global:MemoryInUse -ge $MemWarn){
            #Write-Log -Level Warn -Message "Memory warning threshold is exeeded"
            $MemTempExitCode = $ExitCodes["WARNING"]
        }
        elseif($global:MemoryInUse -lt $MemWarn){
            #Write-Log -Level Info -Message "Memory warning threshold is NOT exeeded"
            $MemTempExitCode = $ExitCodes["OK"]
        }
        if($CPUTempExitCode -eq 2 -or $MemTempExitCode -eq 2){
            $TempExitCode = "CRITICAL"
            #Write-Log -Level Warn -Message "Exit code was set to CRITICAL"
        }
        if($CPUTempExitCode -eq 1 -or $MemTempExitCode -eq 1){
            $TempExitCode = "WARNING"
            #Write-Log -Level Warn -Message "Exit code was set to WARNING"
        }
        if($CPUTempExitCode -eq 0 -and $MemTempExitCode -eq 0){
            $TempExitCode = "OK"
            #Write-Log -Level Info -Message "Exit code was set to OK"
        }
        #Write-Log -Level Info -Message ("Script ended with exit code " + $ExitCodes[$TempExitCode])
        Write-Host -NoNewline ($TempExitCode + " - Used Mem " + $global:MemoryInUse + " MB, Used CPU " +$global:CPUInUse + " % | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCritical + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCritical)
        exit $ExitCodes[$TempExitCode]
    }
    #Don't check if no switch was set
    if (!$CPU -and !$Mem){
    #Write-Log -Level Warn -Message "No switch was set. Please select at least one of both"
    #Write-Log -Level Warn -Message ("Script ended with exit code " + $ExitCodes["UNKNOWN"])
    Write-Host -NoNewline ("UNKNOWN - No switch was set. Please select at least one of both")
    exit $ExitCodes["UNKNOWN"]
    }
}

#-----------------------------------------------------------[Main]------------------------------------------------------------

#Write-Log -Level Info -Message "Running Get-Services"

Get-Services

#Write-Log -Level Info -Message "Running Get-Processes"

Get-Processes

#Write-Log -Level Info -Message "Running Filter-Processes"

Filter-Processes $global:ServiceList $global:ProcessList $global:FilteredProcessListwithParent $global:ProcessListwithParent $Service

#Write-Log -Level Info -Message "Running Count-MemoryUtilization"

Count-MemoryUtilization $global:FilteredProcessList

#Write-Log -Level Info -Message "Running Count-CPUUtilization"

Count-CPUUitlization $global:FilteredProcessList

#Write-Log -Level Info -Message "Running Check-Thresholds"

Check-Thresholds
