Param(
    [parameter(Mandatory=$true)]
    [String] $subscriptionId,
    [parameter(Mandatory=$true)]
    [String] $accountId
)

Import-Module PSDates

$errorActionPreference = "Stop"

# Global used to await VM stopping jobs
$global:vmJobList = @()

# Constants
$STOP_TAG = "automated_stop"
$START_TAG = "automated_start"

function ManageVMPowerState{
    param(
        [Object]$VirtualMachine,
        [string]$DesiredState
    )

    Write-Output "[$($VirtualMachine.Name)]: Managing VM PowerState"

    # Retrieve VM with current status
    $eachVM = Get-AzVM -ResourceGroupName $VirtualMachine.ResourceGroupName -Name $VirtualMachine.Name -Status
    $currentStatus = $eachVM.Statuses | Where-Object Code -like "PowerState*" 
    $currentStatus = $currentStatus.Code -replace "PowerState/",""

    # If should be started and isn't, start VM
    if($DesiredState -eq "Started" -and $currentStatus -notmatch "running")
    {        
        Write-Output "[$($VirtualMachine.Name)]: Starting VM"
        $global:vmJobList += $eachVM | Start-AzVM -AsJob
    }        
    # If should be stopped and isn't, stop VM
    elseif($DesiredState -eq "StoppedDeallocated" -and $currentStatus -ne "deallocated")
    {
        Write-Output "[$($VirtualMachine.Name)]: Stopping VM"
        $global:vmJobList += $eachVM | Stop-AzVM -Force -AsJob
    }
    # Otherwise, current power state is correct
    else
    {
        Write-Output "[$($VirtualMachine.Name)]: Current state [$currentStatus] is correct."
    }
}

$currentTime = (Get-Date).ToUniversalTime()

Write-Output "Runbook started..."
Write-Output "Current UTC time: [$($currentTime.ToString("dddd, yyyy MMM dd HH:mm:ss"))] "

try
{
    "Logging in to Azure..."

    Connect-AzAccount -Identity -AccountId "$accountId" -Subscription "$subscriptionId" | Out-Null

    "Login successful.."
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

try {   
    # Get VM Data
    $allVMs = Get-AzResource -ResourceType "Microsoft.Compute/VirtualMachines" -TagName "$STOP_TAG"

    foreach ($vm in $allVMs) {
        Write-Output "[$($vm.Name)] Processing VM ..."

        # Retrieve the VM start and shutdown schedule
        $stop_schedule = $($vm.Tags)."$STOP_TAG"
        $start_schedule = $($vm.Tags)."$START_TAG"

        # Start schedules are optional on VMs
        $has_start_schedule = ![string]::IsNullOrWhiteSpace($start_schedule)

        if([string]::IsNullOrWhiteSpace($stop_schedule))
        {
            Write-Output "[$($vm.Name)] Skipping due to invalid/empty value in $STOP_TAG"
            continue
        }

        if((Test-CrontabSchedule -crontab "$stop_schedule").Valid -eq $false)
        {
            Write-Output "[$($vm.Name)] Skipping this VM due to invalid cron schedule: $stop_schedule"
        }

        if($has_start_schedule -eq $true)
        {
            if((Test-CrontabSchedule -crontab "$start_schedule").Valid -eq $false)
            {
                Write-Output "[$($vm.Name)] Skipping this VM due to invalid cron schedule: $start_schedule"
            }

            Write-Output "[$($vm.Name)] Start schedule is: $start_schedule"
        }
        Write-Output "[$($vm.Name)] Stop schedule is: $stop_schedule"

        # See what the target stop time is for the VM on current schedule
        $nextStopTime = Get-CronNextOccurrence "$stop_schedule"  -StartTime $currentTime.Date -EndTime $currentTime.Date.AddDays(1)
        Write-Output "[$($vm.Name)] Target stop time is: $nextStopTime"

        # If VM has a start time and a stop time
        if ($has_start_schedule -eq $true) {
            
            # See what the target start time is for the VM on current schedule
            $nextStartTime = Get-CronNextOccurrence "$start_schedule"  -StartTime $currentTime.Date -EndTime $currentTime.Date.AddDays(1)
            Write-Output "[$($vm.Name)] Target start time is: $nextStartTime"

            # If we are between the start and stop times the VM should be running
            if (($currentTime -ge $nextStartTime) -And ($currentTime -le $nextStopTime)) {
                ManageVMPowerState -VirtualMachine $vm -DesiredState "Started"
            } else {
                ManageVMPowerState -VirtualMachine $vm -DesiredState "StoppedDeallocated"
            }

        } else {

            # If VM just has a stop time defined
            if (($currentTime -ge $nextStopTime)) {
                ManageVMPowerState -VirtualMachine $vm -DesiredState "StoppedDeallocated"
            }

        }   
    }

    # Await VM Stop/Start commands
    Write-Output $global:vmJobList | Get-Job | Wait-Job | Receive-Job | Format-Table -AutoSize
}
catch {
    Write-Error "$($_.Exception.Message)"
    throw "Error executing stop/start script"
}
finally {
    Write-Output "Runbook finished (Duration: $(("{0:hh\:mm\:ss}" -f ((Get-Date).ToUniversalTime() - $currentTime))))"
}