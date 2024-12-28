MODULE Disk;  (*NW/PR  11.4.86 / 27.12.95 / 4.2.2014 / AP 1.1.22 Extended Oberon*)
  IMPORT SYSTEM, Host;
  CONST SectorLength* = 1024;
(*
    FSoffset = 80000H; (*256MB in 512-byte blocks*)
    FSoffset = -1;
*)
    mapsize = 10000H; (*1K sectors, 64MB*)
    defaultDisk = "RISC.dsk";

  TYPE Sector* = ARRAY SectorLength OF BYTE;

  VAR NofSectors*: INTEGER;
    sectorMap: ARRAY mapsize DIV 32 OF SET;
    disk, FSoffset : INTEGER;

  PROCEDURE InitSecMap*;
    VAR i: INTEGER;
  BEGIN NofSectors := 0;
    FOR i := 0 TO 5 DO sectorMap[i] := {0 .. 31} END ;           (*mark blocks 0-191 (=6*32 = 192 blocks) as allocated*)
    FOR i := 6 TO mapsize DIV 32 - 1 DO sectorMap[i] := {} END   (*mark blocks 192-65536 (=64K-192 blocks) as unallocated*)
  END InitSecMap;

  PROCEDURE MarkSector*(sec: INTEGER);
  VAR s: INTEGER;
  BEGIN s := sec DIV 29; ASSERT(s * 29 = sec);
    INCL(sectorMap[s DIV 32], s MOD 32); INC(NofSectors)
  END MarkSector;

  PROCEDURE FreeSector*(sec: INTEGER);
  VAR s: INTEGER;
  BEGIN s := sec DIV 29; ASSERT(s * 29 = sec);
    EXCL(sectorMap[s DIV 32], s MOD 32); DEC(NofSectors)
  END FreeSector;

  PROCEDURE AllocSector*(hint: INTEGER; VAR sec: INTEGER);
    VAR s: INTEGER;
  BEGIN (*find free sector, starting after hint*)
    s := hint DIV 29; ASSERT(s * 29 = hint);
    REPEAT INC(s);
      IF s = mapsize THEN s := 1 END ;
    UNTIL ~(s MOD 32 IN sectorMap[s DIV 32]);
    INCL(sectorMap[s DIV 32], s MOD 32); INC(NofSectors); sec := s * 29
  END AllocSector;

  PROCEDURE GetSector*(src: INTEGER; VAR dst: Sector);
  VAR s: INTEGER;
  BEGIN s := src DIV 29; ASSERT(s * 29 = src); 
    IF Host.Read2( disk, SYSTEM.ADR(dst), SectorLength, (s + FSoffset) * SectorLength) # SectorLength THEN
      Host.LogS("GetSector"); Host.LogL;
    END
  END GetSector;
  
  PROCEDURE PutSector*(dst: INTEGER; VAR src: Sector);
  VAR s: INTEGER;
  BEGIN s := dst DIV 29; ASSERT(s * 29 = dst);
    IF Host.Write2( disk, SYSTEM.ADR(src), SectorLength, (s + FSoffset) * SectorLength) # SectorLength THEN
      Host.LogS("PutSector"); Host.LogL;
    END
  END PutSector;

  PROCEDURE Init*;
  VAR name: ARRAY 32 OF CHAR; i, size: INTEGER;
  BEGIN InitSecMap;
    IF ~Host.GetEnv("ODISK", name) THEN name := defaultDisk END;
    disk := Host.Open( name, TRUE, FALSE);
    size := Host.Size(disk);
    IF size > 10000000H THEN FSoffset := 40000H ELSE FSoffset := -1 END;
    Host.LogS(name); Host.LogH(size); Host.LogL;
    i := Host.Read2(disk, SYSTEM.ADR(size), 4, (FSoffset + 1) * 1024); 
    IF size # 9B1EA38DH THEN Host.LogS("wrong format of disk file: "); Host.LogH(size); Host.LogL; Host.Exit(2) END;
  END Init;

END Disk.
