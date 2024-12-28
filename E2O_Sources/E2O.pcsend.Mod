MODULE pcsend;

IMPORT  SYSTEM, Host, Files;

CONST TAB = 09X; LF = 0AX; CR = 0DX; 

VAR name: ARRAY 32 OF CHAR;

PROCEDURE Receive;
VAR  name: ARRAY 32 OF CHAR;
  F: Files.File; R: Files.Rider;
  f, i, j: INTEGER; ch: CHAR;
BEGIN
  i := 1;
  Host.GetArg( 1, name); 
  WHILE name # "" DO
    Host.LogS(" "); Host.LogS(name);
    f := Host.Open( name, FALSE, FALSE);
    IF f > 0 THEN
      F := Files.New( name); Files.Set(R, F, 0);
      f := Host.Open( name, FALSE, FALSE); j := Host.Read( f, SYSTEM.ADR(ch), 1);
      WHILE j = 1 DO Files.Write( R, ch);  j := Host.Read( f, SYSTEM.ADR(ch), 1) END;
      f := Host.Close( f); Files.Register( F);
    ELSE Host.LogS(" failed");
    END;
    INC(i); Host.GetArg( i, name); 
    END;
END Receive;

PROCEDURE Send;
VAR  name:  ARRAY 32 OF CHAR;
  F: Files.File; R: Files.Rider;
  f, i, j: INTEGER; ch: CHAR;
BEGIN
  i := 1;
  Host.GetArg( 1, name); 
  WHILE name # "" DO
    Host.LogS(" "); Host.LogS(name);
    F := Files.Old( name); 
    IF F # NIL THEN Files.Set(R, F, 0); Files.Read( R, ch);
      f := Host.Open( name, TRUE, TRUE);
      WHILE ~R.eof DO j := Host.Write( f, SYSTEM.ADR(ch), 1); Files.Read( R, ch) END;
      f := Host.Close( f);
    ELSE Host.LogS(" failed");
    END;
    INC(i); Host.GetArg( i, name); 
    END;
END Send;

BEGIN
  Host.Init; Files.Init;
  Host.GetArg(0, name); Host.LogS(name);
  IF name = "./pcsend.elf" THEN Send
  ELSIF name = "./pcreceive.elf" THEN Receive
  ELSE
  END;
  Host.LogL;
  Host.Exit(0);
END pcsend.