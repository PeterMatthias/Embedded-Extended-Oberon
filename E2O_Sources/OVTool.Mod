MODULE OVTool;  (*NW 18.2.2013 / 12.4.2017 / AP 10.3.24 Extended Oberon*)
  IMPORT SYSTEM, Files, Modules, Texts, Oberon, ORB;
  CONST TAB = 09X;  (*copied from Input for use as cross development tool*)
    AllocAdr = 16; FPrintAdr = 28; ModAdr = 32; FPrint = 12345678H; (*copied from ORL*)
    IMM8=100H; IMM12 = 1000H; IMM13 = 2000H; IMM14=4000H; IMM15=8000H; IMM16=10000H; IMM20=100000H; IMM24=1000000H; IMM25=2000000H;
    strLOAD ="LB      LH      LW      11111111LBU     LHU     222222223333333";
    strLOADFP ="0000000011111111FLW     FLD     33333333444444445555555566666";
    strOPIMM ="ADDI    SLLI    SLTI    SLTIU   XORI    SRLI    ORI     ANDI   ";
    strSTORE ="SB      SH      SW      000000001111111122222222333333334444444";
    strSTOREFP ="0000000011111111FSW     FSD     3333333344444444555555556666666";
    strOP1 ="ADD     SLL     SLT     SLTU    XOR     SRL     OR      AND    ";
    strOP2 ="SUB     111     222     333    444     SRA     555     666    ";
    strOPM ="MUL     MULH    MULHSU  MULHU   DIV     DUVU    REM     REMU   ";
    strJALR ="JALR    0000000011111111222222223333333344444444555555556666666";

    C15 = 8000H; C16 = 10000H; C24 = 1000000H;

  VAR W: Texts.Writer;
    mnemo0, mnemo1: ARRAY 16, 4 OF CHAR;  (*mnemonics*)
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

PROCEDURE Reg(r: LONGINT);
BEGIN Texts.Write(W, " ");
  IF r=0 THEN Texts.WriteString(W, "ZR")
  ELSIF r = 1 THEN Texts.WriteString(W, "LNK")
  ELSIF r = 2 THEN Texts.WriteString(W, "SP")
  ELSIF r = 5 THEN Texts.WriteString(W, "T0")
(*  ELSIF r = 4 THEN Texts.WriteString(W, "sb")*)
  ELSIF r = 21 THEN Texts.WriteString(W, "TR")

  ELSE Texts.Write(W, "R");
    Texts.WriteInt(W, r , 0)
  END
END Reg;

PROCEDURE FReg(f: LONGINT);
BEGIN
  Texts.Write(W, "f"); Texts.WriteInt(W, f, 0)
END FReg;

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

PROCEDURE RType( str: ARRAY OF CHAR; c: INTEGER);
VAR  funct3, j: INTEGER;
BEGIN
  funct3:=c DIV IMM12 MOD 8;
  FOR j:=(funct3*8) TO funct3*8+5 DO Texts.Write(W, str[j]) END;
  Reg( ASR(c, 7) MOD 20H); Comma;
  Reg( ASR(c, 15) MOD 20H); Comma;
  Reg( ASR(c, 20) MOD 20H);
END RType;

PROCEDURE RFType( c: INTEGER);
VAR funct3, funct7: INTEGER;
BEGIN
  funct7:= ASR(c, 25) MOD 80H;
  funct3:=c DIV IMM12 MOD 8;
  IF funct7= 0 THEN Str( "FADD.S");
  ELSIF funct7= 4 THEN Str( "FSUB.S");
  ELSIF funct7= 8 THEN Str(  "FMUL.S");
  ELSIF funct7= 10 THEN Str( "FDIV.S");
  ELSIF funct7= 2CH THEN Str( "FSQRT.S");
  ELSIF funct7= 10H THEN Str( "Fxxx.S");
  ELSIF funct7= 6 THEN Str( "FCVTxx.S");
  ELSIF funct7= 7 THEN Str( "FMVxx.S");
  ELSIF funct7= 50H THEN Str( "Fcc.S");
  ELSIF funct7= 68H THEN Str( "FCVT.S.Wx");
  ELSIF funct7= 78H THEN Str( "FMV.S.X");
  ELSE Str( "F-error");
  END;
  FReg( ASR(c, 7) MOD 20H); Comma;
  FReg( ASR(c, 15) MOD 20H); Comma;
  FReg( ASR(c, 20) MOD 20H);
END RFType;
    
  PROCEDURE Hex(i: LONGINT; n: INTEGER);
    VAR a: ARRAY 8 OF CHAR; j, dig: INTEGER;
  BEGIN j := 0;
     WHILE j < 8  DO
      dig := (i MOD 16); i := i DIV 16;
      IF dig > 9 THEN INC(dig, ORD("A") - ORD("9") - 1) END ;
      a[j] := CHR(dig + ORD("0")); INC(j)
    END ;
    WHILE n > 0 DO DEC(n); Texts.Write(W, a[n]) END; Texts.Write(W, "H")
  END Hex;

PROCEDURE IType(s: ARRAY OF CHAR;  c: LONGINT);
CONST ADDI=13H;
VAR i0, func3: INTEGER;
BEGIN
  IF c=ADDI THEN Str("NOP");
  ELSE
    func3:= c DIV IMM12 MOD 8;
    IF (c DIV IMM25= 20H ) & (func3=5)&(c MOD 80H= 13H) THEN Texts.WriteString( W, "SRAI  "); c:=c MOD (IMM25);
    ELSE
      FOR i0:= func3*8 TO func3*8+5 DO Texts.Write( W, s[ i0]); END;
    END;
    IF s[ func3*8]="F" THEN FReg( ASR(c, 7) MOD 20H);
    ELSE Reg( ASR(c, 7) MOD 20H);
    END;
    Comma;
    Reg( ASR(c, 15) MOD 20H); Comma;
    Texts.WriteInt(W, ASR(c, 20), 0);
  END;
END IType;

PROCEDURE UType(s: ARRAY OF CHAR; c: INTEGER);
VAR adr : INTEGER;
BEGIN
  adr := c DIV 1000H * 1000H;
  Texts.WriteString( W, s);
  Reg( c DIV 80H MOD 20H); Comma;
  Hex( c DIV 1000H*1000H, 8);
END  UType;

PROCEDURE SType(s: ARRAY OF CHAR;  c: LONGINT);
VAR i0, func3: INTEGER;
BEGIN
  func3:= c DIV IMM12 MOD 8;
  FOR i0:= func3*8 TO func3*8+5 DO Texts.Write( W, s[ i0]); END;
  IF s[ func3*8]="F" THEN  FReg( ASR(c, 20) MOD 20H) ELSE Reg( ASR(c, 20) MOD 20H) END;
  Comma;
  Reg( ASR(c, 15) MOD 20H);
  Comma;
  Texts.WriteInt(W, LSL( ASR(c, 25), 5)+ ASR(c , 7) MOD 20H , 0);
END SType;

PROCEDURE GetSBimm(i: INTEGER): INTEGER;
BEGIN
  RETURN LSL( ASR(i, 31), 12)+ LSL( ASR(i , 25) MOD 40H , 5)+ (ASR(i , 8) MOD 10H) * 2+ LSL( ASR(i, 7) MOD 2, 11)
END GetSBimm;

PROCEDURE SBType( i: INTEGER);
VAR funct3, off: INTEGER;
BEGIN
  off := GetSBimm(i);
  funct3:=i DIV 1000H MOD 8;
  IF funct3=0 THEN Str( "BEQ");
  ELSIF funct3=1 THEN Str( "BNE");
  ELSIF funct3=4 THEN Str( "BLT");
  ELSIF funct3=5 THEN Str( "BGE");
  ELSIF funct3=6 THEN Str( "BLTU");
  ELSIF funct3=7 THEN Str( "BGEU");
  ELSE Str( "Bcc error");
  END;
  Reg( ASR(i, 15) MOD 20H); Comma;
  Reg( ASR(i, 20) MOD 20H); Comma;
  Texts.WriteInt(W, off, 0);
END SBType;

PROCEDURE GetUJimm( op: LONGINT): LONGINT;  (* in words *)
BEGIN
  RETURN LSL(ASR( op, 31), 20)+ASR( op, 21) MOD 400H * 2 +LSL( ASR(op, 20) MOD 2, 11)+LSL( ASR(op, 12) MOD 100H, 12)
END GetUJimm;

PROCEDURE UJType( c: LONGINT);
VAR adr: INTEGER;
BEGIN
  adr :=GetUJimm(c);
  Str( "JAL   ");
  Reg( ASR(c, 7) MOD 20H); Comma;
  Texts.WriteInt( W, adr , 0); Comma;
  Hex(  adr, 8);
END UJType;

  PROCEDURE opcode(code: INTEGER; fixP, fixD: BOOLEAN);  (* adr in words *)
  VAR i0: INTEGER;
  BEGIN
  IF fixD THEN
    Texts.WriteString(W, "LUI "); 
    Texts.WriteString(W, " mno = "); Texts.WriteInt(W, code DIV C24 MOD 100H (*mno*), 3);
    Texts.WriteString(W, " high = "); Texts.WriteInt(W, code DIV C16 MOD 100H, 3)
  
  ELSIF fixP THEN
    Texts.WriteString(W, "JAL "); 
    Texts.WriteString(W, " mno "); Texts.WriteInt(W, code DIV C24 MOD 100H (*mno*), 3);
    Texts.WriteString(W, ", pno "); Texts.WriteInt(W, code DIV C16 MOD 100H (*pno*), 3)
  ELSIF code MOD 4 = 3 THEN
    i0:= code MOD 80H DIV 4;
    IF i0=0 THEN IType( strLOAD, code);
    ELSIF i0=1 THEN IType( strLOADFP, code);
    ELSIF i0=2 THEN Str( "custom-0");
    ELSIF i0=3 THEN Str( "MISC-MEM");
    ELSIF i0=4 THEN IType( strOPIMM, code);
    ELSIF i0=5 THEN UType("AUIPC ", code);
    ELSIF i0=6 THEN Str( "OPIMM32");
    ELSIF i0=7 THEN Str( "48b");

    ELSIF i0= 8THEN SType( strSTORE, code);  
    ELSIF i0= 9 THEN SType( strSTOREFP, code);
    ELSIF i0=10 THEN Str( "custom-1");
    ELSIF i0=11 THEN Str( "AMO");
    ELSIF i0=12 THEN 
      IF ASR(code , 25) = 1 THEN RType(strOP2 , code);
      ELSIF ASR(code , 25) = 20H THEN RType(strOPM , code);
      ELSE RType(strOP1 , code);
      END;
    ELSIF i0=13 THEN UType("LUI   ", code);
    ELSIF i0=14 THEN Str("OP32");
    ELSIF i0=15 THEN Str( "64b");

    ELSIF i0=16 THEN Str( "MADD");
    ELSIF i0=17 THEN Str( "MSUB");
    ELSIF i0=18 THEN Str( "NMSUB");
    ELSIF i0=19 THEN Str( "NMADD");
    ELSIF i0=20 THEN RFType( code);
    ELSIF i0=21 THEN Str( "reserved1");
    ELSIF i0=22 THEN Str( "custom2");
    ELSIF i0=23 THEN Str( "48b");

    ELSIF i0=24 THEN SBType( code);
    ELSIF i0=25 THEN IType( strJALR, code);
    ELSIF i0=26 THEN Str( "reserved2");
    ELSIF i0=27 THEN UJType( code);
    ELSIF i0=28 THEN Str( "ECALL");
    ELSIF i0=29 THEN Str( "reserved3");
    ELSIF i0=30 THEN Str( "custom3");
    ELSIF i0=31 THEN Str( "80b");
    END;
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
          adr := adr - (data MOD C15)*2
        END ;
        adr := prg + fixorgD*2; nofD := 0;
        WHILE adr # prg DO
          Files.Set(R, F, adr);
          Files.ReadInt(R, data);  (*inst*)
          fixD[nofD] := (adr - prg) DIV 4; INC(nofD);
          adr := adr - (data MOD C15)*2
        END ;
        Files.Set(R, F, prg-4);
        (*second pass*)
        Texts.WriteString(W, "program code"); Texts.WriteLn(W);
        Files.ReadInt(R, n); i := 0; DEC(nofP); DEC(nofD);
        WHILE i < n DO
          Files.ReadInt(R, data); Texts.WriteInt(W, i, 4); Texts.Write(W, TAB); Texts.WriteHex(W, data);
          Texts.Write(W, TAB);
          IF (nofP >= 0) & (i = fixP[nofP]) THEN opcode(data, TRUE, FALSE); DEC(nofP)
          ELSIF (nofD >= 0) & (i = fixD[nofD]) THEN opcode(data, FALSE, TRUE); DEC(nofD)
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
           SYSTEM.GET(adr, data); Texts.WriteInt(W, adr, 4); Texts.Write(W, TAB); Texts.WriteHex(W, data);
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
        Files.Set(R, F, FPrintAdr + 80H); Files.ReadInt(R, fprint);
        IF fprint = FPrint THEN
          pos := 80H; Files.Set(R, F, 80H); Texts.WriteLn( W);
          WHILE ~R.eof  DO
            Files.ReadInt(R, prg);
            Texts.WriteHex(W, pos); INC (pos, 4); Texts.WriteString(W, "    ");
            opcode( prg, FALSE, FALSE);
            Texts.WriteLn( W);
          END;

(*
          Files.Set(R, F, AllocAdr); Files.ReadInt(R, AllocPtr); Texts.WriteInt(W, AllocPtr, 7); Texts.WriteLn(W);
          Files.Set(R, F, ModAdr); pos := ModAdr ;
          WHILE ~R.eof & (pos < AllocPtr) DO
            Files.ReadString(R, name);
            Files.Set(R, F, pos+40 ); (*num*) Files.ReadInt(R, num);
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

BEGIN Texts.OpenWriter(W); Texts.WriteString(W, "OVTool 18.2.2013 / AP 10.3.24 2024/08/21");
  Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
END OVTool.
