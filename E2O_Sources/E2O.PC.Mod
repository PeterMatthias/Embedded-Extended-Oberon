MODULE PC;

IMPORT  SYSTEM, Host, Files, Texts, Oberon;

CONST TAB = 09X; LF = 0AX; CR = 0DX; 

VAR W: Texts.Writer;

PROCEDURE Receive*;
VAR beg, end, time: INTEGER;
    S: Texts.Scanner;
  F: Files.File; R: Files.Rider;
  f, i: INTEGER; ch: CHAR;
BEGIN
    Texts.WriteString(W, "PC.Receive");
  Texts.OpenScanner( S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan( S);
    WHILE S.class = Texts.Name DO
    F := Files.New( S.s); Files.Set(R, F, 0);
        Texts.Write(W, " "); Texts.WriteString(W, S.s);
    f := Host.Open( S.s, FALSE, FALSE); i := Host.Read( f, SYSTEM.ADR(ch), 1);
    WHILE i = 1 DO Files.Write( R, ch); i := Host.Read( f, SYSTEM.ADR(ch), 1) END;
    f := Host.Close( f); Files.Register( F);
    Texts.Append(Oberon.Log, W.buf);
    Texts.Scan(S)
    END;
  Texts.WriteLn( W);
  Texts.Append(Oberon.Log, W.buf);
END Receive;

PROCEDURE Send*;
VAR beg, end, time: INTEGER;
    S: Texts.Scanner;
  F: Files.File; R: Files.Rider;
  f, i: INTEGER; ch: CHAR;
BEGIN
    Texts.WriteString(W, "PC.Send");
  Texts.OpenScanner( S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan( S);
    WHILE S.class = Texts.Name DO
    F := Files.Old( S.s); Files.Set(R, F, 0); Files.Read( R, ch);
        Texts.Write(W, " "); Texts.WriteString(W, S.s);
    f := Host.Open( S.s, TRUE, TRUE);
    WHILE ~R.eof DO i := Host.Write( f, SYSTEM.ADR(ch), 1); Files.Read( R, ch) END;
    f := Host.Close( f);
    Texts.Append(Oberon.Log, W.buf);
    Texts.Scan(S)
    END;
  Texts.WriteLn( W);
  Texts.Append(Oberon.Log, W.buf);
END Send;

PROCEDURE Export*;  (* export Oberon Text to ASCII *)
VAR beg, end, time: INTEGER;
  T: Texts.Text; R: Texts.Reader;
    S: Texts.Scanner;
  f, i: INTEGER; ch: CHAR;
BEGIN
    Texts.WriteString(W, "PC.Export ");
  Texts.OpenScanner( S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan( S);
  NEW( T);
    WHILE S.class = Texts.Name DO
        Texts.Write(W, " "); Texts.WriteString(W, S.s);
    Texts.Open( T, S.s); Texts.OpenReader( R, T, 0); Texts.Read( R, ch);
    f := Host.Open( S.s, TRUE, TRUE);
    WHILE ~R.eot DO
      IF ch = CR THEN i := Host.Write( f, SYSTEM.ADR($0A$), 1);
      ELSIF ch = TAB THEN i := Host.Write( f, SYSTEM.ADR("  "), 2);
      ELSIF ch # LF THEN i := Host.Write( f, SYSTEM.ADR(ch), 1);
            END;
      Texts.Read( R, ch);
    END;
    f := Host.Close( f);
    Texts.Append(Oberon.Log, W.buf);
    Texts.Scan(S)
    END;
  Texts.WriteLn( W);
  Texts.Append(Oberon.Log, W.buf);
END Export;

BEGIN
  Texts.OpenWriter(W);
END PC.