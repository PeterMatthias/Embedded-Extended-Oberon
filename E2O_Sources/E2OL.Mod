MODULE E2OL;  (*Oberon boot linker/loader for RISC / AP 2024-08-24 Embedded Extended Oberon*)

(*
    static linker for E2O

    Peter Matthias

    2024-11-18  adopted for optimized fixcode, fixvar
    2024-12-07  get version from module appendix

*)

  IMPORT SYSTEM, Kernel, Disk, Files, Modules, Texts, Oberon;
  CONST 
    a32 = 3; v32 = 4; mps = 5;
    a64 = 43H; v64 = 44H;
    MemSize= 1000000H;
    DescSize = 96; MnLength = 32; BootSec = 2; BootSize = 192; FPrint = 12345678H;
    noerr* = 0; nofile* = 1; badversion* = 2; badkey* = 3; badfile* = 4; nospace* = 5;
    TrapAdr = 4; DestAdr = 8; MemAdr = 12; AllocAdr = 16; RootAdr = 20; StackAdr = 24; FPrintAdr = 28; ModAdr = 32;

    a32MOVT =  0E3400000H; a32MOVW =  0E3000000H;
    a32B = 0EA000000H; a32BL = 0EB000000H;
    a32dPC = 2; (* arm pc 2 instructions ahead *)

    vLNK = 1; 
    vLUI = 37H; vAUIPC = 17H; vJAL = 6FH; vJALR = 67H;
    vADDI = 13H;
    vFLW = 2007H;  vLB = 3;  vLW = 2003H;  
    vFSW = 2027H;  vSB = 23H;  vSW  = 2023H;

    mpsLUI = 3C000000H; mpsJAL = 0C000000H; mpsBGEZAL = 04110000H;
    mpsdPC = 1;
    
    elfheader = 80H; pbase = 10000H+ elfheader ;

    C4 = 10H; C6 = 40H; C8 = 100H; C10 = 400H; C12 = 1000H; C14 = 4000H; C15 = 8000H; C16 = 10000H; C18 = 40000H;
    C20 = 100000H; C21 = 200000H; C22 = 400000H; C24 = 1000000H; C26 = 4000000H; C28 = 10000000H; C30 = 40000000H;

  TYPE  (*copied from Modules for use as cross linker/loader*)
    Module* = POINTER TO ModDesc;
    Command* = PROCEDURE;
    ModuleName* = ARRAY MnLength OF CHAR;
    ModDesc* = RECORD
      name*: ModuleName;
      next*: Module;
      key*, num*, size*, refcnt*: INTEGER;
      var*, str*, tdx*, prg*, imp*, cmd*, ent*, ptr*, pvr*: INTEGER;  (*addresses*)
      selected*, marked, hidden, sel: BOOLEAN;
      final: Command
    END ;

  VAR root: Module;
    AllocPtr, Reused, Start, limit, res*: INTEGER;
    importing*, imported*: ModuleName;
    W: Texts.Writer;
    versionkey : INTEGER;
    appendix: ARRAY 5 OF CHAR;

PROCEDURE WriteELF32( VAR R: Files.Rider; size: INTEGER);
CONST
  a32EMachine = 40; v32EMachine = 243; m32EMachine = 8; 
  a32EFlags = 5000400H; v32EFlags = 0; m32EFlags= 70000000H;
  PHEntSize= 20H; ElfHdrSize= 34H; 
VAR EMachine, EFlags : INTEGER;
BEGIN
(* ELF 32 Header *)
  IF versionkey = a32 THEN EMachine := a32EMachine; EFlags := a32EFlags;
  ELSIF versionkey = v32 THEN EMachine := v32EMachine; EFlags := v32EFlags;
  ELSIF versionkey = mps THEN EMachine := m32EMachine; EFlags := m32EFlags;
  END;
  Files.WriteInt(R, ( ( ORD("F")*100H+ORD("L"))*100H+ORD("E"))*100H+7FH);
  Files.WriteInt(R, 00010101H);
  Files.WriteInt(R, 0);
  Files.WriteInt(R, 0);
  Files.WriteInt(R, EMachine*10000H+2);  (* e-type= ET_EXEC *)
  Files.WriteInt(R, 1);    (* e_version = EV_CURRENT *)
  Files.WriteInt(R, pbase );  (* e_entry = virtual adr to first start control *)
  Files.WriteInt(R, 40H);  (* e_phoff = program header's table file offset *)

  Files.WriteInt(R, 0);  (* e_shoff = section header table's file offset *)
  Files.WriteInt(R, EFlags);
  Files.WriteInt(R, PHEntSize*10000H+ElfHdrSize);  (* e_ehsize = ELF header's size in bytes *) (* e_phentsize = size of one entry in file's program header table *)
  Files.WriteInt(R, 40*10000H+1);        (* e_shentsize = section header entry size, was 40*) (* e_phnum = number of entries in program header's table *)
  Files.WriteInt(R, 0);  (* e_shstrndx = SHN_UNDEF was: 3*)  (* e_shnum = 4 section headers *)
  Files.WriteInt(R, 0);  (* 12 bytes padding  needed *)
  Files.WriteInt(R, 0);
  Files.WriteInt(R, 0);

(* Program Header Table *)
  Files.WriteInt(R, 1);  (* p_type = PT_LOAD *)
  Files.WriteInt(R, 0);  (* was ELFhdrsz+PHTsize+PadSize;*)  (* p_offset = offset from the beginning of the file to first byte of segment *)
  Files.WriteInt(R, 0+ pbase - elfheader);  (* p_vadr = virtual adr of the first byte in memory *)
  Files.WriteInt(R, 0);  (* p_padr = physical adr ignored *)
  Files.WriteInt(R, size + elfheader);  (* p_filesz = number of bytes in the file image of the segment *)
  Files.WriteInt(R, MemSize);
  Files.WriteInt(R, 7);  (* p_flags = PF_R+ PF_W+ PF_X, allow read, write, execution *)
  Files.WriteInt(R, 10000H);  (* p_align = page size; MIPS Creator Ci20 might need 10000H*)

  Files.WriteInt(R, 0);  (* pad to elfheadersize *)
  Files.WriteInt(R, 0);
  Files.WriteInt(R, 0);
  Files.WriteInt(R, 0);
  Files.WriteInt(R, 0);
  Files.WriteInt(R, 0);
  Files.WriteInt(R, 0);
  Files.WriteInt(R, 0);
END WriteELF32;

PROCEDURE WriteELF64( VAR R: Files.Rider; size: INTEGER);
CONST
  a64EMachine= 183; a64EFlags= 0;
  v64EMachine=243; v64EFlags= 2;
  PHEntSize= 38H; ElfHdrSize= 40H;
VAR  EMachine, EFlags: INTEGER;
BEGIN
  IF versionkey = a64 THEN EMachine := a64EMachine; EFlags := a64EFlags;
  ELSIF versionkey = v64 THEN EMachine := v64EMachine; EFlags := v64EFlags;
  END;

(* ELF 64 Header *)
  Files.WriteInt(R, ( ( ORD("F")*100H+ORD("L"))*100H+ORD("E"))*100H+7FH);
  Files.WriteInt(R, 00010102H);
  Files.WriteInt(R, 0);
  Files.WriteInt(R, 0);
  Files.WriteInt(R, EMachine*10000H+2);  (* e-type= ET_EXEC *)
  Files.WriteInt(R, 1);    (* e_version = EV_CURRENT *)
  Files.WriteInt(R, pbase);  (* e_entry = virtual adr to first start control *)
  Files.WriteInt(R, 0);

  Files.WriteInt(R, 40H);  (* e_phoff = program header's table file offset *)
  Files.WriteInt(R, 0);
  Files.WriteInt(R, 0);  (* e_shoff = section header table's file offset *)
  Files.WriteInt(R, 0);
  Files.WriteInt(R, EFlags);    (* 1: compressed support 2: float single, 4: float double, *)
  Files.WriteInt(R, PHEntSize*10000H+ElfHdrSize);  (* e_ehsize = ELF header's size in bytes *) (* e_phentsize = size of one entry in file's program header table *)
  Files.WriteInt(R, 40*10000H+1);        (* e_shentsize = section header entry size, was 40*) (* e_phnum = number of entries in program header's table *)
  Files.WriteInt(R, 0);  (* e_shstrndx = SHN_UNDEF was: 3*)  (* e_shnum = 4 section headers *)

(* Program Header Table *)
  Files.WriteInt(R, 1);  (* p_type = PT_LOAD *)
  Files.WriteInt(R, 7);  (* p_flags = PF_R+ PF_W+ PF_X, allow read, write, execution *)
  Files.WriteInt(R, 0);  (* was ELFhdrsz+PHTsize+PadSize;*)  (* p_offset = offset from the beginning of the file to first byte of segment *)
  Files.WriteInt(R, 0);
  Files.WriteInt(R, pbase-elfheader);  (* p_vadr = virtual adr of the first byte in memory *)
  Files.WriteInt(R, 0);
  Files.WriteInt(R, 0);  (* p_padr = physical adr ignored *)
  Files.WriteInt(R, 0);

  Files.WriteInt(R, size+elfheader);  (* p_filesz = number of bytes in the file image of the segment *)
  Files.WriteInt(R, 0);
  Files.WriteInt(R, MemSize);
  Files.WriteInt(R, 0);
  Files.WriteInt(R, 10000H);  (* p_align = page size; MIPS Creator Ci20 might need 10000H*)
  Files.WriteInt(R, 0);
  Files.WriteInt(R, 0);
  Files.WriteInt(R, 0);

END WriteELF64;


PROCEDURE EndLine;
BEGIN Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END EndLine;

PROCEDURE SetJimm( imm: INTEGER): INTEGER;  (* imm in bytes *)
BEGIN
  IF ASR(imm, 21)# ASR(imm, 20) THEN Texts.WriteString(W, "SetJimm"); EndLine END;
RETURN LSL(ASR( imm, 20), 31)+LSL( imm MOD 800H, 20)+LSL( ASR(imm, 11) MOD 2, 20)+LSL( ASR(imm, 12) MOD 100H, 12)
END SetJimm;

PROCEDURE GetArg(VAR S: Texts.Scanner);
VAR T: Texts.Text; beg, end, time: LONGINT;
BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
  IF (S.class = Texts.Char) & (S.c = "^") THEN
    Oberon.GetSelection(T, beg, end, time);
    IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
  END
END GetArg;

PROCEDURE GetAppendix(VAR FName: ARRAY OF CHAR; name: ARRAY OF CHAR);
VAR i, j: INTEGER;
BEGIN
  i := 0; j := 0;  (*assume name suffix less than 4 characters*)
  WHILE (i < MnLength-5) & (name[i] > 0X) & (name[i] # ".") DO FName[i] := name[i]; INC(i) END;
  FName[i] := 0X; j := 0;
  WHILE (j < LEN(appendix) - 1) & (name[i] > 0X) DO appendix[j] := name[i]; INC(i); INC(j) END;
  IF appendix = ".arm" THEN versionkey := a32;
  ELSIF appendix = ".a64" THEN versionkey := a64;
  ELSIF appendix = ".v32" THEN versionkey := v32;
  ELSIF appendix = ".v64" THEN versionkey := v64;
  ELSIF appendix = ".mps" THEN versionkey := mps;
  ELSE FName[0] := 0X;
  END;
  Texts.WriteString(W, appendix);
END GetAppendix;

PROCEDURE MakeFileName(VAR FName: ARRAY OF CHAR; name, ext: ARRAY OF CHAR);
VAR i, j: INTEGER;
BEGIN i := 0; j := 0;  (*assume name suffix less than 4 characters*)
  WHILE (i < MnLength-5) & (name[i] > 0X) & (name[i] # ".") DO FName[i] := name[i]; INC(i) END ;
  REPEAT FName[i]:= ext[j]; INC(i); INC(j) UNTIL ext[j] = 0X;
  FName[i] := 0X;
END MakeFileName;

PROCEDURE error(n: INTEGER; name: ARRAY OF CHAR);
BEGIN res := n; importing := name
END error;

PROCEDURE check(s: ARRAY OF CHAR; VAR slen: INTEGER);  (*slen includes trailing 0X*)
VAR i: INTEGER; ch: CHAR;
BEGIN ch := s[0]; res := 1; i := 0; slen := 0;
  IF (ch >= "A") & (ch <= "Z") OR (ch >= "a") & (ch <= "z") THEN
    REPEAT INC(i); ch := s[i]
    UNTIL ~((ch >= "0") & (ch <= "9") OR (ch >= "A") & (ch <= "Z")
      OR (ch >= "a") & (ch <= "z") OR (ch = ".")) OR (i >= MnLength);
    IF ch = 0X THEN res := 0; slen := i+1 END
  END
END check;

  PROCEDURE LinkOne(name: ARRAY OF CHAR; VAR newmod: Module; VAR R1: Files.Rider);
    (*search module in list; if not found, link module.
      res = noerr: already present or linked;
      res = nofile: file not available;
      res = badversion: bad file version;
      res = badkey: key conflict;
      res = badfile: corrupted file;
      res = nospace: insufficient space*)
    VAR mod, impmod: Module;
      i, n, key, impkey, mno, nofimps, size: INTEGER;
      version, p, u, v, w: INTEGER;  (*addresses*)
      ch: CHAR;
      body: Command;
      fixorgP, fixorgD, fixorgT, fixorgM: INTEGER;
      rd, disp, adr, inst, pno, vno, dest, offset: INTEGER;
      name1, impname: ModuleName;
      F: Files.File; R: Files.Rider;
      import: ARRAY 64 OF Module;
  BEGIN mod := root; error(noerr, name); nofimps := 0;
    WHILE (mod # NIL) & (name # mod.name) DO mod := mod.next END ;
    IF mod = NIL THEN (*link*)
      check(name, n);
      IF res = noerr THEN MakeFileName(name1, name, appendix); F := Files.Old(name1) ELSE F := NIL END ;
      IF F # NIL THEN
        Files.Set(R, F, 0); Files.ReadString(R, name1); Files.ReadInt(R, key); Files.Read(R, ch);
        version := ORD(ch);
        Files.ReadInt(R, size); importing := name1;
        IF (version = versionkey) (*regular module*) THEN
          Files.ReadString(R, impname);  (*imports*)
          WHILE (impname[0] # 0X) & (res = noerr) DO
            Files.ReadInt(R, impkey);
            LinkOne(impname, impmod, R1); import[nofimps] := impmod; importing := name1;
            IF res = noerr THEN
              IF impmod.key = impkey THEN INC(impmod.refcnt); INC(nofimps)
              ELSE error(badkey, name1); imported := impname
              END
            END ;
            Files.ReadString(R, impname)
          END
        ELSE error(badversion, name1)
        END
      ELSE error(nofile, name)
      END ;
      IF res = noerr THEN
        INC(size, DescSize);
        IF AllocPtr + size < limit THEN (*allocate*)
          p := AllocPtr; mod := SYSTEM.VAL(Module, p);
          AllocPtr := (p + size + 3) DIV 4 * 4; mod.size := AllocPtr - p; u := Reused - Start + pbase;
          IF root = NIL THEN mod.num := 1 ELSE mod.num := root.num + 1 END ;
          mod.next := root; root := mod
        ELSE error(nospace, name1)
        END
      END ;
      IF res = noerr THEN (*read file*)
        INC(p, DescSize); (*allocate descriptor*)
        mod.name := name; mod.key := key; mod.refcnt := 0; i := n;
        WHILE i < MnLength DO mod.name[i] := 0X; INC(i) END ;
        mod.selected := FALSE; mod.hidden := FALSE; mod.marked := FALSE; mod.sel := FALSE;
        mod.var := p; Files.ReadInt(R, n);
        WHILE n > 0 DO SYSTEM.PUT(p, 0); INC(p, 4); DEC(n, 4) END ;  (*variable space*)
        mod.str := p; Files.ReadInt(R, n);
        WHILE n > 0 DO Files.Read(R, ch); SYSTEM.PUT(p, ch); INC(p); DEC(n) END ;  (*strings*)
        mod.tdx := p; Files.ReadInt(R, n);
        WHILE n > 0 DO Files.ReadInt(R, w); SYSTEM.PUT(p, w); INC(p, 4); DEC(n, 4) END ;  (*type descriptors*)
        mod.prg := p; Files.ReadInt(R, n);
        WHILE n > 0 DO Files.ReadInt(R, w); SYSTEM.PUT(p, w); INC(p, 4); DEC(n) END ;  (*program code*)
        mod.imp := p; i := 0;
        WHILE i < nofimps DO SYSTEM.PUT(p, import[i]); INC(p, 4); INC(i) END ;  (*copy imports*)
        mod.cmd := p; Files.Read(R, ch);
        WHILE ch # 0X DO  (*commands*)
          REPEAT SYSTEM.PUT(p, ch); INC(p); Files.Read(R, ch) UNTIL ch = 0X;
          REPEAT SYSTEM.PUT(p, 0X); INC(p) UNTIL p MOD 4 = 0;
          Files.ReadInt(R, n); SYSTEM.PUT(p, n); INC(p, 4); Files.Read(R, ch)
        END ;
        REPEAT SYSTEM.PUT(p, 0X); INC(p) UNTIL p MOD 4 = 0;
        mod.ent := p; Files.ReadInt(R, n);
        WHILE n > 0 DO Files.ReadInt(R, w); SYSTEM.PUT(p, w); INC(p, 4); DEC(n) END ;  (*entries*)
        mod.ptr := p; Files.ReadInt(R, w);
        WHILE w >= 0 DO SYSTEM.PUT(p, mod.var + w + u); INC(p, 4); Files.ReadInt(R, w) END ;  (*pointer references*)
        SYSTEM.PUT(p, 0); INC(p, 4);
        mod.pvr := p; Files.ReadInt(R, w);
        WHILE w >= 0 DO SYSTEM.PUT(p, mod.var + w + u); INC(p, 4); Files.ReadInt(R, w) END ;  (*procedure variable references*)
        SYSTEM.PUT(p, 0); INC(p, 4);
        Files.ReadInt(R, fixorgP); Files.ReadInt(R, fixorgD);
        Files.ReadInt(R, fixorgT); Files.ReadInt(R, fixorgM);
        Files.ReadInt(R, w); body := SYSTEM.VAL(Command, mod.prg + w + u);
        Files.ReadInt(R, w);
        IF w >= 0 THEN mod.final := SYSTEM.VAL(Command, mod.prg + w + u) ELSE mod.final := NIL END ;
        Files.Read(R, ch);
        IF ch # "O" THEN mod := NIL; error(badfile, name) END
      END ;
      IF res = noerr THEN (*fixup of BL*)
        adr := mod.prg + fixorgP*2;
        WHILE adr # mod.prg DO
          SYSTEM.GET(adr, inst);
          IF inst DIV C16 = -1 THEN  dest :=  Start + TrapAdr;
          ELSE
            mno := inst DIV C24 MOD 80H;
            pno := inst DIV C16 MOD 100H;
            SYSTEM.GET(mod.imp + (mno-1) * 4, impmod);
            SYSTEM.GET(impmod.ent + pno * 4, dest); dest := dest + impmod.prg + impmod.pvr;
          END;
          offset := dest - (adr + Reused);
          IF versionkey = a32 THEN  (* +- 16MB for THUMB2 +- 32MB for ARM32 *)
            SYSTEM.PUT(adr, a32BL + (offset DIV 4 - a32dPC ) MOD C24 );
          ELSIF versionkey MOD 40H = v32 THEN  (* +- 1MB for JAL is always enough for statically linked modules *)
            ASSERT( ABS(offset) < 100000H);
            SYSTEM.PUT(adr, vJAL+ vLNK * 80H+ SetJimm(offset ));
          ELSIF versionkey = mps THEN
            SYSTEM.PUT(adr, mpsJAL + ( dest - Start + pbase ) DIV 4);  (* absolute adr, 256MB region *)
(*            SYSTEM.PUT(adr, mpsBGEZAL + ((offset ) DIV 4 - mpsdPC) MOD C16); +-128K relative *)
          END;
          adr := adr - inst MOD C15* 2
        END ;
        (* fixup of LDR/STR/ADD *)
        adr := mod.prg + fixorgD * 2;
        WHILE adr # mod.prg DO
          SYSTEM.GET(adr, inst);
          mno := inst DIV C24 MOD 80H;
          dest := inst DIV C16 MOD C16;
          disp := inst MOD C15;
          IF ~ODD(inst DIV C15) THEN (*global*)  INC(dest, mod.var + u );
          ELSE  (*import*)
            SYSTEM.GET(mod.imp + (mno-1) * 4, impmod);
            vno := dest MOD 100H;
            SYSTEM.GET(impmod.ent + vno * 4, dest);
            IF inst < 0 THEN INC(dest, impmod.prg - Start + impmod.pvr )
            ELSE INC(dest, impmod.var - Start  + impmod.pvr )
            END;
            INC(dest, pbase);
          END ;
          SYSTEM.GET(adr + 4, inst);
          IF versionkey = a32 THEN
            SYSTEM.PUT(adr, a32MOVW + dest DIV 1000H MOD 10H * C16 + 
                inst DIV 1000H MOD 10H * 1000H + dest MOD 1000H );
            SYSTEM.PUT(adr + 4, inst + dest DIV C28 MOD 10H * C16 + dest DIV C16 MOD 1000H );
          ELSIF versionkey MOD 40H = v32 THEN
            SYSTEM.PUT(adr, vLUI + inst DIV 8000H MOD 20H * 80H + ( dest DIV 1000H + dest DIV 800H MOD 2) * 1000H);
            IF (inst MOD 80H = 23H) OR (inst MOD 80H = 27H) THEN (* store, fsw *)
              SYSTEM.PUT(adr+4, inst + LSL( dest DIV 20H MOD 80H, 25) + dest MOD 20H * 80H);
            ELSE SYSTEM.PUT(adr+4, inst +  dest MOD 1000H * C20);
            END;
          ELSIF versionkey = mps THEN
            SYSTEM.PUT(adr, mpsLUI + inst DIV C21 MOD 20H * C16 + dest DIV C16 + dest DIV C15 MOD 2);
            SYSTEM.PUT(adr+ 4, inst +  dest MOD C16);
          END;
          adr := adr - disp * 2
        END ;
        (*fixup of type descriptors*)
        adr := mod.tdx + fixorgT*4;
        WHILE adr # mod.tdx DO
          SYSTEM.GET(adr, inst);
          mno := inst DIV C24 MOD C6;
          vno := inst DIV C12 MOD C12;
          disp := inst MOD C12;
          IF mno = 0 THEN (*global*) inst := mod.tdx + u + vno
          ELSE (*import*)
            SYSTEM.GET(mod.imp + (mno-1)*4, impmod);
            SYSTEM.GET(impmod.ent + vno*4, offset);
            inst := impmod.var - Start + pbase + impmod.pvr + offset
          END ;
          SYSTEM.PUT(adr, inst); adr := adr - disp*4
        END ;
        (*fixup of method tables*)
        adr := mod.tdx + fixorgM*4;
        WHILE adr # mod.tdx DO
          SYSTEM.GET(adr, inst);
          mno := inst DIV C26 MOD C6;
          vno := inst DIV C10 MOD C16;
          disp := inst MOD C10;
          IF mno = 0 THEN (*global*) inst := mod.prg + u + vno
          ELSE (*import*)
            SYSTEM.GET(mod.imp + (mno-1)*4, impmod);
            SYSTEM.GET(impmod.ent + vno*4, offset);
            inst := impmod.prg - Start + pbase + impmod.pvr + offset
          END ;
          SYSTEM.PUT(adr, inst); adr := adr - disp*4
        END ;
        SYSTEM.PUT(Start, ORD(body) - pbase); (*module initialization body*)
        (*write module to boot file*)
        i := SYSTEM.VAL(INTEGER, mod); n := 8;
        WHILE n > 0 DO SYSTEM.GET(i, w); Files.WriteInt(R1, w); INC(i, 4); DEC(n) END ;  (*name*)
        IF mod.next # NIL THEN Files.WriteInt(R1, SYSTEM.VAL(INTEGER, mod.next) - Start + pbase + mod.next.pvr)  (*next*)
        ELSE Files.WriteInt(R1, 0)
        END ;
        Files.WriteInt(R1, mod.key); Files.WriteInt(R1, mod.num);
        Files.WriteInt(R1, mod.size); Files.WriteInt(R1, mod.refcnt);
        Files.WriteInt(R1, mod.var + u); Files.WriteInt(R1, mod.str + u);
        Files.WriteInt(R1, mod.tdx + u); Files.WriteInt(R1, mod.prg + u);
        Files.WriteInt(R1, mod.imp + u); Files.WriteInt(R1, mod.cmd + u);
        Files.WriteInt(R1, mod.ent + u); Files.WriteInt(R1, mod.ptr + u);
        Files.WriteInt(R1, mod.pvr + u); INC(i, 56);
        WHILE i < mod.imp DO
          SYSTEM.GET(i, w); Files.WriteInt(R1, w); INC(i, 4)  (*variables, strings, type descriptors, program code*)
        END ;
        WHILE i < mod.cmd DO SYSTEM.GET(i, w);
          impmod := SYSTEM.VAL(Module, w); Files.WriteInt(R1, w - Start + pbase + impmod.pvr); INC(i, 4)  (*imports*)
        END ;
        WHILE i < mod.ent DO
          SYSTEM.GET(i, w); Files.WriteInt(R1, w); INC(i, 4)  (*commands*)
        END ;
        p := mod.var;
        WHILE i < mod.ptr DO
          SYSTEM.GET(i, w); Files.WriteInt(R1, w); SYSTEM.PUT(p, w); INC(i, 4); INC(p, 4)  (*copy entries to variable area*)
        END ;
        mod.ent := mod.var;
        WHILE i < AllocPtr DO
          SYSTEM.GET(i, w); Files.WriteInt(R1, w); INC(i, 4)  (*pointer and procedure variable references*)
        END ;
        mod.pvr := Reused; INC(Reused, AllocPtr - p); AllocPtr := p  (*reuse module area after entries for the next module*)
      ELSIF res >= badkey THEN importing := name;
        WHILE nofimps > 0 DO DEC(nofimps); DEC(import[nofimps].refcnt) END
      END
    END ;
    newmod := mod
  END LinkOne;

  PROCEDURE Link*;  (*link multiple object files together and create a single boot file M.bin from them*)
    VAR i, x: INTEGER; ch: CHAR;
      F: Files.File; R: Files.Rider;
      S: Texts.Scanner;
      M: Module;
      name, name2: ModuleName;
  BEGIN GetArg(S); res := -1;
    IF S.class = Texts.Name THEN
      root := NIL; Start := Modules.AllocPtr ; AllocPtr :=  Start + ModAdr ; Reused := 0;
      GetAppendix(name2, S.s);
      MakeFileName(name, name2, ".elf"); F := Files.New(name); Files.Set(R, F, 0); (* Todo *)
      WriteELF64(R, 0);  (* dummy write *)
      i := Start;
      WHILE i < AllocPtr DO SYSTEM.PUT(i, 0); Files.WriteInt(R, 0); INC(i, 4) END ; (*placeholder*)
      REPEAT LinkOne(name2, M, R); Texts.Scan(S) UNTIL (S.class # Texts.Name) OR (res # noerr);
      IF res = noerr THEN M := root; Texts.WriteString(W, "  linking");
        WHILE M # NIL DO Texts.Write(W, " "); Texts.WriteString(W, M.name);
          Files.Set(R, F, SYSTEM.VAL(INTEGER, M) - Start + M.pvr + 48+ elfheader); Files.WriteInt(R, M.refcnt);  (*insert refcnt*)
          M := M.next
        END ;
        SYSTEM.GET(Start, x );  (*address of initialization body of the top module relative to Start*)
        IF versionkey = a32 THEN
          SYSTEM.PUT(Start, a32B + x DIV 4 - a32dPC);  (*branch instruction to the initialization body of the top module*)  
        ELSIF versionkey = a64 THEN
          SYSTEM.PUT(Start, -1);  (* ToDo *)
        ELSIF versionkey MOD 40H = v32 THEN
          SYSTEM.PUT(Start, vJAL + SetJimm(x));  (*branch instruction to the initialization body of the top module*)
        ELSIF versionkey = mps THEN
          SYSTEM.PUT(Start, mpsJAL + (x + pbase ) DIV 4);  (*branch instruction to the initialization body of the top module*)
        END;
        SYSTEM.PUT(Start + TrapAdr, 0);  (*trap handler, typically overwritten by the inner core*)
        SYSTEM.PUT(Start + DestAdr, 0);  (*destination address of the prelinked, executable binary*)
        SYSTEM.PUT(Start + MemAdr, 1000000H);  (*limit of available memory, typically overwritten by the boot loader*)
        SYSTEM.PUT(Start + AllocAdr, AllocPtr + Reused - Start + pbase );  (*address of the end of the module space loaded*)
        SYSTEM.PUT(Start + RootAdr, SYSTEM.VAL(INTEGER, root) - Start + root.pvr + pbase);  (*current root of the loaded modules*)
        SYSTEM.PUT(Start + StackAdr, 100000H);  (*current limit of the module area, typically overwritten by the boot loader*)
        SYSTEM.PUT(Start + FPrintAdr, FPrint);  (*fingerprint*)
        Files.Set(R, F, 0); i := Start;
        IF versionkey > 40H THEN WriteELF64(R, AllocPtr + Reused - Start);
        ELSE WriteELF32(R, AllocPtr + Reused - Start);
        END;
        WHILE i < Start + ModAdr DO SYSTEM.GET(i, x); Files.WriteInt(R, x); INC(i, 4) END ; (*insert boot parameters*)
        Texts.WriteInt(W, AllocPtr + Reused - Start, 7); Files.Register(F);
      ELSE
        Texts.WriteString(W, "Link error:  "); Texts.WriteString(W, importing);
        IF res = nofile THEN Texts.WriteString(W, " module not found")
        ELSIF res = badversion THEN Texts.WriteString(W, " bad version")
        ELSIF res = badkey THEN Texts.WriteString(W, " imports ");
          Texts.WriteString(W, imported); Texts.WriteString(W, " with bad key")
        ELSIF res = badfile THEN Texts.WriteString(W, " corrupted obj file")
        ELSIF res = nospace THEN Texts.WriteString(W, " insufficient space")
        END
      END
    ELSE Texts.WriteString(W, "Usage: ORL.Link [module...] topmodule")
    END ;
    EndLine; root := NIL
  END Link;

  PROCEDURE Load*;  (*load prelinked boot file M.bin onto the boot area of the local disk*)
    VAR i, secno: LONGINT; b: BYTE;
      F: Files.File; R: Files.Rider;
      S: Texts.Scanner;
      buf: ARRAY Disk.SectorLength OF BYTE;
  BEGIN GetArg(S); res := -1;
    IF S.class = Texts.Name THEN
      Texts.WriteString(W, "  loading "); Texts.WriteString(W, S.s); F := Files.Old(S.s);
      IF F # NIL THEN Texts.WriteString(W, " onto boot area"); Texts.WriteInt(W, Files.Length(F), 7);
        secno := BootSec; i := 0; Files.Set(R, F, 0); Files.ReadByte(R, b); res := noerr;
        WHILE ~R.eof DO buf[i] := b; INC(i);
          IF i = Disk.SectorLength THEN Disk.PutSector(secno*29, buf); INC(secno); i := 0 END ;
          Files.ReadByte(R, b)
        END ;
        IF i > 0 THEN
          WHILE i < Disk.SectorLength DO buf[i] := 0; INC(i) END ;
          Disk.PutSector(secno*29, buf); INC(secno)
        END ;
        FOR i := 0 TO Disk.SectorLength-1 DO buf[i] := 0 END ;
        WHILE secno < BootSize DO Disk.PutSector(secno*29, buf); INC(secno) END
      ELSE Texts.WriteString(W, " not found")
      END
    ELSE Texts.WriteString(W, "Usage: ORL.Load M.bin")
    END ;
    EndLine
  END Load;

  PROCEDURE RelocateLoaded*(start, dst: INTEGER);  (*relocate prelinked binary loaded at Mem[start] for execution at dst*)
    VAR p, i, j, x, y, im: INTEGER; M: Module;
  BEGIN SYSTEM.GET(start + DestAdr, x); SYSTEM.PUT(start + DestAdr, dst); SYSTEM.GET(start + RootAdr, p);
    p := p + start; dst := dst - x; start := start - x;
    WHILE p # 0 DO (*fixup*)
      M := SYSTEM.VAL(Module, p); p := SYSTEM.VAL(INTEGER, M.next);
      IF p # 0 THEN M.next := SYSTEM.VAL(Module, p + dst); p := p + start END ;
      i := M.tdx + start; j := M.prg + start;
      WHILE i < j DO  (*type descriptors*)
        SYSTEM.GET(i, x); INC(i, 4); y := -x-1;  (*nofmth*)
        WHILE y > 0 DO SYSTEM.GET(i, x);
          IF x > 0 THEN (*not an imported hidden method*) SYSTEM.PUT(i, x + dst) END ;  (*methods*)
          INC(i, 4); DEC(y)
        END ;
        INC(i, 4);  (*size*)
        FOR y := 0 TO 2 DO SYSTEM.GET(i, x);
          IF x # -1 THEN SYSTEM.PUT(i, x + dst) END ;  (*base types*)
          INC(i, 4)
        END ;
        SYSTEM.GET(i, x);
        WHILE x # -1 DO SYSTEM.PUT(i, x + dst); INC(i, 4); SYSTEM.GET(i, x) END ;  (*pointer offsets*)
        INC(i, 4); SYSTEM.GET(i, x);
        WHILE x # -1 DO SYSTEM.PUT(i, x + dst); INC(i, 4); SYSTEM.GET(i, x) END ;  (*procedure variable offsets*)
        INC(i, 4)
      END ;
      j := M.imp + start;
      WHILE i < j DO SYSTEM.GET(i, x);  (*code*)
(*
        IF x DIV C28 * C28 + x DIV C16 MOD C8 * C16 = MOV+U+B THEN  (*marked as fixed up via the B bit*)
          SYSTEM.GET(i+4, y); im := x MOD C16 * C16 + y MOD C16 + dst;
          SYSTEM.PUT(i, x DIV C16 * C16 + im DIV C16);
          SYSTEM.PUT(i+4, y DIV C16 * C16 + im MOD C16); INC(i, 4)
        END ;
*)
        INC(i, 4)
      END ;
      j := M.cmd + start;
      WHILE i < j DO SYSTEM.GET(i, x); SYSTEM.PUT(i, x + dst); INC(i, 4) END ;  (*imports*)
      i := M.ptr + start; SYSTEM.GET(i, x);
      WHILE x # 0 DO SYSTEM.PUT(i, x + dst); INC(i, 4); SYSTEM.GET(i, x) END ;  (*pointer references*)
      i := M.pvr + start; SYSTEM.GET(i, x);
      WHILE x # 0 DO SYSTEM.PUT(i, x + dst); INC(i, 4); SYSTEM.GET(i, x) END ;  (*procedure variable references*)
      M.var := M.var + dst;
      M.str := M.str + dst;
      M.tdx := M.tdx + dst;
      M.prg := M.prg + dst;
      M.imp := M.imp + dst;
      M.cmd := M.cmd + dst;
      M.ent := M.ent + dst;
      M.ptr := M.ptr + dst;
      M.pvr := M.pvr + dst;
      IF M.final # NIL THEN M.final := SYSTEM.VAL(Command, SYSTEM.VAL(INTEGER, M.final) + dst) END
    END
  END RelocateLoaded;

  PROCEDURE Relocate*;  (*relocate prelinked binary M.bin for execution at destadr and write result to output file R.bin*)
    VAR i, start, filelen, destadr, fprint: INTEGER; b: BYTE;
      name, name1: ARRAY 32 OF CHAR;
      F: Files.File; R: Files.Rider;
      S: Texts.Scanner;
  BEGIN GetArg(S); res := -1;
    IF S.class = Texts.Name THEN name := S.s; Texts.Scan(S);
      IF S.class = Texts.Name THEN name1 := S.s; Texts.Scan(S);
        IF S.class = Texts.Int THEN destadr := S.i; res := -2;
          Texts.WriteString(W, "  relocating "); Texts.WriteString(W, name); Texts.WriteString(W, " to ");
          Texts.WriteString(W, name1);
          IF destadr >= 0 THEN F := Files.Old(name);
            IF F # NIL THEN filelen := Files.Length(F);
              IF filelen > ModAdr THEN start := Modules.AllocPtr;
                IF start + filelen < limit THEN
                  Files.Set(R, F, 0); Files.ReadByte(R, b); i := start;
                  WHILE ~R.eof DO SYSTEM.PUT(i, b); INC(i); Files.ReadByte(R, b) END ;
                  SYSTEM.GET(start + FPrintAdr, fprint);  (*fingerprint*)
                  IF fprint = FPrint THEN res := noerr;
                    Texts.WriteString(W, " at address "); Texts.WriteHex(W, destadr);
                    RelocateLoaded(start, destadr);
                    F := Files.New(name1); Files.Set(R, F, 0); i := start;
                    WHILE i < start + filelen DO SYSTEM.GET(i, b); Files.WriteByte(R, b); INC(i) END ;
                    Files.Register(F); Texts.WriteInt(W, Files.Length(F), 7)
                  ELSE Texts.WriteString(W, "  input file format error")
                  END
                ELSE Texts.WriteString(W, "  insufficient space")
                END
              ELSE Texts.WriteString(W, "  input file error")
              END
            ELSE Texts.WriteString(W, "  input file not found")
            END
          ELSE Texts.WriteString(W, "  destadr must be >= 0")
          END
        END
      END
    END ;
    IF res = -1 THEN Texts.WriteString(W, "Usage: ORL.Relocate M.bin R.bin destadr") END ;
    EndLine
  END Relocate;

  PROCEDURE Run*;  (*load and execute prelinked binary M.bin*)
    VAR i, start, filelen, fprint: INTEGER; b: BYTE;
      body: Modules.Command;
      F: Files.File; R: Files.Rider;
      S: Texts.Scanner;
  BEGIN GetArg(S); res := -1;
    IF S.class = Texts.Name THEN
      Texts.WriteString(W, "  executing "); Texts.WriteString(W, S.s);
      F := Files.Old(S.s);
      IF F # NIL THEN filelen := Files.Length(F);
        IF filelen > ModAdr THEN start := Modules.AllocPtr;
          IF start + filelen < limit THEN
            Files.Set(R, F, 0); Files.ReadByte(R, b); i := start;
            WHILE ~R.eof DO SYSTEM.PUT(i, b); INC(i); Files.ReadByte(R, b) END ;
            SYSTEM.GET(start + FPrintAdr, fprint);  (*fingerprint*)
            IF fprint = FPrint THEN res := noerr;
              Texts.WriteString(W, " at address "); Texts.WriteHex(W, start);
              RelocateLoaded(start, start);
              body := SYSTEM.VAL(Command, start); body  (*branch to initialization body of top module*)
            ELSE Texts.WriteString(W, "  input file format error")
            END
          ELSE Texts.WriteString(W, "  insufficient space")
          END
        ELSE Texts.WriteString(W, "  input file error")
        END
      ELSE Texts.WriteString(W, " not found")
      END
    ELSE Texts.WriteString(W, "Usage: ORL.Run M.bin")
    END ;
    EndLine
  END Run;

  PROCEDURE ExtractCode(F: Files.File; start: INTEGER; VAR codelen, entry, res: INTEGER);
    VAR n, p, data: INTEGER;                           (*codelen in words, entry in bytes*)
      ch: CHAR; b: BYTE;
      R: Files.Rider;
      name: ARRAY 32 OF CHAR;
  BEGIN Files.Set(R, F, 0); Files.ReadString(R, name); Files.ReadInt(R, data); (*key*)
    Files.ReadByte(R, b); (*version*) Files.ReadInt(R, data); (*size*)
    Files.ReadString(R, name); (*imports*)
    WHILE ~R.eof & (name[0] # 0X) DO Files.ReadInt(R, data); (*key*) Files.ReadString(R, name) END ;
    Files.ReadInt(R, n); (*variable space*)
    Files.ReadInt(R, n); Files.Set(R, F, Files.Pos(R) + n); (*strings*)
    Files.ReadInt(R, n); Files.Set(R, F, Files.Pos(R) + n); (*type descriptors*)
    Files.ReadInt(R, n); codelen := n;
    IF start + n < limit THEN p := start;
      WHILE ~R.eof & (n > 0) DO Files.ReadInt(R, data); SYSTEM.PUT(p, data); INC(p, 4); DEC(n) END ; (*program code*)
      Files.ReadString(R, name);
      WHILE ~R.eof & (name[0] # 0X) DO Files.ReadInt(R, data); Files.ReadString(R, name) END ; (*commands*)
      Files.ReadInt(R, n); Files.Set(R, F, Files.Pos(R) + n*4); (*entries*)
      Files.ReadInt(R, data);
      WHILE ~R.eof & (data >= 0) DO Files.ReadInt(R, data) END ; (*pointer references*)
      Files.ReadInt(R, data);
      WHILE ~R.eof & (data >= 0) DO Files.ReadInt(R, data) END ; (*procedure variable references*)
      Files.ReadInt(R, data); (*fixorgP*) Files.ReadInt(R, data); (*fixorgD*)
      Files.ReadInt(R, data); (*fixorgT*) Files.ReadInt(R, data); (*fixorgM*)
      Files.ReadInt(R, entry); (*body*) Files.ReadInt(R, data); (*final*)
      Files.Read(R, ch);
      IF ch # "O" THEN res := badfile ELSE res := noerr END
    ELSE res := nospace
    END
  END ExtractCode;

  PROCEDURE Execute*;  (*extract, load and execute code section of standalone program M.rsc*)
    VAR start, codelen, entry: INTEGER;  (*codelen in words, entry in bytes*)
      body: Command;
      F: Files.File;
      S: Texts.Scanner;
  BEGIN GetArg(S); res := -1;
    IF S.class = Texts.Name THEN
      Texts.WriteString(W, "  executing "); Texts.WriteString(W, S.s);
      F := Files.Old(S.s);
      IF F # NIL THEN start := Modules.AllocPtr;
        ExtractCode(F, start, codelen, entry, res);
        IF res = noerr THEN
          Texts.WriteString(W, " at address "); Texts.WriteHex(W, start + entry);
          body := SYSTEM.VAL(Command, start + entry); body
        ELSIF res = nospace THEN Texts.WriteString(W, " program too long")
        ELSIF res = badfile THEN Texts.WriteString(W, " input file format error")
        END
      ELSE Texts.WriteString(W, " not found")
      END
    ELSE Texts.WriteString(W, "Usage: ORL.Execute M.rsc")
    END ;
    EndLine
  END Execute;

BEGIN Texts.OpenWriter(W); Texts.WriteString(W, "E2OL Boot linker/loader  AP 15.5.24"); EndLine;
  limit := Kernel.stackOrg - Kernel.stackSize
END E2OL.
