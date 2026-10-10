@echo off
rem LightCraft installer for Windows 10 and 11. Double-click this file to run it.
rem It checks how LightCraft will run on this PC, downloads the official installer,
rem opens a note in Notepad with the result, and then installs LightCraft.
title LightCraft installer
set "CRAFT_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:CRAFT_SELF); iex $s.Substring($s.IndexOf('#POWERSHELL-BELOW'+[char]35))"
echo.
pause
exit /b
#POWERSHELL-BELOW#
# Everything below is PowerShell (Windows PowerShell 5.1 or newer). The lines above start it.
$ErrorActionPreference = 'Stop'

# ---- settings ----------------------------------------------------------------------------------
$App    = 'lightcraft'
$Name   = 'LightCraft'
$Friend = 'Terry'              # who the messages are addressed to
$Repo   = "storytold/$App"     # official releases: https://github.com/storytold/lightcraft/releases
$RamSlowGB     = 4   # less memory than this: it runs, but slowly
$RamGoodGB     = 8   # this much or more: comfortable
$NoGpuLevel    = 2   # best result without DirectX 12 graphics (2 = good, 1 = slow)
$DiskMinGB     = 3
$DiskComfortGB = 25
$DiskNote = 'LightCraft can use up to 20 GB for its own working files over time, so free up some space when you can.'
$Tip      = 'Your photos are never changed. LightCraft keeps your edits separately, so you can always go back to the original.'
$DryRun   = [bool]$env:CRAFT_DRYRUN   # set CRAFT_DRYRUN=1 to check and download without installing

# ---- small helpers -----------------------------------------------------------------------------
function Say($text) { Write-Host "==> $text" -ForegroundColor Cyan }

# One line that keeps moving, so it is clear nothing has frozen.
$script:spin = 0
function Tick($text) {
  $frame = '|/-\'[$script:spin % 4]
  $script:spin++
  $line = "  $frame $text  Not frozen, still working!"
  if ($line.Length -gt 78) { $line = $line.Substring(0, 78) }
  [Console]::Write("`r" + $line.PadRight(78))
}
function TickEnd { [Console]::Write("`r" + (' ' * 78) + "`r") }
function Clock($since) {
  $s = [int]((Get-Date) - $since).TotalSeconds
  '{0}:{1:00}' -f [math]::Floor($s / 60), ($s % 60)
}
function Probe($block) { try { & $block } catch { $null } }

function Download($url, $out) {
  for ($try = 1; $try -le 3; $try++) {
    $resp = $null; $in = $null; $fs = $null
    try {
      $req = [Net.HttpWebRequest]::Create($url)
      $req.UserAgent = 'craft-installer'
      $req.Timeout = 30000
      $resp = $req.GetResponse()
      $total = [long]$resp.ContentLength
      $in = $resp.GetResponseStream()
      $fs = [IO.File]::Create($out)
      $buf = New-Object byte[] 262144
      $have = [long]0
      $start = Get-Date
      $last = $start
      while ($true) {
        $read = $in.ReadAsync($buf, 0, $buf.Length)
        $quiet = 0
        while (-not $read.Wait(300)) {
          $quiet += 300
          if ($quiet -ge 120000) { throw 'the internet connection went quiet for 2 minutes' }
          Tick "Waiting for the internet, $(Clock $start)."
        }
        $n = $read.Result
        if ($n -le 0) { break }
        $fs.Write($buf, 0, $n)
        $have += $n
        if (((Get-Date) - $last).TotalMilliseconds -ge 300) {
          $last = Get-Date
          if ($total -gt 0) {
            Tick ("Downloading: {0}% ({1} of {2} MB), {3}." -f [int]($have * 100 / $total), [int]($have / 1MB), [int]($total / 1MB), (Clock $start))
          } else {
            Tick ("Downloading: {0} MB, {1}." -f [int]($have / 1MB), (Clock $start))
          }
        }
      }
      $fs.Close(); $fs = $null
      if ($total -gt 0 -and $have -ne $total) { throw 'the download was cut short' }
      TickEnd
      return
    } catch {
      TickEnd
      if ($try -eq 3) { throw "the download failed ($($_.Exception.Message))" }
      Write-Host "  The internet hiccuped. Trying again (attempt $($try + 1) of 3). Not frozen!"
      Start-Sleep -Seconds 3
    } finally {
      if ($fs) { $fs.Close() }
      if ($in) { $in.Close() }
      if ($resp) { $resp.Close() }
    }
  }
}

function Show-Note($lines) {
  $desktop = Probe { [Environment]::GetFolderPath('Desktop') }
  if (-not $desktop -or -not (Test-Path $desktop)) { $desktop = [IO.Path]::GetTempPath() }
  $path = Join-Path $desktop "$Name - message for $Friend.txt"
  Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
  if ($DryRun) { Write-Host "  (dry run) note written to $path" } else { Start-Process notepad.exe -ArgumentList "`"$path`"" }
  $path
}

try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

  # Ask Windows not to go to sleep while this runs (it does not cover closing the lid).
  Probe {
    Add-Type -Namespace Craft -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);'
    [void][Craft.Power]::SetThreadExecutionState([uint32]2147483649)
  } | Out-Null

  Write-Host ""
  Write-Host "Don't worry $Friend, your $Name installation has begun!" -ForegroundColor Green
  Write-Host "  - It takes a few minutes, depending on the internet speed."
  Write-Host "  - A moving line below shows it is still working. It is NOT frozen."
  Write-Host "  - Please don't turn off the laptop or close this window until it says ALL DONE."
  Write-Host "  - Please keep the lid open and the charger plugged in."
  Write-Host ""

  # ---- step 1: system discovery ------------------------------------------------------------------
  Say "Step 1 of 4: checking how $Name will run on this laptop"
  Tick 'Looking at the laptop.'
  $os   = Probe { Get-CimInstance Win32_OperatingSystem }
  $cs   = Probe { Get-CimInstance Win32_ComputerSystem }
  $cpu  = Probe { Get-CimInstance Win32_Processor | Select-Object -First 1 }
  $gpus = @(Probe { Get-CimInstance Win32_VideoController })
  $bat  = Probe { Get-CimInstance Win32_Battery | Select-Object -First 1 }
  $disk = Probe { Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" }

  $build   = [int](Probe { $os.BuildNumber })
  if ($build -le 0 -and [Environment]::OSVersion.Platform -eq 'Win32NT') { $build = [Environment]::OSVersion.Version.Build }
  $ramGB   = [math]::Round([double](Probe { $cs.TotalPhysicalMemory }) / 1GB, 1)
  $cores   = [int](Probe { $cpu.NumberOfCores })
  $threads = [int](Probe { $cpu.NumberOfLogicalProcessors })
  $freeGB  = [math]::Round([double](Probe { $disk.FreeSpace }) / 1GB, 1)
  $arch = $env:PROCESSOR_ARCHITEW6432
  if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
  switch ($arch) {
    'ARM64' { $build_arch = 'arm64' }
    'x86'   { $build_arch = 'x86' }
    default { $build_arch = 'x64' }
  }

  # DirectX details come from Windows' own dxdiag tool; it can take up to a minute.
  $ddi = 0; $featureLevels = ''; $dxGpus = @()
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("craft-install-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  $dxFile = Join-Path $tmp 'dxdiag.xml'
  $dxProc = Probe { Start-Process dxdiag.exe -ArgumentList "/x `"$dxFile`"" -PassThru -WindowStyle Hidden }
  if ($dxProc) {
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt 90 -and -not ($dxProc.HasExited -and (Test-Path $dxFile))) {
      Tick "Checking the graphics, $(Clock $start)."
      Start-Sleep -Milliseconds 300
    }
    if (-not $dxProc.HasExited) { Probe { $dxProc.Kill() } | Out-Null }
    Probe {
      [xml]$dx = Get-Content -LiteralPath $dxFile -Raw
      foreach ($d in @($dx.DxDiag.DisplayDevices.DisplayDevice)) {
        $v = [int]([regex]::Match([string]$d.DDIVersion, '\d+').Value)
        if ($v -gt $script:ddi) { $script:ddi = $v; $script:featureLevels = [string]$d.FeatureLevels }
        $mem = [string]$d.DedicatedMemory
        $script:dxGpus += ,@([string]$d.CardName, $mem)
      }
    } | Out-Null
  }
  TickEnd

  $gpuNames = @($gpus | ForEach-Object { $_.Name } | Where-Object { $_ })
  $realGpus = @($gpuNames | Where-Object { $_ -notmatch 'Basic (Display|Render)|Remote Display|Virtual|Mirror' })
  if ($ddi -ge 12) { $gpuOk = 'yes' }
  elseif ($ddi -gt 0) { $gpuOk = 'no' }
  elseif ($gpuNames.Count -gt 0 -and $realGpus.Count -eq 0) { $gpuOk = 'no' }
  else { $gpuOk = 'unknown' }

  # ---- the verdict: 3 great, 2 good, 1 slow, 0 cannot run ---------------------------------------
  $script:level = 3
  $script:why = New-Object System.Collections.Generic.List[string]
  function Check($cap, $mark, $text) {
    if ($cap -lt $script:level) { $script:level = $cap }
    $script:why.Add(('  [{0}] {1}' -f $mark, $text))
  }

  $osName = [string](Probe { $os.Caption })
  if (-not $osName) { $osName = 'Windows' }
  if ($build -gt 0 -and $build -lt 10240) { Check 0 'PROBLEM' "$osName is too old. $Name needs Windows 10 or 11." }
  elseif ($build -gt 0) { Check 3 'OK' "$osName (build $build) is supported." }
  else { Check 3 'NOTE' 'Could not read the Windows version.' }

  if ($ramGB -le 0) { Check 3 'NOTE' 'Could not read how much memory the laptop has.' }
  elseif ($ramGB -lt $RamSlowGB) { Check 1 'SLOW' "Memory: $ramGB GB. That is low for $Name (best with $RamGoodGB GB or more), so it will feel slow." }
  elseif ($ramGB -lt $RamGoodGB) { Check 2 'OK' "Memory: $ramGB GB. Enough for normal use ($RamGoodGB GB or more is ideal)." }
  else { Check 3 'OK' "Memory: $ramGB GB. Plenty." }

  if ($threads -le 0) { Check 3 'NOTE' 'Could not read the processor details.' }
  elseif ($threads -lt 4) { Check 2 'NOTE' "Processor: $threads threads. It works, but big jobs will take a while." }
  else { Check 3 'OK' "Processor: $cores cores / $threads threads. Fine." }

  if ($gpuOk -eq 'yes') { Check 3 'OK' "Graphics: supports DirectX 12, so $Name can use the graphics chip for speed." }
  elseif ($gpuOk -eq 'no') {
    Check $NoGpuLevel 'SLOW' "Graphics: no DirectX 12 support found, so $Name will do its work on the processor instead. It still works, only slower."
    if ($threads -gt 0 -and $threads -lt 4) { Check 1 'SLOW' 'With a small processor and no graphics help, expect it to be slow.' }
  }
  else { Check 3 'NOTE' 'Graphics: could not check DirectX 12 support. If the picture looks wrong, update the graphics driver.' }
  if (($realGpus -join ' ') -match 'Intel.*(HD|UHD) Graphics') { Check 3 'NOTE' 'Built-in Intel graphics: fine for normal use, slower on heavy work.' }

  if ($freeGB -le 0) { Check 3 'NOTE' 'Could not read the free disk space.' }
  elseif ($freeGB -lt $DiskMinGB) { Check 0 'PROBLEM' "Free space: only $freeGB GB on $($env:SystemDrive). At least $DiskMinGB GB is needed. Delete some files and run this again." }
  elseif ($freeGB -lt $DiskComfortGB) { Check 3 'NOTE' "Free space: $freeGB GB on $($env:SystemDrive). Enough to install. $DiskNote" }
  else { Check 3 'OK' "Free space: $freeGB GB on $($env:SystemDrive). Plenty." }

  $power = 'Plugged in'
  if ($bat) {
    $pct = [int](Probe { $bat.EstimatedChargeRemaining })
    if ([int](Probe { $bat.BatteryStatus }) -eq 1) {
      $power = "On battery ($pct%)"
      Check 3 'NOTE' "The laptop is on battery ($pct%). Please plug in the charger."
    } else { $power = "Plugged in (battery $pct%)" }
  }

  switch ($script:level) {
    3 { $verdict = "GREAT - this laptop should run $Name smoothly." }
    2 { $verdict = "GOOD - $Name will run fine for normal use." }
    1 { $verdict = "IT WILL RUN, BUT SLOWLY - $Name works on this laptop, with some waiting." }
    default { $verdict = "SORRY - $Name cannot be installed on this laptop yet." }
  }
  if ($script:level -gt 0 -and ($ramGB -le 0 -or $threads -le 0)) {
    $verdict = "COULD NOT CHECK - I could not read this laptop's details, so I cannot say how well $Name will run. It is still being installed."
  }

  $specs = @(
    "  Laptop:      $([string](Probe { $cs.Manufacturer })) $([string](Probe { $cs.Model }))".TrimEnd(),
    "  Windows:     $osName, $build_arch",
    "  Processor:   $(([string](Probe { $cpu.Name })).Trim()) ($cores cores / $threads threads)",
    "  Memory:      $ramGB GB"
  )
  if ($dxGpus.Count -gt 0) {
    foreach ($g in $dxGpus) { $specs += "  Graphics:    $($g[0]) ($($g[1]) dedicated memory)" }
  } else {
    foreach ($g in $gpuNames) { $specs += "  Graphics:    $g" }
  }
  if ($ddi -gt 0) { $specs += "  DirectX:     version $ddi (feature levels $featureLevels)" }
  $screen = $gpus | Where-Object { $_.CurrentHorizontalResolution } | Select-Object -First 1
  if ($screen) { $specs += "  Screen:      $($screen.CurrentHorizontalResolution) x $($screen.CurrentVerticalResolution)" }
  $specs += "  Free space:  $freeGB GB on $($env:SystemDrive)"
  $specs += "  Power:       $power"

  Write-Host "  Result: $verdict"
  Write-Host ""

  if ($script:level -eq 0) {
    $note = @("Hello $Friend,", '', "I checked this laptop for $Name.", '', "RESULT:  $verdict", '', 'WHY') + $script:why +
      @('', 'THIS LAPTOP') + $specs + @('', "Nothing was installed and nothing on the laptop was changed.", "Please show this note to whoever set this up for you.")
    Show-Note $note | Out-Null
    Write-Host "Sorry $Friend, $Name cannot be installed on this laptop yet." -ForegroundColor Yellow
    Write-Host 'The note that just opened in Notepad explains why. Nothing was changed.'
    return
  }

  # ---- step 2: download --------------------------------------------------------------------------
  Say "Step 2 of 4: downloading $Name (the longest step)"
  Tick "Finding the newest $Name."
  $req = [Net.HttpWebRequest]::Create("https://github.com/$Repo/releases/latest")
  $req.AllowAutoRedirect = $false
  $req.UserAgent = 'craft-installer'
  $resp = $null
  try { $resp = $req.GetResponse() } catch { throw 'could not reach github.com (is the internet connected?)' }
  $location = [string]$resp.Headers['Location']
  $resp.Close()
  TickEnd
  if ($location -notmatch '/tag/v(\d+(\.\d+)+)$') { throw "could not work out the newest version (got '$location')" }
  $version = $Matches[1]
  $asset = "$App-$version-windows-$build_arch.msi"
  $base = "https://github.com/$Repo/releases/download/v$version"
  $msi = Join-Path $tmp $asset
  Download "$base/$asset" $msi

  # ---- step 3: check the download ----------------------------------------------------------------
  Say 'Step 3 of 4: checking the download is complete and genuine'
  $sumsFile = Join-Path $tmp 'SHA256SUMS.txt'
  Download "$base/SHA256SUMS.txt" $sumsFile
  $expected = ''
  foreach ($line in Get-Content -LiteralPath $sumsFile) {
    $parts = $line.Trim() -split '\s+', 2
    if ($parts.Count -eq 2 -and $parts[1].TrimStart('*') -eq $asset) { $expected = $parts[0] }
  }
  if (-not $expected) { throw "$asset is not listed in SHA256SUMS.txt" }
  $actual = (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash
  if ($actual -ne $expected) { throw 'the downloaded file is damaged (checksum mismatch). Please run this again.' }

  # ---- the note for Terry, in Notepad ------------------------------------------------------------
  $note = @(
    "Hello $Friend!",
    '',
    "The $Name $version download has finished. I also checked this laptop,",
    "and here is how $Name should run on it.",
    '',
    "RESULT:  $verdict",
    '',
    'WHY'
  ) + $script:why + @('', 'THIS LAPTOP') + $specs + @(
    '',
    'WHAT HAPPENS NEXT',
    "  1. $Name is being installed right now. Please do not turn off the laptop.",
    '  2. Windows will ask "Do you want to allow this app to make changes to your device?"',
    '     Click YES.',
    '  3. When a small box says ALL DONE, it is finished.',
    "  4. To open it: click the Start button, type $Name, and press Enter.",
    '',
    "TIP: $Tip",
    '',
    'This result is an estimate from the parts inside the laptop, not a speed test.',
    'A copy of this note is saved on your Desktop.'
  )
  Show-Note $note | Out-Null

  # ---- step 4: install ---------------------------------------------------------------------------
  Say "Step 4 of 4: installing $Name"
  Write-Host '  Windows will ask for permission. Click YES.' -ForegroundColor Yellow
  if ($DryRun) {
    Write-Host "  (dry run) would now run: msiexec /i $msi /passive /norestart"
  } else {
    $inst = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /passive /norestart" -PassThru
    $start = Get-Date
    while (-not $inst.HasExited) {
      Tick "Installing, $(Clock $start)."
      Start-Sleep -Milliseconds 300
    }
    TickEnd
    switch ($inst.ExitCode) {
      0 { }
      3010 { }
      1602 { throw 'the install was cancelled. If Windows asked for permission, run this again and click YES.' }
      1618 { throw 'Windows is busy installing something else. Wait a few minutes and run this again.' }
      default { throw "the Windows installer stopped with code $($inst.ExitCode)" }
    }
  }
  Probe { Remove-Item -LiteralPath $tmp -Recurse -Force } | Out-Null

  Write-Host ""
  if ($DryRun) { Write-Host "(dry run) Everything checked out; $Name $version was NOT installed." -ForegroundColor Green; return }
  Write-Host "ALL DONE, $Friend! $Name $version is installed." -ForegroundColor Green
  Write-Host "  - To open it: click the Start button, type $Name, and press Enter."
  Write-Host '  - It is now safe to close this window or turn off the laptop.'
  if ($true) {
    Probe { (New-Object -ComObject WScript.Shell).Popup("ALL DONE, $Friend!`n`n$Name $version is installed.`nTo open it: click the Start button, type $Name, and press Enter.", 0, "$Name is installed", 64 + 4096) } | Out-Null
  }
} catch {
  TickEnd
  Write-Host ""
  Write-Host "Sorry $Friend, the $Name installation stopped." -ForegroundColor Yellow
  Write-Host "Reason: $($_.Exception.Message)"
  Write-Host 'Nothing on the laptop is broken. Check the internet connection and run this again;'
  Write-Host 'if it keeps happening, send a photo of this window to whoever set this up for you.'
}
