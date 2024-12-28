MODULE Display;  (*NW 5.11.2013 / 17.1.2019 / AP 15.9.20 Extended Oberon*)
  IMPORT SYSTEM, Host, Display0;

(*
    ReplPattern not yet converted to 32 bit depth

    2024-11-30  CopyBlock: fixed bug with Zoom

*)

  CONST black* = 0; white* = 1;  (*black = background*)
    replace* = 0; paint* = 1; invert* = 2;  (*modes*)

    Zoom = 2;
    darkgray = 11; mediumgray = 12; realwhite = 15;
    red = 2; green = 3; blue = 4;
    dred = 5; dgreen = 6; dblue = 7;
    Bytes = 4;

  TYPE Frame* = POINTER TO FrameDesc;
    FrameMsg* = RECORD END ;
    Handler* = PROCEDURE (F: Frame; VAR M: FrameMsg);
    FrameDesc* = RECORD next*, dsc*: Frame;
        X*, Y*, W*, H*: INTEGER;
        handle*: Handler
      END ;

  VAR Base*, Width*, Height*: INTEGER;
    arrow*, star*, hook*, updown*, block*, cross*, grey*: INTEGER;
    (*a pattern is an array of bytes; the first is its width (< 32), the second its height, the rest the raster*)

  colmap: ARRAY 16 OF INTEGER;
  Span : INTEGER;

  PROCEDURE Handle*(F: Frame; VAR M: FrameMsg);
  BEGIN
    IF (F # NIL) & (F.handle # NIL) THEN F.handle(F, M) END
  END Handle;

  (* raster ops *)
    
  PROCEDURE Dot*(col, x, y, mode: INTEGER);
  VAR dst: INTEGER; s: SET;
  BEGIN
    col  := colmap[col MOD 10H];
    IF (y>=0) & (y<=Height) THEN
      dst := Base + ((Height- 1 - y )* Span + x) * Bytes * Zoom;
      IF mode = invert THEN SYSTEM.GET(dst, s); col := ORD(SYSTEM.VAL(SET, col) / s) END;
      SYSTEM.PUT(dst, col);
      IF Zoom > 1 THEN SYSTEM.PUT(dst + Bytes, col);
        SYSTEM.PUT(dst + Span * Bytes, col); SYSTEM.PUT(dst +  Span * Bytes + Bytes, col);
      END;
    END;
    Display0.PutImage( x * Zoom , y * Zoom , Zoom, Zoom);
  END Dot;

  PROCEDURE ReplConst*(col, x, y, w, h, mode: INTEGER);
  VAR dst, h2, w2: INTEGER; cols: SET;
  BEGIN
    col  := colmap[col MOD 10H];
    IF (y >= 0) & (y+h <= Height ) THEN
      dst := Base + ( (Height - (h + y)  ) * Span + x ) * Bytes * Zoom;
      h2:= h * Zoom;
      WHILE h2 > 0 DO
        w2:= w * Zoom;
        IF mode = invert THEN
          WHILE w2 > 0 DO
            SYSTEM.GET(dst, cols);  (*  ignore col SYSTEM.PUT(dst, cols/ SYSTEM.VAL(SET, col));*)
            SYSTEM.PUT(dst, -cols);
            INC(dst, Bytes);
            DEC(w2);
          END
        ELSE
          WHILE w2 > 0 DO
            SYSTEM.PUT(dst, col);
            INC(dst, Bytes );
            DEC(w2);
          END;
        END;
        INC( dst,  (Span  - w * Zoom ) * Bytes );
        DEC(h2);
      END;
      Display0.PutImage( x * Zoom , y* Zoom , w* Zoom , h* Zoom );
    END;
  END ReplConst;

PROCEDURE CopyPatternClipped*( col, pat, x, y, left, right, top, bot, mode: INTEGER);
VAR p: CHAR; pix: SET;
    padr, dadr, pw, ex, sx, W, H, H0: INTEGER;
BEGIN
    col := colmap[col MOD LEN(colmap)];
    SYSTEM.GET( pat, p); W := ORD(p)  - right; pw:= (W+7) DIV 8;
    SYSTEM.GET( pat+1, p); H := ORD(p) - top; H0 := H;
    IF mode#invert THEN
      REPEAT
        dadr:= Base+(( Height - (y + H) ) * Span+ (x + left)) * Bytes * Zoom;
        DEC( H);
        padr:= pat + 2+ pw * H ;
        sx:= left;
        REPEAT
          ex:= (sx + 8) DIV 8 * 8;
          IF ex > W THEN ex:= W END;
          SYSTEM.GET( padr+ sx DIV 8 , p);
          REPEAT
            IF ODD( ASR( ORD(p), sx MOD 8)) THEN SYSTEM.PUT( dadr, col);
              IF Zoom > 1 THEN SYSTEM.PUT(dadr + Bytes, col);
                SYSTEM.PUT(dadr + Span * Bytes, col); SYSTEM.PUT(dadr +  (Span  + 1) * Bytes, col);
              END;
            END;
            INC( sx); INC( dadr, Bytes * Zoom);
          UNTIL sx >= ex;          
        UNTIL sx>= W;
      UNTIL H= bot;
    ELSE
      REPEAT
        dadr:= Base+(( Height  - (y + H )) * Span+ (x+ left) )* Bytes * Zoom;
        DEC( H);
        padr:= pat + 2+ pw * H ;
        sx:= left;
        REPEAT
          ex:= (sx + 8) DIV 8 * 8;
          IF ex > W THEN ex:= W END;
          SYSTEM.GET( padr+ sx DIV 8, p);
          REPEAT
            IF ODD( ASR( ORD(p), sx MOD 8)) THEN
              SYSTEM.GET( dadr, pix);   (* ignore col parameter sj:= -s/( SYSTEM.VAL( SET, col)); *)
              SYSTEM.PUT( dadr, -pix);
              IF Zoom > 1 THEN SYSTEM.PUT(dadr + Bytes, -pix);
                SYSTEM.PUT(dadr + Span * Bytes, -pix); SYSTEM.PUT(dadr +  (Span  + 1) * Bytes, -pix);
              END;
            END;
            INC( sx); INC( dadr, Bytes * Zoom);
          UNTIL sx >= ex;
        UNTIL sx>= W;
      UNTIL H= bot;
    END;
    Display0.PutImage( (x + left ) * Zoom, (y + bot ) * Zoom, W* Zoom , H0* Zoom );
END CopyPatternClipped;

PROCEDURE CopyPattern*(col, patadr, x, y, mode: INTEGER);  (*only for modes = paint, invert*)
BEGIN CopyPatternClipped(col, patadr, x, y, 0, 0, 0, 0, mode)
END CopyPattern;

PROCEDURE CopyBlock*(sx, sy, w, h, dx, dy, mode: INTEGER); (*only for mode = replace*)
VAR src, dst, h2, delta: INTEGER;
BEGIN
  IF (sy >= 0) & (sy+h <= Height) & (dy >= 0) & (dy+h <= Height) THEN
    h2:= h * Zoom ;
    IF ( w>0) & ( h>0) THEN
      IF ( sy <= dy) THEN
        src:= Base+((Height- h - sy )* Span+sx ) * Bytes * Zoom;
        dst:= Base+((Height- h - dy )* Span+dx ) * Bytes * Zoom;
        delta := Span * Bytes;
      ELSE
        delta := -Span * Bytes;
        src:= Base+( ( Height - sy )* Span+sx )*Bytes * Zoom + delta;
        dst:= Base+( ( Height - dy )* Span+dx )*Bytes * Zoom + delta;
      END;
      REPEAT
        SYSTEM.COPY(src, dst, w * Zoom);
        INC( src, delta); INC( dst, delta);
        DEC(h2);
      UNTIL h2=0;
      Display0.PutImage( dx* Zoom , dy* Zoom  , w* Zoom , h* Zoom  );
    END;
  END;
END CopyBlock;

  PROCEDURE ReplPattern*(col, patadr, x, y, w, h, mode: INTEGER);
  (* pattern width = 32, fixed; pattern starts at patadr+4, for mode = invert only *)
    VAR al, ar, a0, a1: INTEGER;
      pta0, pta1: INTEGER;  (*pattern addresses*)
      ph: BYTE;
      left, right, mid, pix, pixl, pixr, ptw: SET;
  BEGIN al := Base + y*128; SYSTEM.GET(patadr+1, ph);
    pta0 := patadr+4; pta1 := ph*4 + pta0;
    ar := ((x+w-1) DIV 32)*4 + al; al := (x DIV 32)*4 + al;
    IF ar = al THEN
      mid := {(x MOD 32) .. ((x+w-1) MOD 32)};
      FOR a1 := al TO al + (h-1)*128 BY 128 DO
        SYSTEM.GET(a1, pix); SYSTEM.GET(pta0, ptw); SYSTEM.PUT(a1, (pix - mid) + (pix/ptw * mid)); INC(pta0, 4);
        IF pta0 = pta1 THEN pta0 := patadr+4 END
      END
    ELSIF ar > al THEN
      left := {(x MOD 32) .. 31}; right := {0 .. ((x+w-1) MOD 32)};
      FOR a0 := al TO al + (h-1)*128 BY 128 DO
        SYSTEM.GET(a0, pixl); SYSTEM.GET(pta0, ptw); SYSTEM.PUT(a0, (pixl - left) + (pixl/ptw * left));
        FOR a1 := a0+4 TO ar-4 BY 4 DO SYSTEM.GET(a1, pix); SYSTEM.PUT(a1, pix/ptw) END ;
        SYSTEM.GET(ar, pixr); SYSTEM.PUT(ar, (pixr - right) + (pixr/ptw * right));
        INC(pta0, 4); INC(ar, 128);
        IF pta0 = pta1 THEN pta0 := patadr+4 END
      END
    END
  END ReplPattern;

BEGIN
  Width := 0; Height := 0;
  arrow := SYSTEM.ADR($0F0F 0060 0070 0038 001C 000E 0007 8003 C101 E300 7700 3F00 1F00 3F00 7F00 FF00$);
  star := SYSTEM.ADR($0F0F 8000 8220 8410 8808 9004 A002 C001 7F7F C001 A002 9004 8808 8410 8220 8000$);
  hook := SYSTEM.ADR($0C0C 070F 8707 C703 E701 F700 7F00 3F00 1F00 0F00 0700 0300 01$);
  updown := SYSTEM.ADR($080E 183C 7EFF 1818 1818 1818 FF7E3C18$);
  block := SYSTEM.ADR($0808 FFFF C3C3 C3C3 FFFF$);
  cross := SYSTEM.ADR($0F0F 0140 0220 0410 0808 1004 2002 4001 0000 4001 2002 1004 0808 0410 0220 0140$);
  grey := SYSTEM.ADR($2002 0000 5555 5555 AAAA AAAA$);

  (* colmap resembles Native Oberon *)
  colmap[ black] := 0DFDFDFH;    (* light gray *)  
  colmap[ white] := 0H;    (* black *)
  colmap[ darkgray] := 8A8A8AH;    (* dark gray *)
  colmap[ mediumgray] := 0BEBEBEH;    (* medium gray *)
  colmap[ realwhite] := 0FFFFFFH;    (* White *)

  colmap[ red] := 0FF0000H;  (* Red *)
  colmap[ green] := 0FF00H;    (* Green *)
  colmap[ blue] := 0FFH;    (* Blue *)
  colmap[ dred] := 0AA0000H;    (* dark red *)
  colmap[ dgreen] := 09A00H;    (* dark green *)
  colmap[ dblue] := 09AH;      (* dark blue *)
  colmap[ 8] := 0FF00FFH;  (*  *)
  colmap[ 9] := 0FFFF00H;    (* Yellow *)
  colmap[ 10] := 0FFFFH;    (*  *)
  colmap[ 13] := 082H;      (*  *)
  colmap[ 14] :=  0A6CBF3H;  (*  *)
  Base := Display0.OpenDisplay( Width, Height, Zoom); Span := Width * Zoom;

  Host.LogS("Display.Base:   "); Host.LogH( Base); Host.LogL;
  Host.LogS("Display.Width:  "); Host.LogH( Width); Host.LogL;
  Host.LogS("Display.Height: "); Host.LogH( Height); Host.LogL;
  ReplConst( red, 0, 0, Width, Height, replace);
  ReplConst( green, Width DIV 2, 0, 1, Height, replace);
  ReplConst( blue, 0, Height DIV 2, Width, 1, replace);
  CopyPattern( white, arrow, 100, 200, replace);
  CopyPattern( realwhite, star, 200, 200, replace);
  CopyPattern( black, hook, 300, 200, replace);

END Display.
