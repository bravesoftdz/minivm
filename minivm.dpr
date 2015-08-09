program minivm;

{$APPTYPE CONSOLE}

uses
  Windows, Classes, SysUtils;

type
  TOpFunction = procedure;

var
 fs: TFileStream;
 res: Cardinal;
 ops, ptr_op, ptr_dll, ptr_str, ptr_opEnd: PByte;
 sz: Cardinal;
 dllOffset, opOffset: Cardinal;
 dllHnd: Cardinal;
 dllFunc: TList;
 slots: array[0..255] of Byte;
 OpTable: array[0..3] of TOpFunction;
 funcStack: TList;

// Opcodes

procedure Op_PushString;
begin
  Inc(ptr_op);
  // Add string virtual address
  funcStack.Add(Pointer(PWord(ptr_op)^));
  Inc(ptr_op, sizeof(Word));
end;

procedure Op_Call;
var j: Integer;
    fPtr, oPtr: Pointer;
begin
  Inc(ptr_op);
  fPtr := dllFunc[PWord(ptr_op)^];
  Inc(ptr_op, sizeof(Word));

  // Preserve eax
  asm
    push eax
  end;

  // Push all operands from internal stack onto function stack
  for j := funcStack.Count-1 downto 0 do begin
    oPtr := funcStack[j];
    asm
      push oPtr
    end;
  end;

  // Call DLL function
  asm
    call fPtr
  end;

  // Move result to `res` for preservation
  asm
    mov [res], eax
  end;

  // Pop operands
  for j := 0 to funcStack.Count-1 do asm
    pop eax
  end;
  funcStack.Clear;

  // Preserve eax
  asm
    pop eax
  end;
end;

procedure Op_StoreResult;
begin
  Inc(ptr_op);
  slots[ptr_op^] := res;
  Inc(ptr_op);
end;

procedure Op_PushSlot;
begin
  Inc(ptr_op);
  funcStack.Add(Pointer(slots[ptr_op^]));
  Inc(ptr_op);
end;

// Opcodes end

function ReadString(var ptr: PByte): PChar;
begin
  Result := PChar(ptr);
  while ptr^ > 0 do Inc(ptr);
  Inc(ptr);
end;

begin
  fs := TFileStream.Create('simple2.b', fmOpenRead);
  sz := fs.Size-(sizeof(Cardinal)*2);
  ops := AllocMem(sz);
  fs.Read(ops^, sz);
  fs.Read(dllOffset, sizeof(Cardinal));
  fs.Read(opOffset, sizeof(Cardinal));
  fs.Free;

  // Initialize op table
  OpTable[0] := Op_PushString;
  OpTable[1] := Op_Call;
  OpTable[2] := Op_StoreResult;
  OpTable[3] := Op_PushSlot;

  ptr_str := ops;
  ptr_dll := PByte(Cardinal(ops) + dllOffset);
  ptr_op := PByte(Cardinal(ops) + opOffset);
  ptr_opEnd := PByte(Cardinal(ops) + sz);

  // NOTE: String table remains in memory untouched
  // Register DLL functions
  dllFunc := TList.Create;
  while Cardinal(ptr_dll) < Cardinal(ptr_op) do begin
    if ptr_dll^ = 1 then begin
      // LoadLibrary
      Inc(ptr_dll);
      dllHnd := LoadLibrary(ReadString(ptr_dll));
    end else if ptr_dll^ = 2 then begin
      // GetProcAddress
      Inc(ptr_dll);
      dllFunc.Add(GetProcAddress(dllHnd, ReadString(ptr_dll)));
    end else MessageBox(0, 'Invalid DLL table opcode', 'VM error', 0);
  end;

  // Opcode execution
  funcStack := TList.Create;
  while Cardinal(ptr_op) < Cardinal(ptr_opEnd) do begin
    Writeln(ptr_op^);
    OpTable[ptr_op^]();
  end;
end.
