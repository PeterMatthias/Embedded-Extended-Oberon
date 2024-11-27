# The Embedded Extended Oberon operating system
The Extended Oberon System is a revision of the *Project Oberon 2013* operating system and its compiler.

The Embedded Extended Oberon System is a port of the Extended Oberon System to Linux on ARMv7, MIPS32 and RISC-V32

**Last update:** 2024-11-24

The file [**EOS_news.txt**](EOS_news.txt) describes the changes made to Extended Oberon.

Documentation: [**Documentation**](Documentation)

------------------------------------------------------

# Instructions for running Embedded Extended Oberon

**To obtain Embedded Extended Oberon**:

Download following files from this repository:
 [**RISC.dsk**](RISC.dsk), [**Modules.elf.arm**](Modules.elf.arm), [**pcsend.elf**](pcsend.elf)

**To run Embedded Extended Oberon** 

- make Modules.elf.arm and pcsend.elf executable
- all three files should be in same directory
- run "./Modules.elf.arm"

Following invironment variables are used:
- ODISK=diskname # disk name
- OWIDTH=1024  # Display width
- HEIGHT=800  # Display Heigh

E2O runs well on Raspberry Pi with X11 Windows. Wayland still is buggy on RPi. It runs also well on current Fedora with Wayland.
On X86, qemu can be invoked automatically. If not, run "qemu-arm-static ./Modules.elf.arm" . With environment variables e.g. 
"ODISK=diskname OWIDTH=800 OHEIGHT=600 qemu-arm-static ./Modules.elf.arm" 

First thing you probably want to do is to remove zoom at display:
- open E2O.32.Display.Mod
- set Zoom to 1 and store the file
- compile it with "OAP.Compile E2O.32.Display.Mod~"
- restart the system

This distribution does not include binaries for MIPS and RISC-V. You can easily compile them from within ARM or even RISC5. 
See instruction at BuildE2O.Tool

pcsend.elf copies files from Oberon to Linux like "ODISK=diskname ./psend.elf file1 file2 file3 ..." When renamed to pcreceive.elf, 
it copies files from Linux to Oberon disk.

Warning: This system has known and unknown bugs. Known bug is that FPU registers are not saved e.g. when a function returns a REAL value 
as a direct argument of a procedure. 

All souces are in the disk file. Technical information will be added later.
