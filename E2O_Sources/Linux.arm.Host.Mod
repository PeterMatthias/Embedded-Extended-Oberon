MODULE Host;  
IMPORT SYSTEM;

(* 
  Access to Linux ARM32 Kernel an logging disassembler at disam.pro

ARM32: MOVW R7, Nr.; SVC; BX LR =>  E30d7cba, EF000000, E12FFF1E = 0127003EH, 000000FEH, E1FFF21EH
        MOVT E34drcba;

    Peter Matthias

    2024-08-25  started
    2024-11-17  cleaned up, using common symbol file
    2024-11-18  FixP, FixD: adopted for optimized OAG.fixcode, OAG.fixvar
    2024-11-25  Install: probably fixed startup crashes by adding Cacheflush
    2024-11-28  Cacheflush: remove loop as qemu does not return 0
    2024-12-13  init rounding fp to int to -inf; ARMv8 has own instruction
    2024-12-18  Read2, Write2: use pread64, pwrite64
    2024-12-19  removed virtual registers, mapping registers in OAG

    Set rounding mode to -inf
    EEF10A10; -> 100AF1EE:  VMRS, RH, 1
            -> 020580E3:  ORR RH, RH, 00800000H
    EEE10A10; -> 100AE1EE:  VMSR, 1, RH

*)

CONST
  pbase* = 10080H;  (* base of the system, 80H is size of ELF header *)
  TrapAdr* = 4;
  dPC = 2; R5SP = 14;  (* RISC5 SP *)
  cappendix = ".arm"; cversionkey = 3X;

  (* domain in Socket *)  
  PFUNIX* = 1;  PFINET* = 2;
  SOCKSTREAM = 1;    (* was 1 for X86, RISC-V and ARM, 2 for MIPS *)
  (** Open( .. ) flags *)
  ORDonly = 0;  OWRonly = 1;  ORDWR = 2;  OCREAT = 40H;  OEXCL = 80H;  
  OTRUNC = 200H;  OAPPEND = 400H;  ODSYNC = 1000H;(* from MIPS *)
  ATFDCWD = -100;  (* use current working directory *)  ODirectory = 0;
  (** FLock( .. ) *) (*  LOCKEX= 2;  LOCKNB= 4;  LOCKUN= 8;*)
  (** LSeek *)  SEEKSET=0;  SEEKCURRENT=1;  SEEKEND=2;
  (** Mmap *)  MAPSHARED=1;  MAPPRIVATE=2;  MAPFIXED=10H;  MAPANONYMOUS = 20H;  (* ARM: 20H; MIPS: 800H *)
  PROTREAD=1;  PROTWRITE=2;  PROTEXEC=4;

TYPE
  Syscall1 = PROCEDURE( a: INTEGER): INTEGER;
  Syscall2 = PROCEDURE( a, b: INTEGER): INTEGER;
  Syscall3 = PROCEDURE( a, b, c: INTEGER): INTEGER;
  Syscall4 = PROCEDURE( a, b, c, d: INTEGER): INTEGER;
  Syscall6 = PROCEDURE( a, b, c, d, e, f: INTEGER): INTEGER;

VAR
  appendix*: ARRAY 8 OF CHAR;
  versionkey* : CHAR;
  Kopenat : Syscall4;
  Kclose : Syscall1;
  Kread : Syscall3;
  Kwrite : Syscall3;
  Kpread64 : Syscall6;
  Kpwrite64 : Syscall6;
(*  Kreadv : Syscall3;*)
  Kwritev : Syscall3;
  Kseek : Syscall3;
  Kfstat64 : Syscall2;
  Kmmap2 : Syscall6;
  Kmunmap : Syscall2;
  Kpoll: Syscall3;
(*  Kpselect6 : Syscall6;*)
  KClockGettime : Syscall2;
  Kcacheflush : Syscall3;
  Kioctl :  Syscall3;
  Ksocket : Syscall3;
  Kconnect : Syscall3;
  Kshmget : Syscall3;
  Kshmat : Syscall3;
  Kshmdt : Syscall1;
  Kshmctl : Syscall3;
  Kexit, setRMode : Syscall1;

    startTime, StackOrg, NoOfArgs : INTEGER; 

PROCEDURE Cacheflush*( beg, size: INTEGER);
VAR i: INTEGER;
BEGIN  i := Kcacheflush( beg, beg + size, 0)  (* flags must always be 0 *)
END Cacheflush;

PROCEDURE Exit*( a: INTEGER);
VAR i: INTEGER;
BEGIN  i := Kexit(a);
END Exit;

PROCEDURE Open*( name: ARRAY OF CHAR; write, new: BOOLEAN): INTEGER;  (* 1F7 rwxr--r-x *)
BEGIN  RETURN Kopenat( ATFDCWD, SYSTEM.ADR(name), ORD(write)* 2+ ORD(new)*240H, 01A0H)
END Open;

PROCEDURE Close*( fd: INTEGER): INTEGER;
BEGIN  RETURN Kclose( fd)
END Close;

PROCEDURE Read*( fd, adr, size: INTEGER ): INTEGER;
BEGIN  RETURN Kread( fd, adr, size)
END Read;

PROCEDURE Write*( fd, adr, size: INTEGER ): INTEGER;
BEGIN  RETURN Kwrite( fd, adr, size)
END Write;

PROCEDURE Read2*( fd, adr, size, pos: INTEGER): INTEGER;
BEGIN  RETURN Kpread64( fd, adr, size, 0, pos, 0)
END Read2;

PROCEDURE Write2*( fd, adr, size, pos: INTEGER ): INTEGER;
BEGIN  RETURN Kpwrite64( fd, adr, size, 0, pos, 0)
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
VAR res: INTEGER; j: RECORD sec, usec: INTEGER END;
BEGIN
  res:= KClockGettime( CLOCKBOOTTIME, SYSTEM.ADR( j));
  RETURN j.sec*1000 + j.usec DIV 1000000 - startTime
END Time;

PROCEDURE Mmap*( b: INTEGER ): INTEGER;
BEGIN  RETURN Kmmap2(0, b, 3, MAPANONYMOUS + MAPPRIVATE,  -1, 0 )
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
PROCEDURE Pselect( a, b, c, d, e, f: INTEGER ): INTEGER;
BEGIN  RETURN Kpselect6(a, b, c, d, e, f)
END Pselect;
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
    SYSTEM.GET( StackOrg+(n+1)* 4, l);
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
  sadr:= StackOrg+(NoOfArgs+2)* 4;
  SYSTEM.GET( sadr, n);
  val[0]:=0X;
  WHILE (n#0) & (n < sadr + 100000H) & (val[0]=0X)  DO
    SYSTEM.GET(n, ch);
    j:=0;
    WHILE ch=env[j] DO
      INC(n); SYSTEM.GET(n, ch); INC(j);
    END;
    IF env[j]= 0X THEN
      j:=0; 
      REPEAT
        INC(n);
        SYSTEM.GET(n, ch);
        val[j]:=ch; INC(j);
      UNTIL ch=0X;
      LogS(val);
    END;
    INC(sadr, 4);  
    SYSTEM.GET( sadr, n);
  END;
  LogL;
  RETURN val[0] # 0X
END GetEnv;

PROCEDURE FixP*( adr, dest: INTEGER);  (* used in Modules *)
CONST BL =  0EB000000H; C24 = 1000000H;
BEGIN SYSTEM.PUT(adr, BL + ((dest - adr) DIV 4 - dPC ) MOD C24 );
END FixP;

PROCEDURE FixD*( adr, dest: INTEGER);  (* used in Modules inst always is MOVT*)
CONST C16 = 10000H; C28 = 10000000H; MOVT =  0E3400000H; MOVW =  0E3000000H;
VAR inst : INTEGER;
BEGIN
  SYSTEM.GET(adr + 4, inst);
  SYSTEM.PUT(adr, MOVW + dest DIV 1000H MOD 10H * C16 + inst DIV 1000H MOD 10H * 1000H + dest MOD 1000H  );
  SYSTEM.PUT(adr + 4, inst + dest DIV C28 MOD 10H * C16 + dest DIV C16 MOD 1000H );
END FixD;

PROCEDURE Install*(Padr, at: INTEGER);    (* branch from at to Padr; module is hot -> flush cache*)
CONST B = 0EA000000H;
BEGIN  SYSTEM.PUT(at, B + ((Padr - at) DIV 4 - dPC) MOD 1000000H);
  Cacheflush( at, 16);
END Install;

PROCEDURE Init*;
VAR res: INTEGER;
BEGIN
  appendix := cappendix; versionkey := cversionkey;
          (*  0..8000 0000H flushed  *)
  Kcacheflush := SYSTEM.VAL( Syscall3, SYSTEM.ADR($0270 00E3  0F70 40E3  0000 00EF  1EFF 2FE1$)); (* 0F0002 *)
  Kopenat := SYSTEM.VAL( Syscall4, SYSTEM.ADR($4271 00E3  0000 00EF  1EFF 2FE1$));  (* 142H  56 = 38H    *)
  Kclose := SYSTEM.VAL( Syscall1, SYSTEM.ADR($0670 00E3  0000 00EF  1EFF 2FE1$));   (*6  57 = 39H    *)
  Kread := SYSTEM.VAL( Syscall3, SYSTEM.ADR($0370 00E3  0000 00EF  1EFF 2FE1$));  (*3  63 = 3FH    *)
  Kwrite := SYSTEM.VAL( Syscall3, SYSTEM.ADR($0470 00E3  0000 00EF  1EFF 2FE1$));  (*4  64 = 40H    *)
  Kpread64 := SYSTEM.VAL( Syscall6, SYSTEM.ADR($B470 00E3  0000 00EF  1EFF 2FE1$));  (* 0B4H      *)
  Kpwrite64 := SYSTEM.VAL( Syscall6, SYSTEM.ADR($B570 00E3  0000 00EF  1EFF 2FE1$));  (* 0B5H      *)
(*  Kreadv := SYSTEM.VAL( Syscall3, SYSTEM.ADR($9170 00E3  0000 00EF  1EFF 2FE1$));*)  (*91H  66 = 42H    *)
  Kwritev := SYSTEM.VAL( Syscall3, SYSTEM.ADR($9270 00E3  0000 00EF  1EFF 2FE1$));  (*92H  66 = 42H    *)
  Kseek := SYSTEM.VAL( Syscall3, SYSTEM.ADR($1370 00E3  0000 00EF  1EFF 2FE1$));  (*19 = 13H  62 = 3EH    *)
  Kmmap2 := SYSTEM.VAL( Syscall6, SYSTEM.ADR($C070 00E3  0000 00EF  1EFF 2FE1$));  (*C070 00E3 ;192  222 = DEH*)
  Kmunmap := SYSTEM.VAL( Syscall2, SYSTEM.ADR($5B70 00E3  0000 00EF  1EFF 2FE1$));  (*91  215 = D7H    *)
  Kpoll := SYSTEM.VAL( Syscall3, SYSTEM.ADR($A870 00E3  0000 00EF  1EFF 2FE1$));    (* A8H poll, 15H ppoll*)
(*  Kpselect6 := SYSTEM.VAL( Syscall6, SYSTEM.ADR($4F71 00E3  0000 00EF  1EFF 2FE1$));*)  (*14FH   72 = 48H    *)
  Kfstat64 := SYSTEM.VAL( Syscall2, SYSTEM.ADR($C570 00E3  0000 00EF  1EFF 2FE1$));  (*0C5H=197  80 = 50H    *)
  KClockGettime := SYSTEM.VAL( Syscall2, SYSTEM.ADR($0771 00E3  0000 00EF  1EFF 2FE1$));  (*107H  403 = 193H; RV64: 113    *)
  
  Kioctl := SYSTEM.VAL( Syscall3, SYSTEM.ADR($1D70 00E3  0000 00EF  1EFF 2FE1$));  (*  29 = 1DH    *)
  Ksocket := SYSTEM.VAL( Syscall3, SYSTEM.ADR($1971 00E3  0000 00EF  1EFF 2FE1$));  (*119H  198 = C6H    *)
  Kconnect := SYSTEM.VAL( Syscall3, SYSTEM.ADR($1B71 00E3  0000 00EF  1EFF 2FE1$));  (*11BH  203 = CBH    *)
  Kshmget := SYSTEM.VAL( Syscall3, SYSTEM.ADR($3371 00E3  0000 00EF  1EFF 2FE1$));  (*133H  194 = C2H    *)
  Kshmat := SYSTEM.VAL( Syscall3, SYSTEM.ADR($3171 00E3  0000 00EF  1EFF 2FE1$));  (*131H  196 = C4H    *)
  Kshmdt := SYSTEM.VAL( Syscall1, SYSTEM.ADR($3271 00E3  0000 00EF  1EFF 2FE1$));  (*132H  197 = C5H    *)
  Kshmctl := SYSTEM.VAL( Syscall3, SYSTEM.ADR($3471 00E3  0000 00EF  1EFF 2FE1$));  (*134H  195 = C3H    *)
  Kexit := SYSTEM.VAL( Syscall1, SYSTEM.ADR($0170 00E3  0000 00EF  1EFF 2FE1$));  (*1  93 = 5DH    *)
  StackOrg := SYSTEM.REG( R5SP)+12;
  setRMode := SYSTEM.VAL( Syscall1, SYSTEM.ADR($ 100AF1EE 020580E3 100AE1EE 1EFF2FE1$));
  res := setRMode(0);
  startTime:= Time();
  LogS("StackOrg: "); LogH( StackOrg); LogL;
  SYSTEM.GET(StackOrg, NoOfArgs);
  LogS("NoOfArgs: "); LogH( NoOfArgs); LogL;
  LogS("FPCR    : "); LogH( res); LogL;
END Init;

END Host.