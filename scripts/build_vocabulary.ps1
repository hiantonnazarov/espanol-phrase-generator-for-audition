$ErrorActionPreference = 'Stop'

# Thin wrapper: the actual generator lives in build_vocabulary_sectioned.ps1.
& (Join-Path $PSScriptRoot 'build_vocabulary_sectioned.ps1')
