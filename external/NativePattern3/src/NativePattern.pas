{
   NativePattern Library  |  © 2026 Selahattin Erkoc
   Licensed under MIT License  |  https://opensource.org/licenses/MIT
}
unit NativePattern;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  NativePattern.Core,
  NativePattern.BoyerMooreHorspool,
  NativePattern.Bitap,
  NativePattern.Sbndm,
  NativePattern.RabinKarp,
  NativePattern.Levenshtein,
  NativePattern.Myers,
  NativePattern.TwoWay,
  NativePattern.Avx2,
  NativePattern.AhoCorasick,
  NativePattern.CommentzWalter;

type
  TPatternSearchAlgorithm = (saAuto, saBoyerMooreHorspool, saBitap, saSbndm, saRabinKarp, saLevenshtein, saMyers, saTwoWay, saAvx2);
  TMaskedPatternSearchAlgorithm = (msaBitap, msaSbndm);
  TMultiPatternSearchAlgorithm = (maAuto, maAhoCorasick, maCommentzWalter);

  TPatternSearch = class sealed
  private
    class function PreferBoyerMooreHorspool(const Pattern: TBytes): Boolean; static;
    class function SelectExactByteAlgorithm(const Pattern: TBytes): TPatternSearchAlgorithm; static;
    class function SelectExactTextAlgorithm(PatternByteLength: NativeUInt): TPatternSearchAlgorithm; static;
    class function SelectMultiAlgorithm(PatternCount: Integer; MinPatternLength: NativeUInt): TMultiPatternSearchAlgorithm; static;
  public
    class function Compile(const Pattern: TBytes; Algorithm: TPatternSearchAlgorithm = saAuto; MaxDistance: Integer = 0): TSinglePatternSearcher; overload; static;
    class function Compile(const Pattern: string; Algorithm: TPatternSearchAlgorithm = saAuto; MaxDistance: Integer = 0): TSinglePatternSearcher; overload; static;
    class function Compile(const Pattern: TBytePattern; Algorithm: TMaskedPatternSearchAlgorithm): TSinglePatternSearcher; overload; static;
    class function CompileMany(const Patterns: array of TBytes; Algorithm: TMultiPatternSearchAlgorithm = maAuto): TMultiPatternSearcher; overload; static;
    class function CompileMany(const Patterns: array of string; Algorithm: TMultiPatternSearchAlgorithm = maAuto): TMultiPatternSearcher; overload; static;
    class function CompileSignature(const Signature: string): TBitapSearcher; static;
    class function CompileMaskedSignature(const Signature: string; Algorithm: TMaskedPatternSearchAlgorithm = msaBitap): TSinglePatternSearcher; static;
    class function FindFirst(const Data, Pattern: TBytes; Algorithm: TPatternSearchAlgorithm = saAuto; MaxDistance: Integer = 0): TPatternMatch; overload; static;
    class function FindFirst(const Data: TBytes; const Pattern: TBytePattern; Algorithm: TMaskedPatternSearchAlgorithm = msaBitap): TPatternMatch; overload; static;
    class function FindFirst(const Text, Pattern: string; Algorithm: TPatternSearchAlgorithm = saAuto; MaxDistance: Integer = 0): TPatternMatch; overload; static;
    class function FindFirst(Stream: TStream; const Pattern: TBytes; Algorithm: TPatternSearchAlgorithm = saAuto; MaxDistance: Integer = 0; PreservePosition: Boolean = True): TPatternMatch; overload; static;
    class function FindFirst(Stream: TStream; const Pattern: TBytePattern; Algorithm: TMaskedPatternSearchAlgorithm = msaBitap; PreservePosition: Boolean = True): TPatternMatch; overload; static;
    class function FindFirst(List: TList<Byte>; const Pattern: TBytes; Algorithm: TPatternSearchAlgorithm = saAuto; MaxDistance: Integer = 0): TPatternMatch; overload; static;
    class function FindFirst(List: TList<Byte>; const Pattern: TBytePattern; Algorithm: TMaskedPatternSearchAlgorithm = msaBitap): TPatternMatch; overload; static;
    class function FindAll(const Data, Pattern: TBytes; Algorithm: TPatternSearchAlgorithm = saAuto; MaxDistance: Integer = 0): TPatternMatches; overload; static;
    class function FindAll(const Data: TBytes; const Pattern: TBytePattern; Algorithm: TMaskedPatternSearchAlgorithm = msaBitap): TPatternMatches; overload; static;
    class function FindAll(const Text, Pattern: string; Algorithm: TPatternSearchAlgorithm = saAuto; MaxDistance: Integer = 0): TPatternMatches; overload; static;
    class function FindAll(Stream: TStream; const Pattern: TBytes; Algorithm: TPatternSearchAlgorithm = saAuto; MaxDistance: Integer = 0; PreservePosition: Boolean = True): TPatternMatches; overload; static;
    class function FindAll(Stream: TStream; const Pattern: TBytePattern; Algorithm: TMaskedPatternSearchAlgorithm = msaBitap; PreservePosition: Boolean = True): TPatternMatches; overload; static;
    class function FindAll(List: TList<Byte>; const Pattern: TBytes; Algorithm: TPatternSearchAlgorithm = saAuto; MaxDistance: Integer = 0): TPatternMatches; overload; static;
    class function FindAll(List: TList<Byte>; const Pattern: TBytePattern; Algorithm: TMaskedPatternSearchAlgorithm = msaBitap): TPatternMatches; overload; static;
  end;

implementation

class function TPatternSearch.PreferBoyerMooreHorspool(const Pattern: TBytes): Boolean;
var
  I: Integer;
  PatternLength: NativeUInt;
  ShiftSum: UInt64;
  Shifts: array[Byte] of NativeUInt;
begin
  PatternLength := Length(Pattern);
  for I := 0 to High(Shifts) do
    Shifts[I] := PatternLength;
  for I := 0 to Length(Pattern) - 2 do
    Shifts[Pattern[I]] := PatternLength - NativeUInt(I) - 1;
  ShiftSum := 0;
  for I := 0 to High(Shifts) do
    ShiftSum := ShiftSum + Shifts[I];
  Result := ShiftSum * 4 >= UInt64(PatternLength) * 256 * 3;
end;

class function TPatternSearch.SelectExactByteAlgorithm(const Pattern: TBytes): TPatternSearchAlgorithm;
var
  PatternLength: NativeUInt;
begin
  PatternLength := Length(Pattern);
  if TAvx2Searcher.Available and (PatternLength <= 32) then
    Exit(saAvx2);
  if PatternLength <= 64 then
    Exit(saSbndm);
  if PatternLength <= 256 then
    Exit(saBoyerMooreHorspool);
  if not TAvx2Searcher.Available then
    Exit(saBoyerMooreHorspool);
  if PreferBoyerMooreHorspool(Pattern) then
    Exit(saBoyerMooreHorspool);
  Result := saAvx2;
end;

class function TPatternSearch.SelectExactTextAlgorithm(PatternByteLength: NativeUInt): TPatternSearchAlgorithm;
begin
  if PatternByteLength <= 64 then
    Exit(saSbndm);
  if PatternByteLength <= 256 then
    Exit(saBoyerMooreHorspool);
  Result := saTwoWay;
end;

class function TPatternSearch.SelectMultiAlgorithm(PatternCount: Integer; MinPatternLength: NativeUInt): TMultiPatternSearchAlgorithm;
begin
  if (PatternCount >= 4) and (MinPatternLength >= 4) then
    Result := maCommentzWalter
  else
    Result := maAhoCorasick;
end;

class function TPatternSearch.Compile(const Pattern: TBytes; Algorithm: TPatternSearchAlgorithm; MaxDistance: Integer): TSinglePatternSearcher;
begin
  if MaxDistance < 0 then
    raise EArgumentOutOfRangeException.Create('MaxDistance must not be negative');
  if (MaxDistance > 0) and (Algorithm in [saBoyerMooreHorspool, saBitap, saSbndm, saRabinKarp, saTwoWay, saAvx2]) then
    raise EArgumentException.Create('MaxDistance is only valid with Auto, Levenshtein or Myers');
  if Algorithm = saAuto then
  begin
    if MaxDistance > 0 then
    begin
      if Length(Pattern) <= 64 then
        Algorithm := saMyers
      else
        Algorithm := saLevenshtein;
    end
    else
      Algorithm := SelectExactByteAlgorithm(Pattern);
  end;
  case Algorithm of
    saBoyerMooreHorspool: Result := TBoyerMooreHorspoolSearcher.Create(Pattern);
    saBitap: Result := TBitapSearcher.Create(Pattern);
    saSbndm: Result := TSbndmSearcher.Create(Pattern);
    saRabinKarp: Result := TRabinKarpSearcher.Create(Pattern);
    saLevenshtein: Result := TLevenshteinSearcher.Create(Pattern, MaxDistance);
    saMyers: Result := TMyersSearcher.Create(Pattern, MaxDistance);
    saTwoWay: Result := TTwoWaySearcher.Create(Pattern);
    saAvx2: Result := TAvx2Searcher.Create(Pattern);
  else
    raise EArgumentException.Create('Unsupported search algorithm');
  end;
end;

class function TPatternSearch.Compile(const Pattern: string; Algorithm: TPatternSearchAlgorithm; MaxDistance: Integer): TSinglePatternSearcher;
var
  ByteLength: NativeUInt;
begin
  if MaxDistance < 0 then
    raise EArgumentOutOfRangeException.Create('MaxDistance must not be negative');
  if (MaxDistance > 0) and (Algorithm in [saBoyerMooreHorspool, saBitap, saSbndm, saRabinKarp, saTwoWay, saAvx2]) then
    raise EArgumentException.Create('MaxDistance is only valid with Auto, Levenshtein or Myers');
  ByteLength := NativeUInt(Length(Pattern)) * SizeOf(Char);
  if Algorithm = saAuto then
  begin
    if MaxDistance > 0 then
    begin
      if Length(Pattern) <= 64 then
        Algorithm := saMyers
      else
        Algorithm := saLevenshtein;
    end
    else
      Algorithm := SelectExactTextAlgorithm(ByteLength);
  end;
  case Algorithm of
    saBoyerMooreHorspool: Result := TBoyerMooreHorspoolSearcher.Create(Pattern);
    saBitap: Result := TBitapSearcher.Create(Pattern);
    saSbndm: Result := TSbndmSearcher.Create(Pattern);
    saRabinKarp: Result := TRabinKarpSearcher.Create(Pattern);
    saLevenshtein: Result := TLevenshteinSearcher.Create(Pattern, MaxDistance);
    saMyers: Result := TMyersSearcher.Create(Pattern, MaxDistance);
    saTwoWay: Result := TTwoWaySearcher.Create(Pattern);
    saAvx2: Result := TAvx2Searcher.Create(Pattern);
  else
    raise EArgumentException.Create('Unsupported search algorithm');
  end;
end;

class function TPatternSearch.Compile(const Pattern: TBytePattern; Algorithm: TMaskedPatternSearchAlgorithm): TSinglePatternSearcher;
begin
  case Algorithm of
    msaBitap: Result := TBitapSearcher.Create(Pattern);
    msaSbndm: Result := TSbndmSearcher.Create(Pattern);
  else
    raise EArgumentException.Create('Unsupported masked search algorithm');
  end;
end;

class function TPatternSearch.CompileMany(const Patterns: array of TBytes; Algorithm: TMultiPatternSearchAlgorithm): TMultiPatternSearcher;
var
  I: Integer;
  MinLength: NativeUInt;
begin
  if Length(Patterns) = 0 then
    raise EArgumentException.Create('At least one pattern is required');
  MinLength := High(NativeUInt);
  for I := 0 to High(Patterns) do
  begin
    if Length(Patterns[I]) = 0 then
      raise EArgumentException.CreateFmt('Pattern %d must not be empty', [I]);
    if NativeUInt(Length(Patterns[I])) < MinLength then
      MinLength := Length(Patterns[I]);
  end;
  if Algorithm = maAuto then
    Algorithm := SelectMultiAlgorithm(Length(Patterns), MinLength);
  case Algorithm of
    maAhoCorasick: Result := TAhoCorasickSearcher.Create(Patterns);
    maCommentzWalter: Result := TCommentzWalterSearcher.Create(Patterns);
  else
    raise EArgumentException.Create('Unsupported multi-pattern search algorithm');
  end;
end;

class function TPatternSearch.CompileMany(const Patterns: array of string; Algorithm: TMultiPatternSearchAlgorithm): TMultiPatternSearcher;
var
  I: Integer;
  MinLength: NativeUInt;
begin
  if Length(Patterns) = 0 then
    raise EArgumentException.Create('At least one pattern is required');
  MinLength := High(NativeUInt);
  for I := 0 to High(Patterns) do
  begin
    if Patterns[I] = '' then
      raise EArgumentException.CreateFmt('Pattern %d must not be empty', [I]);
    if NativeUInt(Length(Patterns[I])) < MinLength then
      MinLength := Length(Patterns[I]);
  end;
  if Algorithm = maAuto then
    Algorithm := SelectMultiAlgorithm(Length(Patterns), MinLength);
  case Algorithm of
    maAhoCorasick: Result := TAhoCorasickSearcher.Create(Patterns);
    maCommentzWalter: Result := TCommentzWalterSearcher.Create(Patterns);
  else
    raise EArgumentException.Create('Unsupported multi-pattern search algorithm');
  end;
end;

class function TPatternSearch.CompileSignature(const Signature: string): TBitapSearcher;
begin
  Result := TBitapSearcher.Create(TBytePattern.Parse(Signature));
end;

class function TPatternSearch.CompileMaskedSignature(const Signature: string; Algorithm: TMaskedPatternSearchAlgorithm): TSinglePatternSearcher;
begin
  Result := Compile(TBytePattern.Parse(Signature), Algorithm);
end;

class function TPatternSearch.FindFirst(const Data, Pattern: TBytes; Algorithm: TPatternSearchAlgorithm; MaxDistance: Integer): TPatternMatch;
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := Compile(Pattern, Algorithm, MaxDistance);
  try
    Result := Searcher.FindFirst(Data);
  finally
    Searcher.Free;
  end;
end;

class function TPatternSearch.FindFirst(const Data: TBytes; const Pattern: TBytePattern; Algorithm: TMaskedPatternSearchAlgorithm): TPatternMatch;
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := Compile(Pattern, Algorithm);
  try
    Result := Searcher.FindFirst(Data);
  finally
    Searcher.Free;
  end;
end;

class function TPatternSearch.FindFirst(const Text, Pattern: string; Algorithm: TPatternSearchAlgorithm; MaxDistance: Integer): TPatternMatch;
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := Compile(Pattern, Algorithm, MaxDistance);
  try
    Result := Searcher.FindFirst(Text);
  finally
    Searcher.Free;
  end;
end;

class function TPatternSearch.FindFirst(Stream: TStream; const Pattern: TBytes; Algorithm: TPatternSearchAlgorithm; MaxDistance: Integer; PreservePosition: Boolean): TPatternMatch;
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := Compile(Pattern, Algorithm, MaxDistance);
  try
    Result := Searcher.FindFirst(Stream, PreservePosition);
  finally
    Searcher.Free;
  end;
end;

class function TPatternSearch.FindFirst(Stream: TStream; const Pattern: TBytePattern; Algorithm: TMaskedPatternSearchAlgorithm; PreservePosition: Boolean): TPatternMatch;
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := Compile(Pattern, Algorithm);
  try
    Result := Searcher.FindFirst(Stream, PreservePosition);
  finally
    Searcher.Free;
  end;
end;

class function TPatternSearch.FindFirst(List: TList<Byte>; const Pattern: TBytes; Algorithm: TPatternSearchAlgorithm; MaxDistance: Integer): TPatternMatch;
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := Compile(Pattern, Algorithm, MaxDistance);
  try
    Result := Searcher.FindFirst(List);
  finally
    Searcher.Free;
  end;
end;

class function TPatternSearch.FindFirst(List: TList<Byte>; const Pattern: TBytePattern; Algorithm: TMaskedPatternSearchAlgorithm): TPatternMatch;
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := Compile(Pattern, Algorithm);
  try
    Result := Searcher.FindFirst(List);
  finally
    Searcher.Free;
  end;
end;

class function TPatternSearch.FindAll(const Data, Pattern: TBytes; Algorithm: TPatternSearchAlgorithm; MaxDistance: Integer): TPatternMatches;
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := Compile(Pattern, Algorithm, MaxDistance);
  try
    Result := Searcher.FindAll(Data);
  finally
    Searcher.Free;
  end;
end;

class function TPatternSearch.FindAll(const Data: TBytes; const Pattern: TBytePattern; Algorithm: TMaskedPatternSearchAlgorithm): TPatternMatches;
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := Compile(Pattern, Algorithm);
  try
    Result := Searcher.FindAll(Data);
  finally
    Searcher.Free;
  end;
end;

class function TPatternSearch.FindAll(const Text, Pattern: string; Algorithm: TPatternSearchAlgorithm; MaxDistance: Integer): TPatternMatches;
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := Compile(Pattern, Algorithm, MaxDistance);
  try
    Result := Searcher.FindAll(Text);
  finally
    Searcher.Free;
  end;
end;

class function TPatternSearch.FindAll(Stream: TStream; const Pattern: TBytes; Algorithm: TPatternSearchAlgorithm; MaxDistance: Integer; PreservePosition: Boolean): TPatternMatches;
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := Compile(Pattern, Algorithm, MaxDistance);
  try
    Result := Searcher.FindAll(Stream, PreservePosition);
  finally
    Searcher.Free;
  end;
end;

class function TPatternSearch.FindAll(Stream: TStream; const Pattern: TBytePattern; Algorithm: TMaskedPatternSearchAlgorithm; PreservePosition: Boolean): TPatternMatches;
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := Compile(Pattern, Algorithm);
  try
    Result := Searcher.FindAll(Stream, PreservePosition);
  finally
    Searcher.Free;
  end;
end;

class function TPatternSearch.FindAll(List: TList<Byte>; const Pattern: TBytes; Algorithm: TPatternSearchAlgorithm; MaxDistance: Integer): TPatternMatches;
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := Compile(Pattern, Algorithm, MaxDistance);
  try
    Result := Searcher.FindAll(List);
  finally
    Searcher.Free;
  end;
end;

class function TPatternSearch.FindAll(List: TList<Byte>; const Pattern: TBytePattern; Algorithm: TMaskedPatternSearchAlgorithm): TPatternMatches;
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := Compile(Pattern, Algorithm);
  try
    Result := Searcher.FindAll(List);
  finally
    Searcher.Free;
  end;
end;

end.
