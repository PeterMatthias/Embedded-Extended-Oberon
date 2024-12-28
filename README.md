# The Embedded Extended Oberon operating system

The Embedded Extended Oberon System (short E2O) is a port of the [Extended Oberon System]((https://github.com/andreaspirklbauer/Oberon-extended)) to Linux on ARMv7, MIPS32 and RISC-V32/RISC-V64. Look there for latest changes of the system. I strive to fetch up any changes from there.

The Extended Oberon System is a revision of the *Project Oberon 2013* operating system and its compiler.


The file [E2O_news.md](EOS_news.md) describes the changes made to Embedded Extended Oberon.


## Instructions for running Embedded Extended Oberon

### Obtain Embedded Extended Oberon:

Download files [RISC.dsk](RISC.dsk), [Modules.elf.arm](Modules.elf.arm), [pcsend.elf](pcsend.elf) from this repository.

### Run Embedded Extended Oberon:

- make Modules.elf.arm and pcsend.elf executable `chmod a+x Modules.elf.arm pcsend.elf`
- all three files should be in same directory
- run `./Modules.elf.arm`

Following environment variables are used:

- ODISK=diskname # disk name
- OWIDTH=1024  # Display width
- HEIGHT=800  # Display Heigh

E2O runs well on Raspberry Pi with X11 Windows. Wayland still is buggy on RPi. It runs also well on current Fedora with Wayland.
On X86, qemu can be invoked automatically. If not, run `qemu-arm-static ./Modules.elf.arm` . With environment variables e.g. 
`ODISK=diskname OWIDTH=800 OHEIGHT=600 qemu-arm-static ./Modules.elf.arm`

First thing you probably want to do is to remove zoom at display:

- open E2O.32.Display.Mod
- set Zoom to 1 and store the file
- compile it with `OAP.Compile E2O.32.Display.Mod~`
- restart the system

This distribution does not include binaries for MIPS and RISC-V. You can easily compile them from within ARM or even RISC5. 
See instructions at BuildE2O.Tool

pcsend.elf copies files from Oberon to Linux like `ODISK=diskname ./psend.elf file1 file2 file3 ...` When renamed to pcreceive.elf, 
it copies files from Linux to Oberon disk.

Warning: This system has known and unknown bugs. Known bug is that FPU registers are not saved e.g. when a function returns a REAL value as a direct argument of a procedure. **All software is published as it is without any liability**.

All souces are in the disk file. Technical information is in [underthehood.md](underthehood.md).

## Status
Arm version is the one being in use and working well for me. RISC-V versions should work as well. MIPS lacks EOS features.

## Future

E2O gives lots of possibilities:

- let RISC-V version run on Raspberry Pi Pico 2
- let ARM version output Thumb2 code 
- write an ARM64 target
- change compiler to use FP registers correctly
- change compiler to use register variables
- use non X11 display driver or use X11 without framebuffer
- Oberon System 3 has nice colours which also work with Project Oberon. Check if EOS is also suited for nice colours.
- What I will do now: Try to target [WebAssembly](https://www.w3.org/TR/wasm-core-2/) and [WASI](https://wasi.dev). 


## Acknowledgements
First of course to Niklaus Wirth and the team for the language Oberon and the [Project Oberon System](www.projectoberon.com).

Andreas Pirklbauer for extending the system to [Extended Oberon](https://github.com/andreaspirklbauer/Oberon-extended). EOS turned out to be very portable and well thought out.

The fixup encoding was influenced by the [x86 port](https://github.com/deaddoomer/project-oberon) of Project Oberon. I hope to welcome that port to E2O one day. 

