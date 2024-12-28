MODULE OvG; (* N.Wirth, 16.4.2016 / 4.4.2017 / 31.5.2019  Oberon compiler; code generator for RISC / AP 1.5.24 Extended Oberon*)
  IMPORT SYSTEM, Files, ORS, ORB;
  (*Code generator for Oberon compiler for RISC processor.
     Procedural interface to Parser ORP; result in array "code".
     Procedure Close writes code-files*)
(*
    RISC-V32 version

    all changes by Peter Matthias

    code size can be 2GB;
    2024-08-18  started, based on ORGV32.Mod dated 2023-03-21
    2024-10-17  LDREG and Register changed to map virtual registers  
    2024-11-18  fixcode, fixvar: optimized encoding for 127 Module imports
    2024-11-23  Set: improved and unified
    2024-11-27  Added LargeCode to allow for code sizes > 1MB
    2024-12-07  split to OvG.Mod with 32 bit and OVG.Mod with 64bit
    2024-12-19  LDREG, Register: mapping RISC5 registers to RISC-V
    2024-12-28  Method, ReceiverParam: applied changes from EOS 

    ROR not tested

*)

  CONST version = 4X;  appendix = ".v32";  WordSize* = 4;
    dPC = 0;  minR = 10; TR = 23; SP = 2 ; RA = 1 ; T0= 5 ; ZR = 0 ;  (*dedicated registers, TR is temporary register*)
    LargeCode = FALSE;  (* codesize > 1MB *)
    TrapAdr = 4;
    TrapArray=1; TrapTypeGuard=2; TrapCopyOV=3; TrapNIL=4; TrapIllProc=5; TrapDivZero=6; TrapAssert=7;
    maxCode = 12000; maxStrx = 3500; maxTD = 160; maxSet = WordSize * 8;
    Reg = 10; RegI = 11; Cond = 12;  (*internal item modes*)
    notimplemented="not implemented";

    B32 = 0; (* 0 is 32 bit; 8 is 32bit instructions on risc-v64*)
    (* RV32I Base opcodes *)
    LUI = 37H; AUIPC = 17H; JAL = 6FH; JALR = 67H;
    BEQ = 63H; BNE = 1063H; BLT = 4063H; BGE = 5063H; BLTU = 6063H; BGEU = 7063H;
    LB = 3H; LH = 1003H; LW = 2003H; LBU = 4003H; LHU = 5003H;
    SB = 23H; SH = 1023H; SW = 2023H;
    ADDI = 13H+B32; SLTI = 2013H; SLTIU = 3013H; XORI = 4013H; ORI = 6013H; ANDI = 7013H;
    SLLI = 1013H+B32; SRLI = 5013H+B32; SRAI = 40005013H+B32;
    ADD = 33H+B32; SUB = 40000033H+B32; 
    SLL = 1033H+B32; SLT = 2033H; SLTU = 3033H; XOR = 4033H; SRL = 5033H+B32; SRA = 40005033H+B32;
    ORR = 6033H; AND = 7033H;
    ECALL = 73H; SBREAK = 100073H; NOP = 13H; (* ADDI  0, 0, 0 *)

    (* RV32M *)
    MUL =  02000033H+B32; MULH = 02001033H; MULHSU = 02004033H; MULHU = 02003033H;
    DIVS = 02004033H+B32; DIVU = 02005033H+B32; REM = 02006033H+B32; REMU = 02007033H+B32;

    (* RV32F *)
    FLW = 2007H; FSW = 2027H; 
    RDN = 2000H; RM = RDN; (* rounding mode down *)  RNE = 0;
    FMADD = RNE + 43H; FMSUB = RNE + 47H; FNSUB = RNE + 4BH; FNMADD = RNE + 4FH;
    FADD = RNE + 53H; FSUB = RNE + 08000053H; FMUL = RNE + 10000053H; FDIV = RNE + 18000053H;
    FEQ = 0A0002053H; FLT = 0A0001053H; FLE = 0A0000053H;
    FCVTWF = RM+0C0000053H; FMVXS = 0E0000053H; FCVTFX = RM+0D0000053H; FMVSX = 0F0000053H;
    FSGNJS = 20000053H; FMV = FSGNJS; FSGNJN = 20001053H; FNEG = FSGNJN; FSGNJX = 20002053H; FABS = FSGNJX;

    (*FENCEI=100FH;  XTRAP=702BH; custom extension to get SIGILL, trap no. starts at bit 15 *)

    C4 = 10H; C6 = 40H; C8 = 100H; C10 = 400H; C12 = 1000H; C14 = 4000H; C15 = 8000H; C16 = 10000H; C18 = 40000H; C19 = 80000H;
    C20 = 100000H; C22 = 400000H; C24 = 1000000H; C26 = 4000000H; C28 = 10000000H; C30 = 40000000H;

    TYPE Item* = RECORD
      mode*: INTEGER;
      type*: ORB.Type;
      obj*: ORB.Object;
      a*, b*, r: INTEGER;
      rdo*, deref, super: BOOLEAN  (*read only, dereferenced, super call*)
    END ;
    LabelRange* = RECORD low*, high*, label*: INTEGER END ;

  (* Item forms and meaning of fields:
    mode    r      a       b
    --------------------------------
    Const   -     value (proc adr)  (immediate value)
    Var     base   off     -               (direct adr)
    Par      -     off0     off1         (indirect adr)
    Reg    regno
    RegI   regno   off     -
    Cond  cond   Fchain  Tchain  *)

  VAR pc*: INTEGER;    (*program counter*)
    varx, strx, tdw: INTEGER;  (*varx and strx in bytes, tdw in words*)
    entry, final: INTEGER;   (*main entry point, finalization sequence*)
    RH: INTEGER;  (*available registers R[0] ... R[H-1]*)
    frame: INTEGER;  (*frame offset changed in SaveRegs and RestoreRegs*)
    fixorgP, fixorgD, fixorgT, fixorgM: INTEGER;   (*origins of lists of locations to be fixed up by loader*)
    check: BOOLEAN;  (*emit run-time checks*)

    relmap: ARRAY 6 OF INTEGER;  (*condition codes for relations*)
    code: ARRAY maxCode OF INTEGER;
    str: ARRAY maxStrx OF CHAR;  (*strings*)
    td: ARRAY maxTD OF INTEGER;  (*type descriptors*)

    condf: ARRAY 8 OF INTEGER;

  PROCEDURE incR;
  BEGIN
    IF RH < TR -1 THEN INC(RH) ELSE ORS.Mark("register stack overflow") END
  END incR;

  PROCEDURE PutR(op, rd, rs1, rs2: INTEGER);
  BEGIN (*emit format-0 register instruction*)
    code[pc] := op+LSL(rd, 7)+LSL(rs1, 15)+LSL(rs2, 20); INC(pc)
  END PutR;

  PROCEDURE PutI(op, rd, rs1, im: INTEGER);  (* also used for Load with 12bit signed offset*)
  BEGIN
    IF (im DIV 1000H) # (im DIV 800H) THEN ORS.Mark("PutI") END; 
    code[pc] := op+LSL(rd, 7)+LSL(rs1, 15)+LSL(im, 20); INC(pc)
  END PutI;

  PROCEDURE PutUa( op, rd, im: INTEGER);  (* put upper part adjusted with sign bit of lower part in rd *)
  BEGIN 
    code[pc] := op+LSL(rd , 7)+LSL( im DIV 1000H+ (im DIV 800H) MOD 2, 12); INC(pc)
  END PutUa;

  PROCEDURE PutMOV( rd, rs: INTEGER);
  BEGIN  PutI( ADDI, rd, rs, 0);
  END PutMOV;

  PROCEDURE PutMOVI( rd, im: INTEGER);
  BEGIN
    IF ASR(im, 11) # ASR(im, 12) THEN
      PutUa( LUI, rd, im);
      IF im MOD 1000H # 0 THEN PutI( ADDI, rd, rd, im * C20 DIV C20) END;
    ELSE PutI( ADDI, rd, ZR, im);
    END;
  END PutMOVI;

  PROCEDURE PutL(op, rd, rs1, off: INTEGER);  (* load with 32 bit offset*)
  VAR r : INTEGER;
  BEGIN
    IF (off DIV 1000H) = (off DIV 800H) THEN r := rs1
    ELSE PutUa( LUI, TR, off); PutR( ADD, TR, TR, rs1); r := TR;
    END; 
    code[pc] := op+LSL(rd, 7)+LSL(r, 15)+LSL(off MOD 1000H, 20); INC(pc)
  END PutL;

  PROCEDURE PutS(op, rs2, rs1, off: INTEGER);  (* store with 32 bit offset*)
  VAR r : INTEGER;
  BEGIN
    IF (off DIV 1000H) = (off DIV 800H) THEN r := rs1
    ELSE PutUa( LUI, TR, off); PutR( ADD, TR, TR, rs1); r := TR;
    END;
    code[pc] := op+LSL( rs2 , 20)+LSL( r, 15)+LSL(off DIV 20H MOD 80H, 25)+off MOD 20H * 80H; INC(pc)
  END PutS;

  PROCEDURE SetBimm( imm: INTEGER): INTEGER;  (* imm in bytes +- 4KiB *)
  BEGIN
    IF ASR(imm, 13) # ASR(imm, 12)  THEN ORS.Mark("branch distance >4KB") END;
    RETURN LSL(imm DIV 1000H, 31)+LSL( imm DIV 20H MOD 40H, 25)+ imm MOD 20H * 80H+imm DIV 800H MOD 2 * 80H 
  END SetBimm;

  PROCEDURE PutB(op, rs1, rs2, off: INTEGER);  (* Bcc; check for condition *)
  BEGIN
    code[pc] := op+LSL(rs1, 15)+LSL(rs2, 20)+ SetBimm( off );
    INC(pc)
  END PutB;

PROCEDURE PutBi( op, rs1, rs2, imm: LONGINT);  (* forward branch, interim branch encoding, imm is next branch to fix *)
BEGIN
  IF imm >= 4000H THEN ORS.Mark("PutBi"); imm:= 0 END;
  code[ pc]:= op DIV 1000H + rs1 * 8 + rs2 * 100H + imm * 10000H;
  INC(pc)
END PutBi;

  PROCEDURE SetJimm( imm: INTEGER): INTEGER;  (* imm in bytes *)
  BEGIN
    IF ASR(imm, 21)# ASR(imm, 20) THEN ORS.Mark("SetUJimm too big") END;
    RETURN LSL(ASR( imm, 20), 31)+LSL( imm MOD 800H, 20)+LSL( ASR(imm, 11) MOD 2, 20)
          +LSL( ASR(imm, 12) MOD 100H, 12)
  END SetJimm;

  PROCEDURE PutJAL(rd, off: INTEGER);  (* JAL *)
  BEGIN
    code[pc] := JAL+ LSL(rd, 7) + SetJimm( off); INC(pc);
  END PutJAL;

  PROCEDURE PutI32(op, rd, rs1, im: INTEGER);  (* op can be: addi, slti, sltiu, xori, ori, andi *)
  BEGIN (*same as PutI, but with range test -C12 <= im < C12*)
    IF ASR(im, 11) = ASR(im, 12) THEN PutI(op, rd, rs1, im)
    ELSE
      PutMOVI(TR, im);  (* don"t use RH while adjusting SP *)
      PutR( op+20H, rd, rs1, TR);
    END        
  END PutI32;

PROCEDURE fixcode( mno, pno: INTEGER);
(* fixorgP format: (mno 8bit, pno 8bit, mno > 0 1 bit, displacement 15bit) *)
BEGIN
  IF pc - fixorgP >= 2000H THEN ORS.Mark("fixcode displacement")
  ELSIF mno < - 0FFH THEN ORS.Mark("fixcode mno too big")
  ELSIF (mno # 0) & (pno > 0FFH) THEN ORS.Mark("fixcode pno >= 255")
  ELSE
    code[ pc] :=  - mno * C24 + pno * C16 + ORD(mno # 0) * C15 + (pc - fixorgP) * 2; fixorgP := pc; 
    code[ pc + 1] := NOP; INC(pc, 1 + ORD( LargeCode))  (* for code size > 1MB ; INC(pc, 2) and adjust branch distance in Trap*)
  END;
END fixcode;

PROCEDURE fixvar( mno, vno: INTEGER);
(* fixorgD (mno 7bit, vno 8bit, mno > 0 1 bit, displacement 15bit) check FixLinkPair, static and dynamic linker and disassembler*)
BEGIN
  IF (pc - fixorgD >=  800H) THEN ORS.Mark("fixvar displacement")
  ELSIF mno < -0FFH THEN ORS.Mark("fixvar mno too big")
  ELSIF (mno # 0) & (vno > 0FFH) THEN ORS.Mark("fixvar vno > 255")
  ELSIF (vno > 0FFFFH) THEN ORS.Mark("fixvar vno > 64K")
  ELSE
    code[ pc] :=  - mno * C24 + vno * C16 + ORD(mno # 0) * C15 + (pc - fixorgD) * 2; fixorgD := pc; INC( pc);
  END;
END fixvar;

  PROCEDURE CheckRegs*;
  BEGIN
    IF RH # minR THEN ORS.Mark("Reg Stack"); RH := minR END ;
    IF pc >= maxCode - 40 THEN ORS.Mark("program too long") END ;
    IF frame # 0 THEN ORS.Mark("frame error"); frame := 0 END
  END CheckRegs;

  PROCEDURE SetCC(VAR x: Item; n, r1, r2: INTEGER);
  BEGIN x.mode := Cond; x.a := 0; x.b := 0;
    IF n<0 THEN x.r:= -n+LSL(r2, 15)+LSL(r1, 20);
    ELSE x.r := n+LSL(r1, 15)+LSL(r2, 20);  (* x.r is B format *)
    END;
  END SetCC;

  PROCEDURE negated(cond: INTEGER): INTEGER;
  BEGIN
    RETURN ORD( SYSTEM.VAL(SET, cond) / {12})
  END negated;

  PROCEDURE Trap(cond, r1, r2, num: INTEGER);
  VAR i: INTEGER;
  BEGIN
    IF num = 0 THEN i:= 0 ELSE i:= ORS.Pos() END;
    IF (cond # BEQ) OR (r1 # r2) THEN PutB( negated(cond), r1, r2, 12 + ORD(LargeCode) * 4 - dPC) END;
    PutUa( LUI, TR, (i * 10H + num)* 1000H);
    fixcode( -0FFH, 0FFH );
  END Trap;

  PROCEDURE NilCheck( r: INTEGER);
  BEGIN IF check THEN Trap(BEQ, r, ZR, TrapNIL) END
  END NilCheck;

  (*handling of forward reference, fixups of instruction operands*)

  PROCEDURE fixI(at, with: INTEGER);
    VAR v: INTEGER;
  BEGIN (*fix register immediate instruction*)
    IF (with < 0) OR (with > 800H) THEN ORS.Mark("p.m.: fixI out of bounds") END ;
    code[at] := code[at] MOD C20 + with * C20;
  END fixI;

  PROCEDURE fixB(at, with: INTEGER);
  VAR c: INTEGER;
  BEGIN (*fix branch instruction*)
    c:=code[at];
    IF c MOD 10000H = 0 THEN code[at] := JAL + SetJimm( with * 4);
    ELSE code[at] := BEQ + c MOD 10000H * 1000H + SetBimm( with);
    END;
  END fixB;

  PROCEDURE FixOne*(at: INTEGER);
  BEGIN fixB(at, pc-at-dPC)
  END FixOne;

  PROCEDURE FixLinkWith(L, dst: INTEGER); (* in words *)
    VAR L1, c, disp: INTEGER;
  BEGIN (*fix chain of branch instructions*)
(*    WHILE L # 0 DO L1 := code[L] MOD C24; fixB(L, dst-L); L := L1 END*)

    WHILE L # 0 DO
      c := code[L];
      disp := (dst -L) * 4;
      L1:= c DIV 10000H;
      IF c MOD 10000H = 0 THEN code[ L]:= JAL+ SetJimm(disp);
      ELSE
        IF (disp DIV 2000H) # (disp DIV 1000H) THEN  (* in bytes *)
          IF (dst = pc) THEN  (* conditional forward jump > 4K *)
            code[L]:= JAL + SetJimm( disp + 4);
            PutJAL( ZR , 12);
            PutB(BEQ + c * 1000H, ZR, ZR, 8);
            PutJAL( ZR , -disp -4);
          ELSE ORS.Mark("FixLinkWidth range"); L1 := 0;
          END;
        ELSE code[L]:= BEQ + c MOD 10000H * 1000H +  SetBimm( disp );
        END;
      END;
      L := L1;
    END;
  END FixLinkWith;

  PROCEDURE FixLink*(L: INTEGER);
  BEGIN FixLinkWith(L, pc)
  END FixLink;

  PROCEDURE FixLinkPair(L, adr: INTEGER); (* TODO*)
    VAR q: INTEGER;
  BEGIN (* fix chain of instruction , 0 <= adr < C16 *)
    IF adr >= 10000H THEN ORS.Mark("p.m. FixLinkPair") END;
    WHILE L # 0 DO q := code[L];
      code[L] :=  adr * C16 + q MOD C16;
      L := q DIV C16 MOD C16;
    END
  END FixLinkPair;

  PROCEDURE merged(L0, L1: INTEGER): INTEGER;
    VAR c, L2, L3: INTEGER;
  BEGIN (*merge chains of the two operands of AND and OR*)
    IF L0 # 0 THEN L3 := L0;
(* ARM, RISC-5
      REPEAT L2 := L3; L3 := code[L2] MOD C16 UNTIL L3 = 0;
      code[L2] := code[L2] + L1; L1 := L0
*)
      REPEAT L2 := L3; c:=code[L2]; L3 := c DIV C16 UNTIL L3 = 0;
      code[ L2]:= c MOD C16 + LSL(L1, 16); L1 := L0;
    END ;
    RETURN L1
  END merged;

  (* loading of operands and addresses into registers *)

  PROCEDURE load(VAR x: Item);
    VAR op, offset: INTEGER;
  BEGIN
    IF x.mode = Reg THEN
      IF (x.type= ORB.realType) THEN PutR( FMVXS, x.r, x.r, 0) END;(* mv float reg to int reg *)
    ELSE
      IF x.type.size = 1 THEN op := LBU ELSE op := LW END ;
      IF x.mode = ORB.Const THEN
        IF x.type.form = ORB.Proc THEN
          IF x.r > 0 THEN (*local*) ORS.Mark("not allowed")
          ELSIF x.r = 0 THEN (*global*) offset := x.a -pc*4; PutUa(AUIPC, RH, offset); PutI(ADDI, RH, RH, offset * C20 DIV C20) 
          ELSE (*imported*) fixvar( x.r+ 80H, x.a); PutI( ADDI, RH, RH, 0)  (*mark as progbase-relative*)
          END;
          x.r := RH; incR;
        ELSE
          IF x.a = 0 THEN PutMOVI( RH, x.a); x.r := RH;  (* ToDo: use ZR *)
          ELSE PutMOVI( RH, x.a); x.r := RH;
          END;
          incR;
        END ;
      ELSIF x.mode = ORB.Var THEN
        IF x.r > 0 THEN (*local*) PutL(op, RH, SP, x.a + frame)
        ELSE fixvar( x.r, x.a); PutI( op, RH, RH, 0); 
        END ;
        x.r := RH; incR
      ELSIF x.mode = ORB.Par THEN PutL(LW, RH, SP, x.a + frame); PutL(op, RH, RH, x.b); x.r := RH; incR
      ELSIF x.mode = RegI THEN PutL(op, x.r, x.r, x.a)
      ELSIF x.mode = Cond THEN
(* ToDo
    IF (x.a = 0) & (x.b = 0) THEN
      op := x.r MOD 8000H; 
      rs1:= x.r DIV 8000H MOD 20H;
      rs2 := x.r DIV 100000H MOD 20H;
      IF  op= BEQ THEN PutR(XOR, RH, rs1, rs2); PutI0(SLTIU, RH, RH, 1);
      ELSIF op = BNE THEN PutR(XOR, RH, rs1, rs2); PutR( SLTU, RH, 0, RH);
      ELSIF op = BLT THEN PutR(SLT, RH, rs1, rs2);
      ELSIF op = -BGE THEN PutR(SLT, RH, rs2, rs1); PutI0(XORI, RH, RH, 1);
      ELSIF op = -BLT THEN PutR(SLT, RH, rs2, rs1);
      ELSIF op = BGE THEN PutR(SLT, RH, rs1, rs2); PutI0(XORI, RH, RH, 1);
      END;
      x.r := RH; incR
    ELSE
*)
        PutB( negated(x.r), 0, 0, 12);
        FixLink(x.b); PutMOVI( RH, 1); PutJAL( ZR, 8);
        FixLink(x.a); PutMOVI( RH, 0); x.r := RH; incR
      END ;
      x.mode := Reg
    END
  END load;

PROCEDURE loadf(VAR x: Item);
BEGIN
  IF (x.type# ORB.realType) THEN ORS.Mark("loadf 0") END;
  IF x.mode # Reg THEN
    IF x.mode = ORB.Const THEN
      IF x.type.form = ORB.Proc THEN ORS.Mark("loadf 1");
      ELSE PutMOVI( RH, x.a); PutR( FMVSX, RH, RH, 0);
      END;
      x.r := RH; incR;
    ELSIF x.mode = ORB.Var THEN
      IF x.r > 0 THEN (*local*) PutL( FLW, RH, SP, x.a + frame)
      ELSE fixvar( x.r, x.a); PutI( FLW, RH, RH, 0); 
      END ;
      x.r := RH; incR;
    ELSIF x.mode = ORB.Par THEN PutL(LW, RH, SP, x.a + frame); PutL( FLW, RH, RH, x.b); x.r := RH; incR;
    ELSIF x.mode = RegI THEN PutI( FLW, x.r, x.r, x.a); 
    ELSIF x.mode = Cond THEN ORS.Mark("loadf 2");
    END ;
    x.mode := Reg;
  END;
END loadf;

  PROCEDURE loadAdr(VAR x: Item);
  BEGIN
    IF x.mode = ORB.Var THEN
      IF x.r > 0 THEN (*local*) PutI32(ADDI, RH, SP, x.a + frame)
      ELSE fixvar( x.r, x.a); PutI( ADDI, RH, RH, 0); (*PutPair(x.r, iADR, RH, RH, x.a)*)
      END ;
      x.r := RH; incR
    ELSIF x.mode = ORB.Par THEN PutL(LW, RH, SP, x.a + frame);
      IF x.b # 0 THEN PutI32(ADDI, RH, RH, x.b) END ;
      x.r := RH; incR
    ELSIF x.mode = RegI THEN
      IF x.a # 0 THEN PutI32(ADDI, x.r, x.r, x.a) END
    ELSE ORS.Mark("address error")
    END ;
    x.mode := Reg
  END loadAdr;

  PROCEDURE loadCond(VAR x: Item);
  BEGIN
    IF x.mode # Cond THEN
      IF x.type.form = ORB.Bool THEN
        IF x.mode = ORB.Const THEN x.r := BNE - x.a*1000H  (* x.a can be 0 or 1 *)
        ELSE load(x);
          x.r := BNE + x.r * 8000H; DEC(RH)
        END ;
        x.mode := Cond; x.a := 0; x.b := 0
      ELSE ORS.Mark("not Boolean?")
      END
    END
  END loadCond;

  PROCEDURE loadTypTagAdr(T: ORB.Type);
  BEGIN
    IF T.mno <= 0 THEN fixvar( 0, T.len); (*PutPair(0, iADR, RH, RH, T.len);*) T.len := pc-1  (*insert into fixorgD chain, fixed up in Close*)
    ELSE (*imported*) fixvar( -T.mno, T.len); (*PutPair(-T.mno, iADR, RH, RH, T.len)*)
    END ;
    PutI( ADDI, RH, RH, 0);
    incR
  END loadTypTagAdr;

  PROCEDURE loadStringAdr(VAR x: Item);
  BEGIN
    IF x.r >= 0 THEN fixvar( x.r, varx + x.a);  (*PutPair(0, iADR, RH, RH, varx + x.a)*)
    ELSE (*imported*) fixvar( x.r,  x.a);  (*PutPair(x.r, iADR, RH, RH, x.a)*)
    END ;
    PutI( ADDI, RH, RH, 0);
    x.mode := Reg; x.r := RH; incR
  END loadStringAdr;

  (* Items: Conversion from constants or from Objects on the Heap to Items on the Stack*)

  PROCEDURE MakeConstItem*(VAR x: Item; typ: ORB.Type; val: INTEGER);
  BEGIN x.mode := ORB.Const; x.type := typ; x.a := val
  END MakeConstItem;

  PROCEDURE MakeRealItem*(VAR x: Item; val: REAL);
  BEGIN x.mode := ORB.Const; x.type := ORB.realType; x.a := SYSTEM.VAL(INTEGER, val)
  END MakeRealItem;

  PROCEDURE MakeStringItem*(VAR x: Item; len: INTEGER);  (*copies string from ORS-buffer to ORG-string array*)
    VAR i: INTEGER;
  BEGIN x.mode := ORB.Const; x.type := ORB.strType; x.a := strx; x.b := len; x.r := 0; i := 0;
    IF strx + len + 4 < maxStrx THEN
      WHILE len > 0 DO str[strx] := ORS.str[i]; INC(strx); INC(i); DEC(len) END ;
      WHILE strx MOD 4 # 0 DO str[strx] := 0X; INC(strx) END
    ELSE ORS.Mark("too many strings")
    END
  END MakeStringItem;

  PROCEDURE MakeItem*(VAR x: Item; y: ORB.Object);
  BEGIN x.obj := y; x.mode := y.class; x.type := y.type; x.a := y.val; x.rdo := y.rdo; x.deref := FALSE;
    IF y.class = ORB.Par THEN x.b := 0
    ELSIF (y.class = ORB.Const) & (y.type.form = ORB.String) THEN x.r := y.lev;
      x.a := y.val MOD C20; (*strx/exno*) x.b := y.val DIV C20 (*len*)
    ELSE x.r := y.lev
    END
  END MakeItem;

  (* Code generation for Selectors, Variables, Constants *)

  PROCEDURE Field*(VAR x: Item; y: ORB.Object);   (* x := x.y *)
  BEGIN x.deref := FALSE;
    IF x.mode = ORB.Var THEN
      IF x.r >= 0 THEN x.a := x.a + y.val
      ELSE (*imported*) loadAdr(x); x.mode := RegI; x.a := y.val
      END
    ELSIF x.mode = RegI THEN x.a := x.a + y.val
    ELSIF x.mode = ORB.Par THEN x.b := x.b + y.val
    END
  END Field;

  PROCEDURE Index*(VAR x, y: Item);   (* x := x[y] *)
    VAR s, i, lim: INTEGER;
  BEGIN s := x.type.base.size; lim := x.type.len; x.deref := FALSE;
    IF (y.mode = ORB.Const) & (y.a < 0) THEN ORS.Mark("bad index") END ;
    IF (y.mode = ORB.Const) & (lim >= 0) THEN
      IF y.a >= lim THEN ORS.Mark("bad index") END ;
      IF x.mode = ORB.Var THEN
        IF x.r >= 0 THEN x.a := y.a * s + x.a
        ELSE (*imported*) loadAdr(x); x.mode := RegI; x.a := y.a * s
        END
      ELSIF x.mode = RegI THEN x.a := y.a * s + x.a
      ELSIF x.mode = ORB.Par THEN x.b := y.a * s + x.b
      END
    ELSE load(y);
      IF check THEN  (*check array bounds*)
        IF lim >= 0 THEN PutMOVI(RH, lim)
        ELSIF x.mode IN {ORB.Var, ORB.Par} THEN (*open array param*) PutL(LW, RH, SP, x.a + 4 + frame);
        ELSIF x.mode = RegI THEN (*dynamic open array*) PutI(LW, RH, x.r, -16); (*len*) 
        ELSE ORS.Mark("error in Index")
        END ;
        Trap(BGE, y.r, RH, TrapArray)
      END ;
      IF s = 4 THEN PutR(SLLI, y.r, y.r, 2) ELSIF s > 1 THEN PutMOVI( RH, s); PutR(MUL, y.r, y.r, RH) END ;
      IF x.mode = ORB.Var THEN
        IF x.r > 0 THEN (*local*) PutR(ADD, y.r, y.r, SP); INC(x.a, frame)
        ELSE (*imported*) fixvar( x.r, x.a); PutI( ADDI, RH, RH, 0); PutR(ADD, y.r, y.r, RH); x.a := 0
        END ;
        x.r := y.r; x.mode := RegI
      ELSIF x.mode = ORB.Par THEN
        PutI(LW, RH, SP, x.a + frame);
        PutR(ADD, y.r, y.r, RH); x.mode := RegI; x.r := y.r; x.a := x.b
      ELSIF x.mode = RegI THEN PutR(ADD, x.r, x.r, y.r); DEC(RH)
      END
    END
  END Index;

  PROCEDURE DeRef*(VAR x: Item);
  BEGIN
    IF x.mode = ORB.Var THEN
      IF x.r > 0 THEN (*local*) PutI(LW, RH, SP, x.a + frame)
      ELSE fixvar( x.r, x.a); PutI( LW, RH, RH, 0) (*PutPair(x.r, iLW, RH, RH, x.a)*)
      END ;
      NilCheck( RH); x.r := RH; incR
    ELSIF x.mode = ORB.Par THEN
      PutI(LW, RH, SP, x.a + frame); PutI(LW, RH, RH, x.b); NilCheck( RH); x.r := RH; incR
    ELSIF x.mode = RegI THEN PutI(LW, x.r, x.r, x.a); NilCheck(x.r)
    ELSIF x.mode # Reg THEN ORS.Mark("bad mode in DeRef")
    END ;
    IF x.type.base.form = ORB.Array THEN PutI(ADDI, x.r, x.r, 16) END ; (*pointer to array*)
    x.mode := RegI; x.a := 0; x.b := 0; x.deref := TRUE
  END DeRef;

  PROCEDURE Method*(VAR x: Item; y: ORB.Object; super: BOOLEAN);
  BEGIN loadAdr(x); (*receiver*) x.super := super;
    IF super THEN x.a := y.val; (*mthadr/exno*) x.b := -y.type.mno
    ELSE x.a := y.lev; (*mthno*)
      IF x.deref THEN x.b := ORB.Var ELSE x.b := ORB.Par END
    END
  END Method;

  PROCEDURE Q(T: ORB.Type; VAR tdw: INTEGER);
  BEGIN (*one entry of type descriptor extension table*)
    IF T.base # NIL THEN
      Q(T.base, tdw); td[tdw] := (T.mno*C12 + T.len (*TDoff/exno*)) * C12 + tdw - fixorgT;
      fixorgT := tdw; INC(tdw)
    END
  END Q;

  PROCEDURE FindRefFlds(ftyp: SET; typ: ORB.Type; off: INTEGER; VAR tdw: INTEGER);
    VAR fld: ORB.Object; i, s: INTEGER;
  BEGIN
    IF typ.form IN ftyp THEN td[tdw] := off; INC(tdw)
    ELSIF typ.form = ORB.Record THEN fld := typ.dsc;
      WHILE fld # NIL DO FindRefFlds(ftyp, fld.type, fld.val + off, tdw); fld := fld.next END
    ELSIF typ.form = ORB.Array THEN s := typ.base.size;
      FOR i := 0 TO typ.len-1 DO FindRefFlds(ftyp, typ.base, i*s + off, tdw) END
    END
  END FindRefFlds;

  PROCEDURE BuildTD(T: ORB.Type; VAR tdw: INTEGER);
    VAR k, s: INTEGER; fld, bot: ORB.Object; t: ORB.Type;
  BEGIN (*type descriptors of base types of T already built*)
    k := ORB.NofMethods(T); td[tdw] := -k-1; INC(tdw); s := tdw;
    WHILE k > 0 DO td[tdw] := -1; INC(tdw); DEC(k) END ;
    t := T; fld := NIL;  (*build method table*)
    WHILE t # NIL DO fld := t.dsc;
      IF t.base # NIL THEN bot := t.base.dsc ELSE bot := NIL END ;
      WHILE fld # bot DO
        IF (fld.class = ORB.Const) & (td[tdw-fld.lev-1] = -1) & ((t.mno = 0) OR (fld.name[0] # 0X)) THEN
          td[tdw-fld.lev-1] := (t.mno*C16 + fld.val (*mthadr/exno*)) * C10
        END ;
        fld := fld.next
      END ;
      t := t.base
    END ;
    FOR k := s TO tdw-1 DO  (*insert displacements in ascending order*)
      IF td[k] # -1 THEN td[k] := td[k] + k - fixorgM; fixorgM := k ELSE td[k] := 0 END
    END ;
    s := T.size;  (*convert size for heap allocation*)
    IF s <= 24 THEN s := 32 ELSIF s <= 56 THEN s := 64 ELSIF s <= 120 THEN s := 128
    ELSE s := (s+263) DIV 256 * 256
    END ;
    T.len := tdw*4; td[tdw] := s; INC(tdw);  (*len used as type descriptor offset in bytes relative to tdx*)
    k := T.nofpar;  (*extension level!*)
    IF k > 3 THEN ORS.Mark("ext level too large")
    ELSE Q(T, tdw);
      WHILE k < 3 DO td[tdw] := -1; INC(tdw); INC(k) END
    END ;
    FindRefFlds(ORB.Ptrs, T, 0, tdw); td[tdw] := -1; INC(tdw);
    FindRefFlds(ORB.Procs, T, 0, tdw); td[tdw] := -1; INC(tdw);
    IF tdw >= maxTD THEN ORS.Mark("too many record types"); tdw := 0 END
  END BuildTD;

  PROCEDURE TypeTest*(VAR x: Item; T: ORB.Type; varpar, isguard: BOOLEAN);
    VAR pc0: INTEGER;
  BEGIN
    IF T = NIL THEN
      IF x.mode >= Reg THEN DEC(RH) END ;
      SetCC(x, BEQ, 0, 0) (* ?? *)
    ELSE (*fetch tag into RH*)
      IF varpar THEN PutI(LW, RH, SP, x.a+4+frame)
      ELSE load(x);
        pc0 := pc; PutBi(BEQ, x.r, 0, 0);  (*NIL belongs to every pointer type*)
        PutI(LW, RH, x.r, -8)
      END ;
      PutI(LW, RH, RH, T.nofpar*4); incR;
      loadTypTagAdr(T);  (*tag of T*)
      IF ~varpar THEN fixB(pc0, pc - pc0 - dPC) END ;
      IF isguard THEN
        IF check THEN Trap(BNE, RH-1, RH-2, TrapTypeGuard) END
      ELSE SetCC(x, BEQ, RH-1, RH-2);
        IF ~varpar THEN DEC(RH) END
      END;
      DEC(RH, 2);
    END
  END TypeTest;

  (* Code generation for Boolean operators *)

  PROCEDURE Not*(VAR x: Item);   (* x := ~x *)
    VAR t: INTEGER;
  BEGIN loadCond(x); x.r := negated(x.r); t := x.a; x.a := x.b; x.b := t
  END Not;

  PROCEDURE And1*(VAR x: Item);   (* x := x & *)
  BEGIN loadCond(x); PutBi(negated(x.r), 0, 0, x.a); x.a := pc-1; FixLink(x.b); x.b := 0
  END And1;

  PROCEDURE And2*(VAR x, y: Item);
  BEGIN loadCond(y); x.a := merged(y.a, x.a); x.b := y.b; x.r := y.r
  END And2;

  PROCEDURE Or1*(VAR x: Item);   (* x := x OR *)
  BEGIN loadCond(x); PutBi(x.r, 0, 0, x.b);  x.b := pc-1; FixLink(x.a); x.a := 0
  END Or1;

  PROCEDURE Or2*(VAR x, y: Item);
  BEGIN loadCond(y); x.a := y.a; x.b := merged(y.b, x.b); x.r := y.r
  END Or2;

  (* Code generation for arithmetic operators *)

  PROCEDURE Neg*(VAR x: Item);   (* x := -x *)
  BEGIN
    IF x.type.form = ORB.Int THEN
      IF x.mode = ORB.Const THEN x.a := -x.a
      ELSE load(x); PutR(SUB, RH - 1, ZR, x.r); x.r := RH-1
      END
    ELSIF x.type.form = ORB.Real THEN
      IF x.mode = ORB.Const THEN x.a := x.a + 7FFFFFFFH + 1
      ELSE loadf(x); PutR(FNEG, RH - 1, x.r, x.r); x.r := RH-1
      END
    ELSE (*form = Set*)
      IF x.mode = ORB.Const THEN x.a := -x.a-1 
      ELSE load(x); PutR(XORI, RH - 1, x.r, -1); x.r := RH-1
      END
    END
  END Neg;

  PROCEDURE AddOp*(op: INTEGER; VAR x, y: Item);   (* x := x +- y *)
  BEGIN
    IF op = ORS.plus THEN
      IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a + y.a
      ELSIF y.mode = ORB.Const THEN load(x);
        IF y.a # 0 THEN PutI32(ADDI, x.r, x.r, y.a) END
      ELSE load(x); load(y); PutR(ADD, RH-2, x.r, y.r); DEC(RH); x.r := RH-1
      END
    ELSE (*op = ORS.minus*)
      IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a - y.a
      ELSIF y.mode = ORB.Const THEN load(x);
        IF y.a # 0 THEN PutI32(ADDI, x.r, x.r, -y.a) END
      ELSE load(x); load(y); PutR(SUB, RH-2, x.r, y.r); DEC(RH); x.r := RH-1
      END
    END
  END AddOp;

  PROCEDURE log2(m: INTEGER; VAR e: INTEGER): INTEGER;
  BEGIN e := 0;
    WHILE ~ODD(m) DO m := m DIV 2; INC(e) END ;
    RETURN m
  END log2;

  PROCEDURE MulOp*(VAR x, y: Item);   (* x := x * y *)
    VAR e: INTEGER;
  BEGIN
    IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a * y.a
    ELSIF (y.mode = ORB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN load(x); PutI(SLLI, x.r, x.r, e)
    ELSIF (x.mode = ORB.Const) & (x.a >= 2) & (log2(x.a, e) = 1) THEN load(y); PutI(SLLI, y.r, y.r, e); x.mode := Reg; x.r := y.r
    ELSE load(x); load(y); PutR(MUL, RH-2, x.r, y.r); DEC(RH); x.r := RH-1
    END
  END MulOp;

  PROCEDURE DivOp*(op: INTEGER; VAR x, y: Item);   (* x := x op y *)
    VAR e: INTEGER; yc: BOOLEAN;
  BEGIN
    yc:=y.mode=ORB.Const;
    IF op = ORS.div THEN
      IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
        IF y.a > 0 THEN x.a := x.a DIV y.a ELSE ORS.Mark("bad divisor") END
      ELSIF (y.mode = ORB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN load(x); PutI(SRAI, x.r, x.r, e)
      ELSE
        IF yc & (y.a <= 0) THEN ORS.Mark("bad divisor");
        ELSE
          load(x); load(y);  (* adjust for Oberon definition *)
          PutR( SRAI, RH, x.r, 31); 
          PutR( SUB, T0, x.r, RH);
          PutR( DIVS, RH - 2 , T0, y.r);
              IF ~yc & check THEN Trap( BGE, 0, y.r, TrapDivZero) END;
          PutR( ADD, RH - 2 , RH - 2 , RH);
          DEC(RH); x.r := RH - 1
        END
      END
    ELSE (*op = ORS.mod*)
      IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
        IF y.a > 0 THEN x.a := x.a MOD y.a ELSE ORS.Mark("bad modulus") END
      ELSIF (y.mode = ORB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN load(x);
        IF e < 12 THEN PutI(ANDI, x.r, x.r, y.a-1) ELSE PutI(SLLI, x.r, x.r, 32-e); PutI(SRLI, x.r, x.r, 32-e) END
      ELSE load(x); load(y);  (* adjust for Oberon definition *)
        PutR( REM, RH - 2 , x.r, y.r);
            IF ~yc & check THEN Trap( BGE, 0, y.r, TrapDivZero) END;
        PutR( SRAI, RH, RH - 2 , 31);
        PutR( AND, RH, RH, y.r);
        PutR( ADD, RH - 2 , RH - 2 , RH);  
        DEC(RH); x.r := RH - 1;
      END
    END
  END DivOp;

  (* Code generation for REAL operators *)

  PROCEDURE RealOp*(op: INTEGER; VAR x, y: Item);   (* x := x op y *)
  BEGIN loadf(x); loadf(y);
    IF op = ORS.plus THEN PutR(FADD, RH-2, x.r, y.r)
    ELSIF op = ORS.minus THEN PutR(FSUB, RH-2, x.r, y.r)
    ELSIF op = ORS.times THEN PutR(FMUL, RH-2, x.r, y.r)
    ELSIF op = ORS.rdiv THEN PutR(FDIV, RH-2, x.r, y.r)
    END ;
    DEC(RH); x.r := RH-1
  END RealOp;

  (* Code generation for set operators *)

  PROCEDURE Singleton*(VAR x: Item);  (* x := {x} *)
  BEGIN
    IF x.mode = ORB.Const THEN x.a := LSL(1, x.a)
    ELSE load(x); PutMOVI(RH, 1); PutR(SLL, x.r, RH,  x.r)
    END
  END Singleton;

  PROCEDURE Set*(VAR x, y: Item);   (* x := {x .. y} *)
  BEGIN
    IF (x.mode = ORB.Const) & ( y.mode = ORB.Const) THEN
      IF x.a <= y.a THEN x.a := LSL(2, y.a) - LSL(1, x.a) ELSE x.a := 0 END
    ELSE
      IF (x.mode = ORB.Const) THEN  x.a := LSL(1, x.a)
      ELSE load(x); PutMOVI( RH, 1); PutR( SLL, RH - 1, RH, x.r); x.r := RH - 1;
      END;
      IF (y.mode = ORB.Const) THEN PutMOVI( RH,  LSL(2, x.a)); y.mode := Reg; y.r := RH; incR
          ELSE load(y); PutMOVI( RH, 2); PutR( SLL, y.r, RH, y.r);
      END;
      IF (x.mode = ORB.Const) THEN PutI32( ADDI, RH - 1, y.r, -x.a); x.mode := Reg
      ELSE DEC(RH); PutR( SUB, RH-1, y.r, x.r);    (* don't use x.r as target. y can be loaded before x *)
      END;
      x.r := RH-1; 
    END
  END Set;

  PROCEDURE In*(VAR x, y: Item);  (* x := x IN y *)
  BEGIN load(y);
  IF x.mode = ORB.Const THEN (* check x.a *)
    IF x.a # 0 THEN PutI( SRLI, RH - 1 , y.r, x.a); y.r := RH - 1; END;
  ELSE load(x); PutR( SRL, RH - 2 , y.r, x.r); DEC( RH); y.r := RH - 1;
  END;
  PutI( ANDI, RH-1, y.r, 1);
  x.mode:= Reg; x.r:= RH-1; 
  END In;

  PROCEDURE SetOp*(op: INTEGER; VAR x, y: Item);   (* x := x op y *)
    VAR xset, yset: SET; (*x.type.form = Set*)
  BEGIN
    IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
      xset := SYSTEM.VAL(SET, x.a); yset := SYSTEM.VAL(SET, y.a);
      IF op = ORS.plus THEN xset := xset + yset
      ELSIF op = ORS.minus THEN xset := xset - yset
      ELSIF op = ORS.times THEN xset := xset * yset
      ELSIF op = ORS.rdiv THEN xset := xset / yset
      END ;
      x.a := SYSTEM.VAL(INTEGER, xset)
    ELSIF y.mode = ORB.Const THEN
      load(x);
      IF op = ORS.plus THEN PutI32(ORI, RH-1, x.r, y.a)
      ELSIF op = ORS.minus THEN PutI32(ANDI, RH-1 , x.r, -y.a-1)
      ELSIF op = ORS.times THEN PutI32(ANDI, RH-1, x.r, y.a)
      ELSIF op = ORS.rdiv THEN PutI32(XORI, RH-1, x.r, y.a)
      END ;
      x.r := RH-1
    ELSE load(x); load(y);
      IF op = ORS.plus THEN PutR(ORR, RH-2, x.r, y.r)
      ELSIF op = ORS.minus THEN PutI( XORI, RH, y.r, -1); PutR( AND, RH-2, x.r, RH)
      ELSIF op = ORS.times THEN PutR(AND, RH-2, x.r, y.r)
      ELSIF op = ORS.rdiv THEN PutR(XOR, RH-2, x.r, y.r)
      END ;
      DEC(RH); x.r := RH-1
    END 
  END SetOp;

  (* Code generation for relations *)

  PROCEDURE IntRelation*(op: INTEGER; VAR x, y: Item);   (* x := x < y *)
  BEGIN   (*  SLT gives larger code on average*)
    IF (x.mode = Cond) OR (y.mode = Cond) THEN ORS.Mark(notimplemented) END ;
    load(x); load(y); 
    SetCC( x, relmap[op - ORS.eql], x.r, y.r); DEC(RH, 2);
  END IntRelation;

  PROCEDURE RealRelation*(op: INTEGER; VAR x, y: Item);   (* x := x < y *)
    VAR cmp: INTEGER;
  BEGIN loadf(x); loadf(y);
    cmp:= condf[ op - ORS.eql];
    IF cmp > 0 THEN  (* Fcmp is negative *)
      PutR( -cmp, RH-2, y.r, x.r);
      IF cmp=-FEQ THEN PutI( XORI, RH-2, RH-2, 1) END;
    ELSE PutR( cmp, RH-2, x.r, y.r);
    END;
    DEC(RH);
    x.r := RH -1;
    x.mode:= Reg;
    x.type:= ORB.boolType;
  END RealRelation;

  PROCEDURE StringRelation*(op: INTEGER; VAR x, y: Item);   (* x := x < y *)
    (*x, y are char arrays or strings*)
  BEGIN
    IF x.type.form = ORB.String THEN loadStringAdr(x) ELSE loadAdr(x) END ;
    IF y.type.form = ORB.String THEN loadStringAdr(y) ELSE loadAdr(y) END ;
    PutI(LBU, RH, x.r, 0); PutI(ADDI, x.r, x.r, 1); 
    PutI(LBU, T0, y.r, 0); PutI(ADDI, y.r, y.r, 1);
    PutB( BNE, RH, T0, 8);
    PutB( BNE, RH, 0, -20);
    SetCC(x, relmap[op - ORS.eql], RH, T0); DEC(RH, 2); 
  END StringRelation;

  (* Code generation of Assignments *)

  PROCEDURE StrToChar*(VAR x: Item);
  BEGIN x.type := ORB.charType; DEC(strx, 4); x.a := ORD(str[x.a])
  END StrToChar;

  PROCEDURE Store*(VAR x, y: Item); (* x := y *)
    VAR op: INTEGER;
  BEGIN  load(y);
    IF x.type.size = 1 THEN op := SB ELSE op := SW END ;
    IF x.mode = ORB.Var THEN
      IF x.r > 0 THEN (*local*) PutS(op, y.r, SP, x.a + frame)
      ELSE fixvar( x.r, x.a); PutS( op, y.r, RH, 0); (*PutPair(x.r, iop, RH, y.r, x.a)*)
      END
    ELSIF x.mode = ORB.Par THEN PutI(LW, RH, SP, x.a + frame); PutS(op, y.r, RH, x.b);
    ELSIF x.mode = RegI THEN PutS(op, y.r, x.r, x.a); DEC(RH);
    ELSE ORS.Mark("bad mode in Store")
    END ;
    DEC(RH)
  END Store;

PROCEDURE Storef(VAR x, y: Item); (* x := y *)
VAR i: INTEGER;
BEGIN
  loadf(y);
  IF x.type# ORB.realType THEN ORS.Mark("Storef 0") END;
  IF x.mode = ORB.Var THEN
    IF x.r > 0 THEN (*local*) PutS(FSW, y.r, SP, x.a + frame)
    ELSIF x.r=0 THEN fixvar( x.r, x.a); PutS( FSW, y.r, RH, 0); (*PutPair(x.r, FSW, RH, y.r, x.a)*)
    ELSE ORS.Mark("Storef imported");
    END
  ELSIF x.mode = ORB.Par THEN PutI( LW, RH, SP, x.a + frame); PutS( FSW, y.r, RH, x.b);
  ELSIF x.mode = RegI THEN PutS(FSW, y.r, x.r, x.a); DEC(RH);
  ELSE ORS.Mark("bad mode in Storef")
  END ;
  DEC(RH);
END Storef;

  PROCEDURE StoreStruct*(VAR x, y: Item); (* x := y, frame = 0 *)
    VAR s, pc0: INTEGER;
  BEGIN loadAdr(x); loadAdr(y);
    IF (x.type.form = ORB.Array) & (x.type.len > 0) THEN
      IF y.type.len >= 0 THEN
        IF x.type.size = y.type.size THEN PutMOVI(RH, (y.type.size+3) DIV 4)
        ELSE ORS.Mark("different length/size, not implemented")
        END
      ELSE (*y open array param or dynamic open array*)
        IF y.type.size > 0 THEN PutI(LW, RH, SP, y.a+4) ELSE PutI(LW, RH, y.r, -16) END ; (*len*)
        s := y.type.base.size;  (*element size*)
        pc0 := pc; PutBi(BEQ, RH, 0, 0);
        IF s = 1 THEN PutI(ADDI, RH, RH, 3); PutI(SRAI, RH, RH, 2)
        ELSIF s # 4 THEN PutMOVI(T0, s DIV 4); PutR( MUL, RH, RH, T0)
        END ;
        IF check THEN (*check array lengths*) incR;
          PutMOVI(RH, (x.type.size+3) DIV 4); Trap(BLT, RH, RH-1, TrapCopyOV); DEC(RH)
        END ;
        fixB(pc0, pc + 6 - pc0)
      END
    ELSIF x.type.form = ORB.Record THEN PutMOVI(RH, x.type.size DIV 4)
    ELSE ORS.Mark("inadmissible assignment")
    END ;
    incR;
    PutI(LW, RH, y.r, 0); PutI(ADDI, y.r, y.r, 4);
    PutS(SW, RH, x.r, 0); PutI(ADDI, x.r, x.r, 4);
    PutI(ADDI, RH-1, RH-1, -1); PutB(BLT, 0, RH - 1, -20); RH := minR
  END StoreStruct;

  PROCEDURE CopyString*(VAR x, y: Item);  (* x := y, frame = 0 *) 
     VAR len: INTEGER;
   BEGIN loadAdr(x); len := x.type.len;
    IF len >= 0 THEN
      IF len <  y.b THEN ORS.Mark("string too long") END
    ELSIF check THEN (*x open array param or dynamic open array*)
      IF x.type.size > 0 THEN 
        IF x.a + 4 < 800H THEN PutI(LW, RH, SP, x.a + 4)
        ELSE PutMOVI( TR, x.a + 4); PutR( ADD, RH, SP, TR); PutI(LW, RH, RH, 0)
        END;
      ELSE PutI(LW, RH, x.r, -16) END ; (*len*)
      Trap(BLT, RH, y.b, TrapCopyOV)
    END ;
    loadStringAdr(y);
    PutI(LW, RH, y.r, 0); PutI(ADDI, y.r, y.r, 4);
    PutS(SW, RH, x.r, 0); PutI(ADDI, x.r, x.r, 4);
    PutI(SRLI, RH, RH, 24); PutB(BNE, RH, 0, -20);  RH := minR
  END CopyString;

  (* Code generation for parameters *)

  PROCEDURE OpenArrayParam*(VAR x: Item);
  BEGIN loadAdr(x);
    IF x.type.len >= 0 THEN PutMOVI( RH, x.type.len)
    ELSIF x.type.size > 0 THEN (*open array param*) PutL(LW, RH, SP, x.a+4+frame)
    ELSE (*dynamic open array*) PutL(LW, RH, x.r, -16) (*len*)
    END ;
    incR
  END OpenArrayParam;

  PROCEDURE VarParam*(VAR x: Item; ftype: ORB.Type);
    VAR xmd: INTEGER;
  BEGIN xmd := x.mode; loadAdr(x);
    IF (ftype.form = ORB.Array) & (ftype.len < 0) THEN (*open array*)
      IF x.type.len >= 0 THEN PutMOVI( RH, x.type.len)
      ELSIF x.type.size > 0 THEN (*open array param*) PutL(LW, RH, SP, x.a+4+frame)
      ELSE (*dynamic open array*) PutI(LW, RH, x.r, -16) (*len*)
      END ;
      incR
    ELSIF ftype.form = ORB.Record THEN
      IF x.deref THEN PutI(LW, RH, x.r, -8); incR
      ELSIF xmd = ORB.Par THEN PutL(LW, RH, SP, x.a+4+frame); incR
      ELSE loadTypTagAdr(x.type)
      END
    END
  END VarParam;

PROCEDURE ValueParam*(VAR x: Item);
BEGIN
  IF (x.type= ORB.realType) THEN load(x); 
  ELSE load(x);
    IF x.r # RH - 1 THEN
      PutMOV( RH-1, x.r);
      x.r:=RH-1;
    END;
  END;
END ValueParam;

  PROCEDURE StringParam*(VAR x: Item);
  BEGIN loadStringAdr(x); PutMOVI(RH, x.b); incR  (*len*)
  END StringParam;

  PROCEDURE ReceiverParam*(VAR x: Item; par: ORB.Object);
  BEGIN
    IF x.r # RH THEN PutMOV(RH, x.r) END ;  (*receiver -> R0*)
    incR;
    IF par.class = ORB.Par THEN (*record*) loadTypTagAdr(par.type)  (*type tag*)
    ELSIF ~x.deref THEN ORS.Mark("incompatible receiver");
    END;
  END ReceiverParam;

  (*For Statements*)

  PROCEDURE For0*(VAR x, y: Item);
  BEGIN load(y);
    IF y.r # RH-1 THEN PutMOV( RH - 1 , y.r); y.r := RH - 1; END;
  END For0;

  PROCEDURE For1*(VAR x, y, z, w: Item; VAR L: INTEGER);
  BEGIN 
      load(z);
    L := pc;
    IF w.a > 0 THEN PutBi(BLT, z.r, y.r, 0)
    ELSIF w.a < 0 THEN PutBi(BLT, y.r,z.r, 0)
    ELSE ORS.Mark("zero increment"); PutBi(BEQ, z.r, z.r, 0)
    END ;
    DEC(RH);
    Store(x, y)
  END For1;

  PROCEDURE For2*(VAR x, y, w: Item);
  BEGIN load(x); DEC(RH); PutI32(ADDI, x.r, x.r, w.a)
  END For2;

  (* Branches, procedure calls, procedure prolog and epilog *)

  PROCEDURE Here*(): INTEGER;
  BEGIN RETURN pc
  END Here;

  PROCEDURE FJump*(VAR L: INTEGER);
  BEGIN PutBi(BEQ, ZR, ZR, L); L := pc-1 
  END FJump;

  PROCEDURE CFJump*(VAR x: Item);
  BEGIN loadCond(x);
    PutBi(negated(x.r), ZR, ZR, x.a);
    FixLink(x.b); x.a := pc-1
  END CFJump;

  PROCEDURE BJump*(L: INTEGER);
  BEGIN PutJAL(ZR, (L-pc)*4)
  END BJump;

  PROCEDURE CBJump*(VAR x: Item; L: INTEGER);
  BEGIN loadCond(x); PutB(negated(x.r), ZR, ZR, (L-pc)*4); FixLink(x.b); FixLinkWith(x.a, L)
  END CBJump;

  PROCEDURE Fixup*(VAR x: Item);
  BEGIN FixLink(x.a)
  END Fixup;

  PROCEDURE SaveRegs(r: INTEGER);  (* R[0 .. r-1]*)
    VAR r0: INTEGER;
  BEGIN (*r > 0*) r0 := minR;
    PutI(ADDI, SP, SP, (minR-r)*4); INC(frame, 4*(r-minR));
    REPEAT PutS(SW, r0, SP, (r-r0-1)*4); INC(r0) UNTIL r0 = r
  END SaveRegs;

  PROCEDURE RestoreRegs(r: INTEGER); (*R[0 .. r-1]*)
    VAR r0: INTEGER;
  BEGIN (*r > 0*) r0 := r;
    REPEAT DEC(r0); PutI(LW, r0, SP, (r-r0-1)*4) UNTIL r0 = minR;
    PutI(ADDI, SP, SP, (r-minR)*4); DEC(frame, 4*(r-minR))
  END RestoreRegs;

  PROCEDURE PrepCall*(VAR x: Item; VAR r: INTEGER);
  BEGIN (*x.type.form IN {ORB.Proc, ORB.TProc}*)
    IF x.type.form = ORB.TProc THEN DEC(RH) ELSIF x.mode > ORB.Par THEN load(x) END ;
    r := RH;
    IF RH > minR THEN SaveRegs(RH); RH := minR END
  END PrepCall;

  PROCEDURE Call*(VAR x: Item; r: INTEGER);
  BEGIN (*x.type.form IN {ORB.Proc, ORB.TProc}*)
    IF x.type.form = ORB.TProc THEN  (*type-bound procedure*)
      IF x.super THEN  (*super call*)
        IF x.b >= 0 THEN PutJAL(RA, x.a -pc * 4)
        ELSE (*imported*) fixcode(x.b, x.a);
        END
      ELSE  (*method call*)
        IF x.b = ORB.Var THEN PutI(LW, RH, 0, -8) ELSE PutMOVI(RH, 1) END ;
        PutI(LW, RH, RH, -4-x.a*4); PutI(JALR, RA, RH, 0)
      END
    ELSIF x.mode = ORB.Const THEN  (*regular procedure*)
      IF x.r >= 0 THEN PutJAL( RA, x.a - pc *4)
      ELSE (*imported*) fixcode(x.r, x.a);
      END
    ELSE  (*installed procedure*)
      IF x.mode <= ORB.Par THEN load(x); DEC(RH)
      ELSE PutI(LW, RH, SP, 0); PutI(ADDI, SP, SP, 4); DEC(r); DEC(frame, 4)
      END ;
      IF check THEN Trap(BEQ, RH, 0, TrapIllProc) END ;
      PutI(JALR, RA, RH, 0)
    END ;
    IF x.type.base.form = ORB.NoTyp THEN (*procedure*) RH := minR
    ELSE  (*function*)
      IF r > minR THEN PutMOV(r, minR); RestoreRegs(r) END ;
      x.mode := Reg; x.r := r; RH := r+1
    END
  END Call;

  PROCEDURE Enter*(parblksize, locblksize: INTEGER; int: BOOLEAN);
    VAR a, r: INTEGER; (*procedure prolog*)
  BEGIN frame := 0;
    IF int THEN ORS.Mark("not implemented") END;
    IF locblksize >= C16 THEN ORS.Mark("too many locals") END ;
    a := 4; r := minR;
    PutI32(ADDI, SP, SP, -locblksize); PutS(SW, RA, SP, 0);
    WHILE a < parblksize DO PutS(SW, r, SP, a); INC(r); INC(a, 4) END
  END Enter;

  PROCEDURE Return*(form: INTEGER; VAR x: Item; size: INTEGER; int: BOOLEAN);
  BEGIN (*procedure epilog*)
    IF form # ORB.NoTyp THEN
      IF x.type = ORB.realType THEN loadf(x) ELSE load(x) END;
    END ;
    PutI(LW, RA, SP, 0); PutI32(ADDI, SP, SP, size); PutI(JALR, 0, RA, 0);
    RH := minR
  END Return;

  (* Case Statements *)

  PROCEDURE CaseHead*(VAR x: Item; VAR L0: INTEGER);
  BEGIN load(x);  (*value of case expression*)
    L0 := pc; PutMOVI( RH, 0);  (*higher bound, fixed up in CaseTail*)
    PutBi( BLTU, RH, x.r, 0);  (*branch to else, fixed up in CaseTail*)
    PutI( SLLI, x.r, x.r, 2);
    PutUa( AUIPC, RA, 0);
    PutR( ADD, x.r, x.r, RA);
    PutI( JALR, ZR, x.r, 0); DEC(RH); (*LNK := PC+1; nof bytes between BL instruction at L0+4 and jump table, fixed up in CaseTail*)
  END CaseHead;

  PROCEDURE CaseTail*(L0, L1: INTEGER; n: INTEGER; VAR tab: ARRAY OF LabelRange);  (*L1 = label for else*)
    VAR i, j: INTEGER;
  BEGIN
    IF n > 0 THEN fixI(L0, tab[n-1].high ) (*higher bound*) ELSIF L1 = 0 THEN ORS.Mark("empty case") END ;
    IF L1 = 0 THEN L1 := pc; Trap(BEQ, ZR, ZR,TrapArray) END ;  (*create else*)
    fixB(L0+1, (L1-L0-2)*4);  (*branch to else*)
    fixI(L0+5, (pc-L0-3)*4 );  (*nof bytes between BL instruction at L0+4 and jump table*)
    j := 0;
    FOR i := 0 TO n-1 DO  (*construct jump table*)
      WHILE j < tab[i].low DO BJump(L1); INC(j) END ;  (*else*)
      WHILE j <= tab[i].high DO BJump(tab[i].label); INC(j) END
    END
  END CaseTail;

  (* In-line code procedures *)

  PROCEDURE Increment*(upordown: INTEGER; VAR x, y: Item);
VAR op, zr, v: INTEGER;
BEGIN (*frame = 0*)
  IF upordown = 0 THEN op := ADD ELSE op := SUB END;
  IF x.type = ORB.byteType THEN v := 4000H ELSE v := 2000H END;
  IF y.type.form = ORB.NoTyp THEN y.mode := ORB.Const; y.a := 1 END;
  IF (y.mode = ORB.Const) & ( op= SUB) THEN  y.a:=-y.a END;
  IF (x.mode = ORB.Var) & (x.r > 0) THEN  (* local *)
    zr := RH; PutL(LB+v, zr, SP, x.a); incR;
    IF y.mode = ORB.Const THEN PutI32( ADDI, zr, zr, y.a) ELSE load(y); PutR(op, zr, zr, y.r); DEC(RH) END;
    PutS(SB+(v MOD 4000H), zr, SP, x.a); DEC(RH)
  ELSE loadAdr(x); zr := RH; PutI(LB+v, RH, x.r, 0); incR;  (* ToDo: use LoadAdrUpper *)
    IF y.mode = ORB.Const THEN PutI32( ADDI, zr, zr, y.a) ELSE load(y); PutR(op, zr, zr, y.r); DEC(RH) END;
    PutS(SB+(v MOD 4000H), zr, x.r, 0); DEC(RH, 2)
  END
  END Increment;

  PROCEDURE Include*(inorex: INTEGER; VAR x, y: Item);
    VAR zr: INTEGER;
  BEGIN loadAdr(x); zr := RH; PutI(LW, RH, x.r, 0); incR;
    IF inorex = 0 THEN
      IF y.mode = ORB.Const THEN PutI32( ORI, zr, zr, LSL(1, y.a));
      ELSE load(y); PutMOVI( RH, 1); PutR( SLL, RH, RH, y.r); PutR( ORR, zr, zr, RH); DEC(RH);
      END ;
    ELSE
      IF y.mode = ORB.Const THEN PutI32( ANDI, zr, zr, -LSL(1, y.a)-1);
      ELSE load(y); PutMOVI( RH, 1); PutR( SLL, RH, RH, y.r); PutI( XORI, RH, RH, -1); PutR( AND, zr, zr, RH); DEC(RH);
      END ;
    END;
      PutS(SW, zr, x.r, 0); DEC(RH, 2)
  END Include;

  PROCEDURE Assert*(VAR x: Item);
    VAR cond: INTEGER;
  BEGIN loadCond(x);
    IF x.a = 0 THEN cond := negated(x.r)
    ELSE PutBi(x.r, ZR, ZR, x.b); FixLink(x.a); x.b := pc-1; cond := BEQ
    END ;
    Trap(cond, 0, 0, TrapAssert); FixLink(x.b)
  END Assert;

  PROCEDURE New*(VAR x, y: Item);
    VAR z: Item; xt: ORB.Type; xf: INTEGER;
  BEGIN loadAdr(x);
    IF y.type = ORB.noType THEN (*record*) loadTypTagAdr(x.type.base)
    ELSE (*array*) xt:= x.type.base.base; xf := xt.form;
      IF xf = ORB.Record THEN loadTypTagAdr(xt); PutI(ADDI, RH-1, RH-1, 1)  (*array of record, blktyp = 1*)
      ELSIF xf = ORB.Pointer THEN PutMOVI( RH, 2); incR  (*array of pointer, blktyp = 2*)
      ELSIF xf = ORB.Proc THEN PutMOVI( RH, 7); incR  (*array of procedure, blktyp = 3, tag = 7*)
      ELSIF xf < ORB.Pointer THEN PutMOVI( RH, 3); incR  (*array of basic type, blktyp = 3, tag = 3*)
      ELSE ORS.Mark("no valid ptr base type")
      END ;
      IF y.mode = ORB.Const THEN
        IF y.a > 0 THEN load(y) (*len*) ELSE ORS.Mark("not a valid dyn array length") END
      ELSE load(y); (*len*)
        IF check THEN Trap(BGE, ZR, y.r, TrapArray) END
      END ;
      z.mode := ORB.Const; z.type := ORB.intType; z.a := xt.size; load(z) (*elemsize*)
    END ;
    Trap(BEQ, 0, 0, 0); RH := minR
  END New;

  PROCEDURE Pack*(VAR x, y: Item);
    VAR z: Item;
  BEGIN z := x; load(x); load(y);
    PutR(SLLI, y.r, y.r, 23); PutR(ADD, x.r, x.r, y.r); DEC(RH); Store(z, x)
  END Pack;

  PROCEDURE Unpk*(VAR x, y: Item);
    VAR z, e0: Item;
  BEGIN  z := x; load(x); e0.mode := Reg; e0.r := RH; e0.type := ORB.intType;
    PutR(SRAI, RH, x.r, 23); PutI(ADDI, RH, RH, -127); Store(y, e0); incR;
    PutR(SLLI, RH, RH, 23); PutR(SUB, x.r, x.r, RH); Store(z, x)
  END Unpk;

  PROCEDURE Led*(VAR x: Item);
  BEGIN (*load(x); PutI(ADDI, RH, 0, -60); PutS(SW, x.r, RH, 0); DEC(RH)*)
  END Led;

  PROCEDURE Get*(VAR x, y: Item);
  BEGIN load(x); x.type := y.type; x.mode := RegI; x.a := 0; Store(y, x)
  END Get;

  PROCEDURE Put*(VAR x, y: Item);
  BEGIN load(x); x.type := y.type; x.mode := RegI; x.a := 0; Store(x, y)
  END Put;

  PROCEDURE Copy*(VAR x, y, z: Item);
  BEGIN load(x); load(y);
    IF z.mode = ORB.Const THEN
      IF z.a > 0 THEN load(z) ELSE ORS.Mark("bad count") END
    ELSE load(z);
      IF check THEN Trap(BLT, z.r, 0, TrapCopyOV) END ;
      PutB(BGE, 0, z.r, 28)
    END ;
    PutI(LW, RH, x.r, 0); PutI(ADDI, x.r, x.r, 4);
    PutS(SW, RH, y.r, 0); PutI(ADDI, y.r, y.r, 4);
    PutI(ADDI, z.r, z.r, -1); PutB(BNE, z.r, 0, -20); DEC(RH, 3)
  END Copy;

  PROCEDURE LDPSR*(VAR x: Item);
  BEGIN (*x.mode = Const*)  ORS.Mark( notimplemented)
  END LDPSR;

  PROCEDURE LDREG*(VAR x, y: Item);
  BEGIN
    IF x.a = 15 THEN x.a := RA
    ELSIF x.a = 14 THEN x.a := SP
    ELSIF x.a = 13 THEN x.a := TR
    ELSIF x.a < 0 THEN x.a := - x.a
    ELSE INC(x.a, minR)
    END;
    IF y.mode = ORB.Const THEN PutMOVI(x.a, y.a)
    ELSE load(y); PutR(ADDI, x.a, y.r, 0); DEC(RH)
    END
  END LDREG;

  (* In-line code functions *)

  PROCEDURE Abs*(VAR x: Item);
  BEGIN
    IF x.mode = ORB.Const THEN x.a := ABS(x.a)
    ELSE
      IF x.type.form = ORB.Real THEN loadf(x); PutR( FABS, RH - 1, x.r, x.r); x.r := RH - 1;
      ELSE load(x); PutB( BGE, x.r, 0, 8); PutR( SUB, RH - 1, 0, x.r); x.r := RH - 1;
      END
    END
  END Abs;

  PROCEDURE Odd*(VAR x: Item);
  BEGIN load(x); PutI(ANDI, RH - 1, x.r, 1); x.r := RH - 1
  END Odd;

  PROCEDURE Floor*(VAR x: Item);
  BEGIN loadf(x); PutR( FCVTWF, RH - 1, x.r, 0); x.r := RH - 1;
  END Floor;

  PROCEDURE Float*(VAR x: Item);
  BEGIN load(x); PutR( FCVTFX, RH - 1, x.r, 0); x.r := RH - 1;
  END Float;

  PROCEDURE Ord*(VAR x: Item);
  BEGIN
    IF x.mode IN {ORB.Var, ORB.Par, RegI, Cond} THEN load(x);
      IF (x.type.form = ORB.Pointer) & (x.type.base.form = ORB.Array) THEN PutI(ADDI, x.r, x.r, 16) END
    ELSIF (x.mode = Reg) & (x.type = ORB.realType) THEN PutR( FMVXS, RH - 1, x.r, 0); x.r := RH - 1;
    END
  END Ord;

  PROCEDURE Len*(VAR x: Item);
  BEGIN
    IF x.type.len >= 0 THEN
      IF x.mode = RegI THEN DEC(RH) END ;
      x.mode := ORB.Const; x.a := x.type.len
    ELSIF x.type.size > 0 THEN (*open array param*)
      PutI(LW, RH, SP, x.a + 4 + frame); x.mode := Reg; x.r := RH; incR
    ELSE (*dynamic open array*) PutI(LW, x.r, x.r, -16); (*len*) x.mode := Reg
    END 
  END Len;

  PROCEDURE Shift*(fct: INTEGER; VAR x, y: Item);
    VAR op: INTEGER;
  BEGIN load(x);
    IF y.mode = ORB.Const THEN
      IF y.a#0 THEN
        IF fct=0 THEN PutR( SLLI, x.r, x.r, y.a MOD 20H); 
        ELSIF fct=1 THEN PutR( SRAI, x.r, x.r, y.a MOD 20H);  
        ELSE  (* ROR *)         (* only used in Files.ReadNum *)
          PutR( SRLI, RH, x.r, y.a MOD 20H);
          PutR( SLLI , x.r, x.r, 32 - (y.a MOD 20H));
          PutR( ORR, x.r, x.r, RH);
        END;
      END;
    ELSE load(y);
      IF fct=0 THEN PutR( SLL, RH-2, x.r, y.r);  (* LSL *)
      ELSIF fct=1 THEN PutR( SRA, RH-2, x.r, y.r);  (* ASR*)
      ELSE  (* ROR *) (* ORS.Mark("ROR not tested"); *)
        PutR( SRL, RH, x.r, y.r);
        PutR( SUB, y.r, 0, y.r);
        PutR( SLL, x.r, x.r, y.r);
        PutR( ORR, RH-2, x.r, RH);
      END;
      DEC(RH); x.r := RH-1;
    END;
  END Shift;

  PROCEDURE ADC*(VAR x, y: Item);
  BEGIN ORS.Mark(notimplemented)
  END ADC;

  PROCEDURE SBC*(VAR x, y: Item);
  BEGIN ORS.Mark(notimplemented)
  END SBC;

  PROCEDURE UML*(VAR x, y: Item);
  BEGIN ORS.Mark(notimplemented)
  END UML;

  PROCEDURE Bit*(VAR x, y: Item);
  BEGIN load(x); PutI(LW, x.r, x.r, 0);
    IF y.mode = ORB.Const THEN PutR(SRLI, RH - 1, x.r, y.a);
    ELSE load(y); PutR(SRLI, RH - 2, x.r, y.r); DEC(RH)
    END;
    PutI(ANDI, RH - 1, RH - 1, 1); x.r := RH - 1
  END Bit;

  PROCEDURE Register*(VAR x: Item);
  BEGIN (*x.mode = Const*)
    IF x.a = 15 THEN x.a := RA
    ELSIF x.a = 14 THEN x.a := SP
    ELSIF x.a = 13 THEN x.a := TR
    ELSIF x.a < 0 THEN x.a := -x.a
    ELSE INC(x.a, minR)
    END;
    PutMOV( RH, x.a MOD 20H);
    x.mode := Reg; x.r := RH; incR
  END Register;

  PROCEDURE H*(VAR x: Item);
  BEGIN (*x.mode = Const*)
    ORS.Mark("not imlemented")
  END H;

  PROCEDURE Adr*(VAR x: Item);
  BEGIN 
    IF x.mode IN {ORB.Var, ORB.Par, RegI} THEN loadAdr(x)
    ELSIF (x.mode = ORB.Const) & (x.type.form = ORB.Proc) THEN load(x)
    ELSIF (x.mode = ORB.Const) & (x.type.form = ORB.String) THEN loadStringAdr(x)
    ELSE ORS.Mark("not addressable")
    END
  END Adr;

  PROCEDURE Condition*(VAR x: Item);
  BEGIN (*x.mode = Const*) ORS.Mark(notimplemented);
  END Condition;

  PROCEDURE Open*(v: INTEGER);
  BEGIN pc := 0; final := -1; strx := 0; tdw := 0; RH := minR; check := v # 0;
    fixorgP := 0; fixorgD := 0; fixorgT := 0; fixorgM := 0;
  END Open;

  PROCEDURE SetDataSize*(dc: INTEGER);
  BEGIN varx := dc
  END SetDataSize;

  PROCEDURE Header*;
  BEGIN entry := pc*4; (*RISC-0 part deleted*)
    PutI(ADDI, SP, SP, -4); PutS(SW, RA, SP, 0)
  END Header;

  PROCEDURE Exit*;
  BEGIN (*exit code, RISC-0 part removed*)
    PutI(LW, RA, SP, 0); PutI(ADDI, SP, SP, 4); PutI(JALR, ZR, RA, 0)
  END Exit;

  PROCEDURE Final*;
  BEGIN final := pc*4;  (* RISC-0 part removed*)
    PutI(ADDI, SP, SP, -4); PutS(SW, RA, SP, 0)
  END Final;

  PROCEDURE NofRefs(ftyp: SET; typ: ORB.Type): INTEGER;
    VAR fld: ORB.Object; n: INTEGER;
  BEGIN
    IF typ.form IN ftyp THEN n := 1
    ELSIF typ.form = ORB.Record THEN fld := typ.dsc; n := 0;
      WHILE fld # NIL DO n := NofRefs(ftyp, fld.type) + n; fld := fld.next END
    ELSIF typ.form = ORB.Array THEN n := NofRefs(ftyp, typ.base) * typ.len
    ELSE n := 0
    END ;
    RETURN n
  END NofRefs;

  PROCEDURE FindRefs(VAR R: Files.Rider; ftyp: SET; typ: ORB.Type; off: INTEGER);
    VAR fld: ORB.Object; i, s: INTEGER;
  BEGIN
    IF typ.form IN ftyp THEN Files.WriteInt(R, off)
    ELSIF typ.form = ORB.Record THEN fld := typ.dsc;
      WHILE fld # NIL DO FindRefs(R, ftyp, fld.type, fld.val + off); fld := fld.next END
    ELSIF typ.form = ORB.Array THEN s := typ.base.size;
      FOR i := 0 TO typ.len-1 DO FindRefs(R, ftyp, typ.base, i*s + off) END
    END
  END FindRefs;

  PROCEDURE Close*(VAR modid: ORS.Ident; key, nofent: INTEGER);
    VAR obj: ORB.Object;
      i, comsize, nofimps, nofrefs, size, tdx, fix: INTEGER;
      name: ORS.Ident;
      F: Files.File; R: Files.Rider;
  BEGIN obj := ORB.topScope.next; nofimps := 0; comsize := 4; nofrefs := 0; tdx := varx + strx;
    WHILE obj # NIL DO
      IF (obj.class = ORB.Mod) & (obj.dsc # ORB.system) THEN INC(nofimps)  (*count imports*)
      ELSIF (obj.exno # 0) & (obj.class = ORB.Const) & (obj.type.form = ORB.Proc)
          & (obj.type.nofpar = 0) & (obj.type.base = ORB.noType) THEN i := 0;  (*count commands*)
        WHILE obj.name[i] # 0X DO INC(i) END ;
        i := (i+4) DIV 4 * 4; INC(comsize, i+4)
      ELSIF obj.class = ORB.Var THEN INC(nofrefs, NofRefs(ORB.Ptrs + ORB.Procs, obj.type))  (*count ptrs and pvrs*)
      ELSIF (obj.class = ORB.Typ) & (obj.type.form = ORB.Record) & (obj.type.typobj = obj) THEN  (*build type descriptors*)
        fix := obj.type.len;  (*heading of fixup chain of instruction pairs inserted into fixorgD chain in loadTypTagAdr*)
        BuildTD(obj.type, tdw);  (*obj.type.len now used as type descriptor (TD) offset in bytes relative to tdx*)
        IF fix > 0 THEN FixLinkPair(fix, tdx + obj.type.len) END  (*fix chain of instruction pairs with TD adr*)
      END ;
      obj := obj.next
    END ;
    size := tdx + tdw*4 + comsize + (pc + nofimps + nofent + nofrefs + 2)*4;
    ORB.MakeFileName(name, modid, appendix);  (*write code file*)
    F := Files.New(name); Files.Set(R, F, 0); Files.WriteString(R, modid); Files.WriteInt(R, key); Files.Write(R, version);
    Files.WriteInt(R, size);
    obj := ORB.topScope.next;
    WHILE (obj # NIL) & (obj.class = ORB.Mod) DO  (*imports*)
      IF obj.dsc # ORB.system THEN Files.WriteString(R, obj(ORB.Module).orgname); Files.WriteInt(R, obj.val) END ;
      obj := obj.next
    END ;
    Files.Write(R, 0X);
    Files.WriteInt(R, varx);  (*variable space*)
    Files.WriteInt(R, strx);
    FOR i := 0 TO strx-1 DO Files.Write(R, str[i]) END ;  (*strings*)
    Files.WriteInt(R, tdw*4);
    FOR i := 0 TO tdw-1 DO Files.WriteInt(R, td[i]) END ;  (*type descriptors*)
    Files.WriteInt(R, pc);  (*code len*)
    FOR i := 0 TO pc-1 DO Files.WriteInt(R, code[i]) END ;  (*program*)
    obj := ORB.topScope.next;
    WHILE obj # NIL DO  (*commands*)
      IF (obj.exno # 0) & (obj.class = ORB.Const) & (obj.type.form = ORB.Proc) &
          (obj.type.nofpar = 0) & (obj.type.base = ORB.noType) THEN
        Files.WriteString(R, obj.name); Files.WriteInt(R, obj.val)
      END ;
      obj := obj.next
    END ;
    Files.Write(R, 0X);
    Files.WriteInt(R, nofent); Files.WriteInt(R, entry);
    obj := ORB.topScope.next;
    WHILE obj # NIL DO  (*entries*)
      IF obj.exno # 0 THEN
        IF  obj.class = ORB.Const THEN
          IF obj.type.form = ORB.String THEN Files.WriteInt(R, varx + obj.val MOD C20)  (*convert strx to SB-relative*)
          ELSIF obj.type.form = ORB.Proc THEN Files.WriteInt(R, obj.val)
          ELSIF obj.type.form = ORB.TProc THEN (*dummy to preserve linear order of exno*) Files.WriteInt(R, obj.dsc.val)
          END
        ELSIF obj.class = ORB.Typ THEN
          IF obj.type.form = ORB.Record THEN Files.WriteInt(R, tdx + obj.type.len MOD C16)
          ELSIF (obj.type.form = ORB.Pointer) & ((obj.type.base.typobj = NIL) OR (obj.type.base.typobj.exno = 0)) THEN
            Files.WriteInt(R, tdx + obj.type.base.len MOD C16)
          END
        ELSIF obj.class = ORB.Var THEN Files.WriteInt(R, obj.val)
        END
      END ;
      obj := obj.next
    END ;
    obj := ORB.topScope.next;
    WHILE obj # NIL DO  (*pointer variables*)
      IF obj.class = ORB.Var THEN FindRefs(R, ORB.Ptrs, obj.type, obj.val) END ;
      obj := obj.next
    END ;
    Files.WriteInt(R, -1);
    obj := ORB.topScope.next;
    WHILE obj # NIL DO  (*procedure variables*)
      IF obj.class = ORB.Var THEN FindRefs(R, ORB.Procs, obj.type, obj.val) END ;
      obj := obj.next
    END ;
    Files.WriteInt(R, -1);
    Files.WriteInt(R, fixorgP*2); Files.WriteInt(R, fixorgD*2); Files.WriteInt(R, fixorgT); Files.WriteInt(R, fixorgM);
    Files.WriteInt(R, entry); Files.WriteInt(R, final);
    Files.Write(R, "O"); Files.Register(F)
  END Close;

BEGIN
  relmap[0] := BEQ; relmap[1] := BNE; relmap[2] := BLT; relmap[3] := -BGE (* LE *); relmap[4] := -BLT; (* GT*)  relmap[5] := BGE;
  condf[ 0] := FEQ;  condf[ 1] := -FEQ;  condf[ 2] := FLT;  condf[ 3] := FLE;  condf[ 4] := -FLT;  condf[ 5] := -FLE;
END OvG.
