[CmdletBinding()]
param(
  [string]$FlutterRoot,
  [string]$ReleaseTag,
  [string]$ReleaseChannel = 'pilot',
  [string]$PilotScope = 'pilot-unspecified',
  # The API a released build talks to. Defaults to the hostname already
  # compiled into every installed build; overriding it produces an APK that
  # points somewhere else, which is occasionally what a test build wants and
  # never what a shop build wants by accident.
  [string]$ApiBaseUrl = 'https://api.indianwasteportal.com/api/v1',
  [string]$ArtifactRoot = 'release-artifacts\mobile-local',
  [switch]$PreflightOnly,
  [switch]$SkipPubGet,
  [switch]$SkipCodegen,
  [switch]$SkipAnalyze,
  [switch]$SkipTest,
  [switch]$SkipBuild,
  [switch]$Doctor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$appDir = Join-Path $repoRoot 'apps\mobile_flutter'
$pubspecPath = Join-Path $appDir 'pubspec.yaml'
$androidDir = Join-Path $appDir 'android'
$keyPropertiesPath = Join-Path $androidDir 'key.properties'
$expectedReleaseApkPath = Join-Path $appDir 'build\app\outputs\flutter-apk\app-release.apk'

function Resolve-FlutterExecutable {
  param([string]$ExplicitRoot)

  $candidates = New-Object System.Collections.Generic.List[string]

  if (-not [string]::IsNullOrWhiteSpace($ExplicitRoot)) {
    $candidates.Add((Join-Path $ExplicitRoot 'bin\flutter.bat'))
    $candidates.Add((Join-Path $ExplicitRoot 'bin\flutter'))
  }

  foreach ($envName in @('BUSINESS_HUB_FLUTTER_HOME', 'FLUTTER_HOME')) {
    if (Test-Path "Env:$envName") {
      $envRoot = (Get-Item "Env:$envName").Value
      if (-not [string]::IsNullOrWhiteSpace($envRoot)) {
        $candidates.Add((Join-Path $envRoot 'bin\flutter.bat'))
        $candidates.Add((Join-Path $envRoot 'bin\flutter'))
      }
    }
  }

  foreach ($commandName in @('flutter.bat', 'flutter')) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
      $candidates.Add($command.Source)
    }
  }

  foreach ($root in @(
    'C:\src\flutter',
    'C:\flutter',
    (Join-Path $env:USERPROFILE 'flutter'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Flutter')
  )) {
    $candidates.Add((Join-Path $root 'bin\flutter.bat'))
    $candidates.Add((Join-Path $root 'bin\flutter'))
  }

  foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      continue
    }
    if (Test-Path $candidate) {
      return [System.IO.Path]::GetFullPath($candidate)
    }
  }

  return $null
}

function Resolve-DartExecutable {
  param([string]$FlutterExecutable)

  if ([string]::IsNullOrWhiteSpace($FlutterExecutable)) {
    return $null
  }

  $flutterBin = Split-Path -Parent $FlutterExecutable
  foreach ($candidate in @(
    (Join-Path $flutterBin 'dart.bat'),
    (Join-Path $flutterBin 'dart')
  )) {
    if (Test-Path $candidate) {
      return [System.IO.Path]::GetFullPath($candidate)
    }
  }

  foreach ($commandName in @('dart.bat', 'dart')) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
      return $command.Source
    }
  }

  return $null
}

function Resolve-KeytoolExecutable {
  foreach ($commandName in @('keytool.exe', 'keytool')) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
      return $command.Source
    }
  }

  return $null
}

function Invoke-Checked {
  param(
    [string]$FilePath,
    [string[]]$Arguments,
    [string]$Label,
    [hashtable]$ExtraEnvironment
  )

  Write-Host ''
  Write-Host "==> $Label" -ForegroundColor Cyan
  Write-Host "$FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray

  $oldValues = @{}
  if ($null -ne $ExtraEnvironment) {
    foreach ($pair in $ExtraEnvironment.GetEnumerator()) {
      $oldValues[$pair.Key] = [Environment]::GetEnvironmentVariable($pair.Key, 'Process')
      [Environment]::SetEnvironmentVariable($pair.Key, $pair.Value, 'Process')
    }
  }

  try {
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "$Label failed with exit code $LASTEXITCODE."
    }
  } finally {
    if ($null -ne $ExtraEnvironment) {
      foreach ($pair in $ExtraEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($pair.Key, $oldValues[$pair.Key], 'Process')
      }
    }
  }
}

function Show-ResolveHelp {
  Write-Host ''
  Write-Host 'Flutter SDK was not found.' -ForegroundColor Yellow
  Write-Host 'Try one of these options:' -ForegroundColor Yellow
  Write-Host '  1. Install Flutter locally.' -ForegroundColor Yellow
  Write-Host '  2. Set BUSINESS_HUB_FLUTTER_HOME or FLUTTER_HOME.' -ForegroundColor Yellow
  Write-Host '  3. Pass -FlutterRoot C:\path\to\flutter when running this script.' -ForegroundColor Yellow
}

function Get-PubspecMetadata {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    throw "pubspec.yaml not found: $Path"
  }

  $versionLine = Select-String -Path $Path -Pattern '^\s*version:\s*(.+)\s*$' | Select-Object -First 1
  if ($null -eq $versionLine) {
    throw "Could not find a version entry in $Path"
  }

  $versionValue = $versionLine.Matches[0].Groups[1].Value.Trim()
  $marketingVersion = $versionValue
  $buildNumber = '0'
  if ($versionValue.Contains('+')) {
    $parts = $versionValue.Split('+', 2)
    $marketingVersion = $parts[0]
    $buildNumber = $parts[1]
  }

  return [PSCustomObject]@{
    VersionLine = $versionValue
    MarketingVersion = $marketingVersion
    BuildNumber = $buildNumber
  }
}

function Get-KeyPropertiesMap {
  param([string]$Path)

  $values = @{}
  if (-not (Test-Path $Path)) {
    return $values
  }

  foreach ($line in Get-Content -Path $Path) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#') -or -not $trimmed.Contains('=')) {
      continue
    }

    $parts = $trimmed.Split('=', 2)
    $key = $parts[0].Trim()
    $value = $parts[1].Trim()
    if ([string]::IsNullOrWhiteSpace($key)) {
      continue
    }
    $values[$key] = $value
  }

  return $values
}

function Resolve-SigningValue {
  param(
    [hashtable]$KeyProperties,
    [string]$PropertyName,
    [string]$EnvironmentName
  )

  $propertyValue = $null
  if ($KeyProperties.ContainsKey($PropertyName)) {
    $propertyValue = $KeyProperties[$PropertyName]
  }

  $envValue = [Environment]::GetEnvironmentVariable($EnvironmentName, 'Process')
  if ([string]::IsNullOrWhiteSpace($envValue)) {
    $envValue = [Environment]::GetEnvironmentVariable($EnvironmentName, 'User')
  }
  if ([string]::IsNullOrWhiteSpace($envValue)) {
    $envValue = [Environment]::GetEnvironmentVariable($EnvironmentName, 'Machine')
  }

  if (-not [string]::IsNullOrWhiteSpace($propertyValue) -and -not $propertyValue.StartsWith('YOUR_')) {
    return [PSCustomObject]@{
      Value = $propertyValue
      Source = 'key.properties'
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($envValue)) {
    return [PSCustomObject]@{
      Value = $envValue
      Source = 'environment'
    }
  }

  return [PSCustomObject]@{
    Value = $null
    Source = 'missing'
  }
}

function Resolve-KeystoreFilePath {
  param(
    [string]$StoreFileValue,
    [string]$AndroidRoot
  )

  if ([string]::IsNullOrWhiteSpace($StoreFileValue)) {
    return $null
  }

  if ([System.IO.Path]::IsPathRooted($StoreFileValue)) {
    return [System.IO.Path]::GetFullPath($StoreFileValue)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $AndroidRoot $StoreFileValue))
}

function Get-SigningReadiness {
  param(
    [string]$Path,
    [string]$AndroidRoot
  )

  $keyProperties = Get-KeyPropertiesMap -Path $Path

  $storeFile = Resolve-SigningValue -KeyProperties $keyProperties -PropertyName 'storeFile' -EnvironmentName 'ANDROID_KEYSTORE_PATH'
  $storePassword = Resolve-SigningValue -KeyProperties $keyProperties -PropertyName 'storePassword' -EnvironmentName 'ANDROID_KEYSTORE_PASSWORD'
  $keyAlias = Resolve-SigningValue -KeyProperties $keyProperties -PropertyName 'keyAlias' -EnvironmentName 'ANDROID_KEY_ALIAS'
  $keyPassword = Resolve-SigningValue -KeyProperties $keyProperties -PropertyName 'keyPassword' -EnvironmentName 'ANDROID_KEY_PASSWORD'

  $storeFilePath = Resolve-KeystoreFilePath -StoreFileValue $storeFile.Value -AndroidRoot $AndroidRoot
  $hasSigning =
    -not [string]::IsNullOrWhiteSpace($storeFile.Value) -and
    -not [string]::IsNullOrWhiteSpace($storePassword.Value) -and
    -not [string]::IsNullOrWhiteSpace($keyAlias.Value) -and
    -not [string]::IsNullOrWhiteSpace($keyPassword.Value)

  $sources = @(
    @($storeFile.Source, $storePassword.Source, $keyAlias.Source, $keyPassword.Source) |
      Where-Object { $_ -ne 'missing' } |
      Select-Object -Unique
  )
  $signingSource = if ($sources.Count -eq 0) {
    'none'
  } elseif ($sources.Count -eq 1) {
    $sources[0]
  } else {
    'mixed'
  }

  $keytoolExecutable = Resolve-KeytoolExecutable
  $keytoolAvailable = -not [string]::IsNullOrWhiteSpace($keytoolExecutable)
  $keystoreExists = -not [string]::IsNullOrWhiteSpace($storeFilePath) -and (Test-Path $storeFilePath)
  $verificationStatus = 'not_configured'
  $verificationDetails = 'Release signing values are not fully configured.'

  if ($hasSigning) {
    if (-not $keystoreExists) {
      $verificationStatus = 'keystore_missing'
      $verificationDetails = 'Configured keystore file was not found on disk.'
    } elseif (-not $keytoolAvailable) {
      $verificationStatus = 'keytool_missing'
      $verificationDetails = 'keytool is not available, so keystore verification was skipped.'
    } else {
      # keytool writes progress to stderr even on success. Under PowerShell
      # 5.1, `2>&1` on a native command wraps each stderr line in an
      # ErrorRecord, and with $ErrorActionPreference='Stop' at the top of this
      # script that becomes terminating — so a perfectly good keystore aborted
      # the release before Flutter was ever invoked. Suspending the preference
      # for the duration of the two native calls keeps the output capture while
      # letting the exit code decide, which is what the checks below actually
      # read.
      $previousEap = $ErrorActionPreference
      $ErrorActionPreference = 'Continue'
      $storeCheckOutput = & $keytoolExecutable -list -keystore $storeFilePath -storepass $storePassword.Value 2>&1
      if ($LASTEXITCODE -ne 0) {
        $ErrorActionPreference = $previousEap
        $verificationStatus = 'store_password_invalid'
        $verificationDetails = ($storeCheckOutput | Out-String).Trim()
      } else {
        $aliasCheckOutput = & $keytoolExecutable -list -keystore $storeFilePath -storepass $storePassword.Value -alias $keyAlias.Value 2>&1
        $ErrorActionPreference = $previousEap
        if ($LASTEXITCODE -ne 0) {
          $verificationStatus = 'alias_missing'
          $verificationDetails = ($aliasCheckOutput | Out-String).Trim()
        } else {
          $verificationStatus = 'verified'
          $verificationDetails = 'Keystore password and alias verified successfully.'
        }
      }
    }
  }

  return [PSCustomObject]@{
    HasSigning = $hasSigning
    SigningMode = if ($hasSigning) { 'configured_release' } else { 'fallback_debug' }
    SigningSource = $signingSource
    KeyPropertiesPath = $Path
    KeyPropertiesPresent = (Test-Path $Path)
    KeytoolPath = $keytoolExecutable
    KeytoolAvailable = $keytoolAvailable
    StoreFilePath = $storeFilePath
    KeystoreExists = $keystoreExists
    KeyAlias = $keyAlias.Value
    VerificationStatus = $verificationStatus
    VerificationDetails = $verificationDetails
  }
}

function Get-GitMetadata {
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($null -eq $git) {
    return [PSCustomObject]@{
      FullSha = 'nogit'
      ShortSha = 'nogit'
    }
  }

  $fullSha = & $git.Source rev-parse HEAD 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($fullSha)) {
    return [PSCustomObject]@{
      FullSha = 'nogit'
      ShortSha = 'nogit'
    }
  }

  $fullSha = $fullSha.Trim()
  $shortSha = if ($fullSha.Length -ge 7) { $fullSha.Substring(0, 7) } else { $fullSha }

  return [PSCustomObject]@{
    FullSha = $fullSha
    ShortSha = $shortSha
  }
}

function New-HandoffMarkdown {
  param(
    [string]$Tag,
    [string]$Version,
    [string]$BuildNumber,
    [string]$Channel,
    [string]$PilotScopeLabel,
    [string]$CommitSha,
    [string]$ShortSha,
    [string]$ApkName,
    [string]$Checksum,
    [string]$SigningMode,
    [string]$SigningSource
  )

  return @(
    '# Business Hub Mobile Local Release Handoff',
    '',
    "- Release tag: $Tag",
    "- Version: $Version",
    "- Build number: $BuildNumber",
    "- Channel: $Channel",
    "- Pilot scope: $PilotScopeLabel",
    "- Commit: $CommitSha",
    "- Short SHA: $ShortSha",
    "- APK: $ApkName",
    "- APK SHA256: $Checksum",
    "- Signing mode: $SigningMode",
    "- Signing source: $SigningSource",
    '',
    '## Operator evidence to attach',
    '',
    '- copied pilot snapshot',
    '- copied readiness signoff',
    '- copied full handoff pack',
    '- copied wave signoff pack',
    '- copied wave archive pack',
    '',
    '## Required runbooks',
    '',
    '- docs/mobile-launch-operations-runbook.md',
    '- docs/mobile-pilot-wave-signoff-pack.md',
    '- docs/mobile-pilot-wave-archive-pack.md'
  ) -join [Environment]::NewLine
}

function Resolve-ReleaseTag {
  param(
    [string]$ExplicitTag,
    [pscustomobject]$Metadata
  )

  if (-not [string]::IsNullOrWhiteSpace($ExplicitTag)) {
    return $ExplicitTag.Trim()
  }

  return "mobile-v$($Metadata.MarketingVersion)"
}

function Get-ReleaseTagStatus {
  param([string]$Tag)

  if ([string]::IsNullOrWhiteSpace($Tag)) {
    return 'missing'
  }

  if ($Tag -match '^mobile-v\d+\.\d+\.\d+$') {
    return 'recommended'
  }

  if ($Tag -match '^mobile-v') {
    return 'custom_mobile_tag'
  }

  return 'custom_nonstandard'
}

function Get-PreflightVerdict {
  param(
    [string]$FlutterExecutablePath,
    [pscustomobject]$SigningState,
    [string]$ReleaseTagStatus
  )

  if ([string]::IsNullOrWhiteSpace($FlutterExecutablePath)) {
    return 'blocked'
  }

  if (-not $SigningState.HasSigning) {
    return 'ready_with_debug_signing'
  }

  if ($SigningState.VerificationStatus -ne 'verified') {
    return 'blocked'
  }

  if ($ReleaseTagStatus -eq 'custom_nonstandard') {
    return 'ready_nonstandard_tag'
  }

  return 'ready_for_signed_release'
}

$flutterExecutable = Resolve-FlutterExecutable -ExplicitRoot $FlutterRoot
$dartExecutable = Resolve-DartExecutable -FlutterExecutable $flutterExecutable
$metadata = Get-PubspecMetadata -Path $pubspecPath
$signing = Get-SigningReadiness -Path $keyPropertiesPath -AndroidRoot $androidDir
$resolvedReleaseTag = Resolve-ReleaseTag -ExplicitTag $ReleaseTag -Metadata $metadata
$releaseTagStatus = Get-ReleaseTagStatus -Tag $resolvedReleaseTag
$gitMetadata = Get-GitMetadata
$shortSha = $gitMetadata.ShortSha
$commitSha = $gitMetadata.FullSha
$releaseFolder = Join-Path $repoRoot (Join-Path $ArtifactRoot $resolvedReleaseTag)
$preflightVerdict = Get-PreflightVerdict -FlutterExecutablePath $flutterExecutable -SigningState $signing -ReleaseTagStatus $releaseTagStatus

if ($Doctor -or $PreflightOnly) {
  $resolvedFlutterLabel = if ($null -ne $flutterExecutable) { $flutterExecutable } else { '<not found>' }
  $resolvedDartLabel = if ($null -ne $dartExecutable) { $dartExecutable } else { '<not found>' }

  Write-Host "Repo root: $repoRoot"
  Write-Host "Mobile app: $appDir"
  Write-Host "Resolved Flutter: $resolvedFlutterLabel"
  Write-Host "Resolved Dart: $resolvedDartLabel"
  Write-Host "Version: $($metadata.MarketingVersion)+$($metadata.BuildNumber)"
  Write-Host "Release tag: $resolvedReleaseTag"
  Write-Host "Release tag status: $releaseTagStatus"
  Write-Host "Release channel: $ReleaseChannel"
  Write-Host "Pilot scope: $PilotScope"
  Write-Host "Commit: $commitSha"
  Write-Host "Short SHA: $shortSha"
  Write-Host "Expected APK: $expectedReleaseApkPath"
  Write-Host "Signing mode: $($signing.SigningMode)"
  Write-Host "Signing source: $($signing.SigningSource)"
  Write-Host "Key properties: $($signing.KeyPropertiesPath)"
  Write-Host "Keystore path: $(if ($null -ne $signing.StoreFilePath) { $signing.StoreFilePath } else { '<not configured>' })"
  Write-Host "Keystore exists: $($signing.KeystoreExists)"
  Write-Host "Key alias: $(if ($null -ne $signing.KeyAlias) { $signing.KeyAlias } else { '<not configured>' })"
  Write-Host "Keytool path: $(if ($null -ne $signing.KeytoolPath) { $signing.KeytoolPath } else { '<not found>' })"
  Write-Host "Signing verification: $($signing.VerificationStatus)"
  Write-Host "Signing verification detail: $($signing.VerificationDetails)"
  Write-Host "Artifact folder: $releaseFolder"
  Write-Host "Preflight verdict: $preflightVerdict"

  if ($PreflightOnly) {
    New-Item -ItemType Directory -Force -Path $releaseFolder | Out-Null

    $preflightTextPath = Join-Path $releaseFolder "BusinessHub-Mobile-$resolvedReleaseTag.preflight.txt"
    $preflightJsonPath = Join-Path $releaseFolder "BusinessHub-Mobile-$resolvedReleaseTag.preflight.json"
    $preflightText = @(
      "Tag: $resolvedReleaseTag",
      "Tag Status: $releaseTagStatus",
      "Version: $($metadata.MarketingVersion)",
      "Build: $($metadata.BuildNumber)",
      "Channel: $ReleaseChannel",
      "Pilot Scope: $PilotScope",
      "Commit: $commitSha",
      "Short SHA: $shortSha",
      "Resolved Flutter: $resolvedFlutterLabel",
      "Resolved Dart: $resolvedDartLabel",
      "Expected APK: $expectedReleaseApkPath",
      "Signing Mode: $($signing.SigningMode)",
      "Signing Source: $($signing.SigningSource)",
      "Keystore Path: $(if ($null -ne $signing.StoreFilePath) { $signing.StoreFilePath } else { '<not configured>' })",
      "Keystore Exists: $($signing.KeystoreExists)",
      "Key Alias: $(if ($null -ne $signing.KeyAlias) { $signing.KeyAlias } else { '<not configured>' })",
      "Keytool Path: $(if ($null -ne $signing.KeytoolPath) { $signing.KeytoolPath } else { '<not found>' })",
      "Signing Verification: $($signing.VerificationStatus)",
      "Signing Verification Detail: $($signing.VerificationDetails)",
      "Preflight Verdict: $preflightVerdict",
      "Generated At (UTC): $([DateTime]::UtcNow.ToString('o'))"
    ) -join [Environment]::NewLine
    Set-Content -Path $preflightTextPath -Value $preflightText -Encoding utf8

    $preflightJson = @{
      tag = $resolvedReleaseTag
      tag_status = $releaseTagStatus
      version = $metadata.MarketingVersion
      build_number = $metadata.BuildNumber
      channel = $ReleaseChannel
      pilot_scope = $PilotScope
      commit = $commitSha
      short_sha = $shortSha
      resolved_flutter = $resolvedFlutterLabel
      resolved_dart = $resolvedDartLabel
      expected_apk = $expectedReleaseApkPath
      signing_mode = $signing.SigningMode
      signing_source = $signing.SigningSource
      keystore_path = $signing.StoreFilePath
      keystore_exists = $signing.KeystoreExists
      key_alias = $signing.KeyAlias
      keytool_path = $signing.KeytoolPath
      signing_verification = $signing.VerificationStatus
      signing_verification_detail = $signing.VerificationDetails
      preflight_verdict = $preflightVerdict
      generated_at_utc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 4
    Set-Content -Path $preflightJsonPath -Value $preflightJson -Encoding utf8

    Write-Host "Preflight text: $preflightTextPath"
    Write-Host "Preflight JSON: $preflightJsonPath"
  }

  if ($null -eq $flutterExecutable) {
    Show-ResolveHelp
    exit 1
  }

  if ($Doctor) {
    Invoke-Checked -FilePath $flutterExecutable -Arguments @('--version') -Label 'Flutter version'
  }

  if ($preflightVerdict -eq 'blocked') {
    exit 1
  }

  exit 0
}

if ($null -eq $flutterExecutable) {
  Show-ResolveHelp
  exit 1
}

if (-not (Test-Path $appDir)) {
  throw "Flutter app directory not found: $appDir"
}

$envMap = @{
  'BUSINESS_HUB_RELEASE_CHANNEL' = $ReleaseChannel
  'BUSINESS_HUB_RELEASE_SHA' = $shortSha
  'BUSINESS_HUB_RELEASE_TAG' = $resolvedReleaseTag
  'BUSINESS_HUB_PILOT_SCOPE' = $PilotScope
}

Push-Location $appDir
try {
  if (-not $signing.HasSigning) {
    Write-Host ''
    Write-Host 'Warning: release signing is not configured. Local build may fall back to debug signing.' -ForegroundColor Yellow
    Write-Host "Expected key properties: $($signing.KeyPropertiesPath)" -ForegroundColor Yellow
  }

  if (-not $SkipPubGet) {
    Invoke-Checked -FilePath $flutterExecutable -Arguments @('pub', 'get') -Label 'flutter pub get'
  }

  if (-not $SkipCodegen) {
    if ($null -ne $dartExecutable) {
      Invoke-Checked -FilePath $dartExecutable -Arguments @('run', 'build_runner', 'build', '--delete-conflicting-outputs') -Label 'dart run build_runner'
    } else {
      Invoke-Checked -FilePath $flutterExecutable -Arguments @('pub', 'run', 'build_runner', 'build', '--delete-conflicting-outputs') -Label 'flutter pub run build_runner'
    }
  }

  if (-not $SkipAnalyze) {
    Invoke-Checked -FilePath $flutterExecutable -Arguments @('analyze') -Label 'flutter analyze'
  }

  if (-not $SkipTest) {
    Invoke-Checked -FilePath $flutterExecutable -Arguments @('test') -Label 'flutter test'
  }

  if (-not $SkipBuild) {
    $buildArgs = @(
      'build',
      'apk',
      '--release',
      # Pinned, not left to the default in backend_api_client.dart. The URL a
      # shop's phone talks to is a release decision, and it should be visible
      # in the build command rather than buried in source. Every installed
      # build already carries this hostname, so it does not change without a
      # plan for the phones that cannot be updated remotely.
      "--dart-define=BUSINESS_HUB_API_BASE_URL=$ApiBaseUrl",
      "--dart-define=BUSINESS_HUB_RELEASE_CHANNEL=$ReleaseChannel",
      "--dart-define=BUSINESS_HUB_RELEASE_SHA=$shortSha",
      "--dart-define=BUSINESS_HUB_RELEASE_TAG=$resolvedReleaseTag",
      "--dart-define=BUSINESS_HUB_PILOT_SCOPE=$PilotScope"
    )
    Invoke-Checked -FilePath $flutterExecutable -Arguments $buildArgs -Label 'flutter build apk Release' -ExtraEnvironment $envMap
  }

  $sourceApk = Join-Path $appDir 'build\app\outputs\flutter-apk\app-release.apk'
  if (-not (Test-Path $sourceApk)) {
    throw "Release APK not found: $sourceApk"
  }

  $releaseFolder = Join-Path $repoRoot (Join-Path $ArtifactRoot $resolvedReleaseTag)
  New-Item -ItemType Directory -Force -Path $releaseFolder | Out-Null

  $apkName = "BusinessHub-Mobile-$resolvedReleaseTag.apk"
  $apkTarget = Join-Path $releaseFolder $apkName
  Copy-Item -Path $sourceApk -Destination $apkTarget -Force

  $checksum = (Get-FileHash -Path $apkTarget -Algorithm SHA256).Hash.ToLowerInvariant()
  $checksumPath = "$apkTarget.sha256"
  Set-Content -Path $checksumPath -Value "$checksum  $apkName" -Encoding utf8

  $manifestTextPath = Join-Path $releaseFolder "BusinessHub-Mobile-$resolvedReleaseTag.manifest.txt"
  $manifestJsonPath = Join-Path $releaseFolder "BusinessHub-Mobile-$resolvedReleaseTag.manifest.json"
  $handoffPath = Join-Path $releaseFolder "BusinessHub-Mobile-$resolvedReleaseTag.handoff.md"

  $manifestText = @(
    "Tag: $resolvedReleaseTag",
    "Version: $($metadata.MarketingVersion)",
    "Build: $($metadata.BuildNumber)",
    "Channel: $ReleaseChannel",
    "Pilot Scope: $PilotScope",
    "Commit: $commitSha",
    "Short SHA: $shortSha",
    "APK: $apkName",
    "SHA256: $checksum",
    "Signing Mode: $($signing.SigningMode)",
    "Signing Source: $($signing.SigningSource)",
    "Generated At (UTC): $([DateTime]::UtcNow.ToString('o'))"
  ) -join [Environment]::NewLine
  Set-Content -Path $manifestTextPath -Value $manifestText -Encoding utf8

  $manifestJson = @{
    tag = $resolvedReleaseTag
    version = $metadata.MarketingVersion
    build_number = $metadata.BuildNumber
    channel = $ReleaseChannel
    pilot_scope = $PilotScope
    commit = $commitSha
    short_sha = $shortSha
    apk_name = $apkName
    apk_sha256 = $checksum
    signing_ready = $signing.HasSigning
    signing_mode = $signing.SigningMode
    signing_source = $signing.SigningSource
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
  } | ConvertTo-Json -Depth 4
  Set-Content -Path $manifestJsonPath -Value $manifestJson -Encoding utf8

  $handoffMarkdown = New-HandoffMarkdown `
    -Tag $resolvedReleaseTag `
    -Version $metadata.MarketingVersion `
    -BuildNumber $metadata.BuildNumber `
    -Channel $ReleaseChannel `
    -PilotScopeLabel $PilotScope `
    -CommitSha $commitSha `
    -ShortSha $shortSha `
    -ApkName $apkName `
    -Checksum $checksum `
    -SigningMode $signing.SigningMode `
    -SigningSource $signing.SigningSource
  Set-Content -Path $handoffPath -Value $handoffMarkdown -Encoding utf8

  Write-Host ''
  Write-Host 'Business Hub mobile local release package completed successfully.' -ForegroundColor Green
  Write-Host "Artifact folder: $releaseFolder"
  Write-Host "APK: $apkTarget"
  Write-Host "Checksum: $checksum"
} finally {
  Pop-Location
}
