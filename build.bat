@echo off

if not exist .\build mkdir build

odin build .\src -out:.\build\vulkan_odin.exe -debug -subsystem:console
