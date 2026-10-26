{
   NativePattern Library  |  © 2026 Selahattin Erkoc
   Licensed under MIT License  |  https://opensource.org/licenses/MIT
}
unit NativePattern.Core;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  TPatternMatchUnit = (muByte, muChar);

  TPatternMatch = record
    Offset: Int64;
    MatchLength: NativeUInt;
    PatternIndex: Integer;
    Distance: Integer;
    MatchUnit: TPatternMatchUnit;
    class function NotFound: TPatternMatch; static;
    function Found: Boolean;
  end;

  TPatternMatches = TArray<TPatternMatch>;

  TBytePattern = record
  private
    FBytes: TBytes;
    FMasks: TBytes;
    function GetBytes: TBytes;
    function GetMasks: TBytes;
  public
    class function Exact(const Bytes: TBytes): TBytePattern; static;
    class function Masked(const Bytes, Masks: TBytes): TBytePattern; static;
    class function Parse(const Signature: string): TBytePattern; static;
    function IsExact: Boolean;
    function GetLength: NativeUInt;
    property Bytes: TBytes read GetBytes;
    property Masks: TBytes read GetMasks;
  end;

  TSinglePatternSearcher = class abstract
  private
    FPattern: TBytes;
    FTextMode: Boolean;
    FTextPattern: string;
    function FindStream(Stream: TStream; MaxMatches: Integer; PreservePosition: Boolean): TPatternMatches;
    function GetPattern: TBytes;
  protected
    function DoFindAll(Buffer: PByte; BufferSize, StartOffset: NativeUInt; MaxMatches: Integer = 0): TPatternMatches; virtual;
    function DoFindFirst(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch; virtual; abstract;
    function StreamOverlap: NativeUInt; virtual;
    function CanStopStreamAfterFirst: Boolean; virtual;
    property PatternBytes: TBytes read FPattern;
    property TextMode: Boolean read FTextMode;
    property TextPattern: string read FTextPattern;
  public
    constructor Create(const Pattern: TBytes); overload;
    constructor Create(const Pattern: string); overload;
    function FindFirst(Buffer: Pointer; BufferSize: NativeUInt; StartOffset: NativeUInt = 0): TPatternMatch; overload;
    function FindFirst(const Data: TBytes; StartOffset: NativeUInt = 0): TPatternMatch; overload;
    function FindFirst(const Text: string; StartOffset: NativeUInt = 0): TPatternMatch; overload; virtual;
    function FindFirst(Stream: TStream; PreservePosition: Boolean = True): TPatternMatch; overload;
    function FindFirst(List: TList<Byte>; StartOffset: NativeUInt = 0): TPatternMatch; overload;
    function FindAll(Buffer: Pointer; BufferSize: NativeUInt; StartOffset: NativeUInt = 0): TPatternMatches; overload;
    function FindAll(const Data: TBytes; StartOffset: NativeUInt = 0): TPatternMatches; overload;
    function FindAll(const Text: string; StartOffset: NativeUInt = 0): TPatternMatches; overload; virtual;
    function FindAll(Stream: TStream; PreservePosition: Boolean = True): TPatternMatches; overload;
    function FindAll(List: TList<Byte>; StartOffset: NativeUInt = 0): TPatternMatches; overload;
    property Pattern: TBytes read GetPattern;
  end;

  TMultiPatternSearcher = class abstract
  public
    function FindFirst(Buffer: Pointer; BufferSize: NativeUInt; StartOffset: NativeUInt = 0): TPatternMatch; overload; virtual; abstract;
    function FindFirst(const Data: TBytes; StartOffset: NativeUInt = 0): TPatternMatch; overload; virtual; abstract;
    function FindFirst(const Text: string; StartOffset: NativeUInt = 0): TPatternMatch; overload; virtual; abstract;
    function FindFirst(Stream: TStream; PreservePosition: Boolean = True): TPatternMatch; overload; virtual; abstract;
    function FindFirst(List: TList<Byte>; StartOffset: NativeUInt = 0): TPatternMatch; overload; virtual; abstract;
    function FindAll(Buffer: Pointer; BufferSize: NativeUInt; StartOffset: NativeUInt = 0): TPatternMatches; overload; virtual; abstract;
    function FindAll(const Data: TBytes; StartOffset: NativeUInt = 0): TPatternMatches; overload; virtual; abstract;
    function FindAll(const Text: string; StartOffset: NativeUInt = 0): TPatternMatches; overload; virtual; abstract;
    function FindAll(Stream: TStream; PreservePosition: Boolean = True): TPatternMatches; overload; virtual; abstract;
    function FindAll(List: TList<Byte>; StartOffset: NativeUInt = 0): TPatternMatches; overload; virtual; abstract;
    function PatternCount: Integer; virtual; abstract;
  end;

implementation

const
  STREAM_CHUNK_SIZE = 65536;

procedure AddMatch(var Matches: TPatternMatches; const Match: TPatternMatch);
var
  N: Integer;
begin
  N := Length(Matches);
  SetLength(Matches, N + 1);
  Matches[N] := Match;
end;

procedure AddOrImproveMatch(var Matches: TPatternMatches; const Match: TPatternMatch);
var
  I, J, N: Integer;
begin
  I := High(Matches);
  while I >= 0 do
  begin
    if Matches[I].Offset = Match.Offset then
    begin
      if (Match.Distance < Matches[I].Distance) or ((Match.Distance = Matches[I].Distance) and (Match.MatchLength < Matches[I].MatchLength)) then
        Matches[I] := Match;
      Exit;
    end;
    if Matches[I].Offset < Match.Offset then
      Break;
    Dec(I);
  end;
  N := Length(Matches);
  SetLength(Matches, N + 1);
  for J := N downto I + 2 do
    Matches[J] := Matches[J - 1];
  Matches[I + 1] := Match;
end;

function IsBetterFirstMatch(const Candidate, Current: TPatternMatch): Boolean;
begin
  if Candidate.Offset < Current.Offset then
    Exit(True);
  if Candidate.Offset > Current.Offset then
    Exit(False);
  if Candidate.Distance < Current.Distance then
    Exit(True);
  if Candidate.Distance > Current.Distance then
    Exit(False);
  Result := Candidate.MatchLength < Current.MatchLength;
end;

function HexNibble(C: Char): Integer;
begin
  if (C >= '0') and (C <= '9') then
    Exit(Ord(C) - Ord('0'));
  if (C >= 'A') and (C <= 'F') then
    Exit(Ord(C) - Ord('A') + 10);
  if (C >= 'a') and (C <= 'f') then
    Exit(Ord(C) - Ord('a') + 10);
  Result := -1;
end;

function IsSeparator(C: Char): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13) or (C = ',');
end;

class function TPatternMatch.NotFound: TPatternMatch;
begin
  Result.Offset := -1;
  Result.MatchLength := 0;
  Result.PatternIndex := -1;
  Result.Distance := -1;
  Result.MatchUnit := muByte;
end;

function TPatternMatch.Found: Boolean;
begin
  Result := Offset >= 0;
end;

class function TBytePattern.Exact(const Bytes: TBytes): TBytePattern;
var
  I: Integer;
begin
  if Length(Bytes) = 0 then
    raise EArgumentException.Create('Pattern must not be empty');
  Result.FBytes := Copy(Bytes);
  SetLength(Result.FMasks, Length(Bytes));
  for I := 0 to High(Result.FMasks) do
    Result.FMasks[I] := $FF;
end;

class function TBytePattern.Masked(const Bytes, Masks: TBytes): TBytePattern;
begin
  if Length(Bytes) = 0 then
    raise EArgumentException.Create('Pattern must not be empty');
  if Length(Bytes) <> Length(Masks) then
    raise EArgumentException.Create('Pattern bytes and masks must have the same length');
  Result.FBytes := Copy(Bytes);
  Result.FMasks := Copy(Masks);
end;

class function TBytePattern.Parse(const Signature: string): TBytePattern;
var
  I, N, HiNibble, LoNibble, TokenStart: Integer;
  C1, C2: Char;
begin
  SetLength(Result.FBytes, 0);
  SetLength(Result.FMasks, 0);
  I := 1;
  N := 0;
  while I <= Length(Signature) do
  begin
    while (I <= Length(Signature)) and IsSeparator(Signature[I]) do
      Inc(I);
    if I > Length(Signature) then
      Break;
    TokenStart := I;
    C1 := Signature[I];
    Inc(I);
    if (I <= Length(Signature)) and not IsSeparator(Signature[I]) then
    begin
      C2 := Signature[I];
      Inc(I);
    end
    else if C1 = '?' then
      C2 := '?'
    else
      raise EConvertError.CreateFmt('Incomplete pattern token at character %d', [TokenStart]);
    if (I <= Length(Signature)) and not IsSeparator(Signature[I]) then
      raise EConvertError.CreateFmt('Pattern token is longer than two characters at character %d', [TokenStart]);
    if (C1 <> '?') and (HexNibble(C1) < 0) then
      raise EConvertError.CreateFmt('Invalid pattern token at character %d', [TokenStart]);
    if (C2 <> '?') and (HexNibble(C2) < 0) then
      raise EConvertError.CreateFmt('Invalid pattern token at character %d', [TokenStart + 1]);
    SetLength(Result.FBytes, N + 1);
    SetLength(Result.FMasks, N + 1);
    if C1 = '?' then
    begin
      HiNibble := 0;
      Result.FMasks[N] := 0;
    end
    else
    begin
      HiNibble := HexNibble(C1);
      Result.FMasks[N] := $F0;
    end;
    if C2 = '?' then
      LoNibble := 0
    else
    begin
      LoNibble := HexNibble(C2);
      Result.FMasks[N] := Result.FMasks[N] or $0F;
    end;
    Result.FBytes[N] := Byte((HiNibble shl 4) or LoNibble);
    Inc(N);
  end;
  if N = 0 then
    raise EArgumentException.Create('Pattern must not be empty');
end;

function TBytePattern.GetBytes: TBytes;
begin
  Result := Copy(FBytes);
end;

function TBytePattern.GetMasks: TBytes;
begin
  Result := Copy(FMasks);
end;

function TBytePattern.IsExact: Boolean;
var
  I: Integer;
begin
  if (Length(FBytes) = 0) or (Length(FBytes) <> Length(FMasks)) then
    Exit(False);
  for I := 0 to High(FMasks) do
    if FMasks[I] <> $FF then
      Exit(False);
  Result := True;
end;

function TBytePattern.GetLength: NativeUInt;
begin
  Result := Length(FBytes);
end;

function TSinglePatternSearcher.GetPattern: TBytes;
begin
  Result := Copy(FPattern);
end;

constructor TSinglePatternSearcher.Create(const Pattern: TBytes);
begin
  inherited Create;
  if Length(Pattern) = 0 then
    raise EArgumentException.Create('Pattern must not be empty');
  FPattern := Copy(Pattern);
  FTextMode := False;
  FTextPattern := '';
end;

constructor TSinglePatternSearcher.Create(const Pattern: string);
var
  ByteLength: NativeUInt;
begin
  inherited Create;
  if Pattern = '' then
    raise EArgumentException.Create('Pattern must not be empty');
  FTextMode := True;
  FTextPattern := Pattern;
  ByteLength := NativeUInt(Length(Pattern)) * SizeOf(Char);
  SetLength(FPattern, ByteLength);
  Move(PChar(Pattern)^, FPattern[0], ByteLength);
end;

function TSinglePatternSearcher.DoFindAll(Buffer: PByte; BufferSize, StartOffset: NativeUInt; MaxMatches: Integer): TPatternMatches;
var
  Match: TPatternMatch;
  Position: NativeUInt;
begin
  SetLength(Result, 0);
  if (Buffer = nil) or (StartOffset >= BufferSize) then
    Exit;
  Position := StartOffset;
  while Position < BufferSize do
  begin
    Match := DoFindFirst(Buffer, BufferSize, Position);
    if not Match.Found then
      Break;
    AddMatch(Result, Match);
    if (MaxMatches > 0) and (Length(Result) >= MaxMatches) then
      Break;
    if UInt64(Match.Offset) >= UInt64(High(NativeUInt)) then
      Break;
    Position := NativeUInt(Match.Offset) + 1;
  end;
end;

function TSinglePatternSearcher.StreamOverlap: NativeUInt;
begin
  if Length(FPattern) > 1 then
    Result := Length(FPattern) - 1
  else
    Result := 0;
end;

function TSinglePatternSearcher.FindFirst(Buffer: Pointer; BufferSize, StartOffset: NativeUInt): TPatternMatch;
begin
  if (Buffer = nil) or (StartOffset >= BufferSize) then
    Exit(TPatternMatch.NotFound);
  Result := DoFindFirst(PByte(Buffer), BufferSize, StartOffset);
end;

function TSinglePatternSearcher.FindFirst(const Data: TBytes; StartOffset: NativeUInt): TPatternMatch;
begin
  if (Length(Data) = 0) or (StartOffset >= NativeUInt(Length(Data))) then
    Exit(TPatternMatch.NotFound);
  Result := DoFindFirst(@Data[0], Length(Data), StartOffset);
end;

function TSinglePatternSearcher.FindFirst(const Text: string; StartOffset: NativeUInt): TPatternMatch;
var
  ByteSize, ByteStart, NextStart: NativeUInt;
  Match: TPatternMatch;
begin
  if not FTextMode then
    raise EInvalidOpException.Create('String search requires a string pattern');
  if (Text = '') or (StartOffset >= NativeUInt(Length(Text))) then
    Exit(TPatternMatch.NotFound);
  ByteSize := NativeUInt(Length(Text)) * SizeOf(Char);
  ByteStart := StartOffset * SizeOf(Char);
  NextStart := ByteStart;
  while NextStart < ByteSize do
  begin
    Match := DoFindFirst(PByte(PChar(Text)), ByteSize, NextStart);
    if not Match.Found then
      Exit(Match);
    if (Match.Offset mod SizeOf(Char)) = 0 then
    begin
      Match.Offset := Match.Offset div SizeOf(Char);
      Match.MatchLength := Match.MatchLength div SizeOf(Char);
      Match.MatchUnit := muChar;
      Exit(Match);
    end;
    NextStart := NativeUInt(Match.Offset) + 1;
  end;
  Result := TPatternMatch.NotFound;
end;

function TSinglePatternSearcher.FindFirst(Stream: TStream; PreservePosition: Boolean): TPatternMatch;
var
  Matches: TPatternMatches;
begin
  Matches := FindStream(Stream, 1, PreservePosition);
  if Length(Matches) = 0 then
    Result := TPatternMatch.NotFound
  else
    Result := Matches[0];
end;

function TSinglePatternSearcher.FindFirst(List: TList<Byte>; StartOffset: NativeUInt): TPatternMatch;
var
  Data: TBytes;
begin
  if List = nil then
    Exit(TPatternMatch.NotFound);
  Data := List.ToArray;
  Result := FindFirst(Data, StartOffset);
end;

function TSinglePatternSearcher.FindAll(Buffer: Pointer; BufferSize, StartOffset: NativeUInt): TPatternMatches;
begin
  SetLength(Result, 0);
  if (Buffer = nil) or (StartOffset >= BufferSize) then
    Exit;
  Result := DoFindAll(PByte(Buffer), BufferSize, StartOffset);
end;

function TSinglePatternSearcher.FindAll(const Data: TBytes; StartOffset: NativeUInt): TPatternMatches;
begin
  SetLength(Result, 0);
  if (Length(Data) = 0) or (StartOffset >= NativeUInt(Length(Data))) then
    Exit;
  Result := DoFindAll(@Data[0], Length(Data), StartOffset);
end;

function TSinglePatternSearcher.FindAll(const Text: string; StartOffset: NativeUInt): TPatternMatches;
var
  ByteMatches: TPatternMatches;
  Match: TPatternMatch;
  I: Integer;
  ByteSize, ByteStart: NativeUInt;
begin
  SetLength(Result, 0);
  if not FTextMode then
    raise EInvalidOpException.Create('String search requires a string pattern');
  if (Text = '') or (StartOffset >= NativeUInt(Length(Text))) then
    Exit;
  ByteSize := NativeUInt(Length(Text)) * SizeOf(Char);
  ByteStart := StartOffset * SizeOf(Char);
  ByteMatches := DoFindAll(PByte(PChar(Text)), ByteSize, ByteStart);
  for I := 0 to High(ByteMatches) do
    if (ByteMatches[I].Offset mod SizeOf(Char)) = 0 then
    begin
      Match := ByteMatches[I];
      Match.Offset := Match.Offset div SizeOf(Char);
      Match.MatchLength := Match.MatchLength div SizeOf(Char);
      Match.MatchUnit := muChar;
      AddMatch(Result, Match);
    end;
end;

function TSinglePatternSearcher.FindAll(Stream: TStream; PreservePosition: Boolean): TPatternMatches;
begin
  Result := FindStream(Stream, 0, PreservePosition);
end;

function TSinglePatternSearcher.FindAll(List: TList<Byte>; StartOffset: NativeUInt): TPatternMatches;
var
  Data: TBytes;
begin
  SetLength(Result, 0);
  if List = nil then
    Exit;
  Data := List.ToArray;
  Result := FindAll(Data, StartOffset);
end;

function TSinglePatternSearcher.CanStopStreamAfterFirst: Boolean;
begin
  Result := True;
end;

function TSinglePatternSearcher.FindStream(Stream: TStream; MaxMatches: Integer; PreservePosition: Boolean): TPatternMatches;
var
  SavedPosition, ReadStart, BlockBase: Int64;
  Carry, ReadBuffer, Block: TBytes;
  ReadCount, CarryCount, I, BestIndex: Integer;
  LocalMatches: TPatternMatches;
  Match: TPatternMatch;
  Overlap, KeepCount: NativeUInt;
begin
  SetLength(Result, 0);
  if Stream = nil then
    Exit;
  SavedPosition := Stream.Position;
  try
    ReadStart := Stream.Position;
    SetLength(Carry, 0);
    SetLength(ReadBuffer, STREAM_CHUNK_SIZE);
    Overlap := StreamOverlap;
    repeat
      ReadCount := Stream.Read(ReadBuffer[0], Length(ReadBuffer));
      if ReadCount <= 0 then
        Break;
      CarryCount := Length(Carry);
      SetLength(Block, CarryCount + ReadCount);
      if CarryCount > 0 then
        Move(Carry[0], Block[0], CarryCount);
      Move(ReadBuffer[0], Block[CarryCount], ReadCount);
      BlockBase := ReadStart - CarryCount;
      LocalMatches := DoFindAll(@Block[0], Length(Block), 0);
      for I := 0 to High(LocalMatches) do
      begin
        if (CarryCount > 0) and (LocalMatches[I].Offset + Int64(LocalMatches[I].MatchLength) <= CarryCount) then
          Continue;
        Match := LocalMatches[I];
        Match.Offset := BlockBase + Match.Offset;
        AddOrImproveMatch(Result, Match);
        if (MaxMatches > 0) and (Length(Result) >= MaxMatches) and CanStopStreamAfterFirst then
          Exit;
      end;
      ReadStart := ReadStart + ReadCount;
      if Overlap = 0 then
      begin
        SetLength(Carry, 0);
        Continue;
      end;
      KeepCount := Overlap;
      if KeepCount > NativeUInt(Length(Block)) then
        KeepCount := Length(Block);
      SetLength(Carry, KeepCount);
      if KeepCount > 0 then
        Move(Block[Length(Block) - Integer(KeepCount)], Carry[0], KeepCount);
    until False;
    if (MaxMatches = 1) and (Length(Result) > 1) then
    begin
      BestIndex := 0;
      for I := 1 to High(Result) do
        if IsBetterFirstMatch(Result[I], Result[BestIndex]) then
          BestIndex := I;
      Result[0] := Result[BestIndex];
      SetLength(Result, 1);
    end;
  finally
    if PreservePosition then
      Stream.Position := SavedPosition;
  end;
end;

end.
