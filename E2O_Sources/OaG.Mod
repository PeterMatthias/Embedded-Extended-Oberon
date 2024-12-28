MODULE OaG; (* N.Wirth, 16.4.2016 / 4.4.2017 / 31.5.2019  Oberon compiler; code generator for ARM32 / AP 1.5.24 Extended Oberon*)
  IMPORT SYSTEM, Files, ORS, ORB;
  (*Code generator for Oberon compiler for ARM32 processor.
     Procedural interface to Parser ORP; result in array "code".
     Procedure Close writes code-files*)

(*
    ARM32 version

    all changes by Peter Matthias

    2024-08-27  started, based on ORGA2.Mod dated 2018-10-20
    2024-09-15  simplyfied PutBi
    2024-10-11  using fixvar encoding from x86 version
    2024-11-17  LDREG and Register changed to map virtual registers
    2024-11-18  fixcode, fixvar: optimized encoding for 127 Module imports
    2024-11-23  Set: improved and unified 
    2024-11-26  New(): added CMP before Trap
    2024-12-12  SaveRegs/RestoreRegs: use STM/LDM
    2024-12-12  fixcode: removed NOP
    2024-12-12  Floor: moved mode setting to Host
    2024-12-14  code access via procedures Get4, Put4, Put4at
    2024-12-19  LDREG, Register: mapping RISC5 registers to RISC-V
    2024-12-28  Method, ReceiverParam: applied changes from EOS 

*)

CONST version=3X;  dPC = 2;  appendix=".arm";  (* arm32 *)  WordSize* = 4;
  TrapAdr = 4;
  minR = 0; TR = 12; SP = 13; RA = 14; PC=15;  (*dedicated registers, TR is used as temporary register*)
  TrapArray=1; TrapTypeGuard=2; TrapCopyOV=3; TrapNIL=4; TrapIllProc=5; TrapDivZero=6; TrapAssert=7;

  maxCode = 12000; maxStrx = 3500; maxTD = 160; maxSet = WordSize*8;
  Reg = 10; RegI = 11; Cond = 12;  (*internal item modes*)

  C4 = 10H; C6 = 40H; C8 = 100H; C10 = 400H; C12 = 1000H; C14 = 4000H; C15 = 8000H;  C16 = 10000H; C18 = 40000H; C19 = 80000H;
  C20 = 100000H; C22 = 400000H; C24 = 1000000H; C26 = 4000000H; C28 = 10000000H; C30 = 40000000H;

  SETFLAGS=100000H;  IMM=2000000H;
  BIC=1C00000H; ADD= 0800000H; SUB=0400000H; EOR=0200000H; ORR=1800000H; AND=0000000H; RSB=0600000H;
  UBFX= 7E00050H; SBFX=7A00050H;

  MOV = 1A00000H; MVN=1E00000H; CMP=1500000H; CMN=1700000H; TEQ=1300000H; TST=1100000H;
  MOVT=3400000H-IMM; MOVW= 03000000H-IMM;  (* >= ARMv7 only *)

  ShiftV=10H;
  LSLi=1A00000H;  ASRi=1A00040H;  RORi= 1A00060H;

(*  NOP= 0320F000H;*)

  MUL = 0000090H;  MLA = 0200090H;  MLS = 0600090H;  SDIV = 710F010H;

  B = 0A000000H; BL = 0B000000H; BX = 12FFF10H; BLX = 12FFF30H;

  EQ = 0H; NE = 1H; CC = 3H; MI = 4H; PL = 5H; HI = 8H; LS = 9H; GE = 0AH; LT = 0BH; GT = 0CH; LE = 0DH; AL = 0EH;

    (* load/store imm; *b=based*)
  LSIndex=1000000H;   LSADD=800000H;  LSWBACK=200000H;
  LDRB=4500000H+LSIndex; STRB=4400000H+LSIndex;
  LDR=4100000H+LSIndex; STR=4000000H+LSIndex;
  LDM=8100000H;  LDMIA= LDM+LSADD;  STM=8000000H;  STMIA=STM+LSADD;  STMIB = 9800000H;  STMDB=STM+LSIndex;

  VMOVA= 0E100A10H;  (* mov float to ARM register; single precision to ARM; A8.8.343  (float, ARM, 0)*)
  VMOVV=0E000A10H;  (* mov ARM register to float, single precision *)
  VCVTRL= 0EB80AC0H;  (* REAL := INTEGER *)
  VCVTLR= 0EBD0A40H (*-80H*);  (* INTEGER:= ENTIER(REAL) op should be 0 for rounding mode in FPSCR! see page A8-870*)
  VMRS= 0EF00A10H;  (* reg=1, rt=15 *)
(*  VMSR= 0EE00A10H;*)

  VLDRS=0D100A00H+LSADD;  VSTRS= 0D000A00H+LSADD;

  VNEG= 0EB10A40H;  VABS= 0EB00AC0H;  VCMP= 0EB40A40H;  VCMPZ= VCMP+10000H;
  VADD= 0E300A00H;  VSUB= 0E300A40H;  VMUL= 0E200A00H;  VDIV=0E800A00H;

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

  (*instruction assemblers according to formats*)

PROCEDURE incR;
BEGIN
  IF RH < TR-1 THEN INC(RH) ELSE ORS.Mark("register stack overflow") END
END incR;

PROCEDURE Get4( adr: INTEGER): INTEGER;
BEGIN  RETURN code[adr]
END Get4;

PROCEDURE Put4at( adr, inst: INTEGER);
BEGIN  code[adr] := inst;
END Put4at;

PROCEDURE Put4( inst: INTEGER);
BEGIN  Put4at(pc, inst); INC(pc)
END Put4;

PROCEDURE PutR(op, Rd, Rn, Rm: INTEGER);  (*emit register instruction*)
BEGIN
  Put4( LSL(AL, 28)+op+LSL(Rn, 16)+ LSL(Rd, 12)+ Rm)
END PutR;

PROCEDURE PutMul(op, Rd, Rn, Rm, Ra: INTEGER);  (*emit mul/div instruction*)
BEGIN
  Put4( LSL(AL, 28)+op+LSL(Rd, 16)+ Rn+ LSL(Rm, 8)+LSL(Ra, 12))
END PutMul;

PROCEDURE PutI(op, Rd, Rn, imm: INTEGER);  (*emit imm instruction, im is already encoded *)
BEGIN
  IF imm < 0 THEN ORS.Mark("PutI") END;
  Put4( LSL(AL, 28)+op+ IMM+LSL(Rn, 16)+ LSL(Rd, 12)+ imm)
END PutI;

PROCEDURE PutLS(op, Rt, Rn, off: INTEGER);  (*emit load/store instruction*)
BEGIN
  IF off < 0 THEN off:= -off;
  ELSE
    INC(op, LSADD);
    IF off >= 100000H THEN ORS.Mark("PutLS off too big") END;
    IF off >= 1000H THEN PutI( ADD+0A00H, RH, Rn, off DIV 1000H); off:=off MOD 1000H; Rn:=RH END;
  END;
  Put4( LSL(AL, 28)+op+ LSL(Rn, 16)+ LSL( Rt, 12)+ off )
END PutLS;

PROCEDURE PutVLS(op, Vd, Rn, off: INTEGER);  (*emit V load/store instruction*)
BEGIN
  IF off < 0 THEN ORS.Mark("PutVLS neg offset");
  ELSIF off >= 400H THEN
    IF off>= 40000H THEN ORS.Mark("PutVLS off too big");
    ELSE PutI( ADD+0A00H, RH, Rn, off DIV 400H); off := off MOD 400H; Rn := RH
    END;
  END;
  Put4( LSL( AL, 28) + op + LSL( Rn, 16) + LSL( Vd, 12) + off DIV 4)
END PutVLS;

PROCEDURE PutLSM(op, base: INTEGER;  list: SET);
BEGIN (*emit load/store multiple instruction*)
  Put4( LSL(AL, 28)+op+ LSL(base, 16)+ ORD( list))
END PutLSM;

PROCEDURE PutB(op, cond, off: INTEGER);
BEGIN (*emit branch instruction*)
  Put4( op+ cond * 10000000H + (off MOD 1000000H))
END PutB;

PROCEDURE DecomposeConst(const : INTEGER; VAR imm: INTEGER) : BOOLEAN;
(* Tries to decompose a constant into a 8bit unsigned immediate and a rotation, so that imm>>(2*rot)=const *)
(* returns TRUE if such a combination of (imm,rot) exists *)
VAR rot: INTEGER; ret: BOOLEAN;
BEGIN
  imm:=const; rot:=0;
  WHILE (rot<15) & ((imm<0) OR (imm>255)) DO imm:=ROR(imm,30); INC(rot) END;
  ret:=(imm>=0) & (imm<=255);
  imm:=imm+rot*100H;
  RETURN ret
END DecomposeConst;

PROCEDURE PutMOVI( r, im: INTEGER);
VAR c: INTEGER;
BEGIN
  IF DecomposeConst( im, c) THEN PutI( MOV, r, 0, c);
  ELSIF DecomposeConst( -1-im, c) THEN PutI( MVN, r, 0, c);
  ELSE
    PutI(MOVW, r, im DIV 1000H MOD 10H, im MOD 1000H);
    im:= im DIV 10000H;
      IF im # 0 THEN PutI( MOVT, r, im DIV 1000H MOD 10H, im MOD 1000H) END;
  END;
END PutMOVI;

PROCEDURE PutI32(op, Rd, Rn, im: INTEGER);
VAR c: INTEGER;
BEGIN (*same as PutI, but using up to 32 bit; b must not be RH *)
  IF DecomposeConst( im, c) THEN PutI(op, Rd, Rn, c);
  ELSE PutMOVI( TR, im);  (* don't use RH while adjusting SP *)
    PutR(op, Rd, Rn, TR)
  END
END PutI32;

PROCEDURE fixcode( mno, pno: INTEGER);
(* fixorgP format: (mno 8bit, pno 8bit, mno > 0 1 bit, displacement 15bit) *)
BEGIN
  IF pc - fixorgP >= 2000H THEN ORS.Mark("fixcode displacement")
  ELSIF mno < - 0FFH THEN ORS.Mark("fixcode mno")
  ELSIF (mno # 0) & (pno > 0FFH) THEN ORS.Mark("fixcode pno >= 255")
  ELSE
    Put4(  - mno * C24 + pno * C16 + ORD(mno # 0) * C15 + (pc - fixorgP) * 2); fixorgP := pc - 1;
  END;
END fixcode;

PROCEDURE fixvar( mno, vno: INTEGER);
(* fixorgD (mno 7bit, vno 8bit, mno > 0 1 bit, displacement 15bit) check FixLinkPair, static and dynamic linker and disassembler*)
BEGIN
  IF (pc - fixorgD >=  4000H) THEN ORS.Mark("fixvar displacement")
  ELSIF mno < -0FFH THEN ORS.Mark("fixvar mno")
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

PROCEDURE SetCC(VAR x: Item; n: INTEGER);
BEGIN x.mode := Cond; x.a := 0; x.b := 0; x.r := n
END SetCC;

PROCEDURE negated(cond: INTEGER): INTEGER;
BEGIN
  cond:= cond +  1 - (cond MOD 2) * 2  (* SYSTEM.VAL(SET, cond )/ {0} *)
  RETURN cond
END negated;

PROCEDURE Trap(cond, num: INTEGER);
VAR i: INTEGER;
BEGIN
  i:= ORS.Pos();
  PutI(MOVW, TR, i DIV 1000H MOD 10H, i MOD 1000H);
  PutB( B, cond, 7 - dPC - pc - num );
END Trap;

PROCEDURE NilCheck( r: INTEGER);
BEGIN IF check THEN PutI( CMP, 0, r, 0); Trap(EQ, TrapNIL) END
END NilCheck;

  (*handling of forward reference, fixups of instruction operands*)

PROCEDURE fixI(at, with: INTEGER);
BEGIN (*fix register immediate instruction*)
  IF (with < 0) OR (with > 255) THEN ORS.Mark("p.m.: fixI out of bounds") END ;
  Put4at(at, Get4(at) DIV C8 * C8 + with MOD C8)
END fixI;

PROCEDURE fixB(at, with: INTEGER);
BEGIN (*fix branch instruction*)
  Put4at(at, Get4(at) DIV C24 * C24 + (with- dPC)  MOD C24)
END fixB;

PROCEDURE FixOne*(at: INTEGER);
BEGIN fixB(at, pc - at)
END FixOne;

PROCEDURE FixLinkWith(L, dst: INTEGER);
VAR L1: INTEGER;
BEGIN (*fix chain of branch instructions*)
  WHILE L # 0 DO L1 := Get4(L) MOD C24; fixB(L, dst-L); L := L1 END
END FixLinkWith;

PROCEDURE FixLink*(L: INTEGER);
BEGIN FixLinkWith(L, pc)
END FixLink;

PROCEDURE FixLinkPair(L, adr: INTEGER);
VAR q: INTEGER;
BEGIN (* fix chain of instruction , 0 <= adr < C16 *)
  IF adr >= 10000H THEN ORS.Mark("p.m. FixLinkPair") END;
  WHILE L # 0 DO q := Get4(L);
    Put4at(L,  adr * C16 + q MOD C16);
    L := q DIV C16 MOD C16;
  END
END FixLinkPair;

PROCEDURE merged(L0, L1: INTEGER): INTEGER;
VAR L2, L3: INTEGER;
BEGIN (*merge chains of the two operands of AND and OR*)
  IF L0 # 0 THEN L3 := L0;
    REPEAT L2 := L3; L3 := Get4(L2) MOD C16 UNTIL L3 = 0;
    Put4at(L2, Get4(L2) + L1); L1 := L0
  END ;
  RETURN L1
END merged;

  (* loading of operands and addresses into registers *)

PROCEDURE load(VAR x: Item);
VAR op, c: INTEGER;
BEGIN
  IF (x.type= ORB.realType) THEN 
    IF (x.mode = Reg) THEN PutR( VMOVA, x.r, x.r, 0)  END;
  END;
  IF x.mode # Reg THEN
    IF x.type.size = 1 THEN op := LDRB ELSE op := LDR END ;
    IF x.mode = ORB.Const THEN
      IF x.type.form = ORB.Proc THEN
        IF x.r > 0 THEN (*local*) ORS.Mark("not allowed")
        ELSIF x.r = 0 THEN (*global*)
          c := pc - x.a DIV 4 + dPC;  (* c in words ORS.Mark("p.m. check dPC");*)
          IF c >= 100H THEN PutI( SUB+0B00H, RH, PC, c DIV 100H); PutI( SUB+0F00H, RH, RH, c MOD 100H);
          ELSE PutI( SUB, RH, PC, 0F00H+c );
          END;
        ELSE (*imported*) fixvar( x.r+ 80H, x.a); PutI( MOVT, RH, 0, 0); (*mark as progbase-relative*)
        END
      ELSE PutMOVI( RH, x.a)
      END ;
      x.r := RH; incR
    ELSIF x.mode = ORB.Var THEN
      IF x.r > 0 THEN (*local*) PutLS(op, RH, SP, x.a + frame)
      ELSE fixvar( x.r, x.a); PutI( MOVT, RH, 0, 0); PutLS(op, RH, RH, 0)
      END ;
      x.r := RH; incR
    ELSIF x.mode = ORB.Par THEN PutLS(LDR, RH, SP, x.a + frame); PutLS(op, RH, RH, x.b); x.r := RH; incR
    ELSIF x.mode = RegI THEN PutLS(op, x.r, x.r, x.a)
    ELSIF x.mode = Cond THEN
      PutB(B, negated(x.r), 3- dPC);
      FixLink(x.b); PutI(MOV, RH, 0, 1); PutB(B, AL, 2-dPC);
      FixLink(x.a); PutI(MOV, RH, 0, 0); x.r := RH; incR
    END ;
    x.mode := Reg
  END
END load;

PROCEDURE loadf(VAR x: Item);
CONST op= VLDRS;
BEGIN
  IF (x.type# ORB.realType) THEN ORS.Mark("loadf 0") END;
  IF x.mode # Reg THEN
    IF x.mode = ORB.Const THEN
      IF x.type.form = ORB.Proc THEN ORS.Mark("loadf 1");
      ELSE PutMOVI( RH, x.a); PutR( VMOVV, RH, RH, 0);
      END;
      x.r := RH; incR
    ELSIF x.mode = ORB.Var THEN
      IF x.r > 0 THEN (*local*) PutVLS(op, RH, SP, x.a + frame)
      ELSE fixvar( x.r, x.a); PutI( MOVT, RH, 0, 0); PutVLS(op, RH, RH, 0);
      END ;
      x.r := RH; incR
    ELSIF x.mode = ORB.Par THEN PutLS(LDR, RH, SP, x.a + frame); PutVLS(op, RH, RH, x.b); x.r := RH; incR
    ELSIF x.mode = RegI THEN PutVLS(op, x.r, x.r, x.a) 
    ELSIF x.mode = Cond THEN ORS.Mark("loadf 2");
    END ;
  x.mode := Reg;
  END;
END loadf;

PROCEDURE loadAdr(VAR x: Item);
BEGIN
  IF x.mode = ORB.Var THEN
    IF x.r > 0 THEN (*local*) PutI32(ADD, RH, SP, x.a + frame)
    ELSE fixvar( x.r, x.a); PutI( MOVT, RH, 0, 0);  
    END ;
    x.r := RH; incR
  ELSIF x.mode = ORB.Par THEN PutLS(LDR, RH, SP, x.a + frame);
    IF x.b # 0 THEN PutI32(ADD, RH, RH, x.b) END ;
    x.r := RH; incR
  ELSIF x.mode = RegI THEN
    IF x.a # 0 THEN PutI32(ADD, x.r, x.r, x.a) END
  ELSE ORS.Mark("address error")
  END ;
  x.mode := Reg
END loadAdr;

PROCEDURE loadCond(VAR x: Item);
BEGIN
  IF x.mode # Cond THEN
    IF x.type.form = ORB.Bool THEN
      IF x.mode = ORB.Const THEN x.r := 15- x.a  (* x.a can be 0 or 1 *)
      ELSE load(x);
        PutI(CMP, 0, x.r, 0); (* can be improved *)
        x.r := NE; DEC(RH)
      END ;
      x.mode := Cond; x.a := 0; x.b := 0
    ELSE ORS.Mark("not Boolean?")
    END
  END
END loadCond;

PROCEDURE loadTypTagAdr(T: ORB.Type);
BEGIN
  IF T.mno <= 0 THEN  fixvar( 0, T.len); T.len := pc - 1  (*insert into fixorgD chain, fixed up in Close*)
  ELSE (*imported*) fixvar( -T.mno, T.len);
  END ;
  PutI( MOVT, RH, 0, 0);
  incR
END loadTypTagAdr;

PROCEDURE loadStringAdr(VAR x: Item);
BEGIN
  IF x.r >= 0 THEN fixvar( 0, varx + x.a);  
  ELSE (*imported*) fixvar( x.r, x.a);  
  END ;
  PutI( MOVT, RH, 0, 0);
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
      IF lim >= 0 THEN PutI32(CMP, 0, y.r, lim)
      ELSIF x.mode IN {ORB.Var, ORB.Par} THEN (*open array param*) PutLS(LDR, RH, SP, x.a+4+frame); PutR(CMP, 0, y.r, RH)
      ELSIF x.mode = RegI THEN (*dynamic open array*) PutLS(LDR, RH, x.r, -16); (*len*) PutR(CMP, 0, y.r, RH)
      ELSE ORS.Mark("error in Index")
      END ;
      Trap(GE, 1)
    END ;
    IF s = 4 THEN PutR( LSLi, y.r, 0, y.r+ LSL( 2, 7)) ELSIF s > 1 THEN PutMOVI( RH, s); PutMul(MUL, y.r, y.r, RH, 0) END ;
    IF x.mode = ORB.Var THEN
      IF x.r > 0 THEN (*local*) PutR(ADD, y.r, SP, y.r); INC(x.a, frame)
      ELSIF x.r = 0 THEN (*global*) fixvar( 0, 0); PutI( MOVT, RH, 0, 0); PutR(ADD, y.r, y.r, RH)
      ELSE (*imported*) fixvar( x.r, x.a); PutI( MOVT, RH, 0, 0); PutR(ADD, y.r, y.r, RH);
        x.a := 0
      END ;
      x.r := y.r; x.mode := RegI
    ELSIF x.mode = ORB.Par THEN
      PutLS(LDR, RH, SP, x.a + frame);
      PutR(ADD, y.r, RH, y.r); x.mode := RegI; x.r := y.r; x.a := x.b
    ELSIF x.mode = RegI THEN PutR(ADD, x.r, x.r, y.r); DEC(RH)
    END
  END
END Index;

PROCEDURE DeRef*(VAR x: Item);
BEGIN
  IF x.mode = ORB.Var THEN
    IF x.r > 0 THEN (*local*) PutLS(LDR, RH, SP, x.a + frame)
    ELSE fixvar( x.r, x.a); PutI( MOVT, RH, 0, 0); PutLS(LDR, RH, RH, 0)
    END ;
    NilCheck( RH); x.r := RH; incR
  ELSIF x.mode = ORB.Par THEN
    PutLS(LDR, RH, SP, x.a + frame); PutLS(LDR, RH, RH, x.b); NilCheck(RH); x.r := RH; incR
  ELSIF x.mode = RegI THEN PutLS(LDR, x.r, x.r, x.a); NilCheck(x.r)
  ELSIF x.mode # Reg THEN ORS.Mark("bad mode in DeRef")
  END ;
  IF x.type.base.form = ORB.Array THEN PutI(ADD, x.r, x.r, 16) END ; (*pointer to array*)
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
    Q(T.base, tdw); td[tdw] := (T.mno*1000H + T.len (*TDoff/exno*)) * 1000H + tdw - fixorgT;
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
        td[tdw-fld.lev-1] := (t.mno*C16 + fld.val (*mthadr/exno*)) * 400H
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
    SetCC(x, AL)
  ELSE (*fetch tag into RH*)
    IF varpar THEN PutLS(LDR, RH, SP, x.a+4+frame)
    ELSE load(x); PutI(CMP, 0, x.r, 0);
      pc0 := pc; PutB(B, EQ, 0);  (*NIL belongs to every pointer type*)
      PutLS(LDR, RH, x.r, -8)
    END ;
    PutLS(LDR, RH, RH, T.nofpar*4); incR;
    loadTypTagAdr(T);  (*tag of T*)
    PutR(CMP, 0, RH-1, RH-2); DEC(RH, 2);
    IF ~varpar THEN fixB(pc0, pc - pc0 ) END ;
    IF isguard THEN
      IF check THEN Trap(NE, 2) END
    ELSE SetCC(x, EQ);
      IF ~varpar THEN DEC(RH) END
    END
  END
END TypeTest;

  (* Code generation for Boolean operators *)

PROCEDURE Not*(VAR x: Item);   (* x := ~x *)
VAR t: INTEGER;
BEGIN loadCond(x); x.r := negated(x.r); t := x.a; x.a := x.b; x.b := t
END Not;

PROCEDURE And1*(VAR x: Item);   (* x := x & *)
BEGIN loadCond(x); PutB(B, negated(x.r), x.a); x.a := pc-1; FixLink(x.b); x.b := 0
END And1;

PROCEDURE And2*(VAR x, y: Item);
BEGIN loadCond(y); x.a := merged(y.a, x.a); x.b := y.b; x.r := y.r
END And2;

PROCEDURE Or1*(VAR x: Item);   (* x := x OR *)
BEGIN loadCond(x); PutB(B, x.r, x.b);  x.b := pc-1; FixLink(x.a); x.a := 0
END Or1;

PROCEDURE Or2*(VAR x, y: Item);
BEGIN loadCond(y); x.a := y.a; x.b := merged(y.b, x.b); x.r := y.r
END Or2;

  (* Code generation for arithmetic operators *)

PROCEDURE Neg*(VAR x: Item);   (* x := -x *)
BEGIN
  IF x.type.form = ORB.Int THEN
    IF x.mode = ORB.Const THEN x.a := -x.a
    ELSE load(x); PutI( RSB, x.r, x.r, 0);
    END
  ELSIF x.type.form = ORB.Real THEN
    IF x.mode = ORB.Const THEN x.a := x.a + 7FFFFFFFH + 1
    ELSE loadf(x); PutR( VNEG, x.r, 0, x.r);
    END
  ELSE (*form = Set*)
    IF x.mode = ORB.Const THEN x.a := -x.a-1 
    ELSE load(x); PutR( MVN, x.r, 0, x.r)
    END
  END
END Neg;

PROCEDURE AddOp*(op: INTEGER; VAR x, y: Item);   (* x := x +- y *)
BEGIN
  IF op = ORS.plus THEN
    IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a + y.a
    ELSIF y.mode = ORB.Const THEN load(x);
      IF y.a # 0 THEN PutI32(ADD, x.r, x.r, y.a) END
    ELSE load(x); load(y); PutR(ADD, RH-2, x.r, y.r); DEC(RH); x.r := RH-1
    END
  ELSE (*op = ORS.minus*)
    IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a - y.a
    ELSIF y.mode = ORB.Const THEN load(x);
      IF y.a # 0 THEN PutI32(SUB, x.r, x.r, y.a) END
    ELSE load(x); load(y); PutR(SUB, RH-2, x.r, y.r); DEC(RH); x.r := RH-1
    END
  END
END AddOp;

PROCEDURE log2(m: LONGINT; VAR e: INTEGER): INTEGER;
BEGIN e := 0;
  WHILE ~ODD(m) DO m := m DIV 2; INC(e) END ;
  RETURN m
END log2;

PROCEDURE MulOp*(VAR x, y: Item);   (* x := x * y *)
VAR e: INTEGER;
BEGIN
  IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a * y.a
  ELSIF (y.mode = ORB.Const) & (y.a >= 1) & (log2(y.a, e) = 1) THEN load(x);
    IF e # 0 THEN PutR( LSLi, x.r, 0, x.r+ LSL( e, 7)) END;
  ELSIF (x.mode = ORB.Const) & (x.a >= 1) & (log2(x.a, e) = 1) THEN load(y);
    IF e # 0 THEN PutR( LSLi, y.r, 0, y.r+ LSL( e, 7)) END; x.mode := Reg; x.r := y.r
  ELSE
    IF (x.mode = ORB.Const) & (x.a =0) THEN 
    ELSIF (y.mode = ORB.Const) & (y.a =0) THEN x.mode := ORB.Const; x.a :=0;
    ELSE load(x); load(y); PutMul(MUL, RH-2, x.r, y.r, 0); DEC(RH); x.r := RH-1;
    END;
  END
END MulOp;

PROCEDURE DivOp*(op: INTEGER; VAR x, y: Item);   (* x := x op y *)
VAR e: INTEGER; yc: BOOLEAN;
BEGIN
  yc:=y.mode=ORB.Const;
  IF op = ORS.div THEN
    IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
      IF y.a > 0 THEN x.a := x.a DIV y.a ELSE ORS.Mark("bad divisor") END
    ELSIF yc & (y.a >= 1) & (log2(y.a, e) = 1) THEN load(x);
      IF e # 0 THEN PutR(ASRi+LSL( e, 7), x.r, 0, x.r);
(*      IF code[ pc-1] - code[ pc-2] = ASRi-LSLi THEN DEC(pc, 2); PutR( SBFX, x.r, 32-1-e, x.r) END; (* fuse *)*)
      END;
    ELSE
      IF yc & (y.a <= 0) THEN ORS.Mark("bad divisor");
      ELSE
        load(x); load(y);
        PutR( SUB+LSL(31, 7)+64, RH, x.r, y.r);  (* adjust for Oberon definition *)
        PutMul( SDIV, RH, RH, y.r, 0);
        IF ~yc & check THEN PutI( CMP, 0, y.r, 0); Trap(LE, TrapDivZero) END;
        PutR( ADD+LSL(31, 7)+64, RH-2, RH, x.r);  (* adjust *)
        DEC(RH); x.r := RH-1;
      END;
    END
  ELSE (*op = ORS.mod*)
    IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
      IF y.a > 0 THEN x.a := x.a MOD y.a ELSE ORS.Mark("bad modulus") END
    ELSIF yc & (y.a >= 1) & (log2(y.a, e) = 1) THEN load(x);
      IF e = 0 THEN x.mode:=ORB.Const; x.a:=0; 
      ELSE PutR( UBFX, x.r, e-1, x.r);
      END;
    ELSE
      IF yc & (y.a <= 0) THEN ORS.Mark("bad modulus");
      ELSE
        load(x); load(y);
        PutR( SUB+LSL(31, 7) + 64, RH, x.r, y.r);    (* sign bit *)
        PutMul( SDIV, RH, RH, y.r, 0);
        IF ~yc & check THEN PutI( CMP, 0, y.r, 0); Trap(LE, TrapDivZero) END;
        PutR( ADD+LSL(31, 7)+64, RH, RH, x.r);    (* sign bit *)
        PutMul( MLS, RH-2, RH, y.r, x.r);
        DEC(RH); x.r := RH-1;
      END;
    END
  END
END DivOp;

  (* Code generation for REAL operators *)

PROCEDURE RealOp*(op: INTEGER; VAR x, y: Item);   (* x := x op y *)
BEGIN loadf(x); loadf(y);
  IF op = ORS.plus THEN PutR( VADD, RH-2, x.r, y.r)
  ELSIF op = ORS.minus THEN PutR( VSUB, RH-2, x.r, y.r)
  ELSIF op = ORS.times THEN PutR( VMUL, RH-2, x.r, y.r)
  ELSIF op = ORS.rdiv THEN PutR( VDIV, RH-2, x.r, y.r)
  END;
  DEC(RH); x.r := RH-1
END RealOp;

  (* Code generation for set operators *)

PROCEDURE Singleton*(VAR x: Item);  (* x := {x} *)
BEGIN
  IF x.mode = ORB.Const THEN x.a := LSL(1, x.a)
  ELSE load(x); PutI(MOV, RH, 0, 1); PutR(LSLi+ShiftV, x.r, 0, RH+ LSL( x.r, 8))
  END
END Singleton;

PROCEDURE Set*(VAR x, y: Item);   (* x := {x .. y} *)
BEGIN
  IF (x.mode = ORB.Const) & ( y.mode = ORB.Const) THEN
    IF x.a <= y.a THEN x.a := LSL(2, y.a) - LSL(1, x.a) ELSE x.a := 0 END
  ELSE
    IF (x.mode = ORB.Const) THEN  x.a := LSL(1, x.a)
    ELSE load(x); PutI(MOV, RH, 0, 1); PutR(LSLi+ShiftV, x.r, 0, RH+ LSL( x.r, 8)); x.r := RH - 1;
    END;
    IF (y.mode = ORB.Const) THEN PutI( MOV, RH, 0, LSL(2, x.a)); y.mode := Reg; y.r := RH; incR
    ELSE load(y); PutI( MOV, RH, 0, 2); PutR(LSLi+ShiftV, y.r, 0, RH+ LSL( y.r, 8))
    END;
    IF (x.mode = ORB.Const) THEN PutI32( ADD, RH - 1, y.r, -x.a); x.mode := Reg
    ELSE DEC(RH); PutR( SUB, RH-1, y.r, x.r);    (* don't use x.r as target. y can be loaded before x *)
    END;
    x.r := RH-1; 
  END
END Set;

PROCEDURE In*(VAR x, y: Item);  (* x := x IN y *)
BEGIN load(y);
  IF x.mode = ORB.Const THEN PutI( RORi-IMM+SETFLAGS, y.r, 0, y.r+ LSL( (x.a + 1) MOD maxSet, 7)); DEC(RH)
  ELSE load(x); PutI(ADD, x.r, x.r, 1); PutR(RORi+ShiftV+SETFLAGS, y.r, 0, y.r+LSL( x.r, 8)); DEC(RH, 2)
  END ;
  SetCC(x, MI)
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
    x.a := SYSTEM.VAL(LONGINT, xset)
  ELSIF y.mode = ORB.Const THEN
    load(x);
    IF op = ORS.plus THEN PutI32(ORR, x.r, x.r, y.a)
    ELSIF op = ORS.minus THEN PutI32(BIC, x.r, x.r, y.a)
    ELSIF op = ORS.times THEN PutI32(AND, x.r, x.r, y.a)
    ELSIF op = ORS.rdiv THEN PutI32(EOR, x.r, x.r, y.a)
    END ;
  ELSE load(x); load(y);
    IF op = ORS.plus THEN PutR(ORR, RH-2, x.r, y.r)
    ELSIF op = ORS.minus THEN PutR(BIC, RH-2, x.r, y.r)
    ELSIF op = ORS.times THEN PutR(AND, RH-2, x.r, y.r)
    ELSIF op = ORS.rdiv THEN PutR(EOR, RH-2, x.r, y.r)
    END ;
    DEC(RH); x.r := RH-1
  END 
END SetOp;

  (* Code generation for relations *)

  PROCEDURE IntRelation*(op: INTEGER; VAR x, y: Item);   (* x := x < y *)
  VAR op2: INTEGER;
  BEGIN
    IF (y.mode = ORB.Const) & (y.type.form # ORB.Proc) & (y.a >= 0) THEN
      IF y.a < 0 THEN op2:=CMN; y.a:= -y.a ELSE op2 := CMP END;
        load(x); PutI32( op2, 0, x.r, y.a); DEC(RH);    
    ELSE
      IF (x.mode = Cond) OR (y.mode = Cond) THEN ORS.Mark("not implemented") END ;
      load(x); load(y); PutR(CMP, 0, x.r, y.r); DEC(RH, 2)
    END ;
    SetCC(x, relmap[op - ORS.eql])
  END IntRelation;

  PROCEDURE RealRelation*(op: INTEGER; VAR x, y: Item);   (* x := x < y *)
  BEGIN loadf(x);
    IF (y.mode = ORB.Const) & (y.a = 0) THEN PutR( VCMPZ, x.r, 0, 0); PutR( VMRS, 15, 1, 0); DEC(RH)
    ELSE loadf(y); PutR( VCMP, x.r, 0, y.r); PutR( VMRS, 15, 1, 0); DEC(RH, 2)
    END ;
    SetCC(x, relmap[op - ORS.eql])
  END RealRelation;

  PROCEDURE StringRelation*(op: INTEGER; VAR x, y: Item);   (* x := x < y *)
    (*x, y are char arrays or strings*)
  BEGIN
    IF x.type.form = ORB.String THEN loadStringAdr(x) ELSE loadAdr(x) END ;
    IF y.type.form = ORB.String THEN loadStringAdr(y) ELSE loadAdr(y) END ;
      PutLS(LDRB-LSIndex, RH, x.r, 1); incR;
      PutLS(LDRB-LSIndex, RH, y.r, 1); incR;
    PutR(CMP, 0, RH -2, RH-1); PutB(B, NE, 3- dPC);
      PutI(CMP, 0, RH-2, 0); PutB(B, NE, -5- dPC);
    DEC(RH, 4); SetCC(x, relmap[op - ORS.eql])
  END StringRelation;

  (* Code generation of Assignments *)

  PROCEDURE StrToChar*(VAR x: Item);
  BEGIN x.type := ORB.charType; DEC(strx, 4); x.a := ORD(str[x.a])
  END StrToChar;

  PROCEDURE Store*(VAR x, y: Item); (* x := y *)
    VAR op: LONGINT;
  BEGIN  load(y);
    IF x.type.size = 1 THEN op := STRB ELSE op := STR END ;
    IF x.mode = ORB.Var THEN
      IF x.r > 0 THEN (*local*) PutLS(op, y.r, SP, x.a + frame)
      ELSE fixvar( x.r, x.a); PutI( MOVT, RH, 0, 0); PutLS(op, y.r, RH, 0)
      END
    ELSIF x.mode = ORB.Par THEN PutLS(LDR, RH, SP, x.a + frame); PutLS(op, y.r, RH, x.b);
    ELSIF x.mode = RegI THEN PutLS(op, y.r, x.r, x.a); DEC(RH);
    ELSE ORS.Mark("bad mode in Store")
    END ;
    DEC(RH)
  END Store;

PROCEDURE Storef(VAR x, y: Item); (* x := y *)
CONST op = VSTRS;
BEGIN
  loadf(y);
  IF x.type# ORB.realType THEN ORS.Mark("Storef 0") END;
  IF x.mode = ORB.Var THEN
    IF x.r > 0 THEN (*local*) PutVLS(op, y.r, SP, x.a + frame)
    ELSE fixvar( x.r, x.a); PutI( MOVT, RH, 0, 0); PutVLS(op, y.r, RH, 0);
    END
  ELSIF x.mode = ORB.Par THEN PutLS(LDR, RH, SP, x.a + frame); PutVLS(op, y.r, RH, x.b);
  ELSIF x.mode = RegI THEN PutVLS(op, y.r, x.r, x.a); DEC(RH);
  ELSE ORS.Mark("bad mode in Storef")
  END ;
  DEC(RH);
END Storef;

  PROCEDURE StoreStruct*(VAR x, y: Item); (* x := y, frame = 0 *)
    VAR s, pc0: LONGINT;
  BEGIN loadAdr(x); loadAdr(y);
    IF (x.type.form = ORB.Array) & (x.type.len > 0) THEN
      IF y.type.len >= 0 THEN
        IF x.type.size = y.type.size THEN PutMOVI(RH, (y.type.size+3) DIV 4)
        ELSE ORS.Mark("different length/size, not implemented")
        END
      ELSE (*y open array param or dynamic open array*)
        IF y.type.size > 0 THEN PutLS(LDR, RH, SP, y.a+4) ELSE PutLS(LDR, RH, y.r, -16) END ; (*len*)
        s := y.type.base.size;  (*element size*)
        PutI( CMP, 0, RH, 0); pc0 := pc; PutB(B, EQ, 0);
        IF s = 1 THEN PutI(ADD, RH, RH, 3); PutR( ASRi, RH, 0, RH+ LSL( 2, 7));
        ELSIF s # 4 THEN PutMOVI( RH+1, s ); PutMul( MUL, RH, RH, RH+1, 0); 
        END ;
        IF check THEN (*check array lengths*) incR;
          PutMOVI( RH, (x.type.size+3) DIV 4); PutR(CMP, 0, RH-1, RH); Trap(GT, TrapCopyOV); DEC(RH)
        END ;
        fixB(pc0, pc + 4 - pc0) (* p.m. check o.k.*)
      END
    ELSIF x.type.form = ORB.Record THEN PutMOVI( RH, x.type.size DIV 4)
    ELSE ORS.Mark("inadmissible assignment")
    END ;
    incR;
    PutLS(LDR-LSIndex, RH, y.r, 4);
    PutI(SUB+SETFLAGS, RH-1, RH-1, 1);
    PutLS(STR-LSIndex, RH, x.r, 4);
    PutB(B, GT, -3- dPC);
    RH := 0
  END StoreStruct;

  PROCEDURE CopyString*(VAR x, y: Item);  (* x := y, frame = 0 *) 
     VAR len: LONGINT;
   BEGIN loadAdr(x); len := x.type.len;
    IF len >= 0 THEN
      IF len <  y.b THEN ORS.Mark("string too long") END
    ELSIF check THEN (*x open array param or dynamic open array*)
      IF x.type.size > 0 THEN PutLS(LDR, RH, SP, x.a+4) ELSE PutLS(LDR, RH, x.r, -16) END ; (*len*)
      PutI32(CMP, 0, RH, y.b); Trap(LT, TrapCopyOV)
    END ;
    loadStringAdr(y);
      PutLS( LDR-LSIndex, RH, y.r, 4);
      PutLS( STR-LSIndex, RH, x.r, 4);
    PutR( ASRi+SETFLAGS+LSL( 24, 7), RH, 0, RH); PutB(B, NE,  -3- dPC);  RH := 0
  END CopyString;

  (* Code generation for parameters *)

  PROCEDURE OpenArrayParam*(VAR x: Item);
  BEGIN loadAdr(x);
    IF x.type.len >= 0 THEN PutMOVI(RH, x.type.len)
    ELSIF x.type.size > 0 THEN (*open array param*) PutLS(LDR, RH, SP, x.a+4+frame)
    ELSE (*dynamic open array*) PutLS(LDR, RH, x.r, -16) (*len*)
    END ;
    incR
  END OpenArrayParam;

  PROCEDURE VarParam*(VAR x: Item; ftype: ORB.Type);
    VAR xmd: INTEGER;
  BEGIN xmd := x.mode; loadAdr(x);
    IF (ftype.form = ORB.Array) & (ftype.len < 0) THEN (*open array*)
      IF x.type.len >= 0 THEN PutMOVI( RH, x.type.len)
      ELSIF x.type.size > 0 THEN (*open array param*) PutLS(LDR, RH, SP, x.a+4+frame)
      ELSE (*dynamic open array*) PutLS(LDR, RH, x.r, -16) (*len*)
      END ;
      incR
    ELSIF ftype.form = ORB.Record THEN
      IF x.deref THEN PutLS(LDR, RH, x.r, -8); incR
      ELSIF xmd = ORB.Par THEN PutLS(LDR, RH, SP, x.a+4+frame); incR
      ELSE loadTypTagAdr(x.type)
      END
    END
  END VarParam;

  PROCEDURE ValueParam*(VAR x: Item);
  BEGIN load(x)
  END ValueParam;

  PROCEDURE StringParam*(VAR x: Item);
  BEGIN loadStringAdr(x); PutMOVI( RH, x.b); incR  (*len*)
  END StringParam;

  PROCEDURE ReceiverParam*(VAR x: Item; par: ORB.Object);
  BEGIN
    IF x.r # RH THEN PutR(MOV, RH, 0, x.r) END ;  (*receiver*)
    incR;
    IF par.class = ORB.Par THEN (*record*) loadTypTagAdr(par.type)  (*type tag*)
    ELSIF ~x.deref THEN ORS.Mark("incompatible receiver");
    END;
  END ReceiverParam;

  (*For Statements*)

  PROCEDURE For0*(VAR x, y: Item);
  BEGIN load(y)
  END For0;

  PROCEDURE For1*(VAR x, y, z, w: Item; VAR L: LONGINT);
  BEGIN 
    IF z.mode = ORB.Const THEN PutI32(CMP, 0, y.r, z.a)
    ELSE load(z); PutR(CMP, 0, y.r, z.r); DEC(RH)
    END ;
    L := pc;
    IF w.a > 0 THEN PutB(B, GT, 0)
    ELSIF w.a < 0 THEN PutB(B, LT, 0)
    ELSE ORS.Mark("zero increment"); PutB(B, MI, 0)
    END ;
    Store(x, y)
  END For1;

  PROCEDURE For2*(VAR x, y, w: Item);
  BEGIN load(x); DEC(RH); IF w.a<0 THEN PutI32(SUB, x.r, x.r, -w.a) ELSE PutI32(ADD, x.r, x.r, w.a) END;
  END For2;

  (* Branches, procedure calls, procedure prolog and epilog *)

  PROCEDURE Here*(): LONGINT;
  BEGIN RETURN pc
  END Here;

  PROCEDURE FJump*(VAR L: LONGINT);
  BEGIN PutB(B, AL, L); L := pc-1
  END FJump;

  PROCEDURE CFJump*(VAR x: Item);
  BEGIN loadCond(x);
    IF x.r # AL THEN
      PutB(B, negated(x.r), x.a); FixLink(x.b); x.a := pc-1
    END;
  END CFJump;

  PROCEDURE BJump*(L: LONGINT);
  BEGIN PutB(B, AL, L-pc- dPC)
  END BJump;

  PROCEDURE CBJump*(VAR x: Item; L: LONGINT);
  BEGIN loadCond(x); PutB(B, negated(x.r), L-pc-dPC); FixLink(x.b); FixLinkWith(x.a, L)
  END CBJump;

  PROCEDURE Fixup*(VAR x: Item);
  BEGIN FixLink(x.a)
  END Fixup;

  PROCEDURE SaveRegs(r: LONGINT);  (* R[0 .. r-1]*)
  BEGIN (*r > 0*)
    INC(frame, 4*r);
    PutLSM( STMDB+ LSWBACK, SP, {0..r-1});
  END SaveRegs;

  PROCEDURE RestoreRegs(r: LONGINT); (*R[0 .. r-1]*)
  BEGIN (*r > 0*) 
    DEC(frame, 4*r);
    PutLSM( LDMIA + LSWBACK, SP, {0..r-1 });
  END RestoreRegs;

  PROCEDURE PrepCall*(VAR x: Item; VAR r: LONGINT);
  BEGIN (*x.type.form IN {ORB.Proc, ORB.TProc}*)
    IF x.type.form = ORB.TProc THEN DEC(RH) ELSIF x.mode > ORB.Par THEN load(x) END ;
    r := RH;
    IF RH > 0 THEN SaveRegs(RH); RH := 0 END
  END PrepCall;

  PROCEDURE Call*(VAR x: Item; r: LONGINT);
  BEGIN (*x.type.form IN {ORB.Proc, ORB.TProc}*)
    IF x.type.form = ORB.TProc THEN  (*type-bound procedure*)
      IF x.super THEN  (*super call*)
        IF x.b >= 0 THEN PutB(BL, AL, (x.a DIV 4)-pc-dPC)
        ELSE (*imported*) fixcode( x.b, x.a);
        END
      ELSE  (*method call*)
        IF x.b = ORB.Var THEN PutLS(LDR, RH, 0, -8) ELSE PutR(MOV, RH, 0, 1) END ;
        PutLS(LDR, RH, RH, -4-x.a*4); PutB(BLX, AL, RH)
      END
    ELSIF x.mode = ORB.Const THEN  (*regular procedure*)
      IF x.r >= 0 THEN PutB(BL, AL, (x.a DIV 4)-pc-dPC)
      ELSE (*imported*) fixcode( x.r, x.a);
      END
    ELSE  (*installed procedure*)
      IF x.mode <= ORB.Par THEN load(x); DEC(RH)
      ELSE PutLS(LDR, RH, SP, 0); PutI(ADD, SP, SP, 4); DEC(r); DEC(frame, 4)
      END ;
      IF check THEN PutI( CMP, 0, RH, 0); Trap(EQ, TrapIllProc) END ;
      PutB(BLX, AL, RH)
    END ;
    IF x.type.base.form = ORB.NoTyp THEN (*procedure*) RH := 0
    ELSE  (*function*)
      IF r > 0 THEN PutR(MOV, r, 0, 0); RestoreRegs(r) END ;
      x.mode := Reg; x.r := r; RH := r+1
    END
  END Call;

  PROCEDURE Enter*(parblksize, locblksize: LONGINT; int: BOOLEAN);
  BEGIN frame := 0;
    IF int THEN ORS.Mark("not implemented") END; (*procedure prolog*)
    IF locblksize >= 100000H THEN ORS.Mark("too many locals") END ;
    IF locblksize >= 1000H THEN PutI( SUB, SP, SP, locblksize DIV 1000H + 0A00H) END ;
    PutLS(STR + LSWBACK, RA, SP, -(locblksize MOD 1000H));
    IF parblksize > 4 THEN PutLSM( STMIB, SP, {0..(parblksize DIV 4 - 2) }) END
  END Enter;

  PROCEDURE Return*(form: INTEGER; VAR x: Item; size: LONGINT; int: BOOLEAN);
  BEGIN
    IF int THEN ORS.Mark("not implemented") END;
    IF form # ORB.NoTyp THEN
      IF x.type=ORB.realType THEN loadf(x);
      ELSE load(x) 
      END ;
    END;
    IF size <4096 THEN PutLS(LDR-LSIndex, PC, SP, size);
    ELSE PutLS(LDR, RA, SP, 0); PutI32(ADD, SP, SP, size); PutR(BX, 0, 0, RA);
    END;
    RH := minR
  END Return;

  (* Case Statements *)

  PROCEDURE CaseHead*(VAR x: Item; VAR L0: LONGINT);
  BEGIN load(x);  (*value of case expression*)
    L0 := pc; PutI(CMP, 0, x.r, 0);  (*higher bound, fixed up in CaseTail*)
    PutB(B, HI, 0);  (* unsigned higher; branch to else, fixed up in CaseTail*)
    PutI(ADD, RH, x.r, 0);  (*nof words between BL instruction at L0+4 and jump table, fixed up in CaseTail*)
    PutR(ADD, PC, PC, RH+ LSL( 2, 7));
    DEC(RH)
  END CaseHead;

  PROCEDURE CaseTail*(L0, L1: LONGINT; n: INTEGER; VAR tab: ARRAY OF LabelRange);  (*L1 = label for else*)
    VAR i, j: INTEGER;
  BEGIN
    IF n > 0 THEN fixI(L0, tab[n-1].high ) (*higher bound*) ELSIF L1 = 0 THEN ORS.Mark("empty case") END ;
    IF L1 = 0 THEN L1 := pc; Trap(AL, TrapArray) END ;  (*create else*)
    fixB(L0+1, L1-L0 - 1);  (*branch to else*)
    fixI(L0+2, pc-L0 - 3 - dPC);  (*nof words between ADD PC instruction at L0+4 and jump table*)
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
    IF upordown = 0 THEN op := ADD ELSE op := SUB END ;
    IF x.type = ORB.byteType THEN v := 400000H ELSE v := 0 END ;
    IF y.type.form = ORB.NoTyp THEN y.mode := ORB.Const; y.a := 1 END ;
    IF (x.mode = ORB.Var) & (x.r > 0) THEN
      zr := RH; PutLS(LDR+v, zr, SP, x.a); incR;
      IF y.mode = ORB.Const THEN PutI32(op, zr, zr, y.a) ELSE load(y); PutR(op, zr, zr, y.r); DEC(RH) END ;
      PutLS(STR+v, zr, SP, x.a); DEC(RH)
    ELSE loadAdr(x); zr := RH; PutLS(LDR+v, RH, x.r, 0); incR;
      IF y.mode = ORB.Const THEN PutI32(op, zr, zr, y.a) ELSE load(y); PutR(op, zr, zr, y.r); DEC(RH) END ;
      PutLS(STR+v, zr, x.r, 0); DEC(RH, 2)
    END
  END Increment;

  PROCEDURE Include*(inorex: LONGINT; VAR x, y: Item);
    VAR op, zr: LONGINT;
  BEGIN loadAdr(x); zr := RH; PutLS(LDR, RH, x.r, 0); incR;
    IF inorex = 0 THEN op := ORR ELSE op := BIC END ;
    IF y.mode = ORB.Const THEN PutI32(op, zr, zr, LSL(1, y.a))
    ELSE load(y); PutI(MOV, RH, 0, 1); PutR(LSLi+ShiftV, y.r, 0, RH+ LSL( y.r, 8)); PutR(op, zr, zr, y.r); DEC(RH)
    END ;
    PutLS(STR, zr, x.r, 0); DEC(RH, 2)
  END Include;

  PROCEDURE Assert*(VAR x: Item);
    VAR cond: LONGINT;
  BEGIN loadCond(x);
    IF x.a = 0 THEN cond := negated(x.r)
    ELSE PutB(B, x.r, x.b); FixLink(x.a); x.b := pc-1; cond := AL
    END ;
    Trap(cond, TrapAssert); FixLink(x.b)
  END Assert;

  PROCEDURE New*(VAR x, y: Item);
    VAR z: Item; xt: ORB.Type; xf: INTEGER;
  BEGIN loadAdr(x);
    IF y.type = ORB.noType THEN (*record*) loadTypTagAdr(x.type.base)
    ELSE (*array*) xt:= x.type.base.base; xf := xt.form;
      IF xf = ORB.Record THEN loadTypTagAdr(xt); PutI(ADD, RH-1, RH-1, 1)  (*array of record, blktyp = 1*)
      ELSIF xf = ORB.Pointer THEN PutI(MOV, RH, 0, 2); incR  (*array of pointer, blktyp = 2*)
      ELSIF xf = ORB.Proc THEN PutI(MOV, RH, 0, 7); incR  (*array of procedure, blktyp = 3, tag = 7*)
      ELSIF xf < ORB.Pointer THEN PutI(MOV, RH, 0, 3); incR  (*array of basic type, blktyp = 3, tag = 3*)
      ELSE ORS.Mark("no valid ptr base type")
      END ;
      IF y.mode = ORB.Const THEN
        IF y.a > 0 THEN load(y) (*len*) ELSE ORS.Mark("not a valid dyn array length") END
      ELSE load(y); (*len*)
        IF check THEN PutI( CMP, 0, y.r, 0); Trap(LE, TrapArray) END
      END ;
      z.mode := ORB.Const; z.type := ORB.intType; z.a := xt.size; load(z) (*elemsize*)
    END ;
    PutI(MOVW, TR, 0, 0); fixcode( -0FFH, 0FFH ); RH := minR
  END New;

  PROCEDURE Pack*(VAR x, y: Item);
    VAR z: Item;
  BEGIN z := x; load(x); load(y);
    PutR(LSLi, y.r, 0, y.r+ LSL( 23, 7)); PutR(ADD, x.r, x.r, y.r); DEC(RH); Store(z, x)
  END Pack;

  PROCEDURE Unpk*(VAR x, y: Item);
    VAR z, e0: Item;
  BEGIN  z := x; load(x); e0.mode := Reg; e0.r := RH; e0.type := ORB.intType;
      PutR(ASRi, RH, 0, x.r+ LSL( 23, 7)); PutI(SUB, RH, RH, 127); Store(y, e0); incR;
      PutR(LSLi, RH, 0, RH+ LSL( 23, 7)); PutR(SUB, x.r, x.r, RH); Store(z, x);  (* fuse *)
  END Unpk;

  PROCEDURE Led*(VAR x: Item);
  BEGIN (*load(x); PutI(MOV, RH, 0, -60); PutLS(STR, x.r, RH, 0); DEC(RH)*)
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
      PutI( CMP, 0, z.r, 0);
      IF check THEN Trap(LT, TrapCopyOV) END ;
      PutB(B, EQ, 5-dPC)
    END ;
      PutLS(LDR-LSIndex, RH, x.r, 4);
      PutI(SUB+SETFLAGS, z.r, z.r, 1); 
      PutLS(STR-LSIndex, RH, y.r, 4);
      PutB(B, NE, -3-dPC); DEC(RH, 3)
  END Copy;

  PROCEDURE LDPSR*(VAR x: Item);
  BEGIN (*x.mode = Const*)  ORS.Mark("LDPSR not supported")
  END LDPSR;

  PROCEDURE LDREG*(VAR x, y: Item);
  BEGIN
    IF x.a = 15 THEN x.a := RA
    ELSIF x.a = 14 THEN x.a := SP
    ELSIF x.a = 13 THEN x.a := TR
    ELSIF x.a < 0 THEN x.a := - x.a
    ELSE INC(x.a, minR)
    END;
    IF y.mode = ORB.Const THEN PutMOVI( x.a, y.a)
    ELSE load(y); PutR(MOV, x.a, 0, y.r); DEC(RH)
    END
  END LDREG;

  (* In-line code functions *)

  PROCEDURE Abs*(VAR x: Item);
  BEGIN
    IF x.mode = ORB.Const THEN x.a := ABS(x.a)
    ELSE
      IF x.type.form = ORB.Real THEN loadf(x); PutR( VABS, x.r, 0, x.r);
      ELSE load(x); PutI(CMP, 0, x.r, 0); PutI(RSB+LSL(MI-AL, 28), x.r, x.r, 0)
      END
    END
  END Abs;

  PROCEDURE Odd*(VAR x: Item);
  BEGIN load(x); PutI(AND+SETFLAGS, x.r, x.r, 1); SetCC(x, NE); DEC(RH)
  END Odd;

  PROCEDURE Floor*(VAR x: Item);
  BEGIN loadf(x);
    PutR( VCVTLR, x.r, 0, x.r);  (* ARMv7: use mode in FPSCR; ARMv8: VCVTM rounds to -inf *)
    PutR( VMOVA, x.r, x.r, 0);
  END Floor;

  PROCEDURE Float*(VAR x: Item);
  BEGIN load(x); PutR( VMOVV, x.r, x.r, 0); PutR( VCVTRL, x.r, 0, x.r);
  END Float;

  PROCEDURE Ord*(VAR x: Item);
  BEGIN
    IF x.mode IN {ORB.Var, ORB.Par, RegI, Cond} THEN load(x);
      IF (x.type.form = ORB.Pointer) & (x.type.base.form = ORB.Array) THEN PutI(ADD, x.r, x.r, 16) END
    ELSIF (x.mode = Reg) & (x.type = ORB.realType) THEN PutR( VMOVA, x.r, x.r, 0);
    END
  END Ord;

  PROCEDURE Len*(VAR x: Item);
  BEGIN
    IF x.type.len >= 0 THEN
      IF x.mode = RegI THEN DEC(RH) END ;
      x.mode := ORB.Const; x.a := x.type.len
    ELSIF x.type.size > 0 THEN (*open array param*)
      PutLS(LDR, RH, SP, x.a + 4 + frame); x.mode := Reg; x.r := RH; incR
    ELSE (*dynamic open array*) PutLS(LDR, x.r, x.r, -16); (*len*) x.mode := Reg
    END 
  END Len;

  PROCEDURE Shift*(fct: LONGINT; VAR x, y: Item);
    VAR op: LONGINT;
  BEGIN load(x);
    IF fct = 0 THEN op := LSLi ELSIF fct = 1 THEN op := ASRi ELSE op := RORi END ;
    IF y.mode = ORB.Const THEN IF y.a#0 THEN PutR(op, x.r, 0, x.r+ LSL( y.a MOD 20H, 7)) END;
    ELSE load(y); PutR(op+ShiftV, RH-2, 0, x.r+ LSL(y.r, 8)); DEC(RH); x.r := RH-1
    END
  END Shift;

  PROCEDURE ADC*(VAR x, y: Item);
  BEGIN load(x); load(y); PutR(ADD+000H, x.r, x.r, y.r); DEC(RH)
  END ADC;

  PROCEDURE SBC*(VAR x, y: Item);
  BEGIN load(x); load(y); PutR(SUB+2000H, x.r, x.r, y.r); DEC(RH)
  END SBC;

  PROCEDURE UML*(VAR x, y: Item);
  BEGIN load(x); load(y); PutR(MUL+2000H, x.r, x.r, y.r); DEC(RH)
  END UML;

  PROCEDURE Bit*(VAR x, y: Item);
  BEGIN load(x); PutLS(LDR, x.r, x.r, 0);
    IF y.mode = ORB.Const THEN PutI( RORi-IMM+SETFLAGS, x.r, 0, x.r +LSL( y.a+1, 7)); DEC(RH) 
    ELSE load(y); PutI(ADD, y.r, y.r, 1); PutR( RORi+ShiftV+SETFLAGS, x.r, 0, x.r+ LSL(y.r, 8)); DEC(RH, 2)
    END ;
    SetCC(x, MI)
  END Bit;

  PROCEDURE Register*(VAR x: Item);
  BEGIN (*x.mode = Const*)
    IF x.a = 15 THEN x.a := RA
    ELSIF x.a = 14 THEN x.a := SP
    ELSIF x.a = 13 THEN x.a := TR
    ELSIF x.a < 0 THEN x.a := -x.a
    ELSE INC(x.a, minR)
    END;
    PutR(MOV, RH, 0, x.a MOD 10H); x.mode := Reg; x.r := RH; incR
  END Register;

  PROCEDURE H*(VAR x: Item);
  BEGIN (*x.mode = Const*)
      ORS.Mark("H not implemented")
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
  BEGIN (*x.mode = Const*) SetCC(x, x.a)
  END Condition;

  PROCEDURE Open*(v: INTEGER);
  VAR i: INTEGER;
  BEGIN pc := 0; final := -1; strx := 0; tdw := 0; RH := 0; check := v # 0; 
    fixorgP := 0; fixorgD := 0; fixorgT := 0; fixorgM := 0;
    FOR i := 0 TO 6 DO PutI32( ADD, TR, TR, 10000H) END;
    fixcode( -0FFH, 0FFH );
  END Open;

  PROCEDURE SetDataSize*(dc: LONGINT);
  BEGIN varx := dc
  END SetDataSize;

  PROCEDURE Header*;
  BEGIN entry := pc*4;  (*RISC-0 part deleted*)
    PutLS(STR+ LSWBACK, RA, SP, -4)
  END Header;

  PROCEDURE Exit*;
  BEGIN (*exit code*)  (* RISC-0 part removed*)
    PutLS(LDR-LSIndex, PC, SP, 4);
  END Exit;

  PROCEDURE Final*;
  BEGIN final := pc*4;   (* RISC-0 part removed*)
    PutI(SUB, SP, SP, 4); PutLS(STR, RA, SP, 0)
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
    FOR i := 0 TO pc-1 DO Files.WriteInt(R, Get4(i)) END ;  (*program*)
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

BEGIN relmap[0] := EQ; relmap[1] := NE; relmap[2] := LT; relmap[3] := LE; relmap[4] := GT; relmap[5] := GE
END OaG.
