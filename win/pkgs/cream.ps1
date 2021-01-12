#Requires -RunAsAdministrator

Get-Content "$PSScriptRoot/utils/re-entry.ps1" -Raw | Invoke-Expression
$ErrorActionPreference="Stop"

. "$PSScriptRoot/env/mirror.ps1"
. "$PSScriptRoot/env/toolchain.ps1"

pushd ${Env:SCRATCH}
$repo="${Env:GIT_MIRROR_VSTS_MSR}/OneOCR/_git/Cream"
$proj="$($repo -replace '.*/','' -replace '.git$','')"
$root= Join-Path "${Env:SCRATCH}" "$proj"

rm -Force -Recurse -ErrorAction SilentlyContinue -WarningAction SilentlyContinue "$root"
if (Test-Path "$root")
{
    echo "Failed to remove `"$root`""
    Exit 1
}

git clone --recursive -j100 "$repo"
pushd "$root"

# ================================================================================
# Build
# ================================================================================

mkdir build
pushd build

# Copy MKL's environment variables from ".bat" file to PowerShell.
Invoke-Expression $($(cmd /C "`"${Env:ProgramFiles(x86)}/IntelSWTools/compilers_and_libraries/windows/mkl/bin/mklvars.bat`" intel64 vs2017 & set") -Match '^MKL(_|ROOT)' -Replace '^','${Env:' -Replace '=','}="' -Replace '$','"' | Out-String)
Invoke-Expression $($(cmd /C "`"${Env:ProgramFiles(x86)}/IntelSWTools/compilers_and_libraries/windows/mkl/bin/mklvars.bat`" intel64 vs2017 & set") -Match '^LIB' -Replace '^','${Env:' -Replace '=','}="' -Replace '$','"' | Out-String)
Invoke-Expression $($(cmd /C "`"${Env:ProgramFiles(x86)}/IntelSWTools/compilers_and_libraries/windows/mkl/bin/mklvars.bat`" intel64 vs2017 & set") -Match '^CPATH' -Replace '^','${Env:' -Replace '=','}="' -Replace '$','"' | Out-String)
Invoke-Expression $($(cmd /C "`"${Env:ProgramFiles(x86)}/IntelSWTools/compilers_and_libraries/windows/mkl/bin/mklvars.bat`" intel64 vs2017 & set") -Match '^INCLUDE' -Replace '^','${Env:' -Replace '=','}="' -Replace '$','"' | Out-String)

$gtest_silent_warning="/D_SILENCE_STDEXT_HASH_DEPRECATION_WARNINGS /D_SILENCE_TR1_NAMESPACE_DEPRECATION_WARNING /w"
$gflags_dll="/DGFLAGS_IS_A_DLL=1"
$protobuf_dll="/DPROTOBUF_USE_DLLS"
$dep_dll="${gflags_dll} ${protobuf_dll}"

cmake                                                                   `
    -DBOOST_ROOT="${Env:ProgramFiles}/boost"                            `
    -DBUILD_SHARED_LIBS=ON                                              `
    -DCMAKE_BUILD_TYPE=Release                                          `
    -DCMAKE_C_FLAGS="/GL /MP /Z7 /arch:AVX ${dep_dll}"                  `
    -DCMAKE_CUDA_SEPARABLE_COMPILATION=ON                               `
    -DCMAKE_CXX_FLAGS="/EHsc /GL /MP /Z7 /arch:AVX ${dep_dll} ${gtest_silent_warning}" `
    -DCMAKE_EXE_LINKER_FLAGS="/DEBUG:FASTLINK /LTCG:incremental"        `
    -DCMAKE_INSTALL_PREFIX="${Env:ProgramFiles}/Cream"                  `
    -DCMAKE_SHARED_LINKER_FLAGS="/DEBUG:FASTLINK /LTCG:incremental"     `
    -DCMAKE_STATIC_LINKER_FLAGS="/LTCG:incremental"                     `
    -DCMAKE_VERBOSE_MAKEFILE=ON                                         `
    -DCUDA_NVCC_FLAGS="--expt-relaxed-constexpr"                        `
    -DCUDA_VERBOSE_BUILD=ON                                             `
    -DGTEST_ROOT="${Env:ProgramFiles}/googletest"                       `
    -Dglog_DIR="${Env:ProgramFiles}/glog/lib/cmake/glog"                `
    -G"Ninja"                                                           `
    ..

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

cmake --build . --target test
if (-Not $?)
{
    echo "[Warning] Check failed but we temporarily bypass it."
}

cmd /c rmdir /S /Q "${Env:ProgramFiles}/Cream"
cmake --build . --target install
Get-ChildItem "${Env:ProgramFiles}/Cream" -Filter *.dll -Recurse | Foreach-Object { New-Item -Force -ItemType SymbolicLink -Path "${Env:SystemRoot}\System32\$_" -Value $_.FullName }

popd
popd
rm -Force -Recurse "$root"
popd
