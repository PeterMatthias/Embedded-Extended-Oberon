# The E2O System

## Naming convention

Host and architecture dependant source modules have a prefix with host OS and architecture name. Modules changed for E2O and requiring E2O have an E2O prefix. All other code works perfectly well on all targets. You can easily bootstrap E2O from within RISC5, e.g by using the Oberon RISC5 emulator from Peter De Wachter and the Extended Oberon System (EOS) from Andreas Pirklbauer. The modules added for the compiler have a unique 2nd character (lines in italics not available yet and no concrete development started): 

- "a" for ARM32
- *"A" for ARM64*
- "M" for MIPS32
- *"T" for Thumb2* 
- "v" for RISC-V32
- "V" for RISC-V64
- *"W" for WebAssembly😃️*
- *"x" for x86*
- *"X" for x64*

For instructions and registers, I prefer RISC-V naming convention, although this is not yet used stringent. 

## E2O System

Like all of my Oberon systems (OLR, POL), also E2O has no ability to use Linux libraries. Only Kernel interface can be used. This complicates display output. X11 socket interface is being used. Frame-buffer could also be used but is not implemented. No interface of any module was changed from EOS. 

## Memory layout, Stack, Modules, Heap

The ELF file is loaded to 10000H. Memory size is fixed to 16MB. Modules space is from 10000H to 10_0000H minus stack on 64bit targets. Heap is from 10_0000H to 100_0000H.

On 32bit targets, Linux's stack is being used. On 64bit targets, SYSTEM.ADR would not work for local variables with 64bit stack. Stack is switched to 10_0000H inside body on Modules. On stack overflow on 64bit, Modules space is overwritten. 

## Fixup

EOS uses fixup code distributed over 2 instructions. E2O omits register in first instruction and takes it from 2.nd instruction. For imported modules, format is 8 bit module No., 8 bit pno/vno, 1, 15bit displacement. For the own module it is 16 bit offset, 0, 15bit displacement. This way, we get simple portable fixup with large module numbers and large displacement. Displacement is in 16bit half-words. 16bit wide code as used in Thumb2 and compressed RISC-V is supported by this mechanism. Traps and NEW are encoded with highest 16 bits set to 1.

It is possible to eliminate fixup of global variables. When code starts, variable size is fixed. Only string constants can be added during further code parsing. Putting strings growing down below variables and putting variables below code, relative addresses of strings and global variables are known during compile time. This was not used for two reasons:

1. The first E of E2O stands for embedded. In embedded systems, code can run from ROM. Strings can also be in ROM. But variables must use RAM with unknown addresses during compile time.
2. When no fixup is used for global variables, displacement can become too big.

## Traps and NEW

EOS uses dedicated register holding TRAP/NEW address and jumps to the address in the register with an instruction that can hold 20bit private information. 16bit are used for position in source code. 4 bit are used for Trap number. E2O stores 20bit information in Trap Register and jumps to the Trap/NEW address directly. RISC-V can move 20bit with a single instruction. Low instruction count in code path is crucial for fast execution of traps. Non RISC-V targets store 16bit in TR with a single instruction. The jump is to a module prologue that increases trap number depending on jump-in position. Decoding of different formats is automatic. NEW always jumps directly as it is encoded with trap number zero.  

A new versatile approach without using TR at all is being considered. While jumping directly, there is no need to merge NEW and TRAP. NEW can be a normal procedure call at fixed address. Trap does not return from calling. So, code position and trap number can be stored in code space directly after the JAL to the Trap. The address of the information than is automatically stored in LNK/RA register. 



## Host module

Despite being Host and architecture dependant, interface for all hosts is the same, simplifying cross compilation. Only used functionality is exported, no generic system calls. Simple logging facility is implemented in Host.

## Register numbers

E2O uses register numbers from RISC5 for TR, SP and RA in SYSTEM.REG and SYSTEM.LDREG. The compiler translates these numbers to native numbers. Native registers can be accessed by using their negative value.

## FPU Registers

FPU registers currently are not stored e.g. when a functions returns a REAL value as an argument of another procedure. 

## Targets
### ARM32

ARM32 is an outdated instruction set and should be replaced by Thumb2. This should be a relatively easy change as most used instructions are available in both instruction sets with just a different encoding. Access to imported variables take 3 instructions. It would be possible to acces global variables with two instructions within 1MB. This is not yet implemented. Condition codes are very similar to RISC5.

### MIPS32

MIPS uses branch delay slot. It is a miracle that MIPS works mostly without changing EOS structure at all. This is only possible because TrapAdr at pos. 4 is zero at boot-up and the jump at pos. 0 is only executed once. Zero is a NOP in MIPS. EOS specific features will not work with MIPS. Despite the branch delay slot, MIPS is a perfectly well target for Oberon with 16bit branch distance and a simple instruction set with regular encoding.

### RISC-V

Branch distance is only +-4pm
kB. An extension is implemented for larger branches. Encoding of jump, branches and stores are irregular. Default setup is for small Modules space < 1MB with a single instruction jump. A large code model is implemented with access to 32bit with two instruction jumps, but not tested. Local variables > 2K take 3 instructions. RISC-V supports compressed instruction format. This is currently not supported by E2O. With compressed instructions, these 3 instructions usually would take 64bit and could probably be fused in real implementations. Usually, half of the instructions could use compressed format, reducing code size by 25% and improving instruction cache hit rate. A strange decision was made by RISC-V developers by making 32bit system incompatible with 64bit system.



## 64bit

Some tweaks are necessary to run 32bit Oberon on 64 bit targets when stack is at 64bit. Besides switching stack in body of Modules, all tweaks are inside Host.

Unfortunately, EOS uses LONGINT as synonym for INTEGER. I would appreciate defining LONGINT as 64bit (and SHORTINT as 16bit) while keeping Oberon a 32bit system.

### ARM64

ARM64 seems to be a powerful instruction set perfectly suited for Oberon.

## Porting

Porting the system is very straightforward. Mainly, only two modules must be implemented. A Host module for the host interface, and the code generator of the compiler OxG.Mod. Only very few lines of code must be added to the static linker E2OL.Mod. The parser OxP.Mod is virtually the same with just an alias in the import of ORG. A disassembler OxTool helps to find bugs, but Linux's objdump could also be used.


## Performance

The compiler produces efficient code considered it doesn't use register variables. With register variables on architectures with 32 registers, performance is expected to double. All other optimizations are expected to be in single digit percentage range and not really worthwhile. On system side, system calls are expensive operations. While performance is very good, it could even be further improved by implementing a display driver without them and by memory mapping the disk operations. Frame-buffer could be removed and replaced by direct X11 calls, reducing traffic when using E2O over network.

## Development system

I use a Raspberry Pi 5 as development system. For E2O, even a Raspberry Pi Zero 2 would be sufficient. However, it is nice to have a browser on hand while programming.

