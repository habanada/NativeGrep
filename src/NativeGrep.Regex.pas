unit NativeGrep.Regex;

{$POINTERMATH ON}

interface

uses
  System.SysUtils, System.Classes, Winapi.Windows, NativePattern.Core, NativeGrep.Types;

type
  TPCRECompile = function(Pattern: PByte; PatternLength: NativeUInt; Options: Cardinal; ErrorCode: PInteger; ErrorOffset: PNativeUInt; Context: Pointer): Pointer; cdecl;
  TPCRECodeFree = procedure(Code: Pointer); cdecl;
  TPCREMatchDataCreate = function(Code, Context: Pointer): Pointer; cdecl;
  TPCREMatchDataFree = procedure(Data: Pointer); cdecl;
  TPCREMatch = function(Code: Pointer; Subject: PByte; SubjectLength, StartOffset: NativeUInt; Options: Cardinal; Data, Context: Pointer): Integer; cdecl;
  TPCREVector = function(Data: Pointer): PNativeUInt; cdecl;
  TPCREVectorCount = function(Data: Pointer): Cardinal; cdecl;
  TPCREContextCreate = function(Context: Pointer): Pointer; cdecl;
  TPCREContextFree = procedure(Context: Pointer); cdecl;
  TPCRESetLimit = function(Context: Pointer; Limit: Cardinal): Integer; cdecl;

  TGrepRegexPlan = class sealed
  private
    FLibrary: HMODULE;
    FCode: Pointer;
    FMatchData: Pointer;
    FMatchContext: Pointer;
    FPrefixSearcher: TSinglePatternSearcher;
    FPrefix: TBytes;
    FAllowInvalidUtf8: Boolean;
    FCompile: TPCRECompile;
    FCodeFree: TPCRECodeFree;
    FMatchDataCreate: TPCREMatchDataCreate;
    FMatchDataFree: TPCREMatchDataFree;
    FMatch: TPCREMatch;
    FVector: TPCREVector;
    FVectorCount: TPCREVectorCount;
    FContextCreate: TPCREContextCreate;
    FContextFree: TPCREContextFree;
    FSetMatchLimit: TPCRESetLimit;
    FSetDepthLimit: TPCRESetLimit;
    procedure LoadBackend;
    function HasRequiredPrefix(const Data: TBytes; StartByte, Count: Integer): Boolean;
  public
    constructor Create(const Query: TGrepQuery);
    destructor Destroy; override;
    procedure ScanStream(const SourceName: string; Stream: TStream; const Options: TGrepOptions;
      const IsCancelled: TFunc<Boolean>; const OnMatch: TProc<TGrepMatch>; var BytesRead: Int64;
      var ReadTicks, MatchTicks, PositionTicks, EnqueueTicks: Int64; var BufferAllocations: Integer; var Buffer: TBytes);
  end;

implementation

uses
  NativePattern, NativeGrep.Timing;

const
  GrepPcreDllLoadFlags: DWORD = $00001100;
  PcreUtf = $00080000;
  PcreMatchInvalidUtf = $04000000;
  PcreUcp = $00020000;
  PcreCaseless = $00000008;
  PcreMultiline = $00000400;
  PcreAnchored = $80000000;
  PcreNotEmptyAtStart = $00000008;
  PcreNoMatch = -1;

function RequiredAsciiPrefix(const Pattern: string; CaseFold: Boolean): TBytes;
var
  I, Depth, ClassDepth, PrefixEnd: Integer;
  Escaped: Boolean;
  Ch: Char;
begin
  Result := nil;
  if CaseFold or (Pos('(?', Pattern) > 0) or (Pos('(*', Pattern) > 0) or
    (Pos('\Q', Pattern) > 0) or (Pos('\E', Pattern) > 0) then Exit;
  PrefixEnd := 0;
  while PrefixEnd < Length(Pattern) do
  begin
    Ch := Pattern[PrefixEnd + 1];
    if not (((Ch >= 'A') and (Ch <= 'Z')) or ((Ch >= 'a') and (Ch <= 'z')) or
      ((Ch >= '0') and (Ch <= '9')) or (Ch = '_')) then Break;
    Inc(PrefixEnd);
  end;
  if PrefixEnd < 3 then Exit;
  if (PrefixEnd < Length(Pattern)) and (CharInSet(Pattern[PrefixEnd + 1], ['?', '*', '+', '{'])) then Exit;
  Depth := 0;
  ClassDepth := 0;
  Escaped := False;
  for I := 1 to Length(Pattern) do
  begin
    Ch := Pattern[I];
    if Escaped then
    begin
      Escaped := False;
      Continue;
    end;
    if Ch = '\' then
    begin
      Escaped := True;
      Continue;
    end;
    if Ch = '[' then
    begin
      Inc(ClassDepth);
      Continue;
    end;
    if (Ch = ']') and (ClassDepth > 0) then
    begin
      Dec(ClassDepth);
      Continue;
    end;
    if ClassDepth > 0 then Continue;
    if Ch = '(' then Inc(Depth)
    else if Ch = ')' then Dec(Depth)
    else if (Ch = '|') and (Depth = 0) then Exit;
  end;
  Result := TEncoding.ASCII.GetBytes(Copy(Pattern, 1, PrefixEnd));
end;

procedure TGrepRegexPlan.LoadBackend;
var
  Path: string;
  function Sym(const Name: AnsiString): Pointer;
  begin
    Result := GetProcAddress(FLibrary, PAnsiChar(Name));
    if Result = nil then raise EInvalidOpException.Create('PCRE2 symbol missing: ' + string(Name));
  end;
begin
  Path := ExtractFilePath(ParamStr(0)) + 'pcre2-8.dll';
  FLibrary := LoadLibraryEx(PChar(Path), 0, GrepPcreDllLoadFlags);
  if FLibrary = 0 then raise EInvalidOpException.Create('PCRE2 not available: place Win64 pcre2-8.dll beside npgrep.exe or the host application');
  FCompile := TPCRECompile(Sym('pcre2_compile_8'));
  FCodeFree := TPCRECodeFree(Sym('pcre2_code_free_8'));
  FMatchDataCreate := TPCREMatchDataCreate(Sym('pcre2_match_data_create_from_pattern_8'));
  FMatchDataFree := TPCREMatchDataFree(Sym('pcre2_match_data_free_8'));
  FMatch := TPCREMatch(Sym('pcre2_match_8'));
  FVector := TPCREVector(Sym('pcre2_get_ovector_pointer_8'));
  FVectorCount := TPCREVectorCount(Sym('pcre2_get_ovector_count_8'));
  FContextCreate := TPCREContextCreate(Sym('pcre2_match_context_create_8'));
  FContextFree := TPCREContextFree(Sym('pcre2_match_context_free_8'));
  FSetMatchLimit := TPCRESetLimit(Sym('pcre2_set_match_limit_8'));
  FSetDepthLimit := TPCRESetLimit(Sym('pcre2_set_depth_limit_8'));
end;

constructor TGrepRegexPlan.Create(const Query: TGrepQuery);
var
  Pattern: TBytes;
  ErrorCode: Integer;
  ErrorOffset: NativeUInt;
  Flags: Cardinal;
begin
  inherited Create;
  if Query.Text = '' then raise EArgumentException.Create('Regex pattern must not be empty');
    if not (Query.Encoding in [geAuto, geUtf8]) then raise EArgumentException.Create('Regex supports UTF-8 and automatic UTF-8 detection only');
    if Query.CaseInsensitiveAscii then raise EArgumentException.Create('Regex ASCII-only ignore-case is not supported; use --ignore-case=unicode');
    if Query.UnicodeNormalizeNfd or Query.FuzzyCodePoints or (Query.MaxDistance <> 0) then
      raise EArgumentException.Create('Regex cannot be combined with NFD normalization or fuzzy search');
    FAllowInvalidUtf8 := Query.RegexAllowInvalidUtf8;
    LoadBackend;
    Pattern := TEncoding.UTF8.GetBytes(Query.Text);
    ErrorCode := 0;
    ErrorOffset := 0;
    Flags := PcreUtf or PcreUcp or PcreMultiline;
    if Query.UnicodeCaseFold then Flags := Flags or PcreCaseless;
    if FAllowInvalidUtf8 then Flags := Flags or PcreMatchInvalidUtf;
    FCode := FCompile(@Pattern[0], Length(Pattern), Flags, @ErrorCode, @ErrorOffset, nil);
    if FCode = nil then raise EArgumentException.CreateFmt('Invalid PCRE2 pattern: code=%d at UTF-8 byte=%d', [ErrorCode, Int64(ErrorOffset)]);
    FMatchData := FMatchDataCreate(FCode, nil);
    FMatchContext := FContextCreate(nil);
    if (FMatchData = nil) or (FMatchContext = nil) then raise EOutOfMemory.Create('PCRE2 allocation failed');
    if FVectorCount(FMatchData) > 256 then raise EArgumentOutOfRangeException.Create('Regex has more than 255 capture groups');
    FPrefix := RequiredAsciiPrefix(Query.Text, Query.UnicodeCaseFold);
    if Length(FPrefix) > 0 then FPrefixSearcher := TPatternSearch.Compile(FPrefix);
end;

destructor TGrepRegexPlan.Destroy;
begin
  FPrefixSearcher.Free;
  if FMatchData <> nil then FMatchDataFree(FMatchData);
  if FMatchContext <> nil then FContextFree(FMatchContext);
  if FCode <> nil then FCodeFree(FCode);
  if FLibrary <> 0 then FreeLibrary(FLibrary);
  inherited;
end;

function TGrepRegexPlan.HasRequiredPrefix(const Data: TBytes; StartByte, Count: Integer): Boolean;
var
  M: TPatternMatch;
begin
  if FPrefixSearcher = nil then Exit(True);
  if Count < Length(FPrefix) then Exit(False);
  M := FPrefixSearcher.FindFirst(@Data[StartByte], Count, 0);
  Result := M.Found;
end;

function InvalidUtf8Offset(const Data: TBytes; StartByte, Limit: Integer): Integer;
var
  I, Remaining: Integer;
  B, Minimum, Maximum: Byte;
begin
  I := StartByte;
  Remaining := 0;
  Minimum := $80;
  Maximum := $BF;
  while I < Limit do
  begin
    B := Data[I];
    if Remaining <> 0 then
    begin
      if (B < Minimum) or (B > Maximum) then Exit(I);
      Dec(Remaining);
      Minimum := $80;
      Maximum := $BF;
    end
    else if B < $80 then Remaining := 0
    else if (B >= $C2) and (B <= $DF) then Remaining := 1
    else if B = $E0 then
    begin
      Remaining := 2;
      Minimum := $A0;
    end
    else if ((B >= $E1) and (B <= $EC)) or ((B >= $EE) and (B <= $EF)) then Remaining := 2
    else if B = $ED then
    begin
      Remaining := 2;
      Maximum := $9F;
    end
    else if B = $F0 then
    begin
      Remaining := 3;
      Minimum := $90;
    end
    else if (B >= $F1) and (B <= $F3) then Remaining := 3
    else if B = $F4 then
    begin
      Remaining := 3;
      Maximum := $8F;
    end
    else Exit(I);
    Inc(I);
  end;
  if Remaining <> 0 then Exit(Limit);
  Result := -1;
end;

procedure StepPosition(const Data: TBytes; var Position: Integer; Stop: Integer; var Line, Column: Int64; var LastCR: Boolean);
var
  B: Byte;
begin
  while Position < Stop do
  begin
    B := Data[Position];
    if B = 13 then
    begin
      Inc(Line);
      Column := 1;
      LastCR := True;
    end
    else if B = 10 then
    begin
      if not LastCR then Inc(Line);
      Column := 1;
      LastCR := False;
    end
    else if (B and $C0) <> $80 then
    begin
      LastCR := False;
      if B >= $F0 then Inc(Column, 2) else Inc(Column);
    end;
    Inc(Position);
  end;
end;

function NextBoundary(const Data: TBytes; Offset, Limit: Integer): Integer;
begin
  Result := Offset + 1;
  while (Result < Limit) and ((Data[Result] and $C0) = $80) do Inc(Result);
end;

procedure TGrepRegexPlan.ScanStream(const SourceName: string; Stream: TStream; const Options: TGrepOptions;
  const IsCancelled: TFunc<Boolean>; const OnMatch: TProc<TGrepMatch>; var BytesRead: Int64;
  var ReadTicks, MatchTicks, PositionTicks, EnqueueTicks: Int64; var BufferAllocations: Integer; var Buffer: TBytes);
var
  Data: TBytes;
  Capacity, Used, N, StartByte, SubjectLength, Cursor, Rc, I, Groups, Position, MatchStart: Integer;
  MatchFlags: Cardinal;
  Stamp: Int64;
  Vector: PNativeUInt;
  Match: TGrepMatch;
  TrackPosition, LastCR: Boolean;
  InvalidByte: Integer;
  Line, Column, Emitted: Int64;
  Subject: PByte;
begin
  if Length(Buffer) <> 65536 then
  begin
    SetLength(Buffer, 65536);
    Inc(BufferAllocations);
  end;
  Used := 0;
  Capacity := 0;
  while True do
  begin
    if IsCancelled() then Exit;
    Stamp := GrepTimestamp;
    try
      N := Stream.Read(Buffer[0], Length(Buffer));
    finally
      Inc(ReadTicks, GrepTimestamp - Stamp);
    end;
    Inc(BytesRead, N);
    if N = 0 then Break;
    if Int64(Used) + N > Options.RegexMaxBytes then
      raise EArgumentOutOfRangeException.CreateFmt('Regex source exceeds %d bytes; increase --regex-max-mib', [Options.RegexMaxBytes]);
    if Used + N > Capacity then
    begin
      Capacity := Capacity * 2;
      if Capacity < 65536 then Capacity := 65536;
      if Capacity < Used + N then Capacity := Used + N;
      if Capacity > Options.RegexMaxBytes then Capacity := Integer(Options.RegexMaxBytes);
      SetLength(Data, Capacity);
    end;
    Move(Buffer[0], Data[Used], N);
    Inc(Used, N);
  end;
  StartByte := 0;
  if Used >= 2 then
    if ((Data[0] = $FF) and (Data[1] = $FE)) or ((Data[0] = $FE) and (Data[1] = $FF)) then
      raise EArgumentException.Create('Regex currently requires UTF-8; UTF-16 BOM detected');
  if (Used >= 3) and (Data[0] = $EF) and (Data[1] = $BB) and (Data[2] = $BF) then StartByte := 3;
  SubjectLength := Used - StartByte;
  InvalidByte := InvalidUtf8Offset(Data, StartByte, Used);
  if (InvalidByte >= 0) and not FAllowInvalidUtf8 then
    raise EArgumentException.CreateFmt('Invalid UTF-8 at byte %d; use --regex-invalid-utf to search valid UTF-8 regions', [InvalidByte]);
  if not HasRequiredPrefix(Data, StartByte, SubjectLength) then Exit;
  SetLength(Data, Used);
  if SubjectLength = 0 then Subject := nil else Subject := @Data[StartByte];
  FSetMatchLimit(FMatchContext, Options.RegexMatchLimit);
  FSetDepthLimit(FMatchContext, Options.RegexDepthLimit);
  Cursor := 0;
  MatchFlags := 0;
  Position := StartByte;
  Line := 1;
  Column := 1;
  LastCR := False;
  Emitted := 0;
  TrackPosition := (Options.TextPositions <> gtpNone) and (Options.BinaryPolicy <> gbRaw) and (InvalidByte < 0);
  while Cursor <= SubjectLength do
  begin
    if IsCancelled() then Exit;
    Stamp := GrepTimestamp;
    try
      Rc := FMatch(FCode, Subject, SubjectLength, Cursor, MatchFlags, FMatchData, FMatchContext);
    finally
      Inc(MatchTicks, GrepTimestamp - Stamp);
    end;
    if Rc = PcreNoMatch then
    begin
      if MatchFlags = 0 then Break;
      MatchFlags := 0;
      if Cursor = SubjectLength then Break;
      Cursor := NextBoundary(Data, Cursor + StartByte, Used) - StartByte;
      Continue;
    end;
    if Rc < 0 then raise EInvalidOpException.CreateFmt('PCRE2 match failed (%d) in %s', [Rc, SourceName]);
    Vector := FVector(FMatchData);
    if (Vector[1] > NativeUInt(SubjectLength)) or (Vector[0] > Vector[1]) then
      raise EInvalidOpException.Create('PCRE2 returned an invalid match range');
    MatchStart := Integer(Vector[0]) + StartByte;
    Match := Default(TGrepMatch);
    Match.SourcePath := SourceName;
    Match.ByteOffset := MatchStart;
    Match.ByteLength := Vector[1] - Vector[0];
    Match.PatternIndex := 0;
    if TrackPosition then
    begin
      Stamp := GrepTimestamp;
      StepPosition(Data, Position, MatchStart, Line, Column, LastCR);
      Match.Line := Line;
      Match.Column := Column;
      Inc(PositionTicks, GrepTimestamp - Stamp);
    end;
    Groups := Integer(FVectorCount(FMatchData));
    SetLength(Match.Captures, Groups - 1);
    for I := 1 to Groups - 1 do
    begin
      Match.Captures[I - 1].Index := I;
      Match.Captures[I - 1].Matched := Vector[I * 2] <> High(NativeUInt);
      if Match.Captures[I - 1].Matched then
      begin
        Match.Captures[I - 1].ByteOffset := Int64(Vector[I * 2]) + StartByte;
        Match.Captures[I - 1].ByteLength := Vector[I * 2 + 1] - Vector[I * 2];
      end;
    end;
    Stamp := GrepTimestamp;
    try
      OnMatch(Match);
    finally
      Inc(EnqueueTicks, GrepTimestamp - Stamp);
    end;
    Inc(Emitted);
    if (Options.MaxMatchesPerFile > 0) and (Emitted >= Options.MaxMatchesPerFile) then Exit;
    if Vector[0] = Vector[1] then
    begin
      Cursor := Integer(Vector[1]);
      MatchFlags := PcreNotEmptyAtStart or PcreAnchored;
    end
    else
    begin
      Cursor := Integer(Vector[1]);
      MatchFlags := 0;
    end;
  end;
end;

end.
