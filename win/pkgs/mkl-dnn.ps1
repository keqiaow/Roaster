#Requires -RunAsAdministrator

Get-Content "$PSScriptRoot/utils/re-entry.ps1" -Raw | Invoke-Expression
$ErrorActionPreference="Stop"

. "$PSScriptRoot/env/mirror.ps1"
. "$PSScriptRoot/env/toolchain.ps1"

pushd ${Env:SCRATCH}
$repo="${Env:GIT_MIRROR}/oneapi-src/oneDNN.git"
$proj="$($repo -replace '.*/','' -replace '.git$','')"
$root="${Env:SCRATCH}/$proj"

rm -Force -Recurse -ErrorAction SilentlyContinue -WarningAction SilentlyContinue "$root"
if (Test-Path "$root")
{
    echo "Failed to remove `"$root`""
    Exit 1
}

$latest_ver="v" + $($(git ls-remote --tags "$repo") -match '.*refs/tags/v[0-9\.]*$' -replace '.*refs/tags/v','' | sort {[Version]$_})[-1]

git clone --depth 1 --recursive --single-branch -b "$latest_ver" "$repo"
pushd "$root"

# Copy MKL's environment variables from ".bat" file to PowerShell.
Invoke-Expression $($(cmd /C "`"${Env:ProgramFiles(x86)}/IntelSWTools/compilers_and_libraries/windows/mkl/bin/mklvars.bat`" intel64 lp64 vs2017 & set") -Match '^MKL(_|ROOT)' -Replace '^','${Env:' -Replace '=','}="' -Replace '$','"' | Out-String)
Invoke-Expression $($(cmd /C "`"${Env:ProgramFiles(x86)}/IntelSWTools/compilers_and_libraries/windows/mkl/bin/mklvars.bat`" intel64 lp64 vs2017 & set") -Match '^LIB' -Replace '^','${Env:' -Replace '=','}="' -Replace '$','"' | Out-String)
Invoke-Expression $($(cmd /C "`"${Env:ProgramFiles(x86)}/IntelSWTools/compilers_and_libraries/windows/mkl/bin/mklvars.bat`" intel64 lp64 vs2017 & set") -Match '^CPATH' -Replace '^','${Env:' -Replace '=','}="' -Replace '$','"' | Out-String)
Invoke-Expression $($(cmd /C "`"${Env:ProgramFiles(x86)}/IntelSWTools/compilers_and_libraries/windows/mkl/bin/mklvars.bat`" intel64 lp64 vs2017 & set") -Match '^INCLUDE' -Replace '^','${Env:' -Replace '=','}="' -Replace '$','"' | Out-String)

mkdir build
pushd build

cmake                                                                   `
    -DCMAKE_BUILD_TYPE=Release                                          `
    -DCMAKE_C_FLAGS="/GL /MP /Zi /arch:AVX"                             `
    -DCMAKE_CXX_FLAGS="/EHsc /GL /MP /Zi /arch:AVX"                     `
    -DCMAKE_EXE_LINKER_FLAGS="/DEBUG:FASTLINK /LTCG:incremental"        `
    -DCMAKE_INSTALL_PREFIX="${Env:ProgramFiles}/oneDNN"                 `
    -DCMAKE_PDB_OUTPUT_DIRECTORY="${PWD}/pdb"                           `
    -DCMAKE_SHARED_LINKER_FLAGS="/DEBUG:FASTLINK /LTCG:incremental"     `
    -DCMAKE_STATIC_LINKER_FLAGS="/LTCG:incremental"                     `
    -DDNNL_CPU_RUNTIME=OMP                                              `
    -DDNNL_LIBRARY_TYPE=SHARED                                          `
    -DMKLDNN_CPU_RUNTIME=OMP                                            `
    -DMKLDNN_LIBRARY_TYPE=SHARED                                        `
    -G"Ninja"                                                           `
    ..

# Some D9025 warnings about /Ob overriding /O2 are expected.
# - https://github.com/oneapi-src/oneDNN/blob/ab549349fc473f35e9bc41ed4d6bff5b1eaabfe0/src/cpu/x64/CMakeLists.txt#L56-L65
cmake --build .
if (-Not $?)
{
    echo "Failed to build."
    echo "Retry with best-effort for logging."
    echo "You may Ctrl-C this if you don't need the log file."
    cmake --build . -- -k0
    cmake --build . 2>&1 | tee ${Env:SCRATCH}/${proj}.log
    exit 1
}

$ErrorActionPreference="SilentlyContinue"
# cmake --build . --target test
# if (-Not $?)
# {
#     echo "Oops! Expect to pass all tests."
#     exit 1
# }
$ErrorActionPreference="Stop"

rm -Force -Recurse -ErrorAction SilentlyContinue -WarningAction SilentlyContinue "${Env:ProgramFiles}/oneDNN"
cmake --build . --target install
cmd /c xcopy    /i /f /y "pdb\*.pdb" "${Env:ProgramFiles}\oneDNN\lib"
Get-ChildItem "${Env:ProgramFiles}/oneDNN" -Filter '*.dll' -Recurse | Foreach-Object { New-Item -Force -ItemType SymbolicLink -Path "${Env:SystemRoot}\System32\$_" -Value $_.FullName }

popd
popd
rm -Force -Recurse "$root"
popd
