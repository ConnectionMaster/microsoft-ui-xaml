[CmdLetBinding()]
Param(
    [string]$BuildOutput,
    [string]$OutputDir,
    [string]$VersionOverride,
    [string]$Subversion = "",
    [string]$prereleaseversion,
    [string]$BuildFlavor = "release",
    [string]$BuildArch = "x86",
    [switch]$NoDeleteTemp,
    [switch]$SkipFrameworkPackage
)

#
# Version is read from the VERSION file.
#

$scriptDirectory = $script:MyInvocation.MyCommand.Path | Split-Path -Parent

pushd $scriptDirectory

if (!$OutputDir)
{
    $OutputDir = $scriptDirectory
}

if (!$BuildOutput)
{
    Write-Host "Must specify BuildOutput parameter" -ForegroundColor Red
    Exit 1
}

if (!$env:NUGETCMD) {

    cmd /c where /Q nuget.exe
    if ($lastexitcode -ne 0) {
        Write-Host "nuget not found on path. Either add it to path or set NUGETCMD environment variable." -ForegroundColor Red
        Exit 1
    }

    $env:NUGETCMD = "nuget.exe"
}

if ($VersionOverride)
{
    $version = $VersionOverride
}
else
{
    [xml]$customProps = (Get-Content ..\..\custom.props)
    $versionMajor = $customProps.GetElementsByTagName("VersionMajor").'#text'
    $versionMinor = $customProps.GetElementsByTagName("VersionMinor").'#text'

    if ((!$versionMajor) -or (!$versionMinor))
    {
        Write-Error "Expected VersionMajor and VersionMinor tags to be in custom.props file"
        Exit 1
    }

    $version = "$versionMajor.$versionMinor"
    
    $pstZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Pacific Standard Time")
    $pstTime = [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $pstZone)
    $version += "." + ($pstTime).ToString("yyMMdd") + "$subversion"

    Write-Verbose "Version = $version"
}

if ($prereleaseversion)
{
    $version = "$version-$prereleaseversion"
}

if (!(Test-Path $OutputDir)) { mkdir $OutputDir }

$nupkgtitle = "Microsoft.UI.Xaml"
if($env:BuildLeanMuxForTheStoreApp -eq "true")
{
    $nupkgtitle = "Microsoft.UI.Xaml-Slim"
}

function New-TemporaryDirectory {
    $parent = [System.IO.Path]::GetTempPath()
    $name = [System.IO.Path]::GetRandomFileName()
    New-Item -ItemType Directory -Path (Join-Path $parent $name)
}

function Copy-IntoNewDirectory {
    Param($source, $destinationDir, [switch]$IfExists = $false)

    if ((-not $IfExists) -or (Test-Path $source))
    {
        Write-Verbose "Copy from '$source' to '$destinationDir'"
        if (-not (Test-Path $destinationDir))
        {
            $ignore = New-Item -ItemType Directory $destinationDir
        }
        Copy-Item -Recurse -Force $source $destinationDir
    }
}

$TempDir = New-TemporaryDirectory

Write-Verbose "TempDir = $($TempDir.FullName)"

# nuspecs can't have conditionals so copy the contents of the runtime folder over, skipping arm64 if those sources aren't
# created in this particular build.
$runtimesDir = "$($TempDir.FullName)\runtimes"
$toolsDir = "$($TempDir.FullName)\tools"

Copy-IntoNewDirectory -IfExists $BuildOutput\release\x86\Microsoft.UI.Xaml\Microsoft.UI.Xaml.dll "$runtimesDir\win10-x86\native"
Copy-IntoNewDirectory -IfExists $BuildOutput\release\x86\Microsoft.UI.Xaml\Microsoft.UI.Xaml.pri "$runtimesDir\win10-x86\native"
Copy-IntoNewDirectory -IfExists ..\..\dev\Materials\Acrylic\Assets\NoiseAsset_256x256_PNG.png "$runtimesDir\win10-x86\native\Microsoft.UI.Xaml\Assets"
Copy-IntoNewDirectory -IfExists $BuildOutput\release\x64\Microsoft.UI.Xaml\Microsoft.UI.Xaml.dll "$runtimesDir\win10-x64\native"
Copy-IntoNewDirectory -IfExists $BuildOutput\release\x64\Microsoft.UI.Xaml\Microsoft.UI.Xaml.pri "$runtimesDir\win10-x64\native"
Copy-IntoNewDirectory -IfExists ..\..\dev\Materials\Acrylic\Assets\NoiseAsset_256x256_PNG.png "$runtimesDir\win10-x64\native\Microsoft.UI.Xaml\Assets"
Copy-IntoNewDirectory -IfExists $BuildOutput\release\arm\Microsoft.UI.Xaml\Microsoft.UI.Xaml.dll "$runtimesDir\win10-arm\native"
Copy-IntoNewDirectory -IfExists $BuildOutput\release\arm\Microsoft.UI.Xaml\Microsoft.UI.Xaml.pri "$runtimesDir\win10-arm\native"
Copy-IntoNewDirectory -IfExists ..\..\dev\Materials\Acrylic\Assets\NoiseAsset_256x256_PNG.png "$runtimesDir\win10-arm\native\Microsoft.UI.Xaml\Assets"
Copy-IntoNewDirectory -IfExists $BuildOutput\release\arm64\Microsoft.UI.Xaml\Microsoft.UI.Xaml.dll "$runtimesDir\win10-arm64\native"
Copy-IntoNewDirectory -IfExists $BuildOutput\release\arm64\Microsoft.UI.Xaml\Microsoft.UI.Xaml.pri "$runtimesDir\win10-arm64\native"
Copy-IntoNewDirectory -IfExists ..\..\dev\Materials\Acrylic\Assets\NoiseAsset_256x256_PNG.png "$runtimesDir\win10-arm64\native\Microsoft.UI.Xaml\Assets"

$CommonNugetArgs = "-properties `"BuildOutput=$BuildOutput``;ID=$nupkgtitle``;RUNTIMESDIR=$runtimesDir`;TOOLSDIR=$toolsDir`;BUILDFLAVOR=$($BuildFlavor)`;BUILDARCH=$($BuildArch)`""

$NugetArgs = "$CommonNugetArgs -OutputDirectory $OutputDir"

$NugetCmdLine = "$env:NUGETCMD pack MUXControls.nuspec $NugetArgs -version $version"
Write-Host $NugetCmdLine
Invoke-Expression $NugetCmdLine
if ($lastexitcode -ne 0)
{
    Exit $lastexitcode; 
    Write-Host "Nuget returned $lastexitcode"
}

if(-not $SkipFrameworkPackage)
{
    # Nuget package with framework package encapsulation

    $NugetArgs = "$CommonNugetArgs -OutputDirectory $OutputDir\FrameworkPackage"

    Copy-IntoNewDirectory -IfExists $BuildOutput\$BuildFlavor\x86\FrameworkPackage\Microsoft.UI.Xaml.*.appx "$toolsDir\AppX\x86\Release"
    Copy-IntoNewDirectory -IfExists $BuildOutput\$BuildFlavor\x64\FrameworkPackage\Microsoft.UI.Xaml.*.appx "$toolsDir\AppX\x64\Release"
    Copy-IntoNewDirectory -IfExists $BuildOutput\$BuildFlavor\arm\FrameworkPackage\Microsoft.UI.Xaml.*.appx "$toolsDir\AppX\arm\Release"
    Copy-IntoNewDirectory -IfExists $BuildOutput\$BuildFlavor\arm64\FrameworkPackage\Microsoft.UI.Xaml.*.appx "$toolsDir\AppX\arm64\Release"
    # Currently we don't have a separate Debug package that we want to ship to customers
    #Copy-IntoNewDirectory -IfExists $BuildOutput\debug\x86\FrameworkPackage\Microsoft.UI.Xaml.Debug.*.appx "$toolsDir\AppX\x86\Debug"
    #Copy-IntoNewDirectory -IfExists $BuildOutput\debug\x64\FrameworkPackage\Microsoft.UI.Xaml.Debug.*.appx "$toolsDir\AppX\x64\Debug"
    #Copy-IntoNewDirectory -IfExists $BuildOutput\debug\arm\FrameworkPackage\Microsoft.UI.Xaml.Debug.*.appx "$toolsDir\AppX\arm\Debug"
    #Copy-IntoNewDirectory -IfExists $BuildOutput\debug\arm64\FrameworkPackage\Microsoft.UI.Xaml.Debug.*.appx "$toolsDir\AppX\arm64\Debug"

    $NugetCmdLine = "$env:NUGETCMD pack MUXControlsFrameworkPackage.nuspec $NugetArgs -version $version"
    Write-Host $NugetCmdLine
    Invoke-Expression $NugetCmdLine
    if ($lastexitcode -ne 0)
    {
        Exit $lastexitcode; 
        Write-Host "Nuget returned $lastexitcode"
    }
}

if (-not $NoDeleteTemp)
{
    Remove-Item -Recurse -Force "$($TempDir.FullName)"
}

popd