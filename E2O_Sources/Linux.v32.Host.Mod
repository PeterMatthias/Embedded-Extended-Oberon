MODULE Host;  
IMPORT SYSTEM;

(* 
  Access to Linux RISC-V32 Kernel an logging risc-v syscall table at jborza.com

  addi R17, R0, 64 = 40H; ECALL; JALR 0, LNK, 0 => 04000893H,00000073H,00008067H; or C.LI, ECALL, C.JR => ... 8280H

    Peter Matthias

    2024-08-25  started
    2024-11-17  cleaned up, using common symbol file
    2024-11-18  FixP, FixD: adapted for optimized OVG.fixcode, OVG.fixvar
    2024-12-07  renamed to Linux.v32.Host.Mod
    2024-12-19  removed virtual registers, mapping registers in OvG
    2024-12-25  Ppoll: polling with timout, exit when window closed

*)

CONST
  pbase* = 10080H;  (* base of the system, 80H is size of ELF header *)
  TrapAdr* = 4;
  dPC = 0;  R5SP = 14; (* RISC5 SP *)
  cappendix = ".v32"; cversionkey = 4X;

  C15 = 8000H; C20 = 100000H; C28 = 10000000H;
  LUI = 37H; AUIPC = 17H; JALR = 67H; JAL = 6FH; T0 = 5; NOP = 13H;

  (* domain in Socket *)  
  PFUNIX* = 1;  PFINET* = 2;
  SOCKSTREAM = 1;    (* 1 for X86, RISC-V and ARM, 2 for MIPS *)
  (** Open( .. ) flags *)
  ORDonly = 0;  OWRonly = 1;  ORDWR = 2;  OCREAT = 40H;  OEXCL = 80H;  
  OTRUNC = 200H;  OAPPEND = 400H;  ODSYNC = 1000H;(* from MIPS *)
  ATFDCWD = -100;  (* use current working directory *)  ODirectory = 0;
  (** FLock( .. ) *) (*  LOCKEX= 2;  LOCKNB= 4;  LOCKUN= 8;*)
  (** LSeek *)  SEEKSET=0;  SEEKCURRENT=1;  SEEKEND=2;
  (** Mmap *)  MAPSHARED=1;  MAPPRIVATE=2;  MAPFIXED=10H;  MAPANONYMOUS=20H;  (* ARM: 20H; MIPS: 800H *)
  PROTREAD=1;  PROTWRITE=2;  PROTEXEC=4;

TYPE
  Syscall0 = PROCEDURE( );
  Syscall1 = PROCEDURE( a: INTEGER): INTEGER;
  Syscall2 = PROCEDURE( a, b: INTEGER): INTEGER;
  Syscall3 = PROCEDURE( a, b, c: INTEGER): INTEGER;
  Syscall4 = PROCEDURE( a, b, c, d: INTEGER): INTEGER;
  Syscall5 = PROCEDURE( a, b, c, d, e: INTEGER): INTEGER;
  Syscall6 = PROCEDURE( a, b, c, d, e, f: INTEGER): INTEGER;
  TimeVal = RECORD sec, sec0, usec, usec0: INTEGER END;

VAR
  appendix*: ARRAY 8 OF CHAR;
  versionkey* : CHAR;
  Kopenat : Syscall4;
  Kclose : Syscall1;
  Kread : Syscall3;
  Kwrite : Syscall3;
  Kpread64 : Syscall4;
  Kpwrite64 : Syscall4;
(*  Kreadv : Syscall3;*)
  Kwritev : Syscall3;
  Klseek : Syscall5;
  Kfstat64 : Syscall2;
  Kmmap : Syscall6;
  Kmunmap : Syscall2;
  Kppoll: Syscall6;
  Kclocknanosleep : Syscall4;
  Kpselect6time32 : Syscall6;
  KclockGettime64 : Syscall2;
  FENCEI : Syscall0;
  Kioctl :  Syscall3;
  Ksocket : Syscall3;
  Kconnect : Syscall3;
  Kshmget : Syscall3;
  Kshmat : Syscall3;
  Kshmdt : Syscall1;
  Kshmctl : Syscall3;
  Kexit : Syscall1;

  startTime, StackOrg, NoOfArgs : INTEGER; 

PROCEDURE Cacheflush*( beg, size: INTEGER);
BEGIN  FENCEI;
END Cacheflush;

PROCEDURE Exit*( a: INTEGER);
VAR i: INTEGER;
BEGIN
  i := Kexit(a);
END Exit;

PROCEDURE Open*( name: ARRAY OF CHAR; write, new: BOOLEAN): INTEGER;
BEGIN
  RETURN Kopenat( ATFDCWD, SYSTEM.ADR(name), ORD(write) * 2, ORD(new) * 40H)
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
  res := Klseek( fd, 0, pos, SYSTEM.ADR(ret), 0);
  RETURN Kread( fd, adr, size)
END Read2;

PROCEDURE Write2*( fd, adr, size, pos: INTEGER ): INTEGER;  (* Todo: use pwrite64 *)
VAR res : INTEGER; ret: ARRAY 16 OF INTEGER;
BEGIN
  res := Klseek( fd, 0, pos, SYSTEM.ADR(ret), 0);
  RETURN Kwrite( fd, adr, size)
END Write2;

PROCEDURE Writev*( fd, adr, size: INTEGER ): INTEGER;
BEGIN  RETURN Kwritev( fd, adr, size)
END Writev;

PROCEDURE Size*( fd: LONGINT): LONGINT;
VAR stat: ARRAY 40 OF INTEGER; res: INTEGER;
BEGIN res:= Kfstat64( fd, SYSTEM.ADR( stat));
  RETURN stat[12]
END Size;

PROCEDURE Time*(): INTEGER;
CONST CLOCKBOOTTIME = 7;
VAR res: INTEGER; j: TimeVal;
BEGIN
  res:= KclockGettime64( CLOCKBOOTTIME, SYSTEM.ADR( j));
  RETURN j.sec * 1000 + j.usec DIV 1000000 - startTime
END Time;

PROCEDURE Mmap*( b: INTEGER ): INTEGER;
BEGIN  RETURN Kmmap(0, b, 3, MAPANONYMOUS + MAPPRIVATE,  -1, 0 )
END Mmap;

PROCEDURE Munmap*( a, b: INTEGER ): INTEGER;
BEGIN  RETURN Kmunmap(a, b)
END Munmap;

PROCEDURE Shmget*( key, size, shmflag: LONGINT): LONGINT;
BEGIN RETURN Kshmget( key, size, shmflag)
END Shmget;

PROCEDURE ShmAt*(shmid, addr, flags: LONGINT): LONGINT;
BEGIN
  RETURN Kshmat(shmid, addr, flags)
END ShmAt;

PROCEDURE ShmCtl*(buf, cmd, shmid: LONGINT): LONGINT;
BEGIN RETURN Kshmctl( buf, cmd, shmid)
END ShmCtl;

PROCEDURE Shmdt*(addr: LONGINT): LONGINT;
BEGIN RETURN Kshmdt( addr)
END Shmdt;

PROCEDURE Socket*( a: INTEGER): INTEGER;
BEGIN RETURN Ksocket( a, SOCKSTREAM, 0)
END Socket;

PROCEDURE Connect*( a, b, c: INTEGER): INTEGER;
BEGIN RETURN Kconnect( a, b, c)
END Connect;

(*
PROCEDURE Avail( fd, nsec: LONGINT): INTEGER;
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

PROCEDURE Ppoll*( fd, timeout: INTEGER ): INTEGER;
TYPE TimeSpec = RECORD sec0, sec1, nsec0, nsec1: LONGINT END;
VAR pollfd: RECORD fd, events, revents: INTEGER END;
  ts: TimeSpec;
BEGIN
  ts.sec0 := timeout DIV 1000; ts.sec1 := 0; ts.nsec0 := timeout MOD 1000 * 1000000; ts.nsec1 := 0;
  pollfd.fd := fd; pollfd.events := 1H; pollfd.revents := 0;
  RETURN Kppoll(SYSTEM.ADR(pollfd), 1, SYSTEM.ADR(ts), 0, 0, 0)
(*
  RETURN Avail( fd, timeout)
*)
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
  val[0] := 0X;
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

PROCEDURE SetJimm( imm: INTEGER): INTEGER;  (* imm in bytes *)
BEGIN
  RETURN LSL(ASR( imm, 20), 31) + LSL( imm MOD 800H, 20) + LSL( ASR(imm, 11) MOD 2, 20) + LSL( ASR(imm, 12) MOD 100H, 12)
END SetJimm;

PROCEDURE FixP*( adr, dest: INTEGER);  (* fix jumps, used in Modules*)
CONST RA = 1;  (* real RA *)
VAR offset, inst: INTEGER;
BEGIN
  offset  := dest - adr;
  IF (offset DIV 100000H) = (offset DIV 80000H) THEN SYSTEM.PUT(adr, JAL+ RA * 80H+ SetJimm(offset )); (* +-1MB *)
  ELSE
    SYSTEM.GET(adr + 4, inst);
    IF inst = NOP THEN (* +- 2GB *)
      SYSTEM.PUT(adr, AUIPC + (offset DIV 1000H + offset DIV 800H MOD 2) * 1000H + RA * 80H);
      SYSTEM.PUT(adr + 4, JALR + offset MOD 1000H * C20 + RA * 8000H + RA * 80H );
    ELSE LogS("Host.FixP"); LogL;
    END;
  END;
END FixP;

PROCEDURE FixD*( adr, dest: INTEGER);  (* fix data adresses, used in Modules *)
VAR inst, rs1 : INTEGER;
BEGIN
  SYSTEM.GET(adr +4, inst);
  rs1 := inst DIV 8000H MOD 20H;
  IF (inst MOD 80H = 23H) OR (inst MOD 80H = 27H) THEN (* store, fsw *)
    SYSTEM.PUT(adr+4, inst + LSL( dest DIV 20H MOD 80H, 25) + dest MOD 20H * 80H);
  ELSE
    SYSTEM.PUT(adr+4, inst +  dest MOD 1000H * C20);
  END;
  SYSTEM.PUT(adr, LUI + rs1 * 80H + LSL(ASR(dest, 12) + ASR(dest, 11) MOD 2, 12));
END FixD;

PROCEDURE Install*(Padr, at: INTEGER);    (* branch from at to Padr; module is hot, so flush cache *)
VAR offset, inst: INTEGER;
BEGIN
  offset  := Padr - at - dPC;
  IF ABS(offset) < 100000H THEN SYSTEM.PUT( at,  JAL+ SetJimm(offset )); (* +-1MB *)
  ELSE 
    SYSTEM.GET( at + 4, inst);
    IF inst = NOP THEN (* +- 2GB *)
      SYSTEM.PUT( at, AUIPC + (offset DIV 1000H + offset DIV 800H MOD 2) * 1000H + T0 * 80H );
      SYSTEM.PUT( at + 4, JALR + offset MOD 1000H * C20 + T0 * 8000H );
    ELSE LogS("Host.Install: ");
    END;
  END;
  Cacheflush( at, 16);
END Install;

PROCEDURE Init*;
VAR res: INTEGER;
BEGIN 
  appendix := cappendix; versionkey := cversionkey;

  FENCEI := SYSTEM.VAL( Syscall0, SYSTEM.ADR($0F10 0000 6780 0000$));  (*  FENCEI = 0000 100FH    *)
  Kopenat := SYSTEM.VAL( Syscall4, SYSTEM.ADR($9308 8003 7300 0000 6780 0000$));  (*  56 = 38H    *)
  Kclose := SYSTEM.VAL( Syscall1, SYSTEM.ADR($9308 9003 7300 0000 6780 0000$));   (*  57 = 39H    *)
  Kread := SYSTEM.VAL( Syscall3, SYSTEM.ADR($9308 F003 7300 0000 6780 0000$));  (*  63 = 3FH    *)
  Kwrite := SYSTEM.VAL( Syscall3, SYSTEM.ADR($9308 0004 7300 0000 6780 0000$));  (*  64 = 40H    *)
  Klseek := SYSTEM.VAL( Syscall5, SYSTEM.ADR($9308 E003 7300 0000 6780 0000$));  (*  62 = 3EH    *)
  Kwritev := SYSTEM.VAL( Syscall3, SYSTEM.ADR($9308 2004 7300 0000 6780 0000$));  (*  66 = 42H    *)
  Kmmap := SYSTEM.VAL( Syscall6, SYSTEM.ADR($9308 E00D 7300 0000 6780 0000$));  (*  222 = DEH    *)
  Kmunmap := SYSTEM.VAL( Syscall2, SYSTEM.ADR($9308 700D 7300 0000 6780 0000$));  (*  215 = D7H    *)

  Kppoll := SYSTEM.VAL( Syscall6, SYSTEM.ADR($9308 E019 7300 0000 67800000$));    (* 414=19EH ppoll_time64 *)
  Kclocknanosleep := SYSTEM.VAL( Syscall4, SYSTEM.ADR($9308 5006 7300 0000 6780 0000$)); (*   407=197H    *)
  Kpselect6time32 := SYSTEM.VAL( Syscall6, SYSTEM.ADR($9308 8004 7300 0000 6780 0000$));  (*  72 = 48H    *)

  Kfstat64 := SYSTEM.VAL( Syscall2, SYSTEM.ADR($9308 0005 7300 0000 6780 0000$));  (*  80 = 50H    *)
  KclockGettime64 := SYSTEM.VAL( Syscall2, SYSTEM.ADR($9308 3019 7300 0000 6780 0000$));  (*  403 = 193H; RV64: 113*)  

  Kioctl := SYSTEM.VAL( Syscall3, SYSTEM.ADR($9308 D001 7300 0000 6780 0000$));  (*  29 = 1DH    *)
  Ksocket := SYSTEM.VAL( Syscall3, SYSTEM.ADR($9308 600C 7300 0000 6780 0000$));  (*  198 = C6H    *)
  Kconnect := SYSTEM.VAL( Syscall3, SYSTEM.ADR($9308 B00C 7300 0000 6780 0000$));  (*  203 = CBH    *)
  Kshmget := SYSTEM.VAL( Syscall3, SYSTEM.ADR($9308 200C 7300 0000 6780 0000$));  (*  194 = C2H    *)
  Kshmat := SYSTEM.VAL( Syscall3, SYSTEM.ADR($9308 400C 7300 0000 6780 0000$));  (*  196 = C4H    *)
  Kshmdt := SYSTEM.VAL( Syscall1, SYSTEM.ADR($9308 500C 7300 0000 6780 0000$));  (*  197 = C5H    *)
  Kshmctl := SYSTEM.VAL( Syscall3, SYSTEM.ADR($9308 300C 7300 0000 6780 0000$));  (*  195 = C3H    *)
  Kexit := SYSTEM.VAL( Syscall1, SYSTEM.ADR($9308 D005 7300 0000 6780 0000$));  (*  93 = 5DH    *)
  
  startTime := Time();
  StackOrg := SYSTEM.REG( R5SP) + 12;
  SYSTEM.GET(StackOrg, NoOfArgs);

  LogS("StackOrg: "); LogH( StackOrg); LogL;
  LogS("NoOfArgs: "); LogH( NoOfArgs); LogL;
END Init;

END Host.