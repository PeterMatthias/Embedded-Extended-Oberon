MODULE OMTool;  (*NW 18.2.2013 / 12.4.2017 / AP 10.3.24 Extended Oberon*)
  IMPORT SYSTEM, Files, Modules, Texts, Oberon, ORB;
  CONST TAB = 09X;  (*copied from Input for use as cross development tool*)
  AllocAdr = 16; FPrintAdr = 28; ModAdr = 32; FPrint = 12345678H; (*copied from ORL*)
  ElfHeaderSize = 80H;

  OP = 4000000H; RS = 200000H; RTi = 10000H; RD = 800H; IMM = 10000H; SHAMT = 40H;
  CO = 2000000H; FMT = RS; FT = RTi; FS = RD; FD = SHAMT; LUI = 15;

  C8=100H; C12 = 1000H; C13 = 2000H; C14=4000H; C15=8000H; C16=10000H; 
  C20=100000H; C24=1000000H; C25=2000000H; C26 = 4000000H;

  VAR W: Texts.Writer;
    typlev: INTEGER;

  PROCEDURE Read(VAR R: Files.Rider; VAR x: INTEGER);
    VAR b: BYTE;
  BEGIN Files.ReadByte(R, b);
    IF b < 80H THEN x := b ELSE x := b - 100H END
  END Read;

  PROCEDURE ReadType(VAR R: Files.Rider);
    VAR key, len, size, off: INTEGER;
      ref, orgref, class, form, readonly: INTEGER;
      name, modname: ARRAY 32 OF CHAR;
  BEGIN INC(typlev); Read(R, ref); Texts.Write(W, " "); Texts.WriteLn(W);
    FOR off := 0 TO typlev DO Texts.Write(W, 09X) END ;
    Texts.Write(W, "[");
    IF ref < 0 THEN Texts.Write(W, "^"); Texts.WriteInt(W, -ref, 1)
    ELSE Texts.WriteInt(W, ref, 1);
      IF ref > 0 THEN  (*named type*)
        Files.ReadString(R, modname);
        IF modname[0] # 0X THEN
          Files.ReadInt(R, key); Files.ReadString(R, name); Read(R, orgref);
          Texts.Write(W, " "); Texts.WriteString(W, modname); Texts.Write(W, "."); Texts.WriteString(W, name);
          Texts.WriteHex(W, key)
        END
      END ;
      Read(R, form); Texts.WriteString(W, "  form = "); Texts.WriteInt(W, form, 1);
      IF form = ORB.Pointer THEN ReadType(R)
      ELSIF form = ORB.Array THEN
        ReadType(R); Files.ReadNum(R, len); Files.ReadNum(R, size);
        Texts.WriteString(W, "  len = "); Texts.WriteInt(W, len, 1);
        Texts.WriteString(W, "  size = "); Texts.WriteInt(W, size, 1)
      ELSIF form = ORB.Record THEN
        ReadType(R);  (*base type*)
        Files.ReadNum(R, off); Texts.WriteString(W, "  exno = "); Texts.WriteInt(W, off, 1);
        Files.ReadNum(R, off); Texts.WriteString(W, "  extlev = "); Texts.WriteInt(W, off, 1);
        Files.ReadNum(R, size); Texts.WriteString(W, "  size = "); Texts.WriteInt(W, size, 1);
        Texts.Write(W, " "); Texts.Write(W, "{"); Read(R, class);
        WHILE class # 0 DO  (*fields*)
          Files.ReadString(R, name);
          IF name[0] # 0X THEN Texts.Write(W, " "); Texts.WriteString(W, name); ReadType(R);
            IF class = ORB.Const THEN Files.ReadNum(R, off); Texts.WriteInt(W, off, 4) END  (*exno*)
          ELSE (*hidden*) Texts.WriteString(W, " --")
          END ;
          Files.ReadNum(R, off); Texts.WriteInt(W, off, 4);  (*mthno/offset*)
          Read(R, class)
        END ;
        Texts.Write(W, "}")
      ELSIF form IN {ORB.Proc, ORB.TProc} THEN
        ReadType(R); Texts.Write(W, "("); Read(R, class);
        WHILE class # 0 DO  (*parameters*)
          Texts.WriteString(W, " class = "); Texts.WriteInt(W, class, 1); Read(R, readonly);
          IF readonly = 1 THEN Texts.Write(W, "#") END ;
          ReadType(R); Read(R, class)
        END ;
        Texts.Write(W, ")")
      END
    END ;
    Texts.Write(W, "]"); DEC(typlev)
  END ReadType;

  PROCEDURE DecSym*;  (*decode symbol file*)
    VAR class, k: INTEGER;
      name: ARRAY 32 OF CHAR;
      F: Files.File; R: Files.Rider;
      S: Texts.Scanner;
  BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF S.class = Texts.Name THEN
      Texts.WriteString(W, "OR-decode "); Texts.WriteString(W, S.s);
      Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
      F := Files.Old(S.s);
      IF F # NIL THEN
        Files.Set(R, F, 0); Files.ReadInt(R, k); Files.ReadInt(R, k);
        Files.ReadString(R, name); Texts.WriteString(W, name); Texts.WriteHex(W, k);
        Read(R, class); Texts.WriteInt(W, class, 3);  (*sym file version*)
        IF class = ORB.versionkey THEN
          Texts.WriteLn(W); Read(R, class); typlev := 0;
          WHILE class # 0 DO
            Texts.WriteInt(W, class, 4); Files.ReadString(R, name); Texts.Write(W, " "); Texts.WriteString(W, name);
            ReadType(R);
            IF (class = ORB.Const) OR (class = ORB.Var) THEN
              Files.ReadNum(R, k); Texts.WriteInt(W, k, 5);  (*Reals, Strings!*)
            END ;
            Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
            Read(R, class)
          END
        ELSE Texts.WriteString(W, " bad symfile version")
        END
      ELSE Texts.WriteString(W, " not found")
      END ;
      Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
    END
  END DecSym;

(* ---------------------------------------------------*)

PROCEDURE Comma;
BEGIN Texts.WriteString(W, ", ")
END Comma;

PROCEDURE int(i: LONGINT);
BEGIN Texts.WriteInt(W, i, 0)
END int;

PROCEDURE Reg(r: LONGINT);
BEGIN Texts.Write(W, " ");
  IF r=0 THEN Texts.WriteString(W, "ZR")
  ELSIF r = 29 THEN Texts.WriteString(W, "SP")
  ELSIF r = 30 THEN Texts.WriteString(W, "FP")
  ELSIF r = 31 THEN Texts.WriteString(W, "RA")
  ELSE Texts.Write(W, "r");
    Texts.WriteInt(W, r , 0)
  END
END Reg;

PROCEDURE FReg(f: LONGINT);
BEGIN
  Texts.Write(W, "f"); Texts.WriteInt(W, f, 0)
END FReg;

PROCEDURE Base(b: LONGINT);
BEGIN
  Texts.Write(W, "("); Reg(b); Texts.Write(W, ")")
END Base;

PROCEDURE Off(a: LONGINT);
BEGIN
  Texts.WriteInt(W, a, 0)
END Off;

PROCEDURE Str( s: ARRAY OF CHAR);
VAR i: LONGINT;
BEGIN
  i:=LEN(s);
  Texts.WriteString(W, s);
  REPEAT
    INC(i);
    Texts.Write(W, " ");
  UNTIL i>=10;
END Str;

PROCEDURE WriteHex(i: LONGINT; n: INTEGER);
VAR a: ARRAY 8 OF CHAR; j, dig: INTEGER;
BEGIN j := 0;
   WHILE j < 8  DO
    dig := (i MOD 16); i := i DIV 16;
    IF dig > 9 THEN INC(dig, ORD("A") - ORD("9") - 1) END ;
    a[j] := CHR(dig + ORD("0")); INC(j)
  END ;
  WHILE n > 0 DO DEC(n); Texts.Write(W, a[n]) END
END WriteHex;

(* I-type *)
PROCEDURE IT( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
  Str( s);
  Reg( ASR(i, 16) MOD 20H); Comma;
  Reg( ASR(i, 21) MOD 20H); Comma;
  Texts.WriteInt(W, LSL(i, 16) DIV 10000H, 0)
END IT;

(* I-Type Float*)
PROCEDURE ITF( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
  Str( s);
  Reg( ASR(i, 21) MOD 20H); Comma;
  FReg( ASR(i, 16) MOD 20H); Comma;
  Texts.WriteInt(W, LSL(i, 16) DIV 10000H, 0)
END ITF;

(* I-Type, 1 argument *)
PROCEDURE IT1( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
  Str( s);
  Reg( ASR(i, 16) MOD 20H); Comma;
  Texts.WriteInt(W, LSL(i, 16) DIV 10000H, 0)
END IT1;

(* I-Type, 1 branch *)
PROCEDURE ITB( pc: INTEGER; s: ARRAY OF CHAR; i: LONGINT);
VAR targ: LONGINT;
BEGIN
  Str( s);
  Reg( ASR(i, 21) MOD 20H); Comma;
  IF ASR(i, 26)#1 THEN Reg( ASR(i, 16) MOD 20H); Comma END;
  targ := (pc + LSL(i, 16) DIV C14);
  Texts.WriteInt(W, targ, 0);
(*
  IF targ < LEN(label) THEN
    IF label[targ] < 0 THEN Texts.WriteString(W, proc[-label[targ]-1]);
    ELSE Texts.Write(W, "L"); Texts.WriteInt(W, label[targ], 0)
    END
  ELSE Texts.WriteString(W, "*****")
  END
*)
END ITB;

(* I-Type, 1 Load/Store *)
PROCEDURE ITL( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
  Str( s);
  Reg( ASR(i, 16) MOD 20H); Comma;
  Texts.WriteInt(W, LSL(i, 16) DIV 10000H, 0);
  Base(ASR(i, 21) MOD 20H);
END ITL;

PROCEDURE JT( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
  Str( s); Texts.WriteHex(W, i MOD C26 * 4);
END JT;

PROCEDURE RT0( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
  Str( s);
  Texts.WriteInt(W, ASR( i, 6), 1);
END RT0;

(* jump register *)
PROCEDURE RT1( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
  Str( s);
  Reg( ASR( i, 21));
END RT1;

(* jump and link register *)
PROCEDURE RT2( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
  Str( s);
  Reg( ASR( i, 11) MOD 20H); Comma;
  Reg( ASR( i, 21) MOD 20H);
END RT2;

(* RT Trap *)
PROCEDURE RT3( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
  Str( s);
  Reg(ASR(i, 21) MOD 20H); Comma; 
  Reg( ASR(i, 16) MOD 20H); Comma;
  Texts.WriteInt(W, ASR( i, 6) MOD 400H, 2);
END RT3;

PROCEDURE RT( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
  Str( s);
  Reg(ASR(i, 11) MOD 20H); Comma; 
  Reg( ASR(i, 21) MOD 20H); Comma;
  Reg( ASR(i, 16) MOD 20H); Comma; 
  Texts.WriteInt(W, ASR( i, 6) MOD 20H, 2);
END RT;

PROCEDURE COP0( i: LONGINT);
BEGIN
  Str("COP0"); Texts.WriteHex(W, i);
END COP0;

PROCEDURE SubCOP1(s: ARRAY OF CHAR; i: LONGINT);
BEGIN
  Str(s);
  Reg( ASR(i, 16)MOD 20H); Comma;
  FReg( ASR(i, 11) MOD 20H);
END SubCOP1;

PROCEDURE SubCOP1BC( i: LONGINT);
VAR j: INTEGER;
BEGIN
  j:=ASR(i, 16) MOD 20H;
  IF j=0 THEN Str("BCF");
  ELSIF j=1 THEN Str("BCT");
  ELSIF j=2 THEN Str("BCFL");
  ELSIF j=3 THEN Str("BCTL");
  ELSE Str("<BC not known>");
  END;
  Comma; Texts.WriteHex(W, i MOD 10000H);
END SubCOP1BC;

PROCEDURE Float2(str: ARRAY OF CHAR; i: LONGINT);
BEGIN
  Str(str); 
  FReg(ASR(i, 6)MOD 32); Comma;
  FReg(ASR(i, 11)MOD 32); 
END Float2;

PROCEDURE Float3(str: ARRAY OF CHAR; i: LONGINT);
BEGIN
  Str(str); 
  FReg(ASR(i, 6)MOD 32); Comma;
  FReg(ASR(i, 11)MOD 32); Comma;
  FReg(ASR(i, 16)MOD 32);
END Float3;

PROCEDURE Float(c: CHAR; i: LONGINT);
BEGIN
  i:= i MOD 64;
  IF i=  0 THEN  Float3("ADD.F", i);
  ELSIF i=  1 THEN Float3("SUB.F", i);
  ELSIF i=  2 THEN Float3("MUL.F", i);
  ELSIF i=  3 THEN Float3("DIV.F", i)
  ELSIF i=  4 THEN Float2("SQRT", i);
  ELSIF i=  5 THEN Float2("ABS", i);
  ELSIF i=  6 THEN Float2("MOV", i);
  ELSIF i=  7 THEN Float2("NEG", i);
  ELSIF i=  12 THEN Float2("ROUND", i);
  ELSIF i=  13 THEN Float2("TRUNC", i);
  ELSIF i=  14 THEN Float2("CEIL", i);
  ELSIF i=  15 THEN Float2("FLOOR", i);
  ELSIF i=  32 THEN Float2("CVT.S", i);
  ELSIF i=  33 THEN Float2("CVT.D", i);
  ELSIF i=  36 THEN Float2("CVT.W", i);
  ELSE Str("<Float not known>");
  END;
END Float;

PROCEDURE COP1( i: LONGINT);
BEGIN
  i:=ASR(i, 21) MOD 32;
  IF i= 0 THEN SubCOP1("MFC1", i);
  ELSIF i= 2 THEN SubCOP1("CFC1", i);
  ELSIF i= 4 THEN SubCOP1("MTC1", i);
  ELSIF i= 6 THEN SubCOP1("CTC1", i);
  ELSIF i= 8 THEN SubCOP1BC( i);
  ELSIF i= 16 THEN Float("S", i);
  ELSIF i= 17 THEN Float("D", i);
  ELSIF i= 20 THEN Float("W", i);
  ELSE Str("<COP1 not known>");
  END;
END COP1;

PROCEDURE COP2( i: LONGINT);
BEGIN
  Str("COP2"); Texts.WriteHex(W, i);
END COP2;

PROCEDURE COP3( i: LONGINT);
BEGIN
  Str("COP3"); Texts.WriteHex(W, i);
END COP3;

PROCEDURE Special( i: LONGINT);
VAR j: INTEGER;
BEGIN
  IF i=0 THEN Texts.WriteString(W, "NOP")
  ELSE j:=i MOD 64;
    IF j= 0 THEN RT("SLL",i)
    ELSIF j= 2 THEN RT("SRL",i)
    ELSIF j= 3 THEN RT("SRA",i)
    ELSIF j= 4 THEN RT("SLLV",i)
    ELSIF j= 6 THEN RT("SRLV",i)
    ELSIF j= 7 THEN RT("SRAV",i)
    ELSIF j= 8 THEN RT1("JR",i)
    ELSIF j= 9 THEN RT2("JALR",i)
    ELSIF j= 12 THEN RT0("SYSCALL",i)
    ELSIF j= 13 THEN RT0("BREAK",i)
    ELSIF j= 15 THEN RT("SYNC",i)
    ELSIF j= 16 THEN RT("MFHI",i)
    ELSIF j= 17 THEN RT("MTHI",i)
    ELSIF j= 18 THEN RT("MFLO",i)
    ELSIF j= 19 THEN RT("MTLO",i)
    ELSIF j= 24 THEN RT("MULT",i)
    ELSIF j= 25 THEN RT("MULTU",i)
    ELSIF j= 26 THEN RT("DIV",i)
    ELSIF j= 27 THEN RT("DIVU",i)
    ELSIF j= 32 THEN RT("ADD",i)
    ELSIF j= 33 THEN RT("ADDU",i)
    ELSIF j= 34 THEN RT("SUB",i)
    ELSIF j= 35 THEN RT("SUBU",i)
    ELSIF j= 36 THEN RT("AND",i)
    ELSIF j= 37 THEN RT("OR",i)
    ELSIF j= 38 THEN RT("XOR",i)
    ELSIF j= 39 THEN RT("NOR",i)
    ELSIF j= 42 THEN RT("SLT",i)
    ELSIF j= 43 THEN RT("SLTU",i)
    ELSIF j= 48 THEN RT3("TGE", i)
    ELSIF j= 49 THEN RT3("TGEU", i)
    ELSIF j= 50 THEN RT3("TLT", i)
    ELSIF j= 51 THEN RT3("TLTU", i)
    ELSIF j= 52 THEN RT3("TEQ", i)
    ELSIF j= 54 THEN RT3("TNE", i)
    ELSE Str("<SPECIAL not known>"); WriteHex(i MOD 64, 8);
    END;
  END
END Special;

PROCEDURE Special2( i: LONGINT);
BEGIN
  IF i MOD 64 =2 THEN RT("MUL", i);
  ELSE Str("<SPECIAL2 not known>"); WriteHex(i MOD 64, 8);
  END;
END Special2;

PROCEDURE Regimm(pc,  i: LONGINT);
VAR j: INTEGER;
BEGIN
  j:=ASR(i, 16) MOD 32;
  IF j=0 THEN ITB(pc, "BLTZ", i)
  ELSIF j= 1 THEN ITB(pc, "BGEZ", i)
  ELSIF j= 16 THEN ITB(pc, "BLTZAL", i)
  ELSIF j= 17 THEN ITB(pc, "BGEZAL", i)
  ELSE Str("<REGIMM not known>"); WriteHex(i MOD 64, 8);
  END;
END Regimm;

PROCEDURE opcode(instr: INTEGER; fixP, fixD: BOOLEAN);
VAR pc, i: INTEGER;
BEGIN
  pc := 0;
  i:=ASR(instr, 26) MOD 40H;
  IF i= 0 THEN Special( instr )
  ELSIF i= 1 THEN Regimm( pc, instr )
  ELSIF i= 2 THEN JT("J", instr )
  ELSIF i= 3 THEN JT("JAL", instr)
  ELSIF i= 4 THEN ITB(pc, "BEQ", instr)
  ELSIF i= 5 THEN ITB(pc, "BNE", instr)
  ELSIF i= 6 THEN ITB(pc, "BLEZ", instr)
  ELSIF i= 7 THEN ITB(pc, "BGTZ", instr)
  ELSIF i= 8 THEN IT("ADDI", instr)
  ELSIF i= 9 THEN IT("ADDIU", instr)
  ELSIF i= 10 THEN IT("SLTI", instr)
  ELSIF i= 11 THEN IT("SLTIU", instr)
  ELSIF i= 12 THEN IT("ANDI", instr)
  ELSIF i= 13 THEN IT("ORI", instr)
  ELSIF i= 14 THEN IT("XORI", instr)
  ELSIF i= 15 THEN IT1("LUI", instr)
  ELSIF i= 16 THEN COP0( instr)
  ELSIF i= 17 THEN COP1( instr)
  ELSIF i= 18 THEN COP2( instr)
  ELSIF i= 19 THEN COP3( instr)
  ELSIF i= 20 THEN ITB(pc, "BEQL*", instr)
  ELSIF i= 21 THEN ITB(pc, "BNEL*", instr)
  ELSIF i= 22 THEN ITB(pc, "BLEZL*", instr)
  ELSIF i= 23 THEN ITB(pc, "BGTZL*", instr)
  ELSIF i= 28 THEN Special2( instr )
  ELSIF i= 32 THEN ITL("LB", instr)
  ELSIF i= 33 THEN ITL("LH", instr)
  ELSIF i= 34 THEN ITL("LWL", instr)
  ELSIF i= 35 THEN ITL("LW", instr)
  ELSIF i= 36 THEN ITL("LBU",  instr)
  ELSIF i= 37 THEN ITL("LHU", instr)
  ELSIF i= 38 THEN ITL("LWR", instr)
  ELSIF i= 40 THEN ITL("SB", instr)
  ELSIF i= 41 THEN ITL("SH", instr)
  ELSIF i= 42 THEN ITL("SWL", instr)
  ELSIF i= 43 THEN ITL("SW", instr)
  ELSIF i= 46 THEN ITL("SWR", instr)
  ELSIF i= 47 THEN IT("CACHE", instr)
  ELSIF i= 48 THEN IT("LL", instr)
  ELSIF i= 49 THEN ITF("LWC1", instr)
  ELSIF i= 50 THEN IT("LWC2", instr)
  ELSIF i= 51 THEN IT("LWC3", instr)
  ELSIF i= 53 THEN ITF("LDC1", instr)
  ELSIF i= 54 THEN IT("LDC2", instr)
  ELSIF i= 55 THEN IT("LDC3", instr)
  ELSIF i= 56 THEN IT("SC", instr)
  ELSIF i= 57 THEN ITF("SWC1", instr)
  ELSIF i= 58 THEN IT("SWC2", instr)
  ELSIF i= 59 THEN IT("SWC3", instr)
  ELSIF i= 61 THEN ITF("SDC1", instr)
  ELSIF i= 62 THEN IT("SDC2", instr)
  ELSIF i= 63 THEN IT("SDC3", instr)
  ELSE  Texts.WriteString(W, "< not known>");
  END;
END opcode;

  PROCEDURE Write(VAR R: Files.Rider; x: INTEGER);
  BEGIN Files.WriteByte(R, x)  (* -128 <= x < 128 *)
  END Write;

  PROCEDURE DecObj*;  (*decode object file*)
    VAR class, i, n, key, size, adr, data, prg: INTEGER;
      ch: CHAR;
      name: ARRAY 32 OF CHAR;
      fixorgP, fixorgD, nofP, nofD: LONGINT;
      fixP, fixD: ARRAY 2000 OF LONGINT;  (*fixup positions*)
      F: Files.File; R: Files.Rider;
      S: Texts.Scanner;
  BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF S.class = Texts.Name THEN
      Texts.WriteString(W, "decode "); Texts.WriteString(W, S.s); F := Files.Old(S.s);
      IF F # NIL THEN
        Files.Set(R, F, 0); Files.ReadString(R, name); Texts.WriteLn(W); Texts.WriteString(W, name);
        Files.ReadInt(R, key); Texts.WriteHex(W, key); Read(R, class); Texts.WriteInt(W, class, 4);  (*version*)
        Files.ReadInt(R, size); Texts.WriteInt(W, size, 6); Texts.WriteLn(W);
        Texts.WriteString(W, "imports:"); Texts.WriteLn(W); Files.ReadString(R, name);
        WHILE name[0] # 0X DO
          Texts.Write(W, TAB); Texts.WriteString(W, name);
          Files.ReadInt(R, key); Texts.WriteHex(W, key); Texts.WriteLn(W);
          Files.ReadString(R, name)
        END ;
        Texts.WriteString(W, "variables"); Files.ReadInt(R, data); Texts.WriteInt(W, data, 6); Texts.WriteLn(W);
        Texts.WriteString(W, "strings"); Files.ReadInt(R, n); Texts.WriteInt(W, n, 6); Texts.WriteLn(W);
        i := 0;
        WHILE i < n DO Files.Read(R, ch); Texts.Write(W, ch); INC(i) END ;
        Texts.WriteLn(W);
        Texts.WriteString(W, "type descriptors"); Files.ReadInt(R, n); Texts.WriteInt(W, n, 6); Texts.WriteLn(W);
        n := n DIV 4; i := 0;
        WHILE i < n DO Files.ReadInt(R, data); Texts.WriteHex(W, data); INC(i) END ;
        Texts.WriteLn(W);
        (*first pass*)
        Files.ReadInt(R, n); prg := Files.Pos(R); Files.Set(R, F, prg + n*4);  (*program code*)
        Files.ReadString(R, name);
        WHILE name[0] # 0X DO Files.ReadInt(R, data); Files.ReadString(R, name) END ;  (*commands*)
        Files.ReadInt(R, n); Files.Set(R, F, Files.Pos(R) + n*4);  (*entries*)
        Files.ReadInt(R, data);
        WHILE data >= 0 DO Files.ReadInt(R, data) END ;  (*pointer references*)
        Files.ReadInt(R, data);
        WHILE data >= 0 DO Files.ReadInt(R, data) END ;  (*procedure variable references*)
        Files.ReadInt(R, fixorgP); Files.ReadInt(R, fixorgD);
        (*record fixup positions*)
        adr := prg + fixorgP*2; nofP := 0;
        WHILE adr # prg DO
          Files.Set(R, F, adr);
          Files.ReadInt(R, data);  (*inst*)
          fixP[nofP] := (adr - prg) DIV 4; INC(nofP);
          adr := adr - (data MOD 8000H) * 2
        END ;
        adr := prg + fixorgD*2; nofD := 0;
        WHILE adr # prg DO
          Files.Set(R, F, adr);
          Files.ReadInt(R, data);  (*inst*)
          fixD[nofD MOD 1024] := (adr - prg) DIV 4; INC(nofD);
          adr := adr - (data MOD 8000H) * 2
        END ;
        Files.Set(R, F, prg-4);
        (*second pass*)
        Texts.WriteString(W, "program code"); Texts.WriteLn(W);
        Files.ReadInt(R, n); i := 0; DEC(nofP); DEC(nofD);
        WHILE i < n DO
          Files.ReadInt(R, data); Texts.WriteHex(W, i * 4); 
          Texts.Write(W, TAB); Texts.WriteHex(W, data); Texts.Write(W, TAB); 
          IF (nofP >= 0) & (i = fixP[nofP]) THEN
            Str(" mno "); int( data DIV C24 MOD 80H);
            Str(", pno "); int( data DIV C16 MOD 100H); DEC(nofP)
          ELSIF (nofD >= 0) & (i = fixD[nofD]) THEN
            Str(" mno ");
            IF ODD(data DIV C15) THEN int(data DIV C24 MOD 80H); Str(" vno "); int(data DIV C16 MOD 100H);
            ELSE int( 0); Str(" vno "); int(data DIV C16);
            END;
            DEC(nofD)
          ELSE opcode(data, FALSE, FALSE)
          END ;
          Texts.WriteLn(W); INC(i)
        END ;
        Texts.WriteString(W, "commands:"); Texts.WriteLn(W);
        Files.ReadString(R, name);
        WHILE name[0] # 0X DO
          Texts.Write(W, TAB); Texts.WriteString(W, name);
          Files.ReadInt(R, adr); Texts.WriteInt(W, adr, 5); Texts.WriteLn(W);
          Files.ReadString(R, name)
        END ;
        Texts.WriteString(W, "entries"); Texts.WriteLn(W);
        Files.ReadInt(R, n); i := 0;
        WHILE i < n DO Files.ReadInt(R, adr); Texts.WriteInt(W, adr, 6); INC(i) END ;
        Texts.WriteLn(W);
        Texts.WriteString(W, "pointer refs"); Texts.WriteLn(W); Files.ReadInt(R, adr);
        WHILE adr # -1 DO Texts.WriteInt(W, adr, 6); Files.ReadInt(R, adr) END ;
        Texts.WriteLn(W);
        Texts.WriteString(W, "procedure variables"); Texts.WriteLn(W); Files.ReadInt(R, adr);
        WHILE adr # -1 DO Texts.WriteInt(W, adr, 6); Files.ReadInt(R, adr) END ;
        Texts.WriteLn(W);
        Files.ReadInt(R, data); Texts.WriteString(W, "fixP = "); Texts.WriteInt(W, data, 8); Texts.WriteLn(W);
        Files.ReadInt(R, data); Texts.WriteString(W, "fixD = "); Texts.WriteInt(W, data, 8); Texts.WriteLn(W);
        Files.ReadInt(R, data); Texts.WriteString(W, "fixT = "); Texts.WriteInt(W, data, 8); Texts.WriteLn(W);
        Files.ReadInt(R, data); Texts.WriteString(W, "fixM = "); Texts.WriteInt(W, data, 8); Texts.WriteLn(W);
        Files.ReadInt(R, data); Texts.WriteString(W, "entry = "); Texts.WriteInt(W, data, 8); Texts.WriteLn(W);
        Files.ReadInt(R, data); Texts.WriteString(W, "final = "); Texts.WriteInt(W, data, 8); Texts.WriteLn(W);
        Files.Read(R, ch);
        IF ch # "O" THEN Texts.WriteString(W, "format error"); Texts.WriteLn(W) END
      ELSE Texts.WriteString(W, " not found"); Texts.WriteLn(W)
      END ;
      Texts.Append(Oberon.Log, W.buf)
    END
  END DecObj;

  PROCEDURE DecMod*;
    VAR mod: Modules.Module;
      adr, data: INTEGER;
      S: Texts.Scanner;
   BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
     IF S.class = Texts.Name THEN
       Texts.WriteString(W, "decode "); Texts.WriteString(W, S.s);
       mod := Modules.root;
       WHILE (mod # NIL) & (mod.name # S.s) DO mod := mod.next END ;
       IF mod # NIL THEN
         Texts.WriteLn(W); adr := mod.prg;
         Texts.WriteString(W, "program code"); Texts.WriteInt(W, (mod.imp - adr) DIV 4, 6); Texts.WriteLn(W);
         WHILE adr # mod.imp DO
           SYSTEM.GET(adr, data); Texts.WriteInt(W, adr, 4); 
           Texts.Write(W, TAB); opcode(data, FALSE, FALSE); Texts.WriteLn(W); INC(adr, 4)
         END ;
       ELSE Texts.WriteString(W, " not loaded"); Texts.WriteLn(W)
       END ;
       Texts.Append(Oberon.Log, W.buf)
     END
  END DecMod;

  PROCEDURE DecBin*;  (*decode pre-linked binary file*)
    VAR AllocPtr, fprint, pos, num, size, prg, refcnt: INTEGER;
      name: ARRAY 32 OF CHAR;
      F: Files.File; R: Files.Rider;
      S: Texts.Scanner;
  BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF S.class = Texts.Name THEN
      Texts.WriteString(W, "decode "); Texts.WriteString(W, S.s); F := Files.Old(S.s);
      IF F # NIL THEN
        Files.Set(R, F, FPrintAdr + ElfHeaderSize); Files.ReadInt(R, fprint);
        IF fprint = FPrint THEN
          pos := ElfHeaderSize; Files.Set(R, F, ElfHeaderSize); Texts.WriteLn( W);
          WHILE ~R.eof  DO
            Files.ReadInt(R, prg);
            Texts.WriteHex(W, pos); INC (pos, 4); Texts.WriteString(W, "    ");
            opcode( prg, FALSE, FALSE);
            Texts.WriteLn( W);
          END;
(*
          Files.Set(R, F, AllocAdr); Files.ReadInt(R, AllocPtr); Texts.WriteInt(W, AllocPtr, 7); Texts.WriteLn(W);
          Files.Set(R, F, ModAdr); pos := ModAdr;
          WHILE ~R.eof & (pos < AllocPtr) DO
            Files.ReadString(R, name);
            Files.Set(R, F, pos+40); (*num*) Files.ReadInt(R, num);
            Files.ReadInt(R, size); (*size*) Files.ReadInt(R, refcnt); (*refcnt*)
            Files.Set(R, F, pos+64); (*prg*) Files.ReadInt(R, prg);
            IF name[0] # 0X THEN Texts.WriteString(W, "  ");
              Texts.WriteString(W, name); Texts.WriteInt(W, num, 4); Texts.Write(W, TAB);
              Texts.WriteHex(W, pos); Texts.WriteHex(W, prg); Texts.WriteInt(W, refcnt, 4)
            ELSE Texts.WriteString(W, "---")
            END ;
            Texts.WriteLn(W); INC(pos, size); Files.Set(R, F, pos)
          END
*)
        ELSE Texts.WriteString(W, "  input file format error"); Texts.WriteLn(W)
        END
      ELSE Texts.WriteString(W, " not found"); Texts.WriteLn(W)
      END ;
      Texts.Append(Oberon.Log, W.buf)
    END
  END DecBin;

BEGIN Texts.OpenWriter(W); Texts.WriteString(W, "OMTool 18.2.2013 / AP 10.3.24");
  Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
END OMTool.
