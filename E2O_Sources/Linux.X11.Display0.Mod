MODULE Display0;  
IMPORT SYSTEM, Host;
(* 
  2024-09-13  fixed cursor keys
  2024-09-14  Host interface
  2024-09-20  removed mmap in Getauth, made SHM default
  2024-11-20  added DEL-key
  2024-11-23  Exit when poll returns true but no input available (e.g. because window closed)
  2024-11-29  OpenDisplay: fixed call of Host.GetEnv("SSH_CONNECTION", bdata)
  2024-11-30  correct display No over SSH connection used for port
  2024-11-30  Poll: made more responsive
  2024-12-17  removed BIG-REQUESTS, made wv (WriteVector) local to PutImage

PutImage
GetImage
CopyArea
PolyFillRectangle

*)

CONST
  WindowName="Embedded Extended Oberon xxx"; WindowNameLength=28; WindowNameWords= (WindowNameLength+3) DIV 4;

  Bytes = 4; TRACE = FALSE;
  TimeOut= 10;  (* in ms *)

(* default window size *)

  defaultWidth= 1280  - 16 ;  
  defaultHeight= 1024  - 32;
  
(* X11 *)
  X11SOCKETPATH="xx/tmp/.X11-unix/X0";  (* first two dummy chars, space for protocol type *)
  CURRENTTIME = 0;
  XAPRIMARY = 1;
  XASTRING = 31;

  Shift = 0; Lock = 1; Control = 2; NumLock = 4; Win = 6; Alt = 7;

TYPE
    SetupRes0= RECORD a, b: INTEGER END;  (*  res, n: CHAR; major, minor: INTEGER;  len: INTEGER;  *)

    SetupRes1= RECORD
        rnr, ridbase, ridmask, motionbuffersize: INTEGER;
        lenvendormaxreqlen: INTEGER;
        noscreens, noformats: CHAR;
        imgbyteorder, bmbitorder: CHAR;
        scanliunrunit, scanlinepad: CHAR;
        minkeycode, maxkeycode: BYTE;
        pad: LONGINT;
    END;
    Format= RECORD
        depth, bpp, slpad, pad0: CHAR;
        pad1: INTEGER;
    END;
    Screen= RECORD
        root, dcolormap, wpixel, bpixel: LONGINT;
        cimasks: LONGINT;
        widthheight: LONGINT;
        wmmhmm: LONGINT;
        minimapsmaximaps: LONGINT;
        rvisual: LONGINT;
        bstores, sunders, rdepth, ndepth: CHAR;
    END;
    DepthT= RECORD a, pad: INTEGER END;  (*  depth, pad0: CHAR; nvisualtypes: INTEGER; pad: LONGINT;  *)

    VisualT= RECORD
        id: LONGINT;
        cbc: LONGINT;  (* class, bprgbvalue: BYTE, cmapentries: INTEGER; *)
        rmask, gmask, bmask: LONGINT;
        pad: LONGINT;
    END;
(* Input *)
  Event= RECORD  (* code, detail: CHAR;sequence: INTEGER; time, a, b, c, d: LONGINT;ex, ey: INTEGER; f: LONGINT; *)
        cds: LONGINT;
        time, a, b, c, d: LONGINT;
        exey: LONGINT;
        f: LONGINT;
  END;

  KeymapArray = ARRAY  OF INTEGER;

VAR 
  Keymap: POINTER TO KeymapArray;

  DisplayBase, DisplayWidth, DisplayHeight, Zoom: INTEGER;

  mkeys: SET;
  mouseX, mouseY: INTEGER;

  cb1, cb2: INTEGER;
  buf: ARRAY 32 OF CHAR; (* input char buffer *)
  kkeys: SET;
  
(* X11 *)
  X11fd, Xdisplay, tcp: INTEGER;  (* X11 socket *)
  scnrdepth, scnroot, gcid, wid, shmseg: INTEGER;
  ShmReqCode, shmid: INTEGER;
  r1data: SetupRes1;

  xkspkc: INTEGER;
  X11err, myProperty, clip: INTEGER;

(* Graphics functions *)

PROCEDURE XPutImage*( adr, x, y, w, h: INTEGER);
CONST PutImage = 72;
VAR res : INTEGER; b: ARRAY 6 OF INTEGER;
BEGIN
  b[ 0]:= PutImage + 2 * 100H + ( 6 + w * h) * 10000H;  (* length *)
  b[ 1]:= wid;
  b[ 2]:= gcid;
  b[ 3]:= DisplayWidth + DisplayHeight * 10000H;  (* total w h*)
  b[ 4]:= x + (DisplayHeight - h - y) * 10000H;  (* dst x y *)
  b[ 5]:= 0+scnrdepth*100H;
  res:= Host.Write( X11fd, SYSTEM.ADR(b), 6*4);
  res:= Host.Write( X11fd, adr, w * h * 4);
END XPutImage;

PROCEDURE XGetImage*( adr, x, y, w, h: INTEGER);
CONST GetImage = 73;
VAR res : INTEGER; b: ARRAY 8 OF INTEGER;
BEGIN
  b[ 0]:= GetImage + 2 * 100H + 5 * 10000H;  (* length *)
  b[ 1]:= wid;
  b[ 3]:= x + (DisplayHeight - h - y) * 10000H;  (* dst x y *)
  b[ 4]:= DisplayWidth + DisplayHeight * 10000H;  (* total w h*)
  b[ 5]:= 00FFFFFFH; (* planemask *)
  res:= Host.Write( X11fd, SYSTEM.ADR(b), 5 * 4);
  res:= Host.Read( X11fd, SYSTEM.ADR(b), 32);
  res:= Host.Read( X11fd, adr, w * h * 4);
END XGetImage;

PROCEDURE XCopyArea*( sx, sy, dx, dy, w, h: INTEGER);
CONST CopyArea = 62;
VAR res : INTEGER; b: ARRAY 8 OF INTEGER;
BEGIN
  b[ 0]:= CopyArea + 7 * 10000H;
  b[ 1]:= wid;
  b[ 2]:= wid;
  b[ 3]:= gcid;
  b[ 4]:= sx + (DisplayHeight - h - sy) * 10000H;  (* src x y *)
  b[ 5]:= dx + (DisplayHeight - h - dy) * 10000H;  (* src x y *)
  b[ 6]:= w + h * 10000H;  (* src w h *)
  res:= Host.Write( X11fd, SYSTEM.ADR(b), 28);
END XCopyArea;

PROCEDURE XPolyFillRectangle*( x, y, w, h, col, mode: INTEGER);
CONST PolyFillREctangle = 70;
VAR res : INTEGER; b: ARRAY 8 OF INTEGER;
BEGIN
  b[ 0]:= PolyFillREctangle + 5 * 10000H;
  b[ 1]:= wid;
  b[ 2]:= gcid;
  b[ 3]:= x + (DisplayHeight - h - y) * 10000H;  
  b[ 4]:= w + h * 10000H;  (* src x y *)
  res:= Host.Write( X11fd, SYSTEM.ADR(b), 20);
END XPolyFillRectangle;

(* Input *)
PROCEDURE Avail( fd, timeout: INTEGER): BOOLEAN;
BEGIN  RETURN Host.Ppoll( fd , timeout) > 0
END Avail;

PROCEDURE GetSym(detail, state: LONGINT): LONGINT;
VAR sym: LONGINT;
BEGIN
  sym:=0;
  IF detail#ORD(r1data.minkeycode) THEN sym:= Keymap[ (detail-ORD(r1data.minkeycode))*xkspkc+ state] END;
  RETURN sym
(*
  sym:= (detail-ORD(r1data.minkeycode))*xkspkc;
  IF (state MOD 4 #0) & (sym#196H) & (sym#244H) THEN INC( sym) END;
  IF ODD(state DIV 128) THEN INC( sym, 4) END;  (* ALT was 2 *)
  RETURN Keymap[ sym, state];
*)
END GetSym;

PROCEDURE Poll( wait: INTEGER);
VAR
  detail, code, state, sym, i, res: LONGINT;
  event: Event;
  c: CHAR;
BEGIN
  WHILE Avail( X11fd, wait) DO
    res:=Host.Read( X11fd, SYSTEM.ADR(event),  32);
    IF res=32 THEN  
      code:= event.cds MOD 32;
      detail:= event.cds DIV 100H MOD 100H;
      IF code=2 THEN    (* KeyPress *)
        state:=event.f MOD 10000H;
        IF state MOD 8 = 2 THEN state:=1;
        ELSIF state MOD 8 =3 THEN state:=2;
        ELSIF ODD(state DIV 10H) & (detail>=4DH) & (detail<=5BH) THEN state:=1;  (* Num-Lock *)
        ELSIF ODD(state DIV 80H) THEN state:= 4;
        ELSIF state>=7 THEN  Host.LogS("X11: event.state:"); Host.LogH( event.f ); Host.LogL; state:= state MOD 8;
        END;
        sym:=GetSym(detail, state);
        IF TRACE THEN 
          Host.LogS("detail:"); Host.LogH( detail); Host.LogL; Host.LogS("symbol:"); Host.LogH( sym); Host.LogL; Host.LogS("state :"); Host.LogH( event.f); Host.LogL;
        END;
        c:= CHR( sym MOD 100H);
        IF detail=024H THEN c:=0DX;  (* cr (enter) *)
        ELSIF detail= 6FH THEN c:=0C1X; c:= 10X;  (* ^ *)
        ELSIF detail= 71H THEN c:=0C4X; c:= 02X;  (* <- *)
        ELSIF detail= 74H THEN c:=0C2X; c:= 0EX;  (* v *)
        ELSIF detail= 72H THEN c:=0C3X; c:= 06X;  (* -> *)
        ELSIF (detail=25H) OR (detail=69H) THEN
          INCL( kkeys, Control); c:=0X;
        ELSIF sym=0FE52H THEN c:=5EX;    (* ^ *)
        ELSIF sym=0FE53H THEN c:= 7EX;    (*  ntilde  *)
        ELSIF sym=0FE03H THEN c:= 0X;    (*  Alt Gr  *)
        ELSIF sym >=0FF00H THEN
          c:=0X;
          sym:=sym MOD 100H;
          IF sym=063H THEN c:=0A0X;  (* ins *) END;
          IF sym=050H THEN c:=0A8X;  (* home *) END;
          IF sym=055H THEN c:=0A2X;  (* pg-up *) END;
          IF sym=0FFH THEN c:=07FX;  (* del-key 0A1X*) END;
          IF sym=057H THEN c:=0A9X;  (* end *) END;
          IF sym=056H THEN c:=0A3X;  (* pg-down *) END;
              
          IF sym=008H THEN c:=08X;  (* backspace *) END;
          IF sym=01BH THEN c:=1BX;  (* Esc=1BX, Oberon.Neutralise=0A5X *) END;
          IF sym=009H THEN c:= 09X;  (* Tab *) END;

          IF sym DIV 2=0BEH DIV 2 THEN c:=CHR(01AH+sym MOD 2);  (* F1, F2 *) END;
          IF sym DIV 2=0C0H DIV 2 THEN c:=CHR(0A6H+sym MOD 2);  (* F3, F4 *) END;
          IF (sym>=0C2H) & (sym<=0C9H) THEN                    (* F5 ..F12 ; F7= redraw screen*)
            c:=CHR(sym-0C2H+0F5H)
          END;
      (* keypad *)
          IF sym=0AFH THEN c:="/";  (* / *) END;
          IF sym=0AAH THEN c:="*";  (* * *) END;
          IF sym=0ADH THEN c:="-";  (* - *) END;
          IF sym=0ABH THEN c:="+";  (* + *) END;
          IF sym=0ACH THEN c:=",";  (* , *) END;
          IF sym=09FH THEN c:=0A1X;  (* del *) END;
          IF (sym>=0B0H) & ( sym <=0B9H) THEN  (* 0..9 *)
            c:= CHR(sym MOD 16 + ORD("0"));
          END;
          IF sym=08DH THEN c:=0DX;  (* enter *) END;
          IF sym=097H THEN c:=0C1X;  (* ^ *) END;
          IF sym=096H THEN c:=0C4X;  (* <- *) END;
          IF sym=099H THEN c:=0C2X;  (* v *) END;
          IF sym=098H THEN c:=0C3X;  (* -> *)END;

        ELSE
          IF c=0DFX THEN c:= 96X END;    (*  ñ  *)
          IF c=0E1X THEN c:= 94X END;    (*  aacute  *)
          IF c=0E7X THEN c:= 93X END;    (*  ccedilla  *)
          IF c=0EFX THEN c:= 92X END;    (*  idiaeresis  *)
          IF c=0EBX THEN c:= 91X END;    (*  ediaeresis  *)
          IF c=0E9X THEN c:= 90X END;    (*  eacute  *)
          IF c=0F9X THEN c:= 8FX END;    (*  ugrave  *)
          IF c=0F2X THEN c:= 8EX END;    (*  ograve  *)
          IF c=0ECX THEN c:= 8DX END;    (*  igrave  *)
          IF c=0E8X THEN c:= 8CX END;    (*  egrave  *)
          IF c=0E0X THEN c:= 8BX END;    (*  agrave  *)
          IF c=0FBX THEN c:= 8AX END;    (*  ucircumflex  *)
          IF c=0F4X THEN c:= 89X END;    (*  ocircumflex  *)
          IF c=0EEX THEN c:= 88X END;    (*  icircimflex  *)
          IF c=0EAX THEN c:= 87X END;    (*  ecircumflex  *)
          IF c=0E2X THEN c:= 86X END;    (*  acircumflex  *)
          IF c= 0FCX THEN c:= 85X END;    (*  Ö; must be 0xyz if c is  unsigned *)
          IF c= 0F6X THEN c:= 84X END;    (*  Ñ  *)
          IF c= 0E4X THEN c:= 83X END;    (*  É  *)
          IF c= 0DCX THEN c:= 82X END;    (*  Ç  *)
          IF c= 0D6X THEN c:= 81X END;    (*  Å  *)
          IF c= 0C4X THEN c:= 80X END;    (*  Ä  *)
        END;

        IF sym=0AFEH THEN (*Paste;   ctrl-v *)
        ELSIF c#0X THEN
          buf[ cb2 MOD 32]:= c;
          INC( cb2);
        END;
      ELSIF code= 3 THEN  (* KeyRelease *)
        IF (detail=25H) OR (detail=69H) THEN
          EXCL(kkeys, Control);
        END;
      ELSIF code= 4 THEN  (* ButtonPress *)
        IF detail<4 THEN
          INCL( mkeys, 3- detail);
        END;
      ELSIF code= 5 THEN
        IF detail<4 THEN  (* ButtonRelease *)
          EXCL( mkeys, 3- detail);
        END;
      ELSIF code= 6 THEN  (* MotionNotify, absolute values *)
        mouseX:= LSL(event.exey, 16) DIV 10000H;  (* keep sign *)
        mouseY:= event.exey DIV 10000H;
        IF mouseX < 0 THEN  mouseX := 0 END;
        IF mouseY < 0 THEN  mouseY := 0 END;
        IF mouseX >= DisplayWidth THEN  mouseX := DisplayWidth - 1 END;
        IF mouseY >= DisplayHeight THEN  mouseY := DisplayHeight - 1 END;
      ELSIF code = 11 THEN  (* KeymapNotify*)
        Host.LogS("KeymapNotify");
      ELSIF code= 12 THEN  (* Expose check if Event.b MOD 10000H can be negative*)
(*
        PutImage( event.a MOD 10000H, DisplayHeight-(event.b + event.a) DIV 10000H, 
          event.b MOD 10000H, event.b DIV 10000H);
*)
      ELSIF code=14 THEN   (*  NoExposure *)
      ELSIF code=15 THEN   (* VisibilityChange *)
      ELSIF code= 28 THEN    (* PropertyNotify *)
      ELSIF code = 29 THEN  (* SelectionClear *)
        Host.LogS("ClearSelection");
(*        selection:=NIL;  *)
      ELSIF code= 30 THEN  (* SelectionRequest, SendSelection *)
(*
        IF (CopyClip # NIL) & (event.a#event.b) THEN CopyClip;
          SendSelection( event);
          clip:=0;
        END;
*)
      ELSIF code= 31 THEN  (* SelectionNotify, ReceiveSelection *)
(*        IF PasteClip# NIL THEN
          ReceiveSelection( event);
          PasteClip;
          clip:=NIL;
        END;*)
      ELSIF code = 0 THEN  (* error *)
        IF X11err < 32  THEN
          Host.LogS("PollX: Received error no."); Host.LogH( detail); Host.LogL;
          Host.LogS("PollX: error."); Host.LogH( event.time); Host.LogL;
          Host.LogS("PollX: opcode."); Host.LogH( event.a); Host.LogL;
          INC(X11err);
        END;
(*        IF detail = 0 THEN Host.Exit( 1) END; *)
      ELSE
        Host.LogS("Event code..."); Host.LogH( code); Host.LogL;
        Host.LogS("Event detail..."); Host.LogH( detail); Host.LogL;
      END;
(*    ELSE
      LogSH("Res Error...", res);*)
    ELSIF res = 0 THEN Host.Exit( 1);
    END;
    wait := 0;
  END
END Poll;

PROCEDURE Available*( wait: INTEGER): INTEGER;  (* res negative: mouse+binary inverted characters; res positive: numbers of Char *)
BEGIN
  RETURN (cb2-cb1)
END Available;

PROCEDURE Mouse*(VAR keys: SET; VAR x, y: INTEGER);
BEGIN Poll( TimeOut);
  keys:= mkeys; 
  x:= ASR(mouseX, Zoom -1)  ; 
  y:= ASR(DisplayHeight-1-mouseY, Zoom -1);
END Mouse;

PROCEDURE Char*( ): CHAR;
BEGIN
  WHILE cb2<= cb1 DO Poll( TimeOut) END;
  INC( cb1);
  RETURN buf[ (cb1-1) MOD 32]
END Char;

PROCEDURE PutImage*( x, y, w, h: INTEGER);
CONST size = 16;  (* data in singel X11 command can be 4* 64KB *)
VAR i, j, res, wl, adr: INTEGER;  b: ARRAY 10 OF INTEGER; wv: ARRAY 4*size+4 OF INTEGER;
BEGIN
  IF x < 0 THEN INC(w, x); x := 0 END;
  IF y < 0 THEN INC(h, y); y := 0 END;
  IF (w > 0) & (h > 0) THEN
    IF ShmReqCode = 0 THEN  (* NO SHM *)
      wl:= w * Bytes;
      y:= DisplayHeight - (h + y);
      b[ 1]:= wid;
      b[ 2]:= gcid;
      b[ 5]:= 0+scnrdepth*100H;
      i := h MOD size;
      IF i = 0 THEN i := size END;
      adr := DisplayBase+ (x + y * DisplayWidth) * Bytes;
      IF Host.versionkey < 40X THEN
        wv[0] := SYSTEM.ADR(b);
        wv[1] := 24;
        REPEAT j := 2; 
          b[ 0]:= 72 + 2 * 100H + (i * w + 6) * 10000H;    (* no BIG-REQUESTS *)
          b[ 3]:= w + i * 10000H;
          b[ 4]:= x + y * 10000H; INC( y, i);
          REPEAT
            wv[ j ] := adr; INC(adr, DisplayWidth * Bytes);
            wv[ j + 1] := wl; INC( j, 2); DEC( h); 
          UNTIL h MOD size = 0;
          res:=Host.Writev( X11fd, SYSTEM.ADR(wv), i + 1); i:= size;
        UNTIL h <= 0;
      ELSE
        wv[0]:= SYSTEM.ADR(b);  wv[1]:= 0;
        wv[2]:= 24;  wv[3]:= 0;
        i:= h MOD size;  (* i must be < writev max iovcnt and (i * wl) < max X11 request sizze *)
        IF i = 0 THEN i := size END;
        REPEAT j := 4; 
          b[ 0] := 72 + 2 * 100H + (i * w + 6) * 10000H;
          b[ 3] := w + i * 10000H;
          b[ 4] := x + y * 10000H; INC( y, i);
          REPEAT
(*        32/64 bit ADR *)
            wv[j ] := adr; wv[j + 1] := 0;  INC(adr, DisplayWidth * Bytes);
            wv[j + 2] := wl; wv[j + 3] := 0; INC( j, 4); DEC( h); 
          UNTIL h MOD size = 0;
          res:= Host.Writev( X11fd, SYSTEM.ADR(wv), i+1); i:= size;
        UNTIL h<=0;
      END;
    ELSIF ShmReqCode > 0 THEN
      b[ 0]:= ShmReqCode+3*100H+10*10000H;  (* XShmPutImage = 3 *)
      b[ 1]:= wid;
      b[ 2]:= gcid;
      b[ 3]:= DisplayWidth + DisplayHeight * 10000H;  (* total w h*)
      b[ 4]:= x + (DisplayHeight - h - y) * 10000H;  (* src x y *)
      b[ 5]:= w + h * 10000H;  (* src w h *)
      b[ 6]:= b[4];  (* dst x y *)
      b[ 7]:= scnrdepth + 2 (* ZPixmap=2 *) * 100H ;    (* depth, format, sendevent, bpad *) 
      b[ 8]:= shmseg;    (* shmseg *)
      b[ 9]:= 0H;    (* offset *)
      res:= Host.Write( X11fd, SYSTEM.ADR(b), 40);
    END;
  END;
END PutImage;

PROCEDURE KeyboardMapping;
VAR b: ARRAY 8 OF LONGINT;
  res, i, j: LONGINT;
BEGIN
  WHILE Avail(X11fd, 0) DO res:= Host.Read( X11fd, SYSTEM.ADR(b[0]), 32) END;
  b[ 0]:= 101+2*10000H;
  b[ 1]:= ORD(r1data.minkeycode)+(ORD(r1data.maxkeycode)-ORD(r1data.minkeycode))*100H;
  res:= Host.Write( X11fd, SYSTEM.ADR(b[0]), 8);
  res:= Host.Read( X11fd, SYSTEM.ADR(b[0]), 32);

  xkspkc:= (b[0] DIV 100H) MOD 100H;    (* line 1552 on ARM *)
  IF b[1] DIV 10000H #0 THEN Host.LogS("Internal X11 server error, should exit"); Host.LogH( b[1]); Host.LogL END;  
  NEW( Keymap, b[1] );
  res:= Host.Read( X11fd, SYSTEM.ADR(Keymap[0]), b[ 1]*4);
  IF TRACE THEN Host.LogS("keysyms-per-keycode:"); Host.LogH( xkspkc); Host.LogL END;
END KeyboardMapping;

PROCEDURE InternAtom(): LONGINT;
VAR b: ARRAY 8 OF LONGINT; res: LONGINT;
BEGIN
  b[0]:=16+ 6*10000H;
  b[1]:= 14;
  SYSTEM.COPY( SYSTEM.ADR( "OberonProperty"), SYSTEM.ADR(b[ 2]), 4 (* was 14 *) );
  res:=Host.Write( X11fd, SYSTEM.ADR(b),  24);
  res:=Host.Read( X11fd, SYSTEM.ADR(b),  32);
  IF TRACE THEN Host.LogS("OberonProperty = "); Host.LogH( b[2]); Host.LogL END;
  RETURN b[2]
END InternAtom;

PROCEDURE GetAuth(VAR s: ARRAY OF CHAR): BOOLEAN;
VAR c, c2 : CHAR; ret: BOOLEAN;
  res, disp2, afd, adr, i2, j: INTEGER; n0, n1: BYTE; 
  t, t2: ARRAY 256 OF CHAR;
  buf: ARRAY 4096 OF BYTE;
BEGIN
  IF ~Host.GetEnv("XAUTHORITY", t) THEN  (* use default *)
    IF Host.GetEnv("HOME", t) THEN END;
    i2:=0;
    WHILE t[i2]#0X DO INC(i2) END;
    j:=0;
    t2:="/.Xauthority";
    WHILE t2[j]#0X DO t[i2]:=t2[j]; INC(i2); INC(j) END;
     t[i2]:=0X;
  END;
(*
  IF Host.GetEnv("DISPLAY", t2) THEN END;
  i2:=0;
  WHILE (t2[i2]#0X) & (t2[i2]#":") DO INC(i2) END;  (* skip adr *)
  disp1:=0; INC(i2);
  WHILE (t2[i2]>="0") & (t2[i2]<="9") DO disp1:=disp1*10+ORD(t2[i2])-ORD("0"); INC(i2) END;
*)
  afd:= Host.Open( t, FALSE, FALSE);
  ret:= FALSE;
  IF afd<=0 THEN Host.LogS("Can't open Xauth file "); Host.LogS(t); Host.LogL
  ELSE
    j:= Host.Size( afd);
    IF (j>=5) & (j<=4096) THEN 
      IF TRACE THEN Host.LogS("opening Xauth file: "); Host.LogS(t); Host.LogS(" disp1= "); Host.LogH( Xdisplay); Host.LogL END;
      adr := SYSTEM.ADR( buf);
      res:= Host.Read( afd, adr, j);
      IF res = j THEN
        n0:=10;
        WHILE ~ ret & (n0>0) DO
          INC(adr, 2);
          DEC(n0);
          REPEAT INC(adr); SYSTEM.GET(adr, c) UNTIL c#0X;
          INC(adr, ORD(c));        (* skip name *)
          REPEAT INC(adr); SYSTEM.GET(adr, n1) UNTIL n1#0;
          disp2:=0;
          WHILE n1>0 DO INC(adr); SYSTEM.GET(adr, c); disp2:=disp2*10+ORD(c)-ORD("0"); DEC(n1) END;
          IF TRACE THEN Host.LogS("disp2= "); Host.LogH( disp2); Host.LogL END;
          REPEAT INC(adr); SYSTEM.GET(adr, c) UNTIL c#0X;
          IF Xdisplay = disp2 THEN
            IF c=12X THEN  (* MIT-MAGIC-COOKIE-1 *)  
              s[ 6]:= c;
              i2:=ORD(c);
              j:=12;
              REPEAT
                INC(adr);
                SYSTEM.GET(adr, c2);
                s[j]:= c2;
                INC(j); DEC(i2);
              UNTIL i2=0;
              REPEAT INC(adr); SYSTEM.GET(adr, c) UNTIL c#0X;
              s[ 8]:= c;
              i2:=ORD(c);
              j:= 32;
              REPEAT
                INC(adr);
                SYSTEM.GET(adr, c2);
                s[j]:= c2;
                INC(j); DEC(i2);
              UNTIL i2=0;
              ret:= TRUE;
            END;
          ELSE  (* disp1 # disp2 *)
            INC(adr, ORD(c));        (* skip protocol *)
            REPEAT INC(adr); SYSTEM.GET(adr, c) UNTIL c#0X;
            INC(adr, ORD(c));        (* skip cookie *)
          END;
        END; (*WHILE*)
      ELSE Host.LogS("Display.GetAuth read failed "); Host.LogH(-adr); Host.LogL;  
      END;
    ELSE Host.LogS("Display.GetAuth status failed "); Host.LogH( -adr); Host.LogL;
    END;
    afd:=Host.Close(afd)
  END;
  RETURN ret
END GetAuth;   

PROCEDURE Str2Int( str: ARRAY OF CHAR): INTEGER;
VAR i, j: INTEGER; neg: BOOLEAN;
BEGIN
  i:=0;
  IF str#"" THEN
    j:=0;
    neg:=str[0]="-";
    IF neg THEN j:=1 END;
    WHILE (j<LEN(str)) & (str[j]>="0") & (str[j]<="9") DO
      i:=i*10+ORD(str[j])-ORD("0");
      INC(j);
    END;
    IF neg THEN i:=-i END;
  END;    
  RETURN i
END Str2Int;

PROCEDURE X11Err( n: LONGINT);
VAR b: ARRAY 8 OF LONGINT; i, res: LONGINT;
BEGIN
  IF Avail( X11fd, 0) THEN
    res:= Host.Read( X11fd, SYSTEM.ADR(b), 32);
    Host.LogS("ERROR: X11Err:"); Host.LogH( n); Host.LogL;
    FOR i:=0 TO 7 DO
      Host.LogS("X11Err:"); Host.LogH( b[i]); Host.LogL
    END;
  END;
END X11Err;

PROCEDURE QueryExtension( name: ARRAY OF CHAR; VAR opcode: LONGINT);
VAR xr: ARRAY 32 OF CHAR; i, res:LONGINT; b: ARRAY 8 OF LONGINT;
BEGIN;
  xr[0]:= 62X; xr[1]:= 0X;  (* 62X=98D *)
  xr[2]:= CHR((LEN( name)+2) DIV 4+2); xr[3]:= 0X;
  xr[4]:= CHR(LEN( name)-1); xr[5]:= 0X;
  xr[6]:= 0X; xr[7]:= 0X;
  i:=0;
  REPEAT
    xr[8+i]:= name[i];
    INC(i);
  UNTIL i=LEN(name);
  res:=Host.Write( X11fd, SYSTEM.ADR(xr), ORD(xr[2])*4);
  res:=Host.Read( X11fd, SYSTEM.ADR(b), 32);
  opcode:= b[2] DIV 100H MOD 100H;
  IF TRACE THEN Host.LogS( name); Host.LogH( opcode); Host.LogL END;
END QueryExtension;

PROCEDURE OpenWindow;
VAR b: ARRAY 24 OF LONGINT; i, cid, pid, gcpid, iwid, res: LONGINT; str: ARRAY 8 OF CHAR;
BEGIN
  iwid:= r1data.ridbase+11235H;
  pid:= iwid+1;  gcpid:=pid+1;
  cid:= gcpid+1;  wid:= cid+1;
  gcid:=wid+1;  shmseg:=gcid+1;

(* use MIT-SHM if available *)
  ShmReqCode:=0;
  IF ~Host.GetEnv("OSHM", str) & ( tcp = 0) THEN QueryExtension("MIT-SHM", ShmReqCode) END;
  IF ShmReqCode = 0 THEN
    Host.LogS( "No MIT-SHM"); Host.LogL;
    DisplayBase:= Host.Mmap( DisplayWidth * DisplayHeight * Bytes );
  ELSE
    shmid:= Host.Shmget( 0, DisplayHeight * DisplayWidth * Bytes, 3FFH);
    DisplayBase:= Host.ShmAt(shmid, 0, 0);  
    b[ 0]:= ShmReqCode + 1 * 100H + 4 * 10000H;  (* X_ShmAttach = 1 *)
    b[ 1]:= shmseg; (*ShmSeg;*)
    b[ 2]:= shmid;
    b[ 3]:= 0;
    res:=Host.Write( X11fd, SYSTEM.ADR(b), 16);
    X11Err(8);
  END;
  IF TRACE THEN Host.LogS("shmid= "); Host.LogH( shmid); Host.LogL; Host.LogS("ShmReqCode = "); Host.LogH( ShmReqCode); Host.LogL END;

(* needed create win for cursor pixmap *)
  b[ 0]:= 1+0*100H+8*10000H;
  b[ 1]:= iwid;
  b[ 2]:= scnroot;
  b[ 3]:= 0+0*10000H;
  b[ 4]:= 1+1*10000H;
  b[ 5]:= 0+2*10000H;
  b[ 6]:= 0;
  b[ 7]:= 0;
  res:= Host.Write(  X11fd, SYSTEM.ADR(b), 32);
  X11Err(1);

(* needed create pixmap for cursor *)
  b[ 0]:=53+ 1*100H+4*10000H;
  b[ 1]:= pid;
  b[ 2]:= iwid;
  b[ 3]:= 1+1*10000H;
  res:= Host.Write( X11fd, SYSTEM.ADR(b), 16);
  X11Err(2);
(*
(* create gc for cursor pixmap *)
  b[ 0]:= 55+4*10000H;
  b[ 1]:= gcpid;
  b[ 2]:= iwid;
  b[ 3]:= 0;
  res:=Host.Write0( fd, SYSTEM.ADR(b), 16);
  WriteSH("create gc ", res);

(* ClearArea, draw cursor *)
  b[ 0]:= 61+4*10000H;
  b[ 1]:= iwid;
  b[ 2]:= 0+0*10000H;
  b[ 3]:= 1+1*10000H;
  res:=Host.Write0( fd, SYSTEM.ADR(b), 16);
  WriteSH("create dc ", res);
*)
(* needed create cursor *)
  b[ 0]:= 93+8*10000H;
  b[ 1]:= cid;
  b[ 2]:= pid;
  b[ 3]:= pid;
  b[ 4]:= 0FFFFFFFFH;
  b[ 5]:= 0;
  b[ 6]:= 0FFFFFFFFH;
  b[ 7]:= 0;
  res:= Host.Write( X11fd, SYSTEM.ADR(b), 32);
  X11Err(3);

  (* CreateWindow *)
  b[ 0]:= 1+scnrdepth*100H+10*10000H;
  b[ 1]:= wid;
  b[ 2]:= scnroot;
  b[ 3]:= 0;  (* x+y*10000H;*)
  b[ 4]:= DisplayWidth+DisplayHeight*10000H;
  b[ 5]:= 1+0*10000H;
  b[ 6]:= 0;      (*visual, was 0*)
  b[ 7]:= 4800H;  (* value-mask: was 4800H, Cursor=4000H, Event Mask=800H ToDo: AddBackgroundPixmap??*)
(*  b[ 8]:= 40804FH;  (* was 804FH  todo: EventMask *)*)
  b[ 8]:= 0804FH;
  b[ 9]:= cid;    (* was cid Cursor , 0=default cursor*)
  res:= Host.Write( X11fd, SYSTEM.ADR(b), 40);
  X11Err(4);
  (* CreateGC *)
  b[ 0]:= 55+4*10000H;
  b[ 1]:= gcid;
  b[ 2]:= wid;
  b[ 3]:= 0;
  res:= Host.Write( X11fd, SYSTEM.ADR(b),  16);
  X11Err(7);

(* ChangeProperty name Window *)
  b[ 0]:= 18+0*100H+(6+WindowNameWords)*10000H;
  b[ 1]:= wid;
  b[ 2]:= 39;  (* WM_NAME *)
  b[ 3]:= 31;  (* String *)
  b[ 4]:= 8;
  b[ 5]:= WindowNameLength;  (* no. of characters *)
  SYSTEM.COPY( SYSTEM.ADR( WindowName), SYSTEM.ADR(b[ 6]), WindowNameWords );
  b[12] := ORD(" ") + ORD(Host.appendix[1])* 100H + ORD(Host.appendix[2])* 10000H + ORD(Host.appendix[3])*1000000H;
  res:=Host.Write( X11fd, SYSTEM.ADR(b),  (6+WindowNameWords)*4);
  X11Err(5);

(* Change Property disable resize *)
  b[ 0]:= 18+0*100H+24*10000H;
  b[ 1]:= wid;
  b[ 2]:= 40;  (* WM_Normal_Hints=40 *)
  b[ 3]:= 41;  (* WM_SIZE_Hints=41 *)
  b[ 4]:= 32;
  b[ 5]:= 18;
  b[ 6]:= 038H; (* location, programm specified size, minsize, maxsize *)
  b[ 7]:= 0;  (* b[7]..b[ 10] is ignored *)
  b[ 8]:= 0;
  b[ 9]:= DisplayWidth;
  b[ 10]:= DisplayHeight;
  b[ 11]:= b[ 9];
  b[12]:= b[10];
  b[13]:= b[ 9];
  b[14]:= b[10];
  b[ 15]:= 0;
  b[ 16]:= 0;
  b[ 17]:= 0;
  b[ 18]:= 0;
  b[ 19]:=0;
  b[ 20]:=0;
  b[ 21]:=0;
  b[ 22]:=0;
  b[ 23]:=0;
  res:=Host.Write( X11fd, SYSTEM.ADR(b),  96);
  X11Err(6);

(* MapWindow *)
  b[ 0]:= 8+2*10000H;
  b[ 1]:= wid;
  res:=Host.Write( X11fd, SYSTEM.ADR(b),  8);
(*  generates exposure event: X11Err(9);*)
  Poll(0);

END OpenWindow;

PROCEDURE CloseWindow;  (* not used ? *)
VAR b: ARRAY 2 OF LONGINT;
  res: LONGINT;
BEGIN
(* Bell *)  
  b[ 0]:= 104+ 1*100H+1*10000H;
  res:=Host.Write( X11fd, SYSTEM.ADR(b),  4);
(* unmap *)
  b[0]:= 10+2*10000H;
  b[1]:= wid;
  res:=Host.Write( X11fd, SYSTEM.ADR(b), 8);
  Host.LogS("Closing Display"); Host.LogL
END CloseWindow;

PROCEDURE OpenDisplay*( VAR Width, Height: INTEGER; zoom: INTEGER): INTEGER;
VAR  i, w, h, res, lw, r0datares, r0datalen, sw, sh, depthnvisualtypes, port: LONGINT;
  r0data: SetupRes0;
  format: Format;
  depth: DepthT;
  visual: VisualT;
  b : ARRAY 4 OF INTEGER;
  bdata: ARRAY 64 OF CHAR;
  sa1: ARRAY 64 OF CHAR;
  adata: ARRAY 128 OF CHAR;
  scn: Screen;
BEGIN
  Zoom := zoom;
  X11err:=0;
  tcp :=0;
  myProperty:=-1;
  cb1:=0; cb2:=0;

  Xdisplay := 0; i := 0;
  IF Host.GetEnv("DISPLAY", adata) THEN
    i:=0;
    WHILE (adata[i]#0X) & (adata[i]#":") DO INC(i) END;  (* skip adr *)
    INC(i);
    WHILE (adata[i]>="0") & (adata[i]<="9") DO Xdisplay :=Xdisplay * 10 + ORD(adata[i])-ORD("0"); INC(i) END;
  END;

  IF ~Host.GetEnv("SSH_CONNECTION", bdata) THEN
    X11fd := Host.Socket( Host.PFUNIX);
    IF TRACE THEN Host.LogS("Socket no.: "); Host.LogH( X11fd); Host.LogL END;
    IF X11fd >=16 THEN Host.LogS("Error: fd>=16:"); Host.LogH( X11fd); Host.LogL (*Kernel.Shutdown(1)*) END;
    sa1:= X11SOCKETPATH;
    sa1[0]:= CHR(Host.PFUNIX MOD 100H);
    sa1[1]:= CHR(Host.PFUNIX DIV 100H);
    res:= Host.Connect( X11fd, SYSTEM.ADR( sa1), 20  (*LEN(X11SOCKETPATH)*) );
  ELSE    (* we are on an SSH connection ... *)
(*
    GetAdr(bdata, tcp, port);
*)
    tcp := 7F000001H;  (* 127.0.0.1, localhost *)
    port := 6000 + Xdisplay;
    Host.LogS("tcp adr: "); Host.LogH(tcp); Host.LogL;
    Host.LogS("tcp port "); Host.LogH( port); Host.LogL;
    X11fd:=Host.Socket( Host.PFINET);

    IF TRACE THEN Host.LogS("Socket no.: "); Host.LogH( X11fd); Host.LogL END;
    IF ( X11fd<=0) OR ( X11fd >=16) THEN Host.LogS("Error: fbfd>=16:"); Host.LogH( X11fd); Host.LogL (*Kernel.Shutdown(1)*) END;
    sa1[0]:= CHR(Host.PFINET MOD 100H);
    sa1[1]:= CHR(Host.PFINET DIV 100H);
    sa1[2]:=CHR(port DIV 256);
    sa1[3]:=CHR(port MOD 256);
    sa1[4]:=CHR(ASR(tcp, 24) MOD 256);
    sa1[5]:=CHR(ASR(tcp, 16) MOD 256);
    sa1[6]:=CHR(ASR(tcp, 8) MOD 256);
    sa1[7]:=CHR(tcp MOD 256);
    res:= Host.Connect( X11fd, SYSTEM.ADR( sa1),  16);
  END;
  IF res#0 THEN (*  Connect failed *)
    Host.LogS("X11: can't connect "); Host.LogH( -res ); Host.LogL
  END;
  bdata[ 0]:= "l";  bdata[ 1]:= 0X;                    (* pad  *)
  bdata[ 2]:= 0BX;  bdata[ 3]:=0X;  (* protocol major *)
  bdata[ 4]:=0X;  bdata[ 5]:=0X;    (* ptotocol minor *)
  bdata[ 6]:=0X;  bdata[ 7]:=0X;  (* auth protocol len *)
  bdata[ 8]:=0X;  bdata[ 9]:=0X;  (* auth prot data len *)
  bdata[ 10]:=0X;  bdata[ 11]:=0X;  (* pad *)
  IF GetAuth(bdata) THEN res:=Host.Write( X11fd, SYSTEM.ADR(bdata), 48);
  ELSE res:=Host.Write( X11fd, SYSTEM.ADR(bdata), 12);
  END;

  res:=Host.Read( X11fd, SYSTEM.ADR(r0data), 8);
  lw:=0;
  r0datares:= r0data.a MOD 100H;
  r0datalen:=r0data.b DIV 10000H;
  IF r0datares = 1(* success *) THEN
    res:=Host.Read( X11fd, SYSTEM.ADR(r1data), 32);
    INC(lw, res);
    IF TRACE THEN
      Host.LogS("r1data.maxreqlen: "); Host.LogH( r1data.lenvendormaxreqlen DIV 10000H MOD 10000H); Host.LogL;
      Host.LogS("r1data.lenvendor: "); Host.LogH( r1data.lenvendormaxreqlen MOD 10000H); Host.LogL;
    END;
    res:=Host.Read( X11fd, SYSTEM.ADR(adata[0]), (r1data.lenvendormaxreqlen MOD 10000H+3) DIV 4 *4);
    INC(lw, res);
    adata[r1data.lenvendormaxreqlen MOD 10000H]:=0X;
    res:=0;
    Host.LogS(adata); Host.LogL;
    FOR i:= 1 TO ORD( r1data.noformats) DO
      res:= Host.Read( X11fd, SYSTEM.ADR(format),  SYSTEM.SIZE(Format));
      INC(lw, res);
      IF TRACE THEN Host.LogS("Format:"); Host.LogH( ORD(format.depth)); Host.LogL END;
    END;
    res:= Host.Read( X11fd, SYSTEM.ADR(scn),  SYSTEM.SIZE(Screen));
    sw:=scn.widthheight MOD 10000H;
    sh:=scn.widthheight DIV 10000H;
    scnrdepth:= ORD( scn.rdepth);
    scnroot:= scn.root;
    INC(lw, res);
    IF TRACE THEN Host.LogS("Screen:"); Host.LogH( ORD(scn.ndepth)); Host.LogL END;
    FOR i:= 1 TO ORD(scn.ndepth) DO
      res:= Host.Read( X11fd, SYSTEM.ADR(depth), SYSTEM.SIZE(DepthT));
      depthnvisualtypes:= depth.a DIV 10000H;
      INC(lw, res);
      IF ORD(scn.rdepth)= depth.a MOD 100H THEN
        res:=Host.Read( X11fd, SYSTEM.ADR(visual), SYSTEM.SIZE(VisualT));
        INC(lw, res);
        IF TRACE THEN 
          Host.LogS("Depth :"); Host.LogH( depth.a MOD 100H); Host.LogL;
          Host.LogS( "depth.nvisualtypes "); Host.LogH( depthnvisualtypes); Host.LogL;
          Host.LogS("using Visual: "); Host.LogH( visual.id); Host.LogL;
          Host.LogS("visual.class: "); Host.LogH(visual.cbc MOD 100H); Host.LogL;
  (*        Kernel.WriteHex( visual.rmask, 9);  Kernel.WriteHex( visual.gmask, 9);  Kernel.WriteHex( visual.bmask, 9); *)
        END;
        DEC(depthnvisualtypes);
      END;
      WHILE depthnvisualtypes > 0 DO
        res:=Host.Read( X11fd, SYSTEM.ADR(visual),  SYSTEM.SIZE(VisualT));
        INC(lw, res);
        DEC(depthnvisualtypes);
      END;
    END;
    IF lw DIV 4# r0datalen THEN
      Host.LogS("X11: warning: Size mismatch, Longwords read: "); Host.LogH( lw DIV 4); Host.LogL;
      Host.LogS("X11: warning: Size mismatch, r0data.len    : "); Host.LogH( r0datalen); Host.LogL;
    END;
    IF ORD(scn.rdepth) #18H THEN Host.LogS("Error: no X11 visual currently supported"); Host.LogH( ORD(scn.rdepth)); Host.LogL END;
    KeyboardMapping;
    DisplayWidth := defaultWidth * zoom;
    IF Host.GetEnv("OWIDTH", bdata) THEN DisplayWidth:=Str2Int( bdata) END;
    IF sw < DisplayWidth+16 THEN DisplayWidth:= sw -16 END;
    IF DisplayWidth < 0 THEN DisplayWidth:=sw+DisplayWidth END;
    DisplayHeight:= defaultHeight * zoom;
    IF Host.GetEnv("OHEIGHT", bdata) THEN DisplayHeight:=Str2Int( bdata) END;
    IF sh < DisplayHeight+32 THEN DisplayHeight:= sh -32 END;
    IF DisplayHeight < 0 THEN DisplayHeight:=sh+DisplayHeight END;
    OpenWindow;
  ELSE
    res:=Host.Read( X11fd, SYSTEM.ADR(adata[0]),  r0datalen*4);
    adata[ r0datalen*4-1]:=0X; Host.LogS(adata); Host.LogL;
    Host.LogS("X11 error: "); Host.LogH( r0datares); Host.LogL;    (* rdata.res  =2X authenticate *)
    IF r0datares  =0 THEN                      (* rdata.res  =0X failed *)
      Host.LogS("Can't connect to xhost:"); Host.LogL;
      Host.LogS("Please execute 'xhost local:', 'xhost +', 'xhost +si:localuser:$USER' or start xserver with -ac option"); Host.LogL;
    END;
  END;
  myProperty:=InternAtom();
  Width:=DisplayWidth DIV zoom; Height:= DisplayHeight DIV zoom;
  RETURN DisplayBase
END OpenDisplay;

PROCEDURE CloseDisplay;
CONST IPCRMID=100H; (* ORI in libc for MIPS*)
VAR i, res: LONGINT;
  b: ARRAY 2 OF LONGINT;
BEGIN
  Host.LogS("Closing Display."); Host.LogL;
  IF ShmReqCode#0 THEN
    b[0]:=ShmReqCode+2*100H+2*10000H;  (* X_ShmDetach = 2 *)
    b[1]:= shmseg; (*ShmSeg;*)
    res:=Host.Write( X11fd, SYSTEM.ADR(b),  8);
(*  Xdestroyimage  *)
    res:=Host.Shmdt( DisplayBase);
    res:=Host.ShmCtl( shmid, IPCRMID, 0);
  END;
  res:= Host.Close( X11fd);
END CloseDisplay;

BEGIN
END Display0.