# Finds the Derail Valley install directory and prints it to stdout.

$ErrorActionPreference = 'Stop'

function Get-SteamRoots {
    $roots = @()

    $reg = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue
    if ($reg -and $reg.SteamPath) {
        # the registry stores the path with forward slashes
        $roots += $reg.SteamPath.Replace('/', '\')
    }

    $steam = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Steam'
    if (Test-Path -LiteralPath $steam) {
        $roots += $steam
    }

    return @($roots | Select-Object -Unique)
}

function Get-LibraryRoots {
    param([string[]] $SteamRoots)

    $libs = @()
    foreach ($root in $SteamRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        $libs += $root

        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            $content = Get-Content -LiteralPath $vdf -Raw
            foreach ($match in [regex]::Matches($content, '"path"\s+"([^"]+)"')) {
                # VDF escapes path separators as \\
                $libs += $match.Groups[1].Value.Replace('\\', '\')
            }
        }
    }

    return @($libs | Select-Object -Unique)
}

foreach ($lib in Get-LibraryRoots (Get-SteamRoots)) {
    $candidate = Join-Path $lib 'steamapps\common\Derail Valley'

    # the build consumes the Managed assemblies directly, so validate those
    if (Test-Path -LiteralPath (Join-Path $candidate 'DerailValley_Data\Managed\Assembly-CSharp.dll')) {
        Write-Output (Resolve-Path -LiteralPath $candidate).ProviderPath
        exit 0
    }
}

exit 0
