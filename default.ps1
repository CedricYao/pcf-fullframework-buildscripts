$script:project_config = "Release"
properties {
  Framework '4.6'
  $domain = "yourdomain.google.com"
  $base_dir = resolve-path .
  $project_dir = "$base_dir\src\$project_name"
  $build_dir = ".\build-artifacts"
  $project_file = "$project_dir\$project_name.csproj"
  $solution_file = "$base_dir\$solution_name.sln"
  $test_dir = "$base_dir\test"
  $packages_dir = "$base_dir\packages"
  $publish_dir = "$base_dir\publish"
  $output_dir = "$build_dir"
  $published_website = "$base_dir\src\$project_name\bin"
  $nuget_exe = "$base_dir\.nuget\nuget.exe"
  $version = get_version
  $date = Get-Date 
  $ReleaseNumber =  $version
  
  Write-Host "**********************************************************************"
  Write-Host "Release Number: $ReleaseNumber"
  Write-Host "**********************************************************************"
  
  $packageId = if ($env:package_id) { $env:package_id } else { "$solution_name" }
}

#These are aliases for other build tasks. They typically are named after the camelcase letters (rd = Rebuild Databases)
task default -depends InitialPrivateBuild
task dev -depends DeveloperBuild
task ci -depends IntegrationBuildv2
task ? -depends help
task test -depends RunUnitTests
task pp -depends Publish-Push
task scan -depends ScanBuild

task emitProperties {
  Write-Host "solution_name=$solution_name"
  Write-Host "domain=$domain"
  Write-Host "base_dir=$base_dir"
  Write-Host "build_dir=$build_dir"
  Write-Host "project_dir=$project_dir"
  Write-Host "project_file=$project_file"
  Write-Host "solution_file=$solution_file"
  Write-Host "test_dir=$test_dir"
  Write-Host "packages_dir=$packages_dir"
  Write-Host "publish_dir=$publish_dir"
  Write-Host "output_dir=$output_dir"
  Write-Host "published_website=$published_website"
}

task help {
   Write-Help-Header
   Write-Help-Section-Header "Comprehensive Building"
   Write-Help-For-Alias "(default)" "Intended for first build or when you want a fresh, clean local copy"
   Write-Help-For-Alias "dev" "Optimized for local dev"
   Write-Help-For-Alias "ci" "Continuous Integration build (long and thorough) with packaging"
   Write-Help-For-Alias "test" "Run local test"
   Write-Help-For-Alias "pnp" "Intended for pushing to PCF without webpack"
   Write-Help-For-Alias "pp" "Intended for pushing to PCF. Will run webpack without tests"
   Write-Help-For-Alias "scan" "Intended for fortify code scan"
   Write-Help-Footer
   exit 0
}

#These are the actual build tasks. They should be Pascal case by convention
task InitialPrivateBuild -depends Clean, Compile
task RunUnitTests -depends UnitTest
task DeveloperBuild -depends SetDebugBuild, Clean, Restore, Compile
task ScanBuild -depends SetDebugBuild, Clean, Restore, Compile,  Publish, RemoveDevelopmentConfig
task IntegrationBuildv1 -depends emitProperties, SetReleaseBuild, Clean, Compile, Publish
task IntegrationBuildv2 -depends emitProperties, SetReleaseBuild, Clean, Publish_MSWebDeploy_Package
task Publish-Push -depends SetReleaseBuild, Clean, Compile, UnitTest, Publish, push
task SetDebugBuild {
    $script:project_config = "Debug"
}

task SetReleaseBuild {
    $script:project_config = "Release"
}

task SetVersion {
    set-content $base_dir\CommonAssemblyInfo.cs "// Generated file - do not modify",
            "using System.Reflection;",
            "[assembly: AssemblyVersion(`"$version`")]",
            "[assembly: AssemblyFileVersion(`"$version`")]",
            "[assembly: AssemblyInformationalVersion(`"$version`")]"
    Write-Host "Using version#: $version"
}

task UnitTest {
   Write-Host "******************* Now running Unit Tests *********************"
   $vstest_exe = get_vstest_executable($packages_dir)
   Push-Location $base_dir
   $test_assemblies = @((Get-ChildItem -Recurse -Filter "*Tests.dll" | Where-Object {$_.Directory -like '*build-artifacts*'}).FullName) -join ' '
   Write-Host "Executing tests on the following assemblies: $test_assemblies"
   Start-Process -FilePath $vstest_exe -ArgumentList $test_assemblies ,"/Parallel" -NoNewWindow -Wait
   Pop-Location
}

task Clean {
    Get-ChildItem -inc build-artifacts -rec | Remove-Item -rec -Force
    if (Test-Path $publish_dir) {
        delete_directory $publish_dir
    }
    Write-Host "******************* Now Cleaning the Solution *********************"
    exec { msbuild /t:clean /v:q /p:Configuration=$project_config /p:Platform="Any CPU" $solution_file }
}

task RemoveConnectionString {
    $webConfigPath = "$base_dir\$project_name\build-artifacts\_PublishedWebsites\$project_name\Web.config"
    $webConfig = [xml](Get-content $webConfigPath)
    $webConfig.configuration.connectionStrings.ChildNodes.SetAttribute("connectionString", "")
    $webConfig.Save($webConfigPath)
}

task Restore -depends Clean{
    exec { & $nuget_exe restore $solution_file  }
}

task Compile -depends Clean {
    exec { msbuild.exe /t:build /v:q /p:Configuration=$project_config /p:Platform="Any CPU" /nologo $solution_file }
}

task Publish_MSWebDeploy_Package {
    if (Test-Path $publish_dir) {
        delete_directory $publish_dir
    }
    exec { & $nuget_exe restore $solution_file }
    exec { msbuild.exe /t:build /v:q /nologo $project_file /p:Configuration=$project_config /p:Platform="AnyCPU" /p:CreatePackageOnPublish=True /p:PublishProfileRootFolder="$PSScriptRoot/src/Folders/Properties/PublishProfiles" /p:PublishProfile="Release" /p:PackageLocation=$publish_dir /p:DeployOnBuild=True }
}

task Publish {
    Write-Host "Publishing to $publish_dir *****"
    if (!(Test-Path $publish_dir)) {
        New-Item -ItemType Directory -Force -Path $publish_dir
    }
    Copy-Item -Path $published_website\* -Destination $publish_dir -recurse -Force
}

task RemoveDevelopmentConfig {
    Write-Host "Removing development configutation files from $publish_dir *****"
    delete_file $publish_dir\appSettings.*.json
}

task Push {
    Push-Location $publish_dir
    exec { & "cf" push -d $domain}
    Pop-Location
}

# -------------------------------------------------------------------------------------------------------------
# generalized functions for Help Section
# --------------------------------------------------------------------------------------------------------------

function Write-Help-Header($description) {
   Write-Host ""
   Write-Host "********************************" -foregroundcolor DarkGreen -nonewline;
   Write-Host " HELP " -foregroundcolor Green  -nonewline;
   Write-Host "********************************"  -foregroundcolor DarkGreen
   Write-Host ""
   Write-Host "This build script has the following common build " -nonewline;
   Write-Host "task " -foregroundcolor Green -nonewline;
   Write-Host "aliases set up:"
}

function Write-Help-Footer($description) {
   Write-Host ""
   Write-Host " For a complete list of build tasks, view default.ps1."
   Write-Host ""
   Write-Host "**********************************************************************" -foregroundcolor DarkGreen
}

function Write-Help-Section-Header($description) {
   Write-Host ""
   Write-Host " $description" -foregroundcolor DarkGreen
}

function Write-Help-For-Alias($alias,$description) {
   Write-Host "  > " -nonewline;
   Write-Host "$alias" -foregroundcolor Green -nonewline;
   Write-Host " = " -nonewline;
   Write-Host "$description"
}

# -------------------------------------------------------------------------------------------------------------
# generalized functions
# --------------------------------------------------------------------------------------------------------------

function global:delete_file($file) {
    if($file) { remove-item $file -force -ErrorAction SilentlyContinue | out-null }
}

function global:delete_directory($directory_name)
{
  rd $directory_name -recurse -force  -ErrorAction SilentlyContinue | out-null
}

function global:delete_files($directory_name) {
    Get-ChildItem -Path $directory_name -Include * -File -Recurse | foreach { $_.Delete()}
}

function global:get_vstest_executable($lookin_path) {
    $vstest_exe = exec { & "c:\\Program Files (x86)\\Microsoft Visual Studio\\Installer\\vswhere.exe"  -latest -products * -requires Microsoft.VisualStudio.PackageGroup.TestTools.Core -property installationPath}
    $vstest_exe = join-path $vstest_exe 'Common7\IDE\CommonExtensions\Microsoft\TestWindow\vstest.console.exe'
    return $vstest_exe
}

function global:get_version(){
    Write-Host "******************* Getting the Version Number ********************"
    $version = get-content "$base_Dir\..\version\number" -ErrorAction SilentlyContinue
    if ($version -eq $null) {
        Write-Host "--------- No version found defaulting to 1.0.0 --------------------" -foregroundcolor Red
        $version = '1.0.0'
    }
    return $version
}

