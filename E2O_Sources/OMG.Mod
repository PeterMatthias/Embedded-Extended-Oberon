MODULE OMG; (* N.Wirth, 16.4.2016 / 4.4.2017 / 31.5.2019  Oberon compiler; code generator for RISC / AP 1.5.24 Extended Oberon*)
  IMPORT SYSTEM, Files, ORS, ORB;
  (*Code generator for Oberon compiler for RISC processor.
     Procedural interface to Parser OMP; result in array "code".
     Procedure Close writes code-files*)
(*
    MIPS32 version

    all changes by Peter Matthias

    2024-11-09  started, based on pol mips version
    2024-11-13  first boot, system compiles itself, CASE broken
    2024-11-14  implemented CASE
    2024-11-17  LDREG, Register: changed to map virtual registers
    2024-11-18  fixcode, fixvar: optimized encoding for 127 Module imports
    2024-11-23  Set: fixed and unified
    2024-12-19  LDREG, Register: mapping RISC5 registers to MIPS
    2024-12-28  Method, ReceiverParam: applied changes from EOS 

*)

  CONST  version= 5X; dPC = 1;  appendix=".mps";  WordSize* = 4;
    minR = 4; TR = 25; SP = 29; RA = 31; ZR = 0;  (*dedicated registers, TR is temporary register*)

    TrapAdr = 4;
    TrapArray=1; TrapTypeGuard=2; TrapCopyOV=3; TrapNIL=4; TrapIllProc=5; TrapDivZero=6; TrapAssert=7;
    notimplemented="not implemented";

    maxCode = 12000; maxStrx = 3500; maxTD = 160; maxSet = WordSize*8;
    Reg = 10; RegI = 11; Cond = 12;  (*internal item modes*)

    C4 = 10H; C6 = 40H; C8 = 100H;  C10 = 400H;  C12 = 1000H;  C14 = 4000H;  C15 = 8000H;  C16 = 10000H; C18 = 40000H; C19 = 80000H;
    C20 = 100000H; C22 = 400000H; C24 = 1000000H; C26 = 4000000H; C28 = 10000000H; C30 = 40000000H;

    (* instruction format *)
    OP = 4000000H; RS = 200000H; RT = 10000H; RD = 800H; IMM = 10000H; SHAMT = 40H;
    CO = 2000000H; FMT = RS; FT = RT; FS = RD; FD = SHAMT;

    (* R2000 opcodes *)
    SPECIAL = 0; (*BCOND = 1*OP;*) J = 2*OP; JAL = 3*OP; BEQ = 4*OP; BNE = 5*OP; BLEZ = 6*OP; BGTZ = 7*OP;
    ADDI = 8*OP; ADDIU = 9*OP; SLTI = 10*OP; SLTIU = 11*OP; ANDI = 12*OP; ORI = 13*OP; XORI = 14*OP; LUI = 15*OP;
    COP0 = 16*OP; COP1 = 17*OP; 
    SPECIAL2=28*OP; 
    LB = -32*OP; LH = -31*OP; (*LWL = -30;*) LW = -29*OP; LBU = -28*OP; LHU = -27*OP; (*LWR = -26;*)
    SB = -24*OP; SH = -23*OP; (*SWL = -22;*) SW = 43*OP; (*SWR = -18;*)
    LWC0 = -16*OP; SWC0 = -8*OP; LWC1 = -15*OP; SWC1 = -7*OP; LDC1=-11*OP; SDC1= -3*OP;

    (* SPECIAL *)
    SLLi = 0; SRLi = 2; ROTRi=SRLi+200000H; SRAi = 3; SLLV = 4; SRLV = 6; ROTRV= SRLV+40H; SRAV = 7; (* attention, rs, rt reversed for shift variable! *)
    JR = 8; JALR = 9; SYSCALL=12; MFHI = 16; MFLO = 18; MULT = 24; DIVv = 26;
    ADDU = 33; SUBU = 35; AND = 36; ORR = 37; XOR = 38; NOR = 39;
    SLT = 42; SLTU = 43;
    NOP = 0; (* SLL 0, 0, 0 *) 

    (* SPECIAL2 *)
    MUL= SPECIAL2+2;
    
    (* BCOND *)
    BGEZAL= 04110000H; BLTZ = 04000000H; BGEZ = 04010000H;
    
    (* COPZ *)
    (*MF = 0; MT = 4;*) BCF = 45000000H; BCT = 45010000H; (*CF = 2; CT = 6;*)
    
    (* R2010 functions *)
    Sfmt=16; Dfmt=17; Wfmt=20; 
    ADDf = 0;  ADDS=COP1+Sfmt*FMT+ADDf;
    SUBf = 1;  SUBS=COP1+Sfmt*FMT+SUBf;
    MULf = 2;  MULS=COP1+Sfmt*FMT+MULf;
    DIVf = 3;  DIVS=COP1+Sfmt*FMT+DIVf;
    ABSf = 5;  ABSS=COP1+Sfmt*FMT+ABSf;
    MOVf = 6;  MOVS=COP1+Sfmt*FMT+MOVf;
    NEGf = 7;  NEGS=COP1+Sfmt*FMT+NEGf;
    FLOORWf=15;  FLOORWS=COP1+Sfmt*FMT+FLOORWf;
    CVTSf = 32;  CVTSW=COP1+Wfmt*FMT+CVTSf;
    MTC1=COP1+0800000H; 
    MFC1=COP1+0H;

    CEQf = COP1+Sfmt*FMT+50; CLTf = COP1+Sfmt*FMT+60; CLEf = COP1+Sfmt*FMT+62;

(*    CVTDf = 33; CVTWf = 36;*)

    TYPE Item* = RECORD
      mode*: INTEGER;
      type*: ORB.Type;
      obj*: ORB.Object;
      a*, b*, r: LONGINT;
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

  VAR pc*: LONGINT;    (*program counter*)
    varx, strx, tdw: LONGINT;  (*varx and strx in bytes, tdw in words*)
    entry, final: LONGINT;   (*main entry point, finalization sequence*)
    RH: LONGINT;  (*available registers R[0] ... R[H-1]*)
    frame: LONGINT;  (*frame offset changed in SaveRegs and RestoreRegs*)
    fixorgP, fixorgD, fixorgT, fixorgM: LONGINT;   (*origins of lists of locations to be fixed up by loader*)
    check: BOOLEAN;  (*emit run-time checks*)

    relmap: ARRAY 6 OF INTEGER;  (*condition codes for relations*)
    condf: ARRAY 8 OF INTEGER;

    code: ARRAY maxCode OF LONGINT;
    str: ARRAY maxStrx OF CHAR;  (*strings*)
    td: ARRAY maxTD OF LONGINT;  (*type descriptors*)

  (*instruction assemblers according to formats*)

PROCEDURE incR;
BEGIN
  IF RH < TR-1 THEN INC(RH) ELSE ORS.Mark("register stack overflow") END
END incR;

PROCEDURE Put4( op: INTEGER);
BEGIN  code[pc] := op; INC(pc)
END Put4;

PROCEDURE PutR( op, rd, rs, rt: INTEGER);
BEGIN  (* SPECIAL = 0 *)
  Put4( op + rs * RS + rd * RD+ rt * RT)
END PutR;

PROCEDURE PutF (op, fd, fs, ft: INTEGER);
BEGIN  (* COP1 *)
  Put4( op + fs * FS + fd * FD + ft * FT)
END PutF;

PROCEDURE PutIS( op, rt, rs, imm: INTEGER);  (* imm sign extended *)
BEGIN
  IF (imm DIV 8000H )  # (imm DIV 10000H ) THEN ORS.Mark("PutIS offset too big") END;
  Put4(op+rs*RS+rt*RT+imm MOD IMM)
END PutIS;

PROCEDURE PutIU( op, rt, rs, imm: INTEGER);  (* imm unsigned extended *)
BEGIN
  IF imm DIV IMM # 0 THEN ORS.Mark("PutIU offset too big") END;
  Put4( op+rs*RS+rt*RT+imm MOD IMM)
END PutIU;

PROCEDURE PutSI( op, rd, rt, sa: INTEGER);  (* shift immediate *)
BEGIN
  Put4( op+rd*RD+rt*RT+sa*SHAMT)
END PutSI;

PROCEDURE PutMOV( rd, rs: INTEGER);
BEGIN PutIS( ADDI, rd, rs, 0);
END PutMOV;

PROCEDURE PutMOVI( rd, im: INTEGER);
BEGIN
  IF ASR(im, 15) = -1 THEN PutIS( ADDI, rd, ZR, im);
  ELSIF ASR(im, 16) = 0 THEN PutIU( ORI, rd, ZR, im);
  ELSE PutIS( LUI, rd, ZR, im DIV C16);
    IF im MOD C16 # 0 THEN PutIU( ORI, rd, rd, im MOD C16) END;
  END;
END PutMOVI;

PROCEDURE PutI32Add( rd, rs1, im: INTEGER);
BEGIN (*same as PutI0, but using up to 32 bit *)
  IF (im DIV 8000H +1) DIV 2 = 0 THEN PutIS( ADDIU, rd, rs1, im);  (* keep sign of const value *)
  ELSE PutMOVI( TR, im);
    PutR( ADDU, rd, rs1, TR);
  END
END PutI32Add;

PROCEDURE PutI32Log(op, rd, rs1, im: LONGINT);  (* op can be andi, ori, xori *)
BEGIN (*same as PutI0, but using up to 32 bit *)
  IF im DIV 10000H = 0 THEN PutIU( op, rd, rs1, im);
  ELSE PutMOVI( TR, im);
    PutR( op DIV OP MOD 8 +20H, rd, rs1, TR);
  END
END PutI32Log;

PROCEDURE fixcode( mno, pno: INTEGER);
(* fixorgP format: (mno 8bit, pno 8bit, mno > 0 1 bit, displacement 15bit) *)
BEGIN
  IF pc - fixorgP >= 2000H THEN ORS.Mark("fixcode displacement")
  ELSIF mno < - 0FFH THEN ORS.Mark("fixcode mno too big")
  ELSIF (mno # 0) & (pno > 0FFH) THEN ORS.Mark("fixcode pno >= 255")
  ELSE
    Put4(  - mno * C24 + pno * C16 + ORD(mno # 0) * C15 + (pc - fixorgP) * 2); fixorgP := pc - 1;
    Put4( NOP)
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
    Put4(  - mno * C24 + vno * C16 + ORD(mno # 0) * C15 + (pc - fixorgD) * 2); fixorgD := pc - 1;
  END;
END fixvar;

  PROCEDURE CheckRegs*;
  BEGIN
    IF RH # minR THEN ORS.Mark("Reg Stack"); RH := minR END ;
    IF pc >= maxCode - 40 THEN ORS.Mark("program too long") END ;
    IF frame # 0 THEN ORS.Mark("frame error"); frame := 0 END
  END CheckRegs;

  PROCEDURE SetCC(VAR x: Item; op, rs, rt: INTEGER);
  BEGIN
  IF op <16 THEN
    IF op=ORS.eql THEN op:=BEQ;
    ELSIF op=ORS.neq THEN op:=BNE;
    ELSE
      IF op=ORS.lss THEN PutR( SLT, TR, rs, rt); op:=BNE;
      ELSIF op=ORS.leq THEN PutR( SLT, TR, rt, rs); op:=BEQ;
      ELSIF op=ORS.gtr THEN PutR( SLT, TR, rt, rs); op:=BNE;
      ELSIF op=ORS.geq THEN PutR( SLT, TR, rs, rt); op:=BEQ;
      ELSE ORS.Mark("CC not allowed");
      END;
      rs:= TR; rt:=0;
    END;
  END;
  x.mode := Cond; x.a := 0; x.b := 0; 
  x.r := op+LSL(rs, 21)+LSL(rt, 16);  (* x.r is SB format *)
  END SetCC;

  PROCEDURE Trap(cond, rs, rt, num: INTEGER);
  BEGIN
    PutIS( cond, rt, rs, 7 - dPC - pc - num );
    PutIU( LUI, TR, ZR, ORS.Pos() MOD C16);
  END Trap;

  PROCEDURE NilCheck( r: INTEGER);
  BEGIN IF check THEN Trap(BEQ, r, ZR, TrapNIL) END
  END NilCheck;

  (*handling of forward reference, fixups of instruction operands*)

PROCEDURE negated(cond: INTEGER): INTEGER;
BEGIN
  IF cond DIV OP MOD 8=1 THEN  (* REGIMM, COP1 *)
    cond:=cond + (1 - cond DIV C16 MOD 2 * 2) * C16;  (* XOR IMM16 *)
  ELSE
    cond:=cond + (1 - cond DIV C26 MOD 2 * 2) * C26;  (* XOR IMM26 *)
  END;
  RETURN cond
END negated;

  PROCEDURE fixI(at, with: INTEGER);
    VAR v: INTEGER;
  BEGIN (*fix register immediate instruction*)
    IF (with < 0) OR (with > 8000H) THEN ORS.Mark("p.m.: fixI out of bounds") END ;
    code[at] := code[at] DIV C16 * C16 + with;
  END fixI;

  PROCEDURE fixB(at, with: INTEGER);
  BEGIN (*fix branch instruction*)
  code[at] := code[at] DIV C16 * C16+ (with - dPC ) MOD 10000H;
  END fixB;

  PROCEDURE FixOne*(at: INTEGER);
  BEGIN fixB(at, pc - at )
  END FixOne;

  PROCEDURE FixLinkWith(L, dst: INTEGER);
    VAR L1: INTEGER;
  BEGIN (*fix chain of branch instructions*)
    WHILE L # 0 DO
        L1 := code[L] MOD C16;
        fixB(L, dst-L);  L := L1
    END
  END FixLinkWith;

  PROCEDURE FixLink*(L: LONGINT);
  BEGIN FixLinkWith(L, pc)
  END FixLink;

  PROCEDURE FixLinkPair(L, adr: LONGINT);
    VAR q: INTEGER;
  BEGIN (* fix chain of instruction , 0 <= adr < C16 *)
    IF adr >= 10000H THEN ORS.Mark("p.m. FixLinkPair") END;
    WHILE L # 0 DO q := code[L];
      code[L] :=  adr * C16 + q MOD C16;  (* bit 15 is 0 *)
      L := q DIV C16 MOD C16;
    END
  END FixLinkPair;

  PROCEDURE merged(L0, L1: LONGINT): LONGINT;
    VAR L2, L3: LONGINT;
  BEGIN (*merge chains of the two operands of AND and OR*)
    IF L0 # 0 THEN L3 := L0;
      REPEAT L2 := L3; L3 := code[L2] MOD C16 UNTIL L3 = 0;
      code[L2] := code[L2] + L1; L1 := L0
    END ;
    RETURN L1
  END merged;

  (* loading of operands and addresses into registers *)

  PROCEDURE load(VAR x: Item);
    VAR op: INTEGER;
  BEGIN
      IF x.mode = Reg THEN
      IF (x.type= ORB.realType) THEN PutF( MFC1, 0, x.r, x.r) END;(* mv float reg to int reg *)
    ELSE
      IF x.type.size = 1 THEN op := LBU ELSE op := LW END ;
      IF x.mode = ORB.Const THEN
        IF x.type.form = ORB.Proc THEN
          IF x.r > 0 THEN (*local*) ORS.Mark("not allowed")
          ELSIF x.r = 0 THEN (*global*) PutIS(BGEZAL, 0, ZR, 2- dPC); PutI32Add( RH, RA, x.a - (pc + dPC) * 4 )
          ELSE (*imported*) fixvar( x.r + 80H, x.a); PutIS( ADDI, RH, RH, 0);  ORS.Mark("p.m. progbase-relative")(*mark as progbase-relative*)
          END
        ELSE PutMOVI( RH, x.a)
        END ;
        x.r := RH; incR
      ELSIF x.mode = ORB.Var THEN
        IF x.r > 0 THEN (*local*) PutIS(op, RH, SP, x.a + frame)
        ELSE fixvar( x.r, x.a); PutIS( op, RH, RH, 0);
        END ;
        x.r := RH; incR
      ELSIF x.mode = ORB.Par THEN PutIS(LW, RH, SP, x.a + frame); PutIS(op, RH, RH, x.b); x.r := RH; incR
      ELSIF x.mode = RegI THEN PutIS(op, x.r, x.r, x.a)
      ELSIF x.mode = Cond THEN
        IF (x.b = 0) THEN
          PutIS( x.r, 0, 0, 3- dPC); PutIU( ORI, RH, 0, 1);
          FixLink(x.a); PutIU( ORI, RH, 0, 0);
        ELSIF (x.a = 0) THEN
          PutIS( negated(x.r), 0, 0, 3- dPC); PutIU( ORI, RH, 0, 0);
          FixLink(x.b); PutIU( ORI, RH, 0, 1);
        ELSE
              PutIS( negated(x.r), 0, 0, 4- dPC); Put4(NOP); FixLink(x.b); 
          PutIS( BEQ, 0, 0, 3- dPC);
          PutIU( ORI, RH, 0, 1); FixLink(x.a); PutIU( ORI, RH, 0, 0);
        END;
        x.r := RH; incR
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
      ELSE 
        PutMOVI( RH, x.a); PutF( MTC1, 0, RH, RH);   
      END;
      x.r := RH; incR
    ELSIF x.mode = ORB.Var THEN
      IF x.r > 0 THEN (*local*) PutIS( LWC1, RH, SP, x.a + frame)
      ELSE fixvar( x.r, x.a); PutIS( LWC1, RH, RH, 0);
      END ;
      x.r := RH; incR
    ELSIF x.mode = ORB.Par THEN PutIS(LW, RH, SP, x.a + frame); PutIS( LWC1, RH, RH, x.b); x.r := RH; incR
    ELSIF x.mode = RegI THEN PutIS( LWC1, x.r, x.r, x.a) 
    ELSIF x.mode = Cond THEN ORS.Mark("loadf 2");
    END ;
    x.mode := Reg;
  END;
END loadf;

  PROCEDURE loadAdr(VAR x: Item);
  BEGIN
    IF x.mode = ORB.Var THEN
      IF x.r > 0 THEN (*local*) PutI32Add(RH, SP, x.a + frame)
      ELSE fixvar( x.r, x.a); PutIS( ADDIU, RH, RH, 0);
      END ;
      x.r := RH; incR
    ELSIF x.mode = ORB.Par THEN PutIS(LW, RH, SP, x.a + frame);
      IF x.b # 0 THEN PutI32Add( RH, RH, x.b) END ;
      x.r := RH; incR
    ELSIF x.mode = RegI THEN
      IF x.a # 0 THEN PutI32Add( x.r, x.r, x.a) END
    ELSE ORS.Mark("address error")
    END ;
    x.mode := Reg
  END loadAdr;

  PROCEDURE loadCond(VAR x: Item);
  BEGIN
    IF x.mode # Cond THEN
      IF x.type.form = ORB.Bool THEN
        IF x.mode = ORB.Const THEN  x.r := BNE - x.a*OP  (* x.a can be 0 or 1 *)
        ELSE load(x);
          x.r := BNE+x.r*10000H; DEC(RH)
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
    PutIS( ADDIU, RH, RH, 0);
    incR
  END loadTypTagAdr;

  PROCEDURE loadStringAdr(VAR x: Item);
  BEGIN
    IF x.r >= 0 THEN fixvar( x.r, varx + x.a);  (*PutPair(0, iADR, RH, RH, varx + x.a)*)
    ELSE (*imported*) fixvar( x.r,  x.a);  (*PutPair(x.r, iADR, RH, RH, x.a)*)
    END ;
    PutIS( ADDIU, RH, RH, 0);
    x.mode := Reg; x.r := RH; incR
  END loadStringAdr;

  (* Items: Conversion from constants or from Objects on the Heap to Items on the Stack*)

  PROCEDURE MakeConstItem*(VAR x: Item; typ: ORB.Type; val: LONGINT);
  BEGIN x.mode := ORB.Const; x.type := typ; x.a := val
  END MakeConstItem;

  PROCEDURE MakeRealItem*(VAR x: Item; val: REAL);
  BEGIN x.mode := ORB.Const; x.type := ORB.realType; x.a := SYSTEM.VAL(LONGINT, val)
  END MakeRealItem;

  PROCEDURE MakeStringItem*(VAR x: Item; len: LONGINT);  (*copies string from ORS-buffer to ORG-string array*)
    VAR i: LONGINT;
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
    VAR s, lim: INTEGER;
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
        IF lim >= 0 THEN PutIS( SLTIU, TR, y.r, lim);
        ELSIF x.mode IN {ORB.Var, ORB.Par} THEN (*open array param*) PutIS(LW, RH, SP, x.a+4+frame); PutR( SLTU, TR, y.r, RH)
        ELSIF x.mode = RegI THEN (*dynamic open array*) PutIS(LW, RH, x.r, -16); (*len*) PutR( SLTU, TR, y.r, RH)
        ELSE ORS.Mark("error in Index")
        END ;
        Trap(BEQ, TR, ZR, TrapArray)
      END ;
      IF s = 4 THEN PutSI(SLLi, y.r, y.r, 2) ELSIF s > 1 THEN PutMOVI( RH, s); PutR( MUL, y.r, y.r, RH) END ;
      IF x.mode = ORB.Var THEN
        IF x.r > 0 THEN (*local*) PutR(ADDU, y.r, SP, y.r); INC(x.a, frame)
        ELSE (*imported*) fixvar( x.r, x.a); PutIS( ADDI, RH, RH, 0); PutR(ADDU, y.r, y.r, RH); x.a := 0
        END ;
        x.r := y.r; x.mode := RegI
      ELSIF x.mode = ORB.Par THEN
        PutIS(LW, RH, SP, x.a + frame);
        PutR(ADDU, y.r, RH, y.r); x.mode := RegI; x.r := y.r; x.a := x.b
      ELSIF x.mode = RegI THEN PutR(ADDU, x.r, x.r, y.r); DEC(RH)
      END
    END
  END Index;

  PROCEDURE DeRef*(VAR x: Item);
  BEGIN
    IF x.mode = ORB.Var THEN
      IF x.r > 0 THEN (*local*) PutIS(LW, RH, SP, x.a + frame)
      ELSE fixvar( x.r, x.a); PutIS( LW, RH, RH, 0)
      END ;
      NilCheck(RH); x.r := RH; incR
    ELSIF x.mode = ORB.Par THEN
      PutIS(LW, RH, SP, x.a + frame); PutIS(LW, RH, RH, x.b); NilCheck(RH); x.r := RH; incR
    ELSIF x.mode = RegI THEN PutIS(LW, x.r, x.r, x.a); NilCheck(x.r)
    ELSIF x.mode # Reg THEN ORS.Mark("bad mode in DeRef")
    END ;
    IF x.type.base.form = ORB.Array THEN PutIS(ADDIU, x.r, x.r, 16) END ; (*pointer to array*)
    x.mode := RegI; x.a := 0; x.b := 0; x.deref := TRUE
  END DeRef;

  PROCEDURE Method*(VAR x: Item; y: ORB.Object; super: BOOLEAN);
  BEGIN loadAdr(x); (*receiver*) x.super := super;
    IF super THEN x.a := y.val; (*mthadr/exno*) x.b := -y.type.mno
    ELSE x.a := y.lev; (*mthno*)
      IF x.deref THEN x.b := ORB.Var ELSE x.b := ORB.Par END
    END ;
  END Method;

  PROCEDURE Q(T: ORB.Type; VAR tdw: LONGINT);
  BEGIN (*one entry of type descriptor extension table*)
    IF T.base # NIL THEN
      Q(T.base, tdw); td[tdw] := (T.mno*C12 + T.len (*TDoff/exno*)) * C12 + tdw - fixorgT;
      fixorgT := tdw; INC(tdw)
    END
  END Q;

  PROCEDURE FindRefFlds(ftyp: SET; typ: ORB.Type; off: LONGINT; VAR tdw: LONGINT);
    VAR fld: ORB.Object; i, s: LONGINT;
  BEGIN
    IF typ.form IN ftyp THEN td[tdw] := off; INC(tdw)
    ELSIF typ.form = ORB.Record THEN fld := typ.dsc;
      WHILE fld # NIL DO FindRefFlds(ftyp, fld.type, fld.val + off, tdw); fld := fld.next END
    ELSIF typ.form = ORB.Array THEN s := typ.base.size;
      FOR i := 0 TO typ.len-1 DO FindRefFlds(ftyp, typ.base, i*s + off, tdw) END
    END
  END FindRefFlds;

  PROCEDURE BuildTD(T: ORB.Type; VAR tdw: LONGINT);
    VAR k, s: LONGINT; fld, bot: ORB.Object; t: ORB.Type;
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
    VAR pc0: LONGINT;
  BEGIN
    IF T = NIL THEN
      IF x.mode >= Reg THEN DEC(RH) END ;
      SetCC(x, BEQ, 0, 0)
    ELSE (*fetch tag into RH*)
      IF varpar THEN PutIS(LW, RH, SP, x.a+4+frame)
      ELSE load(x);
        pc0 := pc; PutIS(BEQ, x.r, ZR, 0);  (*NIL belongs to every pointer type*)
        PutIS(LW, RH, x.r, -8)
      END ;
      PutIS(LW, RH, RH, T.nofpar*4); incR;
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
    VAR t: LONGINT;
  BEGIN loadCond(x); x.r := negated(x.r); t := x.a; x.a := x.b; x.b := t
  END Not;

  PROCEDURE And1*(VAR x: Item);   (* x := x & *)
  BEGIN loadCond(x); PutIS( negated(x.r), 0, 0, x.a); x.a := pc-1; FixLink(x.b); Put4( NOP); x.b := 0
  END And1;

  PROCEDURE And2*(VAR x, y: Item);
  BEGIN loadCond(y); x.a := merged(y.a, x.a); x.b := y.b; x.r := y.r
  END And2;

  PROCEDURE Or1*(VAR x: Item);   (* x := x OR *)
  BEGIN loadCond(x); PutIS( x.r, 0, 0, x.b); x.b := pc-1; FixLink(x.a); Put4(NOP); x.a := 0
  END Or1;

  PROCEDURE Or2*(VAR x, y: Item);
  BEGIN loadCond(y); x.a := y.a; x.b := merged(y.b, x.b); x.r := y.r
  END Or2;

  (* Code generation for arithmetic operators *)

  PROCEDURE Neg*(VAR x: Item);   (* x := -x *)
  BEGIN
    IF x.type.form = ORB.Int THEN
      IF x.mode = ORB.Const THEN x.a := -x.a
      ELSE load(x); PutR(SUBU, RH- 1, ZR, x.r); x.r := RH-1
      END
    ELSIF x.type.form = ORB.Real THEN
      IF x.mode = ORB.Const THEN x.a := x.a + 7FFFFFFFH + 1
      ELSE loadf(x); PutF( NEGS, x.r, x.r, 0);
      END
    ELSE (*form = Set*)
      IF x.mode = ORB.Const THEN x.a := -x.a-1 
      ELSE load(x); PutR(NOR, RH-1, x.r, 0); x.r:=RH-1;
      END
    END
  END Neg;

  PROCEDURE AddOp*(op: LONGINT; VAR x, y: Item);   (* x := x +- y *)
  BEGIN
    IF op = ORS.plus THEN
      IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a + y.a
      ELSIF y.mode = ORB.Const THEN load(x);
        IF y.a # 0 THEN PutI32Add(x.r, x.r, y.a) END
      ELSE load(x); load(y); PutR(ADDU, RH-2, x.r, y.r); DEC(RH); x.r := RH-1
      END
    ELSE (*op = ORS.minus*)
      IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a - y.a
      ELSIF y.mode = ORB.Const THEN load(x);
        IF y.a # 0 THEN PutI32Add(x.r, x.r, - y.a) END
      ELSE load(x); load(y); PutR(SUBU, RH-2, x.r, y.r); DEC(RH); x.r := RH-1
      END
    END
  END AddOp;

  PROCEDURE log2(m: LONGINT; VAR e: LONGINT): LONGINT;
  BEGIN e := 0;
    WHILE ~ODD(m) DO m := m DIV 2; INC(e) END ;
    RETURN m
  END log2;

  PROCEDURE MulOp*(VAR x, y: Item);   (* x := x * y *)
    VAR e: LONGINT;
  BEGIN
    IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a * y.a
    ELSIF (y.mode = ORB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN load(x); PutSI(SLLi, x.r, x.r, e)
    ELSIF (x.mode = ORB.Const) & (x.a >= 2) & (log2(x.a, e) = 1) THEN load(y); PutSI(SLLi, y.r, y.r, e); x.mode := Reg; x.r := y.r
    ELSE load(x); load(y); PutR(MUL, RH-2, x.r, y.r); DEC(RH); x.r := RH-1
    END
  END MulOp;

  PROCEDURE DivOp*(op: LONGINT; VAR x, y: Item);   (* x := x op y *)
    VAR e: INTEGER; yc: BOOLEAN;
  BEGIN
    yc := y.mode = ORB.Const;
    IF op = ORS.div THEN
      IF (x.mode = ORB.Const) & yc THEN
        IF y.a > 0 THEN x.a := x.a DIV y.a ELSE ORS.Mark("bad divisor") END
      ELSIF yc & (y.a >= 2) & (log2(y.a, e) = 1) THEN load(x); PutSI(SRAi, x.r, x.r, e);
      ELSE
        IF yc & (y.a <= 0) THEN ORS.Mark("bad divisor");
        ELSE
          load(x); load(y);  (* adjust for Oberon definition *)
          PutSI( SRAi, RH, x.r, 31); incR;
          PutR( SUBU, RH, x.r, RH-1);
          PutR( DIVv, 0, RH, y.r); DEC( RH);
              IF ~yc & check THEN Trap( BLEZ, y.r, ZR, TrapDivZero) END;
          PutR( MFLO, x.r, 0, 0);
          PutR( ADDU, RH-2, x.r, RH);
          DEC(RH); x.r:=RH-1;
        END;
      END;
    ELSE (*op = ORS.mod*)
      IF (x.mode = ORB.Const) & yc THEN
        IF y.a > 0 THEN x.a := x.a MOD y.a ELSE ORS.Mark("bad modulus") END
      ELSIF yc & (y.a >= 2) & (log2(y.a, e) = 1) THEN load(x);
        IF e <= 16 THEN PutIU(ANDI, x.r, x.r, y.a-1) ELSE PutSI(SLLi, x.r, x.r, 32-e); PutSI(SRLi, x.r, x.r, 32-e) END
      ELSE
        IF yc & ( y.a <= 0) THEN ORS.Mark("bad modulus")
        ELSE
          load(x); load(y);  (* adjust for Oberon definition *)
          PutR( DIVv, 0, x.r, y.r);
              IF ~yc & check THEN Trap( BLEZ, y.r, 0, TrapDivZero) END;
          PutR( MFHI, x.r, 0, 0);
          PutSI( SRAi, RH, x.r, 31);
          PutR( AND, RH, RH, y.r);
          PutR( ADDU, RH-2, x.r, RH);  
          DEC(RH); x.r:=RH-1;
        END;
      END
    END
  END DivOp;

  (* Code generation for REAL operators *)

  PROCEDURE RealOp*(op: INTEGER; VAR x, y: Item);   (* x := x op y *)
  BEGIN loadf(x); loadf(y);
    IF op = ORS.plus THEN PutF(ADDS, RH-2, x.r, y.r)
    ELSIF op = ORS.minus THEN PutF(SUBS, RH-2, x.r, y.r)
    ELSIF op = ORS.times THEN PutF(MULS, RH-2, x.r, y.r)
    ELSIF op = ORS.rdiv THEN PutF(DIVS, RH-2, x.r, y.r)
    END ;
    DEC(RH); x.r := RH-1
  END RealOp;

  (* Code generation for set operators *)

  PROCEDURE Singleton*(VAR x: Item);  (* x := {x} *)
  BEGIN
    IF x.mode = ORB.Const THEN x.a := LSL(1, x.a)
    ELSE load(x); PutMOVI(RH, 1); PutR( SLLV, RH-1, x.r, RH); x.r:=RH-1;
    END
  END Singleton;

  PROCEDURE Set*(VAR x, y: Item);   (* x := {x .. y} *)
  BEGIN
    IF (x.mode = ORB.Const) & ( y.mode = ORB.Const) THEN
      IF x.a <= y.a THEN x.a := LSL(2, y.a) - LSL(1, x.a) ELSE x.a := 0 END
    ELSE
      IF (x.mode = ORB.Const) THEN  x.a := LSL(1, x.a)
      ELSE load(x); PutMOVI( RH, 1); PutR( SLLV, RH - 1, x.r, RH); x.r := RH - 1;
      END;
      IF (y.mode = ORB.Const) THEN PutMOVI( RH,  LSL(2, x.a)); y.mode := Reg; y.r := RH; incR
          ELSE load(y); PutMOVI( RH, 2); PutR( SLLV, y.r, y.r, RH);
      END;
      IF (x.mode = ORB.Const) THEN PutI32Add( RH - 1, y.r, -x.a); x.mode := Reg
      ELSE DEC(RH); PutR( SUBU, RH-1, y.r, x.r);    (* don't use x.r as target. y can be loaded before x *)
      END;
      x.r := RH-1; 
(*
          load(x); PutMOVI( RH, -1); PutR( SLLV, RH - 1, x.r, RH); x.r := RH - 1;
          load(y); PutMOVI( RH, -2); PutR( SLLV, RH - 1, y.r, RH); y.r := RH - 1;
          DEC(RH); PutR( NOR, RH, y.r, 0); PutR( AND, RH-1, x.r, RH);
          x.r := RH-1;
*)
    END
  END Set;

  PROCEDURE In*(VAR x, y: Item);  (* x := x IN y *)
  BEGIN load(y);
    IF x.mode = ORB.Const THEN
      IF x.a # 0 THEN PutSI( SRLi, y.r, y.r, x.a) END;
    ELSE load(x); PutR( SRLV, y.r, x.r, y.r); DEC( RH);
    END;
    PutIU( ANDI, RH-1, y.r, 1);
    x.mode:= Reg; x.r:= RH-1; 
  END In;

  PROCEDURE SetOp*(op: LONGINT; VAR x, y: Item);   (* x := x op y *)
    VAR xset, yset: SET; (*x.type.form = Set*)
  BEGIN
    IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
      xset := SYSTEM.VAL(SET, x.a); yset := SYSTEM.VAL(SET, y.a);
      IF op = ORS.plus THEN xset := xset + yset
      ELSIF op = ORS.minus THEN xset := xset - yset
      ELSIF op = ORS.times THEN xset := xset * yset
      ELSIF op = ORS.rdiv THEN xset := xset / yset
      END ;
      x.a := SYSTEM.VAL(LONGINT, xset)
    ELSIF y.mode = ORB.Const THEN
      load(x);
          IF op = ORS.plus THEN PutI32Log( ORI, x.r, x.r, y.a)
          ELSIF op = ORS.minus THEN PutI32Log( ANDI, x.r, x.r, -y.a-1)
          ELSIF op = ORS.times THEN PutI32Log( ANDI, x.r, x.r, y.a)
          ELSIF op = ORS.rdiv THEN PutI32Log( XORI, x.r, x.r, y.a)
          END ;
    ELSE load(x); load(y);
          IF op = ORS.plus THEN PutR( ORR, RH-2, x.r, y.r)
          ELSIF op = ORS.minus THEN PutR( NOR, y.r, y.r, 0); PutR( AND, RH-2, x.r, y.r)
          ELSIF op = ORS.times THEN PutR( AND, RH-2, x.r, y.r)
          ELSIF op = ORS.rdiv THEN PutR( XOR, RH-2, x.r, y.r)
          END ;
      DEC(RH); x.r := RH-1
    END 
  END SetOp;

  (* Code generation for relations *)

  PROCEDURE IntRelation*(op: INTEGER; VAR x, y: Item);   (* x := x < y *)
  BEGIN
    IF (x.mode = Cond) OR (y.mode = Cond) THEN ORS.Mark(notimplemented) END ;
    load(x); load(y);
    SetCC( x, op, x.r, y.r);
    DEC(RH, 2);
  END IntRelation;

PROCEDURE RealRelation*(op: INTEGER; VAR x, y: Item);   (* x := x < y *)
VAR cmp: INTEGER;
BEGIN loadf(x); loadf(y);
  cmp:= condf[ op - ORS.eql];
  IF cmp >0 THEN PutF( cmp, 0, x.r, y.r); op:=BCT;  (* TRUE Jump *)
  ELSE PutF( -cmp, 0, x.r, y.r); op:=BCF;
  END;
  SetCC( x, op, 0, 0);
  DEC(RH, 2);
END RealRelation;

PROCEDURE StringRelation*(op: INTEGER; VAR x, y: Item);   (* x := x < y *)
  (*x, y are char arrays or strings*)
BEGIN
  IF x.type.form = ORB.String THEN loadStringAdr(x) ELSE loadAdr(x) END ;
  IF y.type.form = ORB.String THEN loadStringAdr(y) ELSE loadAdr(y) END ;
  PutIS( LBU, RH, x.r, 0); 
  PutIS( LBU , RH+1, y.r, 0); 
  PutIS( BNE, RH, RH+1, 4- dPC); PutIS( ADDIU, x.r, x.r, 1);
  PutIS( BNE, RH, 0, -4- dPC); PutIS( ADDIU, y.r, y.r, 1);
  SetCC( x, op, RH, RH+1);
  DEC(RH, 2);
END StringRelation;

  (* Code generation of Assignments *)

  PROCEDURE StrToChar*(VAR x: Item);
  BEGIN x.type := ORB.charType; DEC(strx, 4); x.a := ORD(str[x.a])
  END StrToChar;

  PROCEDURE Store*(VAR x, y: Item); (* x := y *)
    VAR op: LONGINT;
  BEGIN  load(y);
    IF x.type.size = 1 THEN op := SB ELSE op := SW END ;
    IF x.mode = ORB.Var THEN
      IF x.r > 0 THEN (*local*) PutIS(op, y.r, SP, x.a + frame)
      ELSE fixvar( x.r, x.a); PutIS( op, y.r, RH, 0);
      END
    ELSIF x.mode = ORB.Par THEN PutIS(LW, RH, SP, x.a + frame); PutIS(op, y.r, RH, x.b);
    ELSIF x.mode = RegI THEN PutIS(op, y.r, x.r, x.a); DEC(RH);
    ELSE ORS.Mark("bad mode in Store")
    END ;
    DEC(RH)
  END Store;

PROCEDURE Storef*(VAR x, y: Item); (* x := y *)
VAR i: INTEGER;
BEGIN
  loadf(y);
  IF x.type# ORB.realType THEN ORS.Mark("Storef 0") END;
  IF x.mode = ORB.Var THEN
    IF x.r > 0 THEN (*local*) PutIS( SWC1, y.r, SP, x.a + frame)
    ELSE fixvar( x.r, x.a); PutIS( SWC1, y.r, RH, 0);
    END
  ELSIF x.mode = ORB.Par THEN PutIS( LW, RH, SP, x.a + frame); PutIS( SWC1, y.r, RH, x.b);
  ELSIF x.mode = RegI THEN PutIS(SWC1, y.r, x.r, x.a); DEC(RH);
  ELSE ORS.Mark("bad mode in Storef")
  END ;
  DEC(RH);
END Storef;

  PROCEDURE StoreStruct*(VAR x, y: Item); (* x := y, frame = 0 *)
    VAR s, pc0: LONGINT;
  BEGIN loadAdr(x); loadAdr(y);
    IF (x.type.form = ORB.Array) & (x.type.len > 0) THEN
      IF y.type.len >= 0 THEN
        IF x.type.size = y.type.size THEN PutMOVI( RH, (y.type.size+3) DIV 4)
        ELSE ORS.Mark("different length/size, not implemented")
        END
      ELSE (*y open array param or dynamic open array*)
        IF y.type.size > 0 THEN PutIS(LW, RH, SP, y.a+4) ELSE PutIS(LW, RH, y.r, -16) END ; (*len*)
        s := y.type.base.size;  (*element size*)
        pc0 := pc; PutIS(BEQ, RH, ZR, 0);
        IF s = 1 THEN PutIS(ADDIU, RH, RH, 3); PutSI(SRAi, RH, RH, 2)
        ELSIF s # 4 THEN PutMOVI(TR, s DIV 4); PutR( MUL, RH, RH, TR)
        END ;
        IF check THEN (*check array lengths*) incR;
          PutIS( SLTIU, RH, RH - 1, (x.type.size+ 7) DIV 4); Trap(BEQ, RH, ZR, TrapCopyOV); DEC(RH)
        END ;
        fixB(pc0, pc + 6 - pc0 ) (* jmp to end*)
      END
    ELSIF x.type.form = ORB.Record THEN PutMOVI( RH, x.type.size DIV 4)
    ELSE ORS.Mark("inadmissible assignment")
    END ;
    incR;
    PutIS( LW, RH, y.r, 0);
    PutIS( ADDIU, RH -1 , RH - 1, - 1);
    PutIS( ADDIU, x.r, x.r, 4);
    PutIS( ADDIU, y.r, y.r, 4);
    PutIS( BGTZ, 0, RH - 1, - 4 - dPC);
    PutIS( SW, RH, x.r, -4);
    RH := minR
  END StoreStruct;

  PROCEDURE CopyString*(VAR x, y: Item);  (* x := y, frame = 0 *) 
     VAR len: LONGINT;
   BEGIN loadAdr(x); len := x.type.len;
    IF len >= 0 THEN
      IF len <  y.b THEN ORS.Mark("string too long") END
    ELSIF check THEN (*x open array param or dynamic open array*)
      IF x.type.size > 0 THEN PutIS(LW, RH, SP, x.a+4) ELSE PutIS(LW, RH, x.r, -16) END ; (*len*)
      PutR( SLT, TR, RH, y.b); Trap(BNE, TR, ZR, TrapCopyOV)
    END ;
    loadStringAdr(y);
      PutIS( LW, RH, y.r, 0);
    PutIS( ADDIU, y.r, y.r, 4);
      PutIS( SW, RH, x.r, 0);
      PutSI( SRAi, RH, RH, 24);
    PutIS( BNE, RH, 0, - 4 - dPC); 
    PutIS( ADDIU, x.r, x.r, 4); RH := minR;
  END CopyString;

  (* Code generation for parameters *)

  PROCEDURE OpenArrayParam*(VAR x: Item);
  BEGIN loadAdr(x);
    IF x.type.len >= 0 THEN PutMOVI( RH, x.type.len)
    ELSIF x.type.size > 0 THEN (*open array param*) PutIS(LW, RH, SP, x.a+4+frame)
    ELSE (*dynamic open array*) PutIS(LW, RH, x.r, -16) (*len*)
    END ;
    incR
  END OpenArrayParam;

  PROCEDURE VarParam*(VAR x: Item; ftype: ORB.Type);
    VAR xmd: INTEGER;
  BEGIN xmd := x.mode; loadAdr(x);
    IF (ftype.form = ORB.Array) & (ftype.len < 0) THEN (*open array*)
      IF x.type.len >= 0 THEN PutMOVI( RH, x.type.len)
      ELSIF x.type.size > 0 THEN (*open array param*) PutIS(LW, RH, SP, x.a+4+frame)
      ELSE (*dynamic open array*) PutIS(LW, RH, x.r, -16) (*len*)
      END ;
      incR
    ELSIF ftype.form = ORB.Record THEN
      IF x.deref THEN PutIS(LW, RH, x.r, -8); incR
      ELSIF xmd = ORB.Par THEN PutIS(LW, RH, SP, x.a+4+frame); incR
      ELSE loadTypTagAdr(x.type)
      END
    END
  END VarParam;

PROCEDURE ValueParam*(VAR x: Item);
BEGIN
  IF (x.type= ORB.realType) THEN loadf(x); PutF( MFC1, 0, x.r, x.r);
  ELSE load(x);
    IF x.r = 0 THEN
      PutIS( ORI, RH-1, 0, 0);
      x.r:=RH-1;
    END;
  END;
END ValueParam;

  PROCEDURE StringParam*(VAR x: Item);
  BEGIN loadStringAdr(x); PutMOVI( RH, x.b); incR  (*len*)
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
    IF y.r=0 THEN
      PutIU( ORI, RH-1, ZR, 0);
      y.r:=RH-1;
    END;
  END For0;

  PROCEDURE For1*(VAR x, y, z, w: Item; VAR L: LONGINT);
  BEGIN 
      load(z);
    IF w.a > 0 THEN PutR( SLT, TR, z.r, y.r);
    ELSIF w.a < 0 THEN PutR( SLT, TR, y.r, z.r);
    ELSE ORS.Mark("zero increment"); 
    END;
    L := pc;
      PutIS( BNE, TR, 0, 0); Put4(NOP);
    DEC(RH);
    Store(x, y)
  END For1;

  PROCEDURE For2*(VAR x, y, w: Item);
  BEGIN load(x); DEC(RH); ASSERT( x.r # 0); PutI32Add( x.r, x.r, w.a);
  END For2;

  (* Branches, procedure calls, procedure prolog and epilog *)

  PROCEDURE Here*(): LONGINT;
  BEGIN RETURN pc
  END Here;

  PROCEDURE FJump*(VAR L: LONGINT);
  BEGIN PutIS( BEQ, 0, 0, L); L := pc-1;  Put4(NOP);
  END FJump;

  PROCEDURE CFJump*(VAR x: Item);
  BEGIN loadCond(x);
      PutIS(negated(x.r), 0, 0, x.a); x.a := pc-1; Put4(NOP); FixLink(x.b);  
  END CFJump;

  PROCEDURE BJump*(L: LONGINT);
  BEGIN PutIS( BEQ, 0, 0, L-pc- dPC); Put4(NOP);
  END BJump;

  PROCEDURE CBJump*(VAR x: Item; L: LONGINT);
  BEGIN loadCond(x); 
      PutIS( negated(x.r), 0, 0, L-pc- dPC ); Put4(NOP); FixLink(x.b); FixLinkWith(x.a, L); 
  END CBJump;

  PROCEDURE Fixup*(VAR x: Item);
  BEGIN FixLink(x.a)
  END Fixup;

  PROCEDURE SaveRegs(r: LONGINT);  (* R[0 .. r-1]*)
    VAR r0: LONGINT;
  BEGIN (*r > 0*) r0 := minR;
    PutIS(ADDI, SP, SP, (minR-r)*4); INC(frame, 4*(r-minR));
    REPEAT PutIS(SW, r0, SP, (r-r0-1)*4); INC(r0) UNTIL r0 = r
  END SaveRegs;

  PROCEDURE RestoreRegs(r: LONGINT); (*R[0 .. r-1]*)
    VAR r0: LONGINT;
  BEGIN (*r > 0*) r0 := r;
    REPEAT DEC(r0); PutIS(LW, r0, SP, (r-r0-1)*4) UNTIL r0 = minR;
    PutIS(ADDI, SP, SP, (r-minR)*4); DEC(frame, 4*(r-minR))
  END RestoreRegs;

  PROCEDURE PrepCall*(VAR x: Item; VAR r: LONGINT);
  BEGIN (*x.type.form IN {ORB.Proc, ORB.TProc}*)
    IF x.type.form = ORB.TProc THEN DEC(RH) ELSIF x.mode > ORB.Par THEN load(x) END ;
    r := RH;
    IF RH > minR THEN SaveRegs(RH); RH := minR END
  END PrepCall;

  PROCEDURE Call*(VAR x: Item; r: LONGINT);
  BEGIN (*x.type.form IN {ORB.Proc, ORB.TProc}*)
    IF x.type.form = ORB.TProc THEN  (*type-bound procedure*)
      IF x.super THEN  (*super call*)
        IF x.b >= 0 THEN PutIS(BGEZAL, ZR, ZR, (x.a DIV 4) - pc - dPC); Put4( NOP);
        ELSE (*imported*) fixcode(x.b, x.a);
        END
      ELSE  (*method call*)
        IF x.b = ORB.Var THEN PutIS(LW, RH, 0, -8) ELSE PutMOVI( RH, 1) END ;
        PutIS(LW, RH, RH, -4-x.a*4); PutR(JALR, RA, RH, 0); Put4( NOP);
      END
    ELSIF x.mode = ORB.Const THEN  (*regular procedure*)
      IF x.r >= 0 THEN PutIS( BGEZAL , 0, 0, x.a DIV 4  -pc- dPC ); Put4( NOP);
      ELSE (*imported*) fixcode(x.r, x.a);
      END
    ELSE  (*installed procedure*)
      IF x.mode <= ORB.Par THEN load(x); DEC(RH)
      ELSE PutIS(LW, RH, SP, 0); PutIS(ADDIU, SP, SP, 4); DEC(r); DEC(frame, 4)
      END ;
      IF check THEN Trap(BEQ, RH, 0, TrapIllProc) END ;
      PutR(JALR, RA, RH, 0); Put4( NOP);
    END ;
    IF x.type.base.form = ORB.NoTyp THEN (*procedure*) RH := minR
    ELSE  (*function*)
      IF r > minR THEN PutMOV( r, minR); RestoreRegs(r) END ;
      x.mode := Reg; x.r := r; RH := r+1
    END
  END Call;

  PROCEDURE Enter*(parblksize, locblksize: LONGINT; int: BOOLEAN);
    VAR a, r: LONGINT;
  BEGIN frame := 0;
    IF locblksize >= 8000H THEN ORS.Mark("too many locals") END ;
    a := 4; r := minR;
    PutIS(ADDIU, SP, SP, -locblksize); PutIS(SW, RA, SP, 0);
    WHILE a < parblksize DO PutIS(SW, r, SP, a); INC(r); INC(a, 4) END
  END Enter;

  PROCEDURE Return*(form: INTEGER; VAR x: Item; size: LONGINT; int: BOOLEAN);
  BEGIN
    IF form # ORB.NoTyp THEN
      IF x.type = ORB.realType THEN loadf(x) ELSE load(x) END;
    END ;
    PutIS(LW, RA, SP, 0); PutR(JR, 0, RA, 0); PutIS(ADDIU, SP, SP, size); 
    RH := minR
  END Return;

  (* Case Statements *)

  PROCEDURE CaseHead*(VAR x: Item; VAR L0: LONGINT);
  BEGIN load(x);  (*value of case expression*)
(* R5-version
    L0 := pc; Put1(Cmp, RH, x.r, 0);  (*higher bound, fixed up in CaseTail*)
    Put3(BC, CC, 0);  (*branch to else, fixed up in CaseTail*)
    Put1(Add, x.r, x.r, 0);  (*nof words between BL instruction at L0+4 and jump table, fixed up in CaseTail*)
    Put1(Lsl, x.r, x.r, 2);
    (*L0+4*) Put3(BL, 7, 0);  (*LNK := PC+1*)
    Put0(Add, LNK, LNK, x.r); Put3(BR, 7, LNK); DEC(RH)
*)
    L0 := pc; PutIS( SLTIU, RH, x.r, 0);  (*higher bound, fixed up in CaseTail*)
    PutIS( BEQ, RH, 0, 0);  (*branch to else, fixed up in CaseTail*)
    Put4(NOP);
    PutSI( SLLi, x.r, x.r, 3);
    PutIS( BGEZAL, 0, 0, 2 - dPC);  (* LNK := PC + 2 *)
    (* L0 + 5 *) PutIS( ADDIU, x.r, x.r, 0);
    PutR( ADDU, x.r, x.r, RA);
    PutR( JR, 0, x.r, 0);
    Put4(NOP);
    DEC(RH); (*LNK := PC+1; nof bytes between BL instruction at L0+4 and jump table, fixed up in CaseTail*)
  END CaseHead;

  PROCEDURE CaseTail*(L0, L1: LONGINT; n: INTEGER; VAR tab: ARRAY OF LabelRange);  (*L1 = label for else*)
    VAR i, j: INTEGER;
  BEGIN
    IF n > 0 THEN fixI(L0, tab[n-1].high + 1) (*higher bound*) ELSIF L1 = 0 THEN ORS.Mark("empty case") END ;
    IF L1 = 0 THEN L1 := pc; Trap(BEQ, ZR, ZR,TrapArray) END ;  (*create else*)
    fixB(L0 + 1, L1 - L0 - 3);  (*branch to else*)
    fixI(L0 + 5, (pc - L0 - 6) * 4);  (* nof bytes between BL instruction at L0+ 5 and jump table*)
    j := 0;
    FOR i := 0 TO n-1 DO  (*construct jump table*)
      WHILE j < tab[i].low DO BJump(L1); INC(j) END ;  (*else*)
      WHILE j <= tab[i].high DO BJump(tab[i].label); INC(j) END
    END
  END CaseTail;

  (* In-line code procedures *)

  PROCEDURE Increment*(upordown: LONGINT; VAR x, y: Item);
    VAR op, zr, v: LONGINT;
  BEGIN (*frame = 0*)
    IF upordown = 0 THEN op := ADDU ELSE op := SUBU END ;
    IF x.type = ORB.byteType THEN v := 10000000H ELSE v := 0C000000H END ;
    IF y.type.form = ORB.NoTyp THEN y.mode := ORB.Const; y.a := 1 END ;
    IF (y.mode = ORB.Const) & ( op= SUBU) THEN  y.a:=-y.a END;
    IF (x.mode = ORB.Var) & (x.r > 0) THEN
      zr := RH; PutIS(LB+v, zr, SP, x.a); incR;
      IF y.mode = ORB.Const THEN PutI32Add( zr, zr, y.a) ELSE load(y); PutR(op, zr, zr, y.r); DEC(RH) END ;
      PutIS(SB+(v MOD 10000000H), zr, SP, x.a); DEC(RH)
    ELSE loadAdr(x); zr := RH; PutIS(LB+v, RH, x.r, 0); incR;
      IF y.mode = ORB.Const THEN PutI32Add(zr, zr, y.a) ELSE load(y); PutR(op, zr, zr, y.r); DEC(RH) END ;
      PutIS(SB+(v MOD 10000000H), zr, x.r, 0); DEC(RH, 2)
    END
  END Increment;

PROCEDURE Include*(inorex: LONGINT; VAR x, y: Item);
  VAR op, zr: LONGINT;
BEGIN loadAdr(x); zr := RH; PutIS(LW, RH, x.r, 0); incR;
(*
    IF inorex = 0 THEN op := Ior ELSE op := Ann END ;
    IF y.mode = ORB.Const THEN Put1a(op, zr, zr, LSL(1, y.a))
    ELSE load(y); Put1(Mov, RH, 0, 1); Put0(Lsl, y.r, RH, y.r); Put0(op, zr, zr, y.r); DEC(RH)
    END ;
    Put2(Str, zr, x.r, 0); DEC(RH, 2)
*)
  IF inorex = 0 THEN
    IF y.mode = ORB.Const THEN PutI32Log( ORI, zr, zr, LSL(1, y.a));
    ELSE load(y); PutMOVI( RH, 1); PutR( SLLV, y.r, y.r, RH); PutR( ORR, zr, zr, y.r); DEC(RH);
    END ;
  ELSE
    IF y.mode = ORB.Const THEN PutI32Log( ANDI, zr, zr, -LSL(1, y.a)-1);
    ELSE load(y); PutMOVI( RH, 1); PutR( SLLV, y.r, y.r, RH); PutR( NOR, y.r, y.r, 0); PutR( AND, zr, zr, y.r); DEC(RH);
    END ;
  END;
    PutIS(SW, zr, x.r, 0); DEC(RH, 2)
END Include;

  PROCEDURE Assert*(VAR x: Item);
    VAR cond: LONGINT;
  BEGIN loadCond(x);
    IF x.a = 0 THEN cond := negated(x.r)
    ELSE PutIS( x.r, 0, 0, x.b); FixLink(x.a); x.b := pc-1; cond := BEQ
    END ;
    Trap(cond, 0, 0, TrapAssert); FixLink(x.b)
  END Assert;

  PROCEDURE New*(VAR x, y: Item);
    VAR z: Item; xt: ORB.Type; xf: INTEGER;
  BEGIN loadAdr(x);
    IF y.type = ORB.noType THEN (*record*) loadTypTagAdr(x.type.base)
    ELSE (*array*) xt:= x.type.base.base; xf := xt.form;
      IF xf = ORB.Record THEN loadTypTagAdr(xt); PutIS(ADDIU, RH-1, RH-1, 1)  (*array of record, blktyp = 1*)
      ELSIF xf = ORB.Pointer THEN PutMOVI( RH, 2); incR  (*array of pointer, blktyp = 2*)
      ELSIF xf = ORB.Proc THEN PutMOVI( RH, 7); incR  (*array of procedure, blktyp = 3, tag = 7*)
      ELSIF xf < ORB.Pointer THEN PutMOVI( RH, 3); incR  (*array of basic type, blktyp = 3, tag = 3*)
      ELSE ORS.Mark("no valid ptr base type")
      END ;
      IF y.mode = ORB.Const THEN
        IF y.a > 0 THEN load(y) (*len*) ELSE ORS.Mark("not a valid dyn array length") END
      ELSE load(y); (*len*)
        IF check THEN Trap(BLTZ, y.r, ZR, TrapArray) END
      END ;
      z.mode := ORB.Const; z.type := ORB.intType; z.a := xt.size; load(z) (*elemsize*)
    END ;
    fixcode( -0FFH, 0FFH ); DEC(pc); PutMOV(TR, ZR);  RH := minR
  END New;

  PROCEDURE Pack*(VAR x, y: Item);
    VAR z: Item;
  BEGIN z := x; load(x); load(y);
      PutSI( SLLi, y.r, y.r, 23); PutR(ADDU, x.r, x.r, y.r); DEC(RH); Store(z, x);   
  END Pack;

  PROCEDURE Unpk*(VAR x, y: Item);
    VAR z, e0: Item;
  BEGIN  z := x; load(x); e0.mode := Reg; e0.r := RH; e0.type := ORB.intType;
      PutSI(SRAi, RH, x.r, 23); PutIS(ADDIU, RH, RH, -127); Store(y, e0); incR;
      PutSI(SLLi, RH, RH, 23); PutR(SUBU, x.r, x.r, RH); Store(z, x);  (* fuse *)
  END Unpk;

  PROCEDURE Led*(VAR x: Item);
  BEGIN (*load(x); Put1(Mov, RH, 0, -60); Put2(Str, x.r, RH, 0); DEC(RH)*)
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
      IF check THEN Trap( BLTZ, z.r, 0, TrapCopyOV) END ;
      PutIS(BEQ, z.r, 0, 8- dPC); Put4(NOP);
    END ;
      PutIS( LW, RH, x.r, 0);
    PutIS( ADDIU, x.r, x.r, 4);
    PutIS( ADDIU, y.r, y.r, 4);
      PutIS( ADDIU, z.r, z.r, -1); 
      PutIS( BNE, z.r, 0, -4- dPC);
      PutIS( SW, RH, y.r, -4); DEC(RH, 3)
  END Copy;

  PROCEDURE LDPSR*(VAR x: Item);
  BEGIN (*x.mode = Const*) ORS.Mark( notimplemented)
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
    ELSE load(y); PutMOV( x.a, y.r); DEC(RH)
    END
  END LDREG;

  (* In-line code functions *)

  PROCEDURE Abs*(VAR x: Item);
  BEGIN
    IF x.mode = ORB.Const THEN x.a := ABS(x.a)
    ELSE load(x);
        IF x.type.form = ORB.Real THEN loadf(x); PutF( ABSS, x.r, x.r, 0); 
        ELSE load(x); PutIS( BGEZ,  0, x.r, 3- dPC); Put4(NOP); PutR( SUBU, x.r, 0, x.r)
        END
    END
  END Abs;

  PROCEDURE Odd*(VAR x: Item);
  BEGIN load(x); PutIU(ANDI, RH - 1, x.r, 1); x.r := RH - 1
  END Odd;

  PROCEDURE Floor*(VAR x: Item);
  BEGIN loadf(x); PutF( FLOORWS, x.r, x.r, 0); PutF( MFC1, 0, x.r, x.r);
  END Floor;

  PROCEDURE Float*(VAR x: Item);
  BEGIN load(x); PutF( MTC1, 0, x.r, x.r); PutF( CVTSW, x.r, x.r, 0);
  END Float;

  PROCEDURE Ord*(VAR x: Item);
  BEGIN
    IF x.mode IN {ORB.Var, ORB.Par, RegI, Cond} THEN load(x);
      IF (x.type.form = ORB.Pointer) & (x.type.base.form = ORB.Array) THEN PutIS(ADDIU, x.r, x.r, 16) END
    ELSIF (x.mode = Reg) & (x.type = ORB.realType) THEN PutF( MFC1, 0, x.r, x.r);
    END
  END Ord;

  PROCEDURE Len*(VAR x: Item);
  BEGIN
    IF x.type.len >= 0 THEN
      IF x.mode = RegI THEN DEC(RH) END ;
      x.mode := ORB.Const; x.a := x.type.len
    ELSIF x.type.size > 0 THEN (*open array param*)
      PutIS(LW, RH, SP, x.a + 4 + frame); x.mode := Reg; x.r := RH; incR
    ELSE (*dynamic open array*) PutIS(LW, x.r, x.r, -16); (*len*) x.mode := Reg
    END 
  END Len;

PROCEDURE Shift*(fct: LONGINT; VAR x, y: Item);
  VAR op: LONGINT;
BEGIN load(x);
  IF y.mode = ORB.Const THEN
    IF y.a#0 THEN
      IF fct=0 THEN PutSI( SLLi, x.r, x.r, y.a MOD 20H);
      ELSIF fct=1 THEN PutSI( SRAi, x.r, x.r, y.a MOD 20H);
      ELSE  (* ROR *) PutSI( ROTRi, x.r, x.r, y.a MOD 20H);
      END;
    END;
  ELSE load(y);  (* attention, rs, rt reversed! *)
    IF fct=0 THEN PutR( SLLV, RH-2, y.r, x.r);  (* LSL *)
    ELSIF fct=1 THEN PutR( SRAV, RH-2, y.r, x.r);  (* ASR*)
    ELSE PutR( ROTRV, RH-2, y.r, x.r);  (* ROR *)
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
BEGIN load(x); PutIS(LW, x.r, x.r, 0);
    IF y.mode = ORB.Const THEN PutSI( SLLi, x.r, x.r, WordSize*8-1-y.a);
    ELSE ORS.Mark(notimplemented);
    END; 
    DEC( RH); SetCC( x, ORS.lss, x.r, 0);
END Bit;

  PROCEDURE Register*(VAR x: Item);
  BEGIN (*x.mode = Const*)
    IF x.a = 15 THEN x.a := RA
    ELSIF x.a = 14 THEN x.a := SP
    ELSIF x.a = 13 THEN x.a := TR
    ELSIF x.a < 0 THEN x.a := -x.a
    ELSE INC(x.a, minR)
    END;
    PutMOV( RH, x.a MOD 20H); x.mode := Reg; x.r := RH; incR
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
  VAR i: INTEGER;
  BEGIN pc := 0; final := -1; strx := 0; tdw := 0; RH := minR; check := v # 0;
    fixorgP := 0; fixorgD := 0; fixorgT := 0; fixorgM := 0;
    FOR i := 0 TO 5 DO PutIS( ADDI, TR, TR, 1000H) END;
    fixcode( -0FFH, 0FFH ); DEC(pc);
    PutIS( ADDI, TR, TR, 1000H)
  END Open;

  PROCEDURE SetDataSize*(dc: LONGINT);
  BEGIN varx := dc
  END SetDataSize;

  PROCEDURE Header*;
  BEGIN entry := pc * 4;
    PutIS(ADDIU, SP, SP, -4); PutIS(SW, RA, SP, 0)
  END Header;

  PROCEDURE Exit*;
  BEGIN (*exit code*)
    PutIS(LW, RA, SP, 0); PutR(JR, 0, RA, 0); PutIS(ADDIU, SP, SP, 4); 
  END Exit;

  PROCEDURE Final*;
  BEGIN final := pc*4;
    PutIS(ADDI, SP, SP, -4); PutIS(SW, RA, SP, 0)
  END Final;

  PROCEDURE NofRefs(ftyp: SET; typ: ORB.Type): LONGINT;
    VAR fld: ORB.Object; n: LONGINT;
  BEGIN
    IF typ.form IN ftyp THEN n := 1
    ELSIF typ.form = ORB.Record THEN fld := typ.dsc; n := 0;
      WHILE fld # NIL DO n := NofRefs(ftyp, fld.type) + n; fld := fld.next END
    ELSIF typ.form = ORB.Array THEN n := NofRefs(ftyp, typ.base) * typ.len
    ELSE n := 0
    END ;
    RETURN n
  END NofRefs;

  PROCEDURE FindRefs(VAR R: Files.Rider; ftyp: SET; typ: ORB.Type; off: LONGINT);
    VAR fld: ORB.Object; i, s: LONGINT;
  BEGIN
    IF typ.form IN ftyp THEN Files.WriteInt(R, off)
    ELSIF typ.form = ORB.Record THEN fld := typ.dsc;
      WHILE fld # NIL DO FindRefs(R, ftyp, fld.type, fld.val + off); fld := fld.next END
    ELSIF typ.form = ORB.Array THEN s := typ.base.size;
      FOR i := 0 TO typ.len-1 DO FindRefs(R, ftyp, typ.base, i*s + off) END
    END
  END FindRefs;

  PROCEDURE Close*(VAR modid: ORS.Ident; key, nofent: LONGINT);
    VAR obj: ORB.Object;
      i, comsize, nofimps, nofrefs, size, tdx, fix: LONGINT;
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

BEGIN relmap[0] := 1; relmap[1] := 9; relmap[2] := 5; relmap[3] := 6; relmap[4] := 14; relmap[5] := 13;
  condf[ 0] := CEQf;  condf[ 1] := -CEQf;  condf[ 2] := CLTf;  condf[ 3] := CLEf;  condf[ 4] := -CLEf;  condf[ 5] := -CLTf;
END OMG.
