Compile E2O for ARM, MIPS32 and RISC-V32:

OAP.Compile Linux.arm.Host.Mod E2O.Kernel.Mod E2O.Disk.Mod 
  FileDir.Mod Files.Mod E2O.Modules.Mod E2O.pcsend.Mod
  Linux.X11.Display0.Mod E2O.Input.Mod E2O.32.Display.Mod 
  Viewers.Mod Fonts.Mod Texts.Mod E2O.Oberon.Mod 
  MenuViewers.Mod TextFrames.Mod System.Mod Edit.Mod 
  ORS.Mod ORB.Mod OAG.Mod OAP.Mod E2OL.Mod
  Hilbert.Mod Sierpinski.Mod Hennessy4.pm.Mod E2O.PC.Mod~

OMP.Compile Linux.mps.Host.Mod E2O.Kernel.Mod E2O.Disk.Mod
  FileDir.Mod Files.Mod E2O.Modules.Mod 
  Linux.X11.Display0.Mod E2O.Input.Mod E2O.32.Display.Mod 
  Viewers.Mod Fonts.Mod Texts.Mod E2O.Oberon.Mod 
  MenuViewers.Mod TextFrames.Mod System.Mod Edit.Mod 
  ORS.Mod ORB.Mod OMG.Mod OMP.Mod E2OL.Mod
  Hilbert.Mod Sierpinski.Mod Hennessy4.pm.Mod E2O.PC.Mod~

OVP.Compile Linux.rsv.Host.Mod E2O.Kernel.Mod E2O.Disk.Mod
  FileDir.Mod Files.Mod E2O.Modules.Mod
  Linux.X11.Display0.Mod E2O.Input.Mod E2O.32.Display.Mod 
  Viewers.Mod Fonts.Mod Texts.Mod E2O.Oberon.Mod
  MenuViewers.Mod TextFrames.Mod System.Mod Edit.Mod 
  ORS.Mod ORB.Mod OVG.Mod OVP.Mod E2OL.Mod
  Hilbert.Mod Sierpinski.Mod Hennessy4.pm.Mod E2O.PC.Mod~

Statically link Modules.elf for ARM, MIPS or RISC-V:

E2OL.LinkA Modules ~ E2OL.LinkM Modules ~ E2OL.LinkV Modules ~

Copy Modules.elf to Linux, all linked files have same name, 
rename it in Linux e.g to Modules.elf.arm:

PC.Export Modules.elf ~

Export source files and tools, converted to ASCII:

PC.Export Linux.arm.Host.Mod Linux.mps.Host.Mod Linux.rsv.Host.Mod 
  E2O.Kernel.Mod E2O.Disk.Mod E2O.Modules.Mod E2O.pcsend.Mod
  Linux.X11.Display0.Mod E2O.Input.Mod E2O.32.Display.Mod 
  E2O.Oberon.Mod OAG.Mod OAP.Mod E2OL.Mod 
  OMG.Mod OMP.Mod OVG.Mod OVP.Mod 
  OATool.Mod OMTool.Mod OVTool.Mod
  Hennessy4.pm.Mod E2O.PC.Mod BuildE2O.Tool~

Send object files to linux filesystem:

PC.Send Host.smb Host.arm Kernel.arm Disk.arm 
  FileDir.arm Files.arm Modules.arm
  Display0.smb Display0.arm Input.arm Display.arm 
  Viewers.arm Fonts.arm Texts.arm Oberon.arm 
  MenuViewers.arm TextFrames.arm System.arm Edit.arm 
  ORS.arm ORB.arm OAG.arm OAP.arm E2OL.arm
  Hilbert.arm Sierpinski.arm Hennessy.arm PC.arm ~

From within linux, copy files to exsisting disk image. Both, FPGA images and disk files should work:
I prefer smaller disk file format over disk image format. Both should work:

dd if=RISC.img of=RISC.dsk skip=524290

ODISK=RISC.dsk ./pcreceive.elf Linux.arm.Host.Mod Linux.mps.Host.Mod Linux.rsv.Host.Mod \
  E2O.Kernel.Mod E2O.Disk.Mod E2O.Modules.Mod E2O.pcsend.Mod \
  Linux.X11.Display0.Mod E2O.Input.Mod E2O.32.Display.Mod \
  E2O.Oberon.Mod OAG.Mod OAP.Mod E2OL.Mod \
  OMG.Mod OMP.Mod OVG.Mod OVP.Mod \
  OATool.Mod OMTool.Mod OVTool.Mod \
  Hennessy4.pm.Mod E2O.PC.Mod BuildE2O.Tool \
  Host.smb Host.arm Kernel.arm Disk.arm \
  FileDir.arm Files.arm Modules.arm \
  Display0.smb Display0.arm Input.arm Display.arm \
  Viewers.arm Fonts.arm Texts.arm Oberon.arm \
  MenuViewers.arm TextFrames.arm System.arm Edit.arm \
  ORS.arm ORB.arm OAG.arm OAP.arm E2OL.arm \
  Hilbert.arm Sierpinski.arm Hennessy.arm PC.arm

From an existing RISC5 system, you can copy only the source code, compile the compiler and linker,
send the linked modules to host and use tham on the new system. 
