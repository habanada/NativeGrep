unit NativeGrep.Sort;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Generics.Defaults, NativeGrep.Types;

type
  TGrepSortedMatchHandler = reference to function(const Match: TGrepMatch): Boolean;

  TGrepMatchSorter = class sealed
  private
    FBuffer: TList<TGrepMatch>;
    FLevels: TList<string>;
    FComparer: IComparer<TGrepMatch>;
    FIsCancelled: TFunc<Boolean>;
    class function CompareMatches(const A, B: TGrepMatch): Integer; static;
    class procedure WriteMatch(Stream: TStream; const Match: TGrepMatch); static;
    class function ReadMatch(Stream: TStream; out Match: TGrepMatch): Boolean; static;
    class function MergeFiles(const LeftPath, RightPath: string; const IsCancelled: TFunc<Boolean>): string; static;
    procedure FlushBuffer;
  public
    constructor Create(const IsCancelled: TFunc<Boolean> = nil);
    destructor Destroy; override;
    procedure Add(const Match: TGrepMatch);
    procedure Drain(const OnMatch: TGrepSortedMatchHandler; const IsCancelled: TFunc<Boolean>);
  end;

implementation

uses
  System.IOUtils;

const
  SortChunkSize = 2048;

function ComparePaths(const A, B: string): Integer;
var
  I, L: Integer;
begin
  L := Length(A);
  if Length(B) < L then L := Length(B);
  for I := 1 to L do
    if A[I] <> B[I] then
    begin
      if Ord(A[I]) < Ord(B[I]) then Exit(-1);
      Exit(1);
    end;
  if Length(A) < Length(B) then Exit(-1);
  if Length(A) > Length(B) then Exit(1);
  Result := 0;
end;

class function TGrepMatchSorter.CompareMatches(const A, B: TGrepMatch): Integer;
begin
  Result := ComparePaths(A.SourcePath, B.SourcePath);
  if Result <> 0 then Exit;
  if A.ByteOffset < B.ByteOffset then Exit(-1);
  if A.ByteOffset > B.ByteOffset then Exit(1);
  if A.PatternIndex < B.PatternIndex then Exit(-1);
  if A.PatternIndex > B.PatternIndex then Exit(1);
  if A.Distance < B.Distance then Exit(-1);
  if A.Distance > B.Distance then Exit(1);
  if A.ByteLength < B.ByteLength then Exit(-1);
  if A.ByteLength > B.ByteLength then Exit(1);
  if A.Line < B.Line then Exit(-1);
  if A.Line > B.Line then Exit(1);
  if A.Column < B.Column then Exit(-1);
  if A.Column > B.Column then Exit(1);
  Result := 0;
end;

constructor TGrepMatchSorter.Create(const IsCancelled: TFunc<Boolean>);
begin
  inherited Create;
  FIsCancelled := IsCancelled;
  FBuffer := TList<TGrepMatch>.Create;
  FLevels := TList<string>.Create;
  FComparer := TComparer<TGrepMatch>.Construct(
    function(const A, B: TGrepMatch): Integer
    begin
      Result := CompareMatches(A, B);
    end);
end;

destructor TGrepMatchSorter.Destroy;
var
  Path: string;
begin
  for Path in FLevels do
    if Path <> '' then System.SysUtils.DeleteFile(Path);
  FLevels.Free;
  FBuffer.Free;
  inherited;
end;

class procedure TGrepMatchSorter.WriteMatch(Stream: TStream; const Match: TGrepMatch);
var
  Len: Integer;
begin
  Len := Length(Match.SourcePath);
  if Len > 32768 then raise EArgumentOutOfRangeException.Create('Sorted path too long');
  Stream.WriteBuffer(Len, SizeOf(Len));
  if Len > 0 then Stream.WriteBuffer(Match.SourcePath[1], Len * SizeOf(Char));
  Stream.WriteBuffer(Match.ByteOffset, SizeOf(Match.ByteOffset));
  Stream.WriteBuffer(Match.ByteLength, SizeOf(Match.ByteLength));
  Stream.WriteBuffer(Match.Line, SizeOf(Match.Line));
  Stream.WriteBuffer(Match.Column, SizeOf(Match.Column));
  Stream.WriteBuffer(Match.PatternIndex, SizeOf(Match.PatternIndex));
  Stream.WriteBuffer(Match.Distance, SizeOf(Match.Distance));
  Len := Length(Match.Captures);
  if Len > 256 then raise EArgumentOutOfRangeException.Create('Too many regex capture groups for sorted output');
  Stream.WriteBuffer(Len, SizeOf(Len));
  if Len > 0 then Stream.WriteBuffer(Match.Captures[0], Len * SizeOf(TGrepCapture));
end;

class function TGrepMatchSorter.ReadMatch(Stream: TStream; out Match: TGrepMatch): Boolean;
var
  Len: Integer;
begin
  Result := Stream.Position < Stream.Size;
  if not Result then Exit;
  Match := Default(TGrepMatch);
  Stream.ReadBuffer(Len, SizeOf(Len));
  if (Len < 0) or (Len > 32768) then raise EReadError.Create('Invalid sorted path length');
  SetLength(Match.SourcePath, Len);
  if Len > 0 then Stream.ReadBuffer(Match.SourcePath[1], Len * SizeOf(Char));
  Stream.ReadBuffer(Match.ByteOffset, SizeOf(Match.ByteOffset));
  Stream.ReadBuffer(Match.ByteLength, SizeOf(Match.ByteLength));
  Stream.ReadBuffer(Match.Line, SizeOf(Match.Line));
  Stream.ReadBuffer(Match.Column, SizeOf(Match.Column));
  Stream.ReadBuffer(Match.PatternIndex, SizeOf(Match.PatternIndex));
  Stream.ReadBuffer(Match.Distance, SizeOf(Match.Distance));
  Stream.ReadBuffer(Len, SizeOf(Len));
  if (Len < 0) or (Len > 256) then raise EReadError.Create('Invalid regex capture count');
  SetLength(Match.Captures, Len);
  if Len > 0 then Stream.ReadBuffer(Match.Captures[0], Len * SizeOf(TGrepCapture));
end;

class function TGrepMatchSorter.MergeFiles(const LeftPath, RightPath: string; const IsCancelled: TFunc<Boolean>): string;
var
  LeftStream, RightStream, OutputStream: TFileStream;
  LeftMatch, RightMatch: TGrepMatch;
  HasLeft, HasRight: Boolean;
  Batch: Integer;
begin
  if Assigned(IsCancelled) and IsCancelled() then raise EAbort.Create('Sort cancelled');
  Result := TPath.GetTempFileName;
  LeftStream := nil;
  RightStream := nil;
  OutputStream := nil;
  try
    try
      LeftStream := TFileStream.Create(LeftPath, fmOpenRead or fmShareDenyWrite);
      RightStream := TFileStream.Create(RightPath, fmOpenRead or fmShareDenyWrite);
      OutputStream := TFileStream.Create(Result, fmCreate);
      HasLeft := ReadMatch(LeftStream, LeftMatch);
      HasRight := ReadMatch(RightStream, RightMatch);
      Batch := 0;
      while HasLeft or HasRight do
      begin
        if ((Batch and 255) = 0) and Assigned(IsCancelled) and IsCancelled() then raise EAbort.Create('Sort cancelled');
        Inc(Batch);
        if HasLeft and (not HasRight or (CompareMatches(LeftMatch, RightMatch) <= 0)) then
        begin
          WriteMatch(OutputStream, LeftMatch);
          HasLeft := ReadMatch(LeftStream, LeftMatch);
        end
        else
        begin
          WriteMatch(OutputStream, RightMatch);
          HasRight := ReadMatch(RightStream, RightMatch);
        end;
      end;
    finally
      OutputStream.Free;
      RightStream.Free;
      LeftStream.Free;
    end;
  except
    System.SysUtils.DeleteFile(Result);
    raise;
  end;
end;

procedure TGrepMatchSorter.FlushBuffer;
var
  CurrentPath, OldPath, NewPath: string;
  Stream: TFileStream;
  Match: TGrepMatch;
  Level: Integer;
begin
  if FBuffer.Count = 0 then Exit;
  if Assigned(FIsCancelled) and FIsCancelled() then raise EAbort.Create('Sort cancelled');
  FBuffer.Sort(FComparer);
  CurrentPath := TPath.GetTempFileName;
  try
    Stream := TFileStream.Create(CurrentPath, fmCreate);
    try
      for Match in FBuffer do WriteMatch(Stream, Match);
    finally
      Stream.Free;
    end;
    FBuffer.Clear;
    Level := 0;
    while True do
    begin
      if Level = FLevels.Count then FLevels.Add('');
      OldPath := FLevels[Level];
      if OldPath = '' then
      begin
        FLevels[Level] := CurrentPath;
        CurrentPath := '';
        Break;
      end;
      NewPath := MergeFiles(OldPath, CurrentPath, FIsCancelled);
      FLevels[Level] := '';
      System.SysUtils.DeleteFile(OldPath);
      System.SysUtils.DeleteFile(CurrentPath);
      CurrentPath := NewPath;
      Inc(Level);
    end;
  finally
    if CurrentPath <> '' then System.SysUtils.DeleteFile(CurrentPath);
  end;
end;

procedure TGrepMatchSorter.Add(const Match: TGrepMatch);
begin
  if Assigned(FIsCancelled) and FIsCancelled() then raise EAbort.Create('Sort cancelled');
  FBuffer.Add(Match);
  if FBuffer.Count >= SortChunkSize then FlushBuffer;
end;

procedure TGrepMatchSorter.Drain(const OnMatch: TGrepSortedMatchHandler; const IsCancelled: TFunc<Boolean>);
var
  I: Integer;
  Path, CurrentPath, NewPath: string;
  Stream: TFileStream;
  Match: TGrepMatch;
begin
  if FLevels.Count = 0 then
  begin
    FBuffer.Sort(FComparer);
    for Match in FBuffer do
      if IsCancelled() or not OnMatch(Match) then Break;
    FBuffer.Clear;
    Exit;
  end;
  FlushBuffer;
  CurrentPath := '';
  try
    for I := 0 to FLevels.Count - 1 do
    begin
      Path := FLevels[I];
      if Path = '' then Continue;
      if CurrentPath = '' then
      begin
        CurrentPath := Path;
        FLevels[I] := '';
        Continue;
      end;
      NewPath := MergeFiles(CurrentPath, Path, IsCancelled);
      FLevels[I] := '';
      System.SysUtils.DeleteFile(Path);
      System.SysUtils.DeleteFile(CurrentPath);
      CurrentPath := NewPath;
    end;
    if CurrentPath = '' then Exit;
    Stream := TFileStream.Create(CurrentPath, fmOpenRead or fmShareDenyWrite);
    try
      while not IsCancelled() and ReadMatch(Stream, Match) do
        if not OnMatch(Match) then Break;
    finally
      Stream.Free;
    end;
  finally
    if CurrentPath <> '' then System.SysUtils.DeleteFile(CurrentPath);
  end;
end;

end.
