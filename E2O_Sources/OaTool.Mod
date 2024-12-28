MODULE OaTool;  (*NW 18.2.2013 / 12.4.2017 / AP 10.3.24 Extended Oberon*)
  IMPORT SYSTEM, Files, Modules, Texts, Oberon, ORB;
  CONST TAB = 09X;  (*copied from Input for use as cross development tool*)
    AllocAdr = 16; FPrintAdr = 28; ModAdr = 32; FPrint = 12345678H; (*copied from ORL*)
    C15 = 8000H;  C16 = 10000H;  C24 = 1000000H;
  VAR W: Texts.Writer;
    name0, name1, branch, branchl, dfloat, mfloat, cptnf, tnf, bnf, CC, Rot, Psr, Reg, FReg: ARRAY 80 OF CHAR;
    halfword: ARRAY 16 OF CHAR; 

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

  PROCEDURE Ch(ch: CHAR);
  BEGIN Texts.Write(W, ch)
  END Ch;

  PROCEDURE Str(s: ARRAY OF CHAR);
  BEGIN Texts.WriteString(W, s)
  END Str;
  
  PROCEDURE int(i: LONGINT);
  BEGIN Texts.WriteInt(W, i, 0)
  END int;
  
  PROCEDURE tab;
  BEGIN Texts.Write(W, 09X)
  END tab;
  
  PROCEDURE Ln;
  BEGIN Texts.WriteLn(W)
  END Ln;

  PROCEDURE FixHex(n: LONGINT);
  BEGIN Texts.WriteHex(W, n)
  END FixHex;

  PROCEDURE Hex(n: LONGINT);
    VAR i, j, k: INTEGER; s : ARRAY 12 OF CHAR;
  BEGIN
    i := 32;      
    REPEAT DEC( i, 4) UNTIL (i= 0) OR ( ASR(n, i) MOD 10H # 0);
    k := 0;
    IF ASR( n, i) MOD 10H >= 10 THEN s[0] := "0"; k := 1 END;
    WHILE i >= 0 DO
      j := ASR( n, i) MOD 10H;
      IF j < 10 THEN s[k] := CHR(j +ORD("0")) ELSE s[k] := CHR(j - 10 + ORD("A")) END;
      DEC(i, 4); INC(k);
    END;
    s[k]:="H"; s[k+1] := 0X;
    Texts.WriteString(W, s)
  END Hex;
  
  PROCEDURE word(VAR n: ARRAY OF CHAR; p: LONGINT);
  BEGIN
    p := p*4;
    Texts.Write(W, n[p]); Texts.Write(W, n[p+1]); Texts.Write(W, n[p+2]); 
  END word;
  
  PROCEDURE word2(VAR n: ARRAY OF CHAR; p : LONGINT);
  BEGIN
    p := p*4;
    Texts.Write(W, n[p]); Texts.Write(W, n[p+1]); Texts.Write(W, n[p+2]); Texts.Write(W, n[p+3]); 
  END word2;

  PROCEDURE word3(VAR n : ARRAY OF CHAR; p : LONGINT);
  BEGIN
    p:=p*2;
    Texts.Write(W, n[p]); Texts.Write(W, n[p+1])
  END word3;

  PROCEDURE cond(cc: LONGINT);
  BEGIN
    cc:= cc*3;
    Texts.Write(W, CC[cc]); Texts.Write(W, CC[cc+1])
  END cond;
  
  PROCEDURE s;
  BEGIN Texts.Write(W, "S");
  END s;  
  
  PROCEDURE byte;
  BEGIN Texts.Write(W, "B");
  END byte;

  PROCEDURE reg(n: LONGINT);
  BEGIN
    n:= n*3;
    Texts.Write(W, Reg[n]); Texts.Write(W, Reg[n + 1])
  END reg;
  
  PROCEDURE freg(n: LONGINT);
  BEGIN
    n:= n*3;
    Texts.Write(W, FReg[n]); Texts.Write(W, FReg[n + 1]);
  END freg;
  
  PROCEDURE psr(s, a: LONGINT);
    VAR i: LONGINT;
  BEGIN a := (a MOD 2 + a DIV 4)*8 - 8 + s*24 ;
    IF (a >= 0) & (a<48) THEN
      FOR i:= a TO a + 7 DO
        Texts.Write(W, Psr[i]) 
      END
    END
  END psr;
  
  PROCEDURE rot(t, c: LONGINT);
    VAR n: LONGINT;
  BEGIN
    IF ODD(t) THEN (* register form*)
      DEC(t); (* t MOD 8 isn't needed, since t.3=0 *)
      Texts.Write(W, Rot[t*2]); Texts.Write(W, Rot[t*2+1]);
      Texts.Write(W, Rot[t*2+2]); Texts.Write(W, Rot[t*2+3]);
      reg(c)
    ELSE
      n := c*2 + t DIV 8;
      IF n # 0 THEN
        Texts.Write(W, Rot[(t MOD 8)*2]); Texts.Write(W, Rot[(t MOD 8)*2+1]);
        Texts.Write(W, Rot[(t MOD 8)*2+2]); Texts.Write(W, Rot[(t MOD 8)*2+3]);
        Texts.WriteInt(W, n, 0)
      ELSIF (t MOD 8) = 6 THEN (* rrx *) 
        Texts.WriteString(W, "RRX");
      ELSIF ((t MOD 8) = 2) OR ( (t MOD 8) = 4) THEN (* rotate 32*)
        Texts.Write(W, Rot[(t MOD 8)*2]); Texts.Write(W, Rot[(t MOD 8)*2+1]);
        Texts.Write(W, Rot[(t MOD 8)*2+2]); Texts.Write(W, Rot[(t MOD 8)*2+3]);
        Texts.WriteInt(W, 32, 0)
      END        
    END
  END rot;
  
  PROCEDURE imm(i, r: LONGINT);
  BEGIN Hex(ROR(i, 2*r ))
  END imm;

  PROCEDURE PCRelAddr(adr, sign, ofs : LONGINT);
  BEGIN
    tab; tab; Str("( = "); int((adr+8)+sign*ofs); Str(" (");  FixHex((adr+8)+sign*ofs); Str("H)  )");
  END PCRelAddr;

  PROCEDURE decode(adr, code: LONGINT);
    VAR cc, a, b, c, d, e, f, g, i: LONGINT; regset: SET; sign : LONGINT;
  BEGIN
    g := code MOD 10H;   (* split instruction *)
    f := code DIV 10H MOD 10H;
    e := code DIV 100H MOD 10H;
    d := code DIV 1000H MOD 10H;
    c := code DIV 10000H MOD 10H;
    b := code DIV 100000H MOD 10H;
    a := code DIV 1000000H MOD 10H;
    cc :=  code DIV 10000000H MOD 10H;
    IF (a >=0) & ( a<4) THEN
      IF (a = 0) & (f = 9) THEN (*mul / mull *)
        IF ODD(b DIV 8) THEN (* mull *)
          IF ODD(b DIV 4) THEN Ch("S") ELSE Ch("U") END;
          word(name0, (b DIV 2) MOD 2 + 16 ); Ch("L"); 
          cond(cc); IF ODD(b) THEN s ELSE Ch(" ") END; tab; Str("  ");
          reg(c); Ch(":"); reg(d); Ch(","); reg(g); Ch(","); reg(e);
        ELSE  (* MLA, MLS *)
          IF b DIV 2=0 THEN   (*  MLA *)
            word(name0, 16 ); cond(cc);
            IF ODD(b) THEN s ELSE Ch(" ") END;
          ELSIF b DIV 2=1 THEN   (*  MLA *)
            word(name0, 17 ); cond(cc);
            IF ODD(b) THEN s ELSE Ch(" ") END;
          ELSIF b=6 THEN   (*  MLS *)
            word(name0, 18 ); cond(cc);
          END;
          tab; tab;
          reg(c);
          IF ODD(b DIV 8) THEN Ch(":"); reg(d) END;
          Ch(","); reg(g); Ch(","); reg(e);
          IF ODD(b DIV 2) THEN Ch(","); reg(d) END;
        END
      ELSIF (f>9) & ODD(f) & (a<2) THEN (* ldrh/strh *)
        word(name1,(b MOD 2)+1);  word3(halfword,(f-9) DIV 2); cond(cc);
        Str("   "); tab; reg(d); Str(",[");
        reg(c); 
        IF ~ODD(a) THEN Ch("]") END; Ch(",");
        IF ODD(b DIV 8) THEN Ch("+"); sign:=1 
        ELSE Ch("-"); sign:=-1 
        END;
        IF ODD(b DIV 4) THEN (* immidiate data transfer*)
          imm(e*10H +  g, 0);
        ELSE  (* reg data transfer *)
          sign:=0;
          reg(g) 
        END;
        IF ODD(a) THEN Ch("]") END;
        IF ODD(b DIV 2) THEN Ch("!") END;
        IF (c=15) & (sign#0) THEN PCRelAddr(adr,sign,e*10H+g) END;
      ELSIF (f = 9) & (a=1) THEN (*single swap *)
        Str("SWP"); cond(cc); IF ODD(b DIV 4) THEN Ch("B") ELSE Ch(" ") END; tab; tab;
        reg(d); Ch(","); reg(g); Str(",["); reg(c); Ch("]");
      ELSIF (a = 1) & (b = 2) (*& (c=0FH) &(d=0FH) & (e=0FH)*) THEN  (* B(L)X *)
        word( bnf, f); cond(cc); Ch(" "); tab; tab; reg( g);
      ELSIF (a = 3) & (b = 2) & (d=0FH) THEN Texts.WriteString(W, "NOP" );
      ELSIF (a = 1) & ((b = 2) OR (b = 6) OR (b = 0) OR (b = 4)) OR (a = 3)&((b = 2) OR (b = 6)) THEN(* msr /mrs *)
        word(tnf, b DIV 2 MOD 2); cond(cc); Ch(" "); tab; tab;
        IF (b = 0) OR (b = 4) THEN reg(d); Ch(","); psr(b DIV 4, 9)
        ELSE psr(b DIV 4, c); Ch(",");
          IF a = 3 THEN imm(f*10H + g, e) ELSE reg(g) END
        END
      ELSE
        IF (a=3) & (b=0) THEN Str("MOVW    "); cond(cc); tab; reg(d); Ch(","); Hex(((c*10H+ e)*10H+f)*10H+g);
        ELSIF (a=3) & (b=4) THEN Str("MOVT    "); cond(cc); tab; reg(d); Ch(","); Hex(((c*10H+ e)*10H+f)*10H+g);
        ELSE
          word(name0, b DIV 2 + a*8 MOD 10H); cond(cc); IF ODD(b) THEN s ELSE Ch(" ") END; tab; tab;
          IF (b DIV 2 + a*8 MOD 10H = 0DH) OR (b DIV 2 + a*8 MOD 10H = 0FH) THEN (* Mov, Mvn*)
            reg(d) 
          ELSIF (b DIV 2 + a*8 MOD 10H >= 8H) & (b DIV 2 + a*8 MOD 10H <=  0BH) THEN (* cmp, tst*)
            reg(c)
          ELSE reg(d); Ch(","); reg(c) 
          END;
          IF ODD(a DIV 2) THEN Ch(","); imm(f*10H + g, e)  (* Immidiate Data processing *)
          ELSE Ch(","); reg(g); Ch(" "); rot(f, e)  (* Data processing *)
          END
        END;
      END  
    ELSIF a<=7 THEN  (*ldr, str *)
      IF (a >= 6) & ODD(f) THEN
        IF (a=7) THEN
          IF (b=1) THEN Str("SDIV    "); cond(cc); tab; reg(c); Ch(","); reg(g); Ch(","); reg(e);
          ELSIF (b=3) THEN  Str("UDIV    "); cond(cc); tab; reg(c); Ch(","); reg(g); Ch(","); reg(e);
          ELSIF (b=15) & (f=15) THEN Str("XTRAP     "); tab; int(d*16+e);
          ELSE
            IF (b DIV 2= 7) THEN Str("UBFX    ");
            ELSIF(b DIV 2= 5) THEN Str("SBFX    "); 
            END;
            cond(cc); tab; reg(d); Ch(","); reg(g); Ch(","); int(e *2 +f DIV 8); Ch(","); int(b MOD 2 * 16 + c+ 1); 
          END;
        ELSE word(name1, 0)  (* undef *)
        END;
      ELSE
        word(name1, (b MOD 2) + 1); cond(cc);  (*ldr, str *)
        IF ODD(b DIV 4) THEN byte ELSE Ch(" ") END; 
        IF ~ODD(a) & ODD(b DIV 2) THEN (* postindex & writeback *) Ch("T") ELSE Ch(" ") END;
        Str("   "); tab;
        reg(d); Ch(",");Ch("[");
        reg(c); IF ~ODD(a) THEN Ch("]") END; Ch(",");
        IF ODD(b DIV 8) THEN Ch("+"); sign:=1 ELSE Ch("-"); sign:=-1 END;
        IF (a < 6) THEN (* immidiate data transfer*)
          imm(e*100H + f*10H + g, 0);
        ELSE  (* reg data transfer *)
          sign:=0;
          reg(g); Ch(" "); rot(f, e) 
        END;
        IF ODD(a) THEN Ch("]") END;
        IF ODD(a) & ODD(b DIV 2) THEN (*preindexed & writeback *) Ch("!") END;
        IF (c=15) & (sign#0) THEN PCRelAddr(adr,sign,e*100H + f*10H + g) END;
      END
    ELSIF a<=9 THEN  (* ldm, stm *)
      word(name1, (b MOD 2) + 3); 
      IF b >= 8 THEN Ch("I") ELSE Ch("D") END;
      IF ODD(a) THEN Ch("B") ELSE Ch("A") END;
      cond(cc);
      Str("   "); tab;
      reg(c); IF ODD(b DIV 2) THEN Ch("!") END; Ch(","); Ch(" ");
      Ch("{");
      regset := SYSTEM.VAL(SET, d*1000H + e*100H + f*10H +g);
      FOR i := 0 TO 15 DO
        IF i IN regset THEN reg(i); Ch(" "); END;
      END;
      Ch("}");
      IF ODD(b DIV 4) THEN Ch("^") END
    ELSIF a=10 THEN word(branch, cc); Str("   "); tab; tab; (* branch *)
        INC( adr,LSL(((((b*10H + c)*10H + d)*10H + e)*10H + f)*10H +g+1, 8) DIV 64);
(*        IF (label[ adr DIV 4]#0) THEN Texts.Write(W, "L"); Texts.WriteInt(W, label[adr DIV 4], 0); Texts.Write(W, " ") END;*)
        int(adr DIV 4 +1); 
    ELSIF a=11 THEN  word2(branchl, cc); Str("  "); tab; tab; (* BL, branch link*)
      INC( adr,LSL(((((b*10H + c)*10H + d)*10H + e)*10H + f)*10H +g+1, 8) DIV 64);

(*
          ASSERT(adr>=0, 73);
          IF label[ adr DIV 4]<0 THEN  Texts.WriteString(W, proc[-label[adr DIV 4]-1]); Texts.Write(W, " ") END;
          IF label[ adr DIV 4]>0 THEN  Texts.WriteInt(W, label[adr DIV 4]-1, 0); Texts.Write(W, " ") END;
*)
      int(adr DIV 4+1); 
    ELSIF a=12 THEN (* floating point push/pop*)
      IF (b=1) & (c=0FH) & (d=0) & (e=7) THEN Str( "XTRAP"); cond(cc); Str("   "); tab; int( f*16 +g);
      ELSE
        word(cptnf, b MOD 2 + 2); Str("   "); tab; tab;
        freg(d); Ch(","); Ch(" "); Ch("["); f := (f*10H+ g) * 4;
(*          IF c = 13 THEN c := 15; (*correction of pc relative index, due to emulation hacks*)
            DEC(f, 4)
          END;*)
        reg(c); Ch("]"); Ch(",");
        IF ODD(b DIV 8) THEN Ch("+") ELSE Ch("-") END; imm(f, 0);
      END;
    ELSIF a=13 THEN (* floating point ldc/stc*)
      word(cptnf, b MOD 2); Str("   "); tab; tab;
      freg(d); Ch(","); Ch(" "); Ch("["); f := ( f*10H+g) * 4;
(*        IF c = 13 THEN c := 15; (*correction of pc relative index, due to emulation hacks*)
          DEC(f, 4)
        END;*)
      reg(c); Ch(",");
      IF ODD(b DIV 8) THEN Ch("+") ELSE Ch("-") END; imm(f, 0);
      Ch("]");
    ELSIF a=14 THEN 
      IF (e = 1) & (f = 0) THEN   (* floating operation *)
        b := b + d DIV 8 * 8; d := d MOD 8;
        word(dfloat, b ); Str("   "); tab; tab;
        IF b < 5 THEN freg(d); Ch(","); freg(c); Ch(","); freg(g)
        ELSIF b <= 10 THEN freg(d); Ch(","); freg(g)
        END
      ELSIF (e = 1) & (f =1) THEN
        word(mfloat, b ); Str("   "); tab; tab;
        IF b = 0 THEN  freg(c); Ch(","); reg(d)
        ELSIF b = 1 THEN  reg(d); Ch(","); freg(g)
        ELSIF b = 2 THEN reg(d); Ch(","); freg(g)
        ELSIF b = 3 THEN freg(c); Ch(","); reg(d)
        ELSIF b = 9 THEN freg(c); Ch(","); freg(g)
        END
      ELSIF e DIV 2=5 THEN
        IF b=0 THEN Str("VMOVV ");
        ELSIF b=1 THEN Str("VMOVA ");
        ELSIF b=2 THEN Str("VMUL  ");
        ELSIF b=3 THEN
          IF f=0 THEN Str("VADD  ");
          ELSIF f=4 THEN Str("VSUB  ");
          END;
        ELSIF b=8 THEN Str("VDIV  ");
        ELSIF b=0BH THEN
          IF c=0 THEN Str("VABS  ");
          ELSIF c=1 THEN Str("VNEG  ");
          ELSIF c=4 THEN Str("VCMP  ");
          ELSE Str("VCVT?  ");
          END;
        ELSIF b=0FH THEN Str("VMRS  ");
        ELSE Str("VFP??  ");
        END;
        tab; tab; freg(d); Ch(",");freg(c); Ch(","); freg(g);
      ELSE  (* mrc/ mcr *)
        word(cptnf, 2 + b MOD 2); cond(cc); Ch(" "); tab; tab;
        IF ODD(b) THEN reg(d); Ch(","); Ch("#"); imm(e, 0); Ch("-"); reg(c); Ch(","); imm(f*10H +g, 0); Ch(" ") 
        ELSE Ch("#"); imm(e, 0); Ch("-"); reg(c); Ch(","); imm(f*10H +g, 0); Ch(" "); Ch(","); reg(d);
        END
      END
    ELSE (* SVC, old SWI *)
      word(name1,7); cond(cc); Ch(" "); tab; tab; Hex(b*100000H + c*10000H + d*1000H + e*100H + f*10H +g);
    END;
  END decode;
 
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
        adr := prg + fixorgP * 2; nofP := 0;
        WHILE adr # prg DO
          Files.Set(R, F, adr);
          Files.ReadInt(R, data);  (*inst*)
          fixP[nofP] := (adr - prg) DIV 4 ; INC(nofP);
          adr := adr - (data MOD C15) * 2
        END ;
        adr := prg + fixorgD * 2; nofD := 0;
        WHILE adr # prg DO
          Files.Set(R, F, adr);
          Files.ReadInt(R, data);  (*inst*)
          fixD[nofD] := (adr - prg) DIV 4; INC(nofD);
          adr := adr - (data MOD C15) * 2
        END ;
        Files.Set(R, F, prg-4);
        (*second pass*)
        Texts.WriteString(W, "program code"); Texts.WriteLn(W);
        Files.ReadInt(R, n); i := 0; DEC(nofP); DEC(nofD);
        WHILE i < n DO
          Files.ReadInt(R, data); Texts.WriteInt(W, i, 4); Texts.Write(W, TAB); Texts.WriteHex(W, data);
          Texts.Write(W, TAB);
          IF (nofP >= 0) & (i = fixP[nofP]) THEN
            Str(" mno "); int( data DIV C24 MOD 80H);
            Str(", pno "); int( data DIV C16 MOD 100H); DEC(nofP)
          ELSIF (nofD >= 0) & (i = fixD[nofD]) THEN
            Str(" mno ");
            IF ODD(data DIV C15) THEN int(data DIV C24 MOD 80H); Str(" vno "); int(data DIV C16 MOD 100H);
            ELSE int( 0); Str(" vno "); int(data DIV C16);
            END;
            DEC(nofD)
          ELSE decode(i*4, data)
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
           Texts.Write(W, TAB); decode(adr, data, FALSE, FALSE); Texts.WriteLn(W); INC(adr, 4)
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
        Files.Set(R, F, FPrintAdr); Files.ReadInt(R, fprint);
        IF fprint = FPrint THEN
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
        ELSE Texts.WriteString(W, "  input file format error"); Texts.WriteLn(W)
        END
      ELSE Texts.WriteString(W, " not found"); Texts.WriteLn(W)
      END ;
      Texts.Append(Oberon.Log, W.buf)
    END
  END DecBin;

BEGIN Texts.OpenWriter(W); Texts.WriteString(W, "OATool 18.2.2013 / AP 10.3.24");
  Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
  CC := "EQ NE CS CC MI PL VS VC HI LS GE LT GT LE    NV";  
  name0 := "AND EOR SUB RSB ADD ADC SBC RSC TST TEQ CMP CMN OR  MOV BIC MVN MUL MLA MLS";
  name1 := "UDF STR LDR STM LDM B   BL  SVC";
  branch := "BEQ BNE BCS BCC BMI BPL BVS BVC BHI BLS BGE BLT BGT BLE B   BNV ";
  branchl := "BLEQBLNEBLCSBLCCBLMIBLPLBLVSBLVCBLHIBLLSBLGEBLLTBLGTBLLEBL  BLNV";
  dfloat := "ADF MUF SUF ??? DVF ??? ??? ??? MVF MNF ABF";
  mfloat := "FLT FIX UPK PCK ??? ??? ??? ??? ??? CMF";
  cptnf := "STC LDC PSH POP MCR MRC ";
  tnf := "MRS MSR";
  bnf :="    BX  1234BLX ";
  Psr := "CPSRcnt CPSRflg CPSRall SPSRcnt SPSRflg SPSRall     ";
  Reg := "R0 R1 R2 R3 R4 R5 R6 R7 R8 R9 RA RB TR SP LR PC ";
  FReg := "F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC FD FE FF ";
  Rot:= "LSL LSR ASR ROR ";
  halfword:="??H SBSH"; 
END OaTool.
