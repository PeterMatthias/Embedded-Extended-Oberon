MODULE Input; 

IMPORT SYSTEM, Display0;
  CONST
   NUL* = 0X; BS* = 08X; TAB* = 09X; LF* = 0AX; CR* = 0DX; SUB* = 1AX; ESC* = 1BX; SPC* = 20X; DEL* = 7FX; (*ascii codes*)
   CtrlA* = 1X; CtrlC* = 03X; CtrlV* = 16X; CtrlX* = 18X; (*text control*)
   CursorLeft* = 02X; CursorRight* = 06X; CursorUp* = 10X; CursorDown* = 0EX; (*cursor keys*)

VAR MW, MH, lastX, lastY: INTEGER;
  Available0: PROCEDURE( wait: INTEGER): INTEGER;
  Mouse0: PROCEDURE( VAR keys: SET; VAR x, y: INTEGER);
  Char0: PROCEDURE( ): CHAR;

  (** Returns the number of keystrokes in the keyboard input buffer. *)
PROCEDURE Available*(): INTEGER;
BEGIN RETURN Display0.Available( 0)
END Available;

PROCEDURE Read*(VAR ch: CHAR);
BEGIN ch:= Display0.Char();
END Read;

PROCEDURE Mouse*(VAR keys: SET; VAR x, y: INTEGER);
BEGIN
  Display0.Mouse( keys, x, y);
  IF (x<0) OR (x>=MW) THEN x:=lastX END; lastX:=x; 
  IF (y<0) OR (y>= MH) THEN y:= lastY END; lastY:=y;
END Mouse;

PROCEDURE SetMouseLimits*(w, h: INTEGER);
BEGIN MW := w ; MH := h;
END SetMouseLimits;

PROCEDURE Init*;
BEGIN  lastX:=0; lastY:=0;
END Init;

END Input.
