# Assembles the community profiles into a single TurboConfig.xml and packages
# them, together with the mod's info.json, into a mod release zip.
param(
    [string]$GameDir = "",
    [switch]$Install
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# Compress-Archive emits OS path separators depending on the PowerShell version,
# so use the .NET API and force forward slashes
function New-ModZip {
    param(
        [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    if (-not ('System.IO.Compression.ZipFile' -as [type])) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    }

    $source = (Resolve-Path -LiteralPath $SourceDirectory).Path
    $rootName = Split-Path -Leaf $source

    if (Test-Path -LiteralPath $DestinationPath) { Remove-Item -LiteralPath $DestinationPath -Force }

    $archive = [System.IO.Compression.ZipFile]::Open($DestinationPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in (Get-ChildItem -LiteralPath $source -Recurse -File)) {
            $relative = $file.FullName.Substring($source.Length + 1).Replace('\', '/')
            $entry = $archive.CreateEntry("$rootName/$relative", [System.IO.Compression.CompressionLevel]::Optimal)
            $entryStream = $entry.Open()
            try {
                $input = [System.IO.File]::OpenRead($file.FullName)
                try { $input.CopyTo($entryStream) } finally { $input.Dispose() }
            } finally {
                $entryStream.Dispose()
            }
        }
    } finally {
        $archive.Dispose()
    }
}

# Reads each <LocoProfile> fragment in $Files and writes a single TurboConfig.xml
# to $Destination, failing on malformed fragments or duplicate livery ids.
function New-TurboConfig {
    param(
        [System.IO.FileInfo[]] $Files,
        [string] $Destination
    )

    $document = New-Object System.Xml.XmlDocument
    $document.AppendChild($document.CreateXmlDeclaration("1.0", "utf-8", $null)) | Out-Null
    $config = $document.CreateElement("TurboConfig")
    $document.AppendChild($config) | Out-Null
    $profiles = $document.CreateElement("LocoProfiles")
    $config.AppendChild($profiles) | Out-Null

    $seen = @{}
    foreach ($file in $Files) {
        $source = New-Object System.Xml.XmlDocument
        try {
            $source.Load($file.FullName)
        } catch {
            Write-Error "Could not read '$($file.Name)': $($_.Exception.Message)"
            exit 1
        }

        $element = $source.DocumentElement
        if ($null -eq $element -or $element.Name -ne "LocoProfile") {
            Write-Error "'$($file.Name)' is not a <LocoProfile> fragment"
            exit 1
        }

        $livery = $element.SelectSingleNode("LiveryId")
        if ($null -eq $livery -or [string]::IsNullOrWhiteSpace($livery.InnerText)) {
            Write-Error "'$($file.Name)' has no LiveryId"
            exit 1
        }

        if ($seen.ContainsKey($livery.InnerText)) {
            Write-Error "Duplicate profile for '$($livery.InnerText)' in '$($file.Name)' and '$($seen[$livery.InnerText])'"
            exit 1
        }
        $seen[$livery.InnerText] = $file.Name

        $profiles.AppendChild($document.ImportNode($element, $true)) | Out-Null
        Write-Host "added $($livery.InnerText) from $($file.Name)"
    }

    # write without a BOM, matching the game's own TurboConfig.xml handling
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)

    $writer = [System.Xml.XmlWriter]::Create($Destination, $settings)
    try {
        $document.Save($writer)
    } finally {
        $writer.Dispose()
    }
}

$profilesDir = Join-Path $root "profiles"
$profileFiles = @(Get-ChildItem -LiteralPath $profilesDir -Filter "*.xml" -File | Sort-Object Name)
if ($profileFiles.Count -eq 0) {
    Write-Error "No profiles found in '$profilesDir'"
    exit 1
}

$stage = "$root\dist\stage\TurboTurboContrib"
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item $stage -ItemType Directory -Force | Out-Null

New-TurboConfig -Files $profileFiles -Destination (Join-Path $stage "TurboConfig.xml")

Copy-Item "$root\info.json" $stage
Copy-Item "$root\include\README.md" $stage

$stagedInfo = Join-Path $stage "info.json"
$version = & "$root\scripts\StampModVersion.ps1" -InfoJson $stagedInfo

$zip = "$root\dist\TurboTurboContrib-$version.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
New-ModZip -SourceDirectory $stage -DestinationPath $zip
Remove-Item "$root\dist\stage" -Recurse -Force

Write-Host "packaged: $zip"

if ($Install) {
    if (-not $GameDir) {
        $GameDir = & "$root\scripts\FindGameDir.ps1"
    }
    if (-not $GameDir -or -not (Test-Path -LiteralPath $GameDir)) {
        Write-Error "Could not locate Derail Valley. Pass the install path: .\build.ps1 -Install -GameDir 'C:\path\to\Derail Valley'"
        exit 1
    }

    $modsDir = Join-Path $GameDir "Mods"
    Expand-Archive -Path $zip -DestinationPath $modsDir -Force
    Write-Host "installed to: $(Join-Path $modsDir 'TurboTurboContrib')"
}
