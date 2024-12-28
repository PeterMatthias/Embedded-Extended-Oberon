MODULE Host;  
IMPORT SYSTEM;

(* 
  Access to Linux MIPS32 Kernel and logging 

    Peter Matthias

    2024-11-09  started
    2024-11-17  cleaned up, using common symbol file
    2024-11-18  FixP, FixD: adopted for optimized OMG.fixcode, OMG.fixvar
    2024-11-23  fixed Size
    2024-12-19  removed virtual registers, mapping RISC5 registers to MIPS in OMG.MOd

    No Oberon.Abort installation possible by design; jump would need valid branch delay slot

*)

CONST
  pbase* = 10080H;  (* base of the system, 80H is size of ELF header *)
  TrapAdr* = 4;
  R5SP = 14;  (* stack pointer register of RISC5 *)
  dPC = 1; 
  cappendix = ".mps"; cversionkey = 5X;

  C15 = 8000H; C16 = 10000H; C20 = 100000H; C21 = 200000H; C28 = 10000000H;

  (* domain in Socket *)  
  PFUNIX*= 1;  PFINET*= 2;
  SOCKSTREAM = 2;    (* was 1 for X86 and ARM, 2 for MIPS *)
  (** Open( .. ) flags *)
  ORDonly = 0;  OWRonly = 1;  ORDWR = 2;  OCREAT = 40H;  OEXCL = 80H;  
  OTRUNC = 200H;  OAPPEND = 400H;  ODSYNC = 1000H;(* from MIPS *)
  ATFDCWD = -100;  (* use current working directory *)  ODirectory = 0;
  (** FLock( .. ) *) (*  LOCKEX= 2;  LOCKNB= 4;  LOCKUN= 8;*)
  (** LSeek *)  SEEKSET=0;  SEEKCURRENT=1;  SEEKEND=2;
  (** Mmap *)  MAPSHARED = 1;  MAPPRIVATE = 2;  MAPFIXED = 10H;  MAPANONYMOUS = 800H;  (* ARM, x86: 20H; MIPS: 800H *)
  PROTREAD = 1;  PROTWRITE = 2;  PROTEXEC = 4;

TYPE
  Syscall1 = PROCEDURE( a: INTEGER): INTEGER;
  Syscall2 = PROCEDURE( a, b: INTEGER): INTEGER;
  Syscall3 = PROCEDURE( a, b, c: INTEGER): INTEGER;
  Syscall4 = PROCEDURE( a, b, c, d: INTEGER): INTEGER;
  (* stack must be adjusted for syscalls with more than 4 parameters *)
  Syscall6 = PROCEDURE( a, b, c, d, e, f: INTEGER): INTEGER;

  TimeVal = RECORD sec, nsec: INTEGER END;

VAR
  appendix*: ARRAY 8 OF CHAR;
  versionkey* : CHAR;
  Kopenat : Syscall4;
  Kclose : Syscall1;
  Kread : Syscall3;
  Kwrite : Syscall3;
  Kpread64 : Syscall4;  (* Todo, read/write at position *)
  Kpwrite64 : Syscall4;
(*  Kreadv : Syscall3;*)
  Kwritev : Syscall3;
  Klseek : Syscall3;
  Kfstat64 : Syscall2;
  Kmmap2 : Syscall6;
  Kmunmap : Syscall2;
  Kpoll: Syscall3;    (* according to qemu, poll (105CH) has 6 arguments *)
  Kclocknanosleep : Syscall4;
  Kpselect6 : Syscall6;
  KclockGettime : Syscall2;
  Kcacheflush : Syscall4;  (* according to qemu, cacheflush has 6 arguments *)
  Kipc : Syscall6;
  Kioctl :  Syscall3;
  Ksocket : Syscall3;
  Kconnect : Syscall3;
  Kexit : Syscall1;

  startTime, StackOrg, NoOfArgs : INTEGER; 

PROCEDURE Cacheflush*( beg, size: INTEGER);
VAR res: INTEGER;
BEGIN
  res := Kcacheflush(beg, size, 3, 0);
END Cacheflush;

PROCEDURE Exit*( a: INTEGER);
VAR res: INTEGER;
BEGIN  res := Kexit(a);
END Exit;

PROCEDURE Open*( name: ARRAY OF CHAR; write, new: BOOLEAN): INTEGER;
BEGIN
  RETURN Kopenat( ATFDCWD, SYSTEM.ADR(name), ORD(write)* 2, ORD(new)*40H)
END Open;

PROCEDURE Close*( fd: INTEGER): INTEGER;
BEGIN
  RETURN Kclose( fd)
END Close;

PROCEDURE Read*( fd, adr, size: INTEGER ): INTEGER;
BEGIN
  RETURN Kread( fd, adr, size)
END Read;

PROCEDURE Write*( fd, adr, size: INTEGER ): INTEGER;
BEGIN
  RETURN Kwrite( fd, adr, size)
END Write;

PROCEDURE Read2*( fd, adr, size, pos: INTEGER): INTEGER;  (* Todo: use pread64 *)
VAR res : INTEGER; ret: ARRAY 16 OF INTEGER;
BEGIN
  res := Klseek( fd, pos, 0);
  RETURN Kread( fd, adr, size)
END Read2;

PROCEDURE Write2*( fd, adr, size, pos: INTEGER ): INTEGER;  (* Todo: use pwrite64 *)
VAR res : INTEGER; ret: ARRAY 16 OF INTEGER;
BEGIN
  res := Klseek( fd, pos, 0);
  RETURN Kwrite( fd, adr, size)
END Write2;

PROCEDURE Writev*( fd, adr, size: INTEGER ): INTEGER;
BEGIN  RETURN Kwritev( fd, adr, size)
END Writev;

PROCEDURE Size*( fd: LONGINT): LONGINT;
VAR stat: ARRAY 40 OF INTEGER; res: INTEGER;
BEGIN res:= Kfstat64( fd, SYSTEM.ADR( stat));
  RETURN stat[14]
END Size;

PROCEDURE Time*(): INTEGER;
CONST CLOCKBOOTTIME = 7;
VAR res: INTEGER; j: TimeVal;
BEGIN
  res:= KclockGettime( CLOCKBOOTTIME, SYSTEM.ADR( j));
  RETURN j.sec*1000 + j.nsec DIV 1000000 - startTime
END Time;

PROCEDURE OMmap( a, b, c, e, f: INTEGER): INTEGER;  (* put 5th and 6th argument on stack adjusted*)
BEGIN
  RETURN Kmmap2(0, b, 3, MAPANONYMOUS + MAPPRIVATE,  -1, 0 )
END OMmap;

PROCEDURE Mmap*( b: INTEGER ): INTEGER;
BEGIN  RETURN OMmap(0, b, 3, -1, 0 )
END Mmap;

PROCEDURE Munmap*( a, b: INTEGER ): INTEGER;
BEGIN  RETURN Kmunmap(a, b)
END Munmap;

PROCEDURE Shmget*( key, size, shmflag: LONGINT): LONGINT;
BEGIN RETURN Kipc( 23, key, size, shmflag, 0, 0)
END Shmget;

PROCEDURE ShmAt*(shmid, addr, flags: LONGINT): LONGINT;
VAR res, a: INTEGER;
BEGIN
  a := addr;
  res:= Kipc( 21, shmid, 0, SYSTEM.ADR(a), 0, 0);
  RETURN a
END ShmAt;

PROCEDURE ShmCtl*(buf, cmd, shmid: LONGINT): LONGINT;
BEGIN RETURN Kipc( 24, buf, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET,cmd)+{8}), 0, shmid, 0)
END ShmCtl;

PROCEDURE Shmdt*(addr: LONGINT): LONGINT;
BEGIN RETURN Kipc( 22, 0, 0, 0, addr, 0)
END Shmdt;

PROCEDURE Socket*( a: INTEGER): INTEGER;
BEGIN RETURN Ksocket( a, SOCKSTREAM, 0)
END Socket;

PROCEDURE Connect*( a, b, c: INTEGER): INTEGER;
BEGIN RETURN Kconnect( a, b, c)
END Connect;

(* old
PROCEDURE Avail( fd, nsec: INTEGER): INTEGER;
CONST FIONREAD = 541BH;
TYPE TimeSpec = RECORD sec0, sec1, nsec0, nsec1: LONGINT END;
VAR res, num: INTEGER; ts: TimeSpec;
BEGIN
  res:= Kioctl( fd, FIONREAD, SYSTEM.ADR(num));
  IF num <=0 THEN
    ts.sec0 := 0; ts.sec1 := 0; ts.nsec0 := nsec; ts.nsec1 := 0;
    res := Kclocknanosleep(SYSTEM.ADR(ts), 0, 0, 0);
  END;
  RETURN num
END Avail;
*)
(*
PROCEDURE Avail( fd, nsec: INTEGER): INTEGER;
VAR timeout: TimeVal; s: SET;
BEGIN
  s := { fd}; timeout.sec:= 0; timeout.nsec:= nsec;    (* don't block at all *)
  RETURN Kpselect6( 8, SYSTEM.ADR( s), 0, 0, SYSTEM.ADR( timeout), 0)
END Avail;
*)

PROCEDURE Ppoll*( fd, timeout: INTEGER ): INTEGER;
VAR pollfd: RECORD fd, events, revents: INTEGER END;
BEGIN  
  pollfd.fd := fd; pollfd.events := 1H; pollfd.revents := 0;
  RETURN Kpoll(SYSTEM.ADR(pollfd), 1, (timeout))
END Ppoll;

PROCEDURE LogL*;
VAR res: INTEGER;
BEGIN res:= Write( 0, SYSTEM.ADR( $0A$), 1);
END LogL;

PROCEDURE LogH*( x: INTEGER);
VAR res, i, j: INTEGER;
  a: ARRAY 10 OF CHAR;
BEGIN
  i := 8; 
    REPEAT
    j:= x MOD 10H;
    IF j < 10 THEN a[i] := CHR(j + 30H) ELSE a[i] := CHR(j + 37H) END;
      x := x DIV 10H; DEC(i);
    UNTIL i = 0;
  a[0] := " "; a[9] := 0X;
  res := Write( 0, SYSTEM.ADR( a), 9);
END LogH;

PROCEDURE LogS*( s: ARRAY OF CHAR);
VAR res, i: INTEGER; c: CHAR;
BEGIN
  i:=0;
  REPEAT c:= s[ i]; INC( i) UNTIL (c=0X) OR (i=LEN(s));
  i:= Write( 0, SYSTEM.ADR( s), i);
END LogS;

PROCEDURE GetArg*(n: LONGINT; VAR val: ARRAY OF CHAR);
VAR l, m: LONGINT; c: CHAR;
BEGIN
  IF (n>=0) & (n<NoOfArgs) THEN
    SYSTEM.GET( StackOrg+(n+1)*4, l);
    m:=0;
    REPEAT
      SYSTEM.GET( l, c);
      val[m]:=c;
      INC(l); INC(m);
    UNTIL (c=0X);
  ELSE val[0]:= 0X;
  END;
END GetArg;

PROCEDURE GetEnv*(env: ARRAY OF CHAR; VAR val: ARRAY OF CHAR): BOOLEAN;
VAR sadr, j, n: INTEGER; ch: CHAR;
BEGIN  (* stack layout at http://asm.sourceforge.net/articles/startup.html *)
  LogS(env); LogS("=");
  sadr:=StackOrg+(NoOfArgs+2)*4;
  SYSTEM.GET( sadr, n);
  val[0]:=0X;
  WHILE n#0  DO  
    SYSTEM.GET(n, ch);
    j:=0;
    WHILE ch=env[j] DO
      INC(n); SYSTEM.GET(n, ch); INC(j);
    END;
    IF ch="=" THEN
      j:=0; 
      REPEAT
        INC(n);
        SYSTEM.GET(n, ch);
        val[j]:=ch; INC(j);
      UNTIL ch=0X;
      LogS(val);
      n:=0;
    END;
    INC(sadr, 4);  
    SYSTEM.GET( sadr, n);
  END;
  LogL;
  RETURN val[0] # 0X
END GetEnv;

PROCEDURE FixP*( adr, dest: INTEGER);  (* fix jumps, used in Modules*)
CONST JAL = 0C000000H;
BEGIN SYSTEM.PUT(adr, JAL+ dest DIV 4 ); 
END FixP;

PROCEDURE FixD*( adr, dest: INTEGER);  (* fix data adresses, used in Modules *)
CONST LUI = 3C000000H;
VAR inst : INTEGER;
BEGIN
  SYSTEM.GET(adr + 4, inst);
  SYSTEM.PUT(adr, LUI + inst DIV C21 MOD 20H * C16 + dest DIV C16 + dest DIV C15 MOD 2);
  SYSTEM.PUT(adr+ 4, inst +  dest MOD C16);
END FixD;

PROCEDURE Install*(Padr, at: INTEGER);    (* branch from at to Padr; module is hot -> flush cache *)
CONST JAL = 0C000000H; J = 08000000H;
VAR inst: INTEGER;
BEGIN SYSTEM.PUT( at,  J+ Padr DIV 4 ); (* 256MB *)
  Cacheflush( at, 16);
END Install;

PROCEDURE Init*;
VAR res: INTEGER;
BEGIN
  appendix := cappendix; versionkey := cversionkey;
  (*  mv R2, nr;  syscall;  SUBU R4, 0, R2;  JR RA;  MOVZ R4, R2, R7  *) 
  Kcacheflush := SYSTEM.VAL( Syscall4, SYSTEM.ADR($3310 0234  0C00 0000  2320 0200  0800 E003  0A20 4700$));  (*  4147 = 1033H    *)
  Kopenat := SYSTEM.VAL( Syscall4, SYSTEM.ADR($C010 0234 0C00 0000 2320 0200 0800 E003 0A20 4700$));  (*  4288 = 10C0H    *)

  Kclose := SYSTEM.VAL( Syscall1, SYSTEM.ADR($A60F 0234 0C00 0000 2320 0200 0800E003 0A204700$));   (*  4006 = 0FA6H    *)
  Kread := SYSTEM.VAL( Syscall3, SYSTEM.ADR($A30F 0234 0C00 0000 2320 0200 0800E003 0A204700$));  (*  4003 = 0FA3H    *)
  Kwrite := SYSTEM.VAL( Syscall3, SYSTEM.ADR($A40F 0234 0C00 0000 2320 0200 0800E003 0A204700$));  (*  4004 = 0FA4H    *)
  Klseek := SYSTEM.VAL( Syscall3, SYSTEM.ADR($B30F 0234 0C00 0000 2320 0200 0800E003 0A204700$));  (*  4019 = 0FB3H    *)
  Kwritev := SYSTEM.VAL( Syscall3, SYSTEM.ADR($3210 0234 0C00 0000 2320 0200 0800E003 0A204700$));  (*  4146 = 1032H    *)
  Kmmap2 := SYSTEM.VAL( Syscall6, SYSTEM.ADR($72100234  0C000000 23200200 0800E003 0A204700$));  (*  4210 = 1072H    *)
(*  Kmmap2 := SYSTEM.VAL( Syscall6, SYSTEM.ADR($FA0F0234 0400BD27  0C000000 FCFFBD27 23200200 0800E003 0A204700$));*)  (*  4210 = 1072H    *)
  Kmunmap := SYSTEM.VAL( Syscall2, SYSTEM.ADR($FB0F0234 0C00 0000 2320 0200 0800 E003 0A204700$));  (*  4091 = 0FFBH    *)

  Kpoll := SYSTEM.VAL( Syscall3, SYSTEM.ADR($5C10 0234 0C00 0000 2320 0200 0800 E003 0A204700$));    (* 105CH*)
  Kclocknanosleep := SYSTEM.VAL( Syscall4, SYSTEM.ADR($A910 0234  0C00 0000  2320 0200  0800 E003  0A204700$)); (*   4265=10A9H    *)
  Kpselect6 := SYSTEM.VAL( Syscall6, SYSTEM.ADR($CD10 0234  0400 BD27  0C00 0000  FCFF BD27  2320 0200  0800 E003  0A204700$));  (*   4301= 10CDH    *)

  Kfstat64 := SYSTEM.VAL( Syscall2, SYSTEM.ADR($7710 0234  0C00 0000  2320 0200  0800 E003  0A204700$));  (*  4215 = 1077H    *)
  KclockGettime := SYSTEM.VAL( Syscall2, SYSTEM.ADR($A710 0234  0C00 0000  2320 0200  0800 E003   0A204700$));  (*  4263 = 10A7H *)  

  Kioctl := SYSTEM.VAL( Syscall3, SYSTEM.ADR($D60F 0234 0C00 0000 2320 0200 0800 E003 0A204700$));  (*  4054 = 0FD6H    *)
  Ksocket := SYSTEM.VAL( Syscall3, SYSTEM.ADR($5710 0234 0C00 0000 2320 0200 0800 E003 0A204700$));  (*   4183= 1057H    *)
  Kconnect := SYSTEM.VAL( Syscall3, SYSTEM.ADR($4A10 0234 0C00 0000 2320 0200 0800 E003 0A204700$));  (*   4170= 104AH    *)
  Kipc := SYSTEM.VAL( Syscall6, SYSTEM.ADR($1510 0234  0400 BD27  0C00 0000  FCFF BD27  2320 0200  0800 E003  0A204700$));  (*   4117= 1015H    *)
  Kexit := SYSTEM.VAL( Syscall1, SYSTEM.ADR($A10F 0234  0C00 0000  2320 0200  0800 E003  0A204700$));  (*  4001 = 0FA1H    *)

  startTime:= Time();

  StackOrg:=SYSTEM.REG( R5SP) + 12;
  SYSTEM.GET( StackOrg, NoOfArgs);
  LogS("StackOrg: "); LogH( StackOrg); LogL;
  LogS("NoOfArgs: "); LogH( NoOfArgs); LogL;
END Init;

END Host.