unit NativeGrep.Context;

interface

uses
  System.SysUtils, NativeGrep.Types;

type
  TGrepContextLine = record
    Line: Int64;
    Text: string;
    IsMatch: Boolean;
    Truncated: Boolean;
  end;

  TGrepContextReader = class sealed
  public
    class function ReadFile(const Match: TGrepMatch; Encoding: TGrepEncoding; BeforeCount, AfterCount: Integer; MaxLineChars: Integer = 2048): TArray<TGrepContextLine>; static;
  end;

implementation

uses
  System.Classes, System.Generics.Collections, NativeGrep.Paths;

type
  TLineRange = record
    FirstChar: Integer;
    LastChar: Integer;
    NextChar: Integer;
  end;

function ActualEncoding(Stream: TStream; Requested: TGrepEncoding): TGrepEncoding;
var
  Prefix: array[0..2] of Byte;
  N: Integer;
begin
  Result := Requested;
  if Requested <> geAuto then Exit;
  Stream.Position := 0;
  N := Stream.Read(Prefix, SizeOf(Prefix));
  Result := geUtf8;
  if N >= 2 then
  begin
    if (Prefix[0] = $FF) and (Prefix[1] = $FE) then Result := geUtf16LE
    else if (Prefix[0] = $FE) and (Prefix[1] = $FF) then Result := geUtf16BE;
  end;
end;

function LineExcerpt(const Value: string; FirstChar, LastChar, HitChar, MaxChars: Integer; IsMatch, AtLeftEdge, AtRightEdge: Boolean; out Truncated: Boolean): string;
var
  N, First, HitInLine, Take: Integer;
begin
  N := LastChar - FirstChar + 1;
  if N < 0 then N := 0;
  First := 0;
  if N > MaxChars then
  begin
    if IsMatch then
    begin
      HitInLine := HitChar - FirstChar;
      First := HitInLine - (MaxChars div 4);
      if First < 0 then First := 0;
      if First > N - MaxChars then First := N - MaxChars;
    end;
  end;
  Take := N - First;
  if Take > MaxChars then Take := MaxChars;
  Result := Copy(Value, FirstChar + First, Take);
  Truncated := AtLeftEdge or AtRightEdge or (N > MaxChars);
  if (AtLeftEdge or (First > 0)) then Result := '...' + Result;
  if AtRightEdge or (First + MaxChars < N) then Result := Result + '...';
end;

class function TGrepContextReader.ReadFile(const Match: TGrepMatch; Encoding: TGrepEncoding; BeforeCount, AfterCount: Integer; MaxLineChars: Integer): TArray<TGrepContextLine>;
var
  Stream: TFileStream;
  SelectedEncoding: TGrepEncoding;
  Decoder: TEncoding;
  Data: TBytes;
  Lines: TList<TLineRange>;
  Current: TLineRange;
  Text: string;
  I, StartChar, HitChar, Target, FirstLine, LastLine, TargetLine, ByteCount, PrefixBytes: Integer;
  WindowStart, WindowEnd, BytesBefore, BytesAfter, FileSize: Int64;
  AtLeft, AtRight: Boolean;
begin
  if (BeforeCount < 0) or (AfterCount < 0) or (BeforeCount > 32) or (AfterCount > 32) then
    raise EArgumentOutOfRangeException.Create('Context line counts must be in range 0..32');
  if (MaxLineChars < 64) or (MaxLineChars > 16384) then
    raise EArgumentOutOfRangeException.Create('MaxLineChars must be in range 64..16384');
  if (Match.Line <= 0) or (Match.ByteOffset < 0) then
    raise EArgumentException.Create('Text context requires a match with a valid line and byte offset');
  Stream := TFileStream.Create(GrepWindowsPath(Match.SourcePath), fmOpenRead or fmShareDenyNone);
  try
    FileSize := Stream.Size;
    if Match.ByteOffset >= FileSize then raise EArgumentOutOfRangeException.Create('Match offset is past the end of the source');
    SelectedEncoding := ActualEncoding(Stream, Encoding);
    BytesBefore := Int64(BeforeCount + 2) * 16384;
    BytesAfter := Int64(AfterCount + 2) * 16384;
    if BytesBefore > 1024 * 1024 then BytesBefore := 1024 * 1024;
    if BytesAfter > 1024 * 1024 then BytesAfter := 1024 * 1024;
    WindowStart := Match.ByteOffset - BytesBefore;
    if WindowStart < 0 then WindowStart := 0;
    WindowEnd := Match.ByteOffset + BytesAfter;
    if WindowEnd > FileSize then WindowEnd := FileSize;
    if SelectedEncoding <> geUtf8 then
    begin
      WindowStart := WindowStart and not Int64(1);
      WindowEnd := WindowEnd and not Int64(1);
      if WindowEnd <= Match.ByteOffset then
      begin
        WindowEnd := Match.ByteOffset + 2;
        if WindowEnd > FileSize then WindowEnd := FileSize;
      end;
    end;
    ByteCount := Integer(WindowEnd - WindowStart);
    SetLength(Data, ByteCount);
    Stream.Position := WindowStart;
    if ByteCount > 0 then Stream.ReadBuffer(Data[0], ByteCount);
    PrefixBytes := Integer(Match.ByteOffset - WindowStart);
    case SelectedEncoding of
      geUtf16LE: Decoder := TEncoding.Unicode;
      geUtf16BE: Decoder := TEncoding.BigEndianUnicode;
    else
      Decoder := TEncoding.UTF8;
    end;
    Text := Decoder.GetString(Data);
    HitChar := Length(Decoder.GetString(Data, 0, PrefixBytes)) + 1;
    if (WindowStart = 0) and (Length(Text) > 0) and (Text[1] = #$FEFF) then
    begin
      Delete(Text, 1, 1);
      Dec(HitChar);
    end;
    Lines := TList<TLineRange>.Create;
    try
      I := 1;
      StartChar := 1;
      while I <= Length(Text) do
      begin
        if (Text[I] = #13) or (Text[I] = #10) then
        begin
          Current.FirstChar := StartChar;
          Current.LastChar := I - 1;
          if (Text[I] = #13) and (I < Length(Text)) and (Text[I + 1] = #10) then Inc(I);
          Current.NextChar := I + 1;
          Lines.Add(Current);
          StartChar := I + 1;
        end;
        Inc(I);
      end;
      Current.FirstChar := StartChar;
      Current.LastChar := Length(Text);
      Current.NextChar := Length(Text) + 2;
      Lines.Add(Current);
      Target := Lines.Count - 1;
      for I := 0 to Lines.Count - 1 do
        if HitChar < Lines[I].NextChar then
        begin
          Target := I;
          if (HitChar = Lines[I].NextChar - 1) and
            (Lines[I].NextChar - Lines[I].LastChar = 3) and (I < Lines.Count - 1) then Inc(Target);
          Break;
        end;
      FirstLine := Target - BeforeCount;
      if FirstLine < 0 then FirstLine := 0;
      LastLine := Target + AfterCount;
      if LastLine >= Lines.Count then LastLine := Lines.Count - 1;
      SetLength(Result, LastLine - FirstLine + 1);
      for I := FirstLine to LastLine do
      begin
        TargetLine := I - FirstLine;
        Result[TargetLine].Line := Match.Line + I - Target;
        Result[TargetLine].IsMatch := I = Target;
        AtLeft := (I = 0) and (WindowStart > 0);
        AtRight := (I = Lines.Count - 1) and (WindowEnd < FileSize);
        Result[TargetLine].Text := LineExcerpt(Text, Lines[I].FirstChar, Lines[I].LastChar, HitChar, MaxLineChars, I = Target, AtLeft, AtRight, Result[TargetLine].Truncated);
      end;
    finally
      Lines.Free;
    end;
  finally
    Stream.Free;
  end;
end;

end.
