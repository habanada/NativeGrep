unit NativeGrep.Matcher;

interface

uses
  System.SysUtils, NativePattern, NativePattern.Core, NativeGrep.Types, NativeGrep.Unicode, NativeGrep.Regex;

type
  TGrepMatcher = class sealed
  private
    FSingle: TSinglePatternSearcher;
    FMulti: TMultiPatternSearcher;
    FPatterns: TArray<TBytes>;
    FMode: TGrepMode;
    FEncoding: TGrepEncoding;
    FIgnoreAscii: Boolean;
    FWindowLength: Integer;
    FMultiCount: Integer;
    FAutomatic: TArray<TGrepMatcher>;
    FUnicode: TGrepUnicodePlan;
    FRegex: TGrepRegexPlan;
    procedure Prepare(const Query: TGrepQuery);
  public
    constructor Create(const Query: TGrepQuery);
    destructor Destroy; override;
    function ForEncoding(Detected: TGrepEncoding): TGrepMatcher;
    function FindFirst(const Buffer: TBytes; Available, StartIndex: Integer): TPatternMatch;
    function MatchAt(const Buffer: TBytes; Available, Offset, PatternIndex: Integer): Boolean;
    procedure Normalize(var Buffer: TBytes; FirstIndex, Count: Integer; BaseOffset: Int64);
    function ValidTextOffset(Offset: Int64): Boolean;
    property WindowLength: Integer read FWindowLength;
    function IsMulti: Boolean;
    property UnicodePlan: TGrepUnicodePlan read FUnicode;
    property RegexPlan: TGrepRegexPlan read FRegex;
    property Encoding: TGrepEncoding read FEncoding;
    property Mode: TGrepMode read FMode;
    function PatternLength(Index: Integer): Integer;
    property MultiCount: Integer read FMultiCount;
  end;

implementation

function FoldAscii(const Value: string): string;
var
  I: Integer;
begin
  Result := Value;
  for I := 1 to Length(Result) do
    if (Result[I] >= 'A') and (Result[I] <= 'Z') then Result[I] := Char(Ord(Result[I]) + 32);
end;

function EncodeText(const Value: string; Encoding: TGrepEncoding): TBytes;
var
  I: Integer;
  V: string;
begin
  V := Value;
  case Encoding of
    geUtf8: Result := TEncoding.UTF8.GetBytes(V);
    geUtf16LE, geUtf16BE:
      begin
        SetLength(Result, Length(V) * 2);
        if Length(Result) > 0 then Move(PChar(V)^, Result[0], Length(Result));
        if Encoding = geUtf16BE then
          for I := 0 to (Length(Result) div 2) - 1 do
          begin
            Result[I * 2] := Byte(Ord(V[I + 1]) shr 8);
            Result[I * 2 + 1] := Byte(Ord(V[I + 1]) and $FF);
          end;
      end;
  end;
end;

constructor TGrepMatcher.Create(const Query: TGrepQuery);
begin
  inherited Create;
  Prepare(Query);
end;

destructor TGrepMatcher.Destroy;
var
  Child: TGrepMatcher;
begin
  for Child in FAutomatic do Child.Free;
  FMulti.Free;
  FSingle.Free;
  FUnicode.Free;
  FRegex.Free;
  inherited;
end;

procedure TGrepMatcher.Prepare(const Query: TGrepQuery);
var
  I, Len: Integer;
  AggregateLength: Int64;
  Value: string;
  Bytes: TBytes;
  ChildQuery: TGrepQuery;
begin
  FMode := Query.Mode;
  FEncoding := Query.Encoding;
  FIgnoreAscii := Query.CaseInsensitiveAscii;
  FWindowLength := 0;
  AggregateLength := 0;
  if FMode = gmRegexText then
  begin
    FRegex := TGrepRegexPlan.Create(Query);
    FWindowLength := 1;
    Exit;
  end;
  if Query.UnicodeCaseFold or Query.UnicodeNormalizeNfd or Query.FuzzyCodePoints then
  begin
    if not (FMode in [gmLiteralText, gmMultiText, gmFuzzyText]) then
      raise EArgumentException.Create('Unicode options require text search');
    if FIgnoreAscii then raise EArgumentException.Create('ASCII fold and Unicode fold modes are mutually exclusive');
    if Query.FuzzyCodePoints and (FMode <> gmFuzzyText) then
      raise EArgumentException.Create('Codepoint distance requires fuzzy text mode');
    if (Query.MaxDistance < 0) or ((FMode <> gmFuzzyText) and (Query.MaxDistance <> 0)) then
      raise EArgumentException.Create('Invalid Unicode distance for query mode');
    if (FMode = gmFuzzyText) and not Query.FuzzyCodePoints then
      raise EArgumentException.Create('Unicode fuzzy search requires codepoint distance');
    FUnicode := TGrepUnicodePlan.Create(Query);
    FWindowLength := FUnicode.WindowLength;
    Exit;
  end;
  if FEncoding = geAuto then
  begin
    if not (FMode in [gmLiteralText, gmMultiText]) then
      raise EArgumentException.Create('Automatic encoding supports exact text search only');
    SetLength(FAutomatic, 3);
    for I := 0 to 2 do
    begin
      ChildQuery := Query;
      case I of
        0: ChildQuery.Encoding := geUtf8;
        1: ChildQuery.Encoding := geUtf16LE;
        2: ChildQuery.Encoding := geUtf16BE;
      end;
      FAutomatic[I] := TGrepMatcher.Create(ChildQuery);
      if FAutomatic[I].WindowLength > FWindowLength then FWindowLength := FAutomatic[I].WindowLength;
    end;
    FEncoding := geAuto;
    Exit;
  end;
  if Query.MaxDistance < 0 then raise EArgumentOutOfRangeException.Create('MaxDistance cannot be negative');
  if (Query.MaxDistance <> 0) and not (FMode in [gmFuzzyText, gmFuzzyBytes]) then
    raise EArgumentException.Create('MaxDistance is only valid for fuzzy search');
  case FMode of
    gmLiteralText, gmFuzzyText:
      begin
        Value := Query.Text;
        if FIgnoreAscii then Value := FoldAscii(Value);
        Bytes := EncodeText(Value, FEncoding);
        SetLength(FPatterns, 1);
        FPatterns[0] := Bytes;
      end;
    gmLiteralBytes, gmFuzzyBytes:
      begin
        SetLength(FPatterns, 1);
        FPatterns[0] := Copy(Query.Bytes);
        if FIgnoreAscii then
          for I := 0 to High(FPatterns[0]) do
            if (FPatterns[0][I] >= 65) and (FPatterns[0][I] <= 90) then Inc(FPatterns[0][I], 32);
      end;
    gmMultiText:
      begin
        SetLength(FPatterns, Length(Query.TextPatterns));
        for I := 0 to High(FPatterns) do
        begin
          Value := Query.TextPatterns[I];
          if FIgnoreAscii then Value := FoldAscii(Value);
          FPatterns[I] := EncodeText(Value, FEncoding);
        end;
      end;
    gmMultiBytes:
      begin
        SetLength(FPatterns, Length(Query.BytePatterns));
        for I := 0 to High(FPatterns) do
        begin
          FPatterns[I] := Copy(Query.BytePatterns[I]);
          if FIgnoreAscii then
            for Len := 0 to High(FPatterns[I]) do
              if (FPatterns[I][Len] >= 65) and (FPatterns[I][Len] <= 90) then Inc(FPatterns[I][Len], 32);
        end;
      end;
    gmMaskedHex:
      begin
        if FIgnoreAscii then raise EArgumentException.Create('ASCII-insensitive mode is not valid for masked hex');
        FSingle := TPatternSearch.CompileMaskedSignature(Query.HexSignature);
        FWindowLength := Length(FSingle.Pattern);
        if FWindowLength > 64 then raise EArgumentOutOfRangeException.Create('Masked pattern exceeds 64 bytes');
        Exit;
      end;
  else
    raise EArgumentException.Create('Unknown grep query mode');
  end;
  FMultiCount := Length(FPatterns);
  if (FMode in [gmMultiText, gmMultiBytes]) and (FMultiCount > 1024) then raise EArgumentOutOfRangeException.Create('Multi-pattern count exceeds 1024');
  if Length(FPatterns) = 0 then raise EArgumentException.Create('At least one pattern is required');
  for I := 0 to High(FPatterns) do
  begin
    Len := Length(FPatterns[I]);
    if Len = 0 then raise EArgumentException.Create('Empty patterns are not supported');
    if Len > 4 * 1024 * 1024 then raise EArgumentOutOfRangeException.Create('Pattern exceeds 4 MiB limit');
    Inc(AggregateLength, Len);
    if Len > FWindowLength then FWindowLength := Len;
  end;
  if (FMode in [gmMultiText, gmMultiBytes]) and (AggregateLength > 32768) then
    raise EArgumentOutOfRangeException.Create('Multi-pattern aggregate length exceeds 32768 bytes');
  if FMode in [gmFuzzyText, gmFuzzyBytes] then
  begin
    if FIgnoreAscii then raise EArgumentException.Create('ASCII-insensitive fuzzy search is not supported');
    if (FMode = gmFuzzyText) and (FEncoding <> geUtf8) then
      raise EArgumentException.Create('Fuzzy text currently supports UTF-8 byte distance only');
    if Query.MaxDistance >= FWindowLength then raise EArgumentOutOfRangeException.Create('MaxDistance must be less than byte pattern length');
    if FWindowLength > 4 * 1024 * 1024 - Query.MaxDistance then raise EArgumentOutOfRangeException.Create('Fuzzy window exceeds 4 MiB');
    Inc(FWindowLength, Query.MaxDistance);
    FSingle := TPatternSearch.Compile(FPatterns[0], saAuto, Query.MaxDistance);
  end
  else if FMode in [gmMultiText, gmMultiBytes] then
    FMulti := TPatternSearch.CompileMany(FPatterns, maAuto)
  else
    FSingle := TPatternSearch.Compile(FPatterns[0]);
end;

function TGrepMatcher.ForEncoding(Detected: TGrepEncoding): TGrepMatcher;
begin
  if Length(FAutomatic) = 0 then Exit(Self);
  case Detected of
    geUtf16LE: Result := FAutomatic[1];
    geUtf16BE: Result := FAutomatic[2];
  else
    Result := FAutomatic[0];
  end;
end;

function TGrepMatcher.FindFirst(const Buffer: TBytes; Available, StartIndex: Integer): TPatternMatch;
begin
  if (StartIndex >= Available) or (Available = 0) then Exit(TPatternMatch.NotFound);
  if FMulti <> nil then Result := FMulti.FindFirst(@Buffer[0], Available, StartIndex)
  else Result := FSingle.FindFirst(@Buffer[0], Available, StartIndex);
end;

function TGrepMatcher.IsMulti: Boolean;
begin
  Result := FMulti <> nil;
end;

function TGrepMatcher.PatternLength(Index: Integer): Integer;
begin
  Result := Length(FPatterns[Index]);
end;

function TGrepMatcher.MatchAt(const Buffer: TBytes; Available, Offset, PatternIndex: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (PatternIndex < 0) or (PatternIndex >= Length(FPatterns)) or (Offset < 0) then Exit;
  if Length(FPatterns[PatternIndex]) > Available - Offset then Exit;
  for I := 0 to High(FPatterns[PatternIndex]) do
    if Buffer[Offset + I] <> FPatterns[PatternIndex][I] then Exit;
  Result := True;
end;

procedure TGrepMatcher.Normalize(var Buffer: TBytes; FirstIndex, Count: Integer; BaseOffset: Int64);
var
  I, Limit: Integer;
  AbsoluteOffset: Int64;
begin
  if not FIgnoreAscii then Exit;
  Limit := FirstIndex + Count;
  if (FMode in [gmLiteralText, gmMultiText]) and (FEncoding <> geUtf8) then
  begin
    I := FirstIndex;
    while I < Limit - 1 do
    begin
      AbsoluteOffset := BaseOffset + I;
      if (AbsoluteOffset and 1) <> 0 then
      begin
        Inc(I);
        Continue;
      end;
      if FEncoding = geUtf16LE then
      begin
        if (Buffer[I + 1] = 0) and (Buffer[I] >= 65) and (Buffer[I] <= 90) then Inc(Buffer[I], 32);
      end
      else if (Buffer[I] = 0) and (Buffer[I + 1] >= 65) and (Buffer[I + 1] <= 90) then Inc(Buffer[I + 1], 32);
      Inc(I, 2);
    end;
    Exit;
  end;
  for I := FirstIndex to Limit - 1 do
    if (Buffer[I] >= 65) and (Buffer[I] <= 90) then Inc(Buffer[I], 32);
end;

function TGrepMatcher.ValidTextOffset(Offset: Int64): Boolean;
begin
  Result := True;
  if FMode in [gmLiteralText, gmMultiText] then
    if FEncoding in [geUtf16LE, geUtf16BE] then Result := (Offset and 1) = 0;
end;

end.
