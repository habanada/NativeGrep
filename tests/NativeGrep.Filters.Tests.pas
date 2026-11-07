unit NativeGrep.Filters.Tests;

interface

procedure RunFileFilterTests(const Dir: string);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.DateUtils,
  System.Generics.Collections, Winapi.Windows,
  NativeGrep.Types, NativeGrep.Filters, NativeGrep.Files, NativeGrep.Api;

type
  TFilterSink = class(TInterfacedObject, IGrepResultSink)
  public
    procedure MatchFound(const Match: TGrepMatch);
    procedure ScanError(const SourcePath, ErrorText: string);
  end;

procedure TFilterSink.MatchFound(const Match: TGrepMatch);
begin
end;

procedure TFilterSink.ScanError(const SourcePath, ErrorText: string);
begin
  raise Exception.Create(SourcePath + ': ' + ErrorText);
end;

procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then raise Exception.Create('FILE FILTER FAIL: ' + Name);
end;

procedure ExpectInvalid(const Action: TProc; const Name: string);
begin
  try
    Action();
  except
    on E: EArgumentException do Exit;
  end;
  raise Exception.Create('FILE FILTER FAIL: expected invalid ' + Name);
end;

procedure StampFile(const Path: string; const Created, Modified, Accessed: Int64);
var
  Handle: THandle;
  C, M, A: TFileTime;
begin
  C.dwLowDateTime := Cardinal(Created and $FFFFFFFF);
  C.dwHighDateTime := Cardinal(Created shr 32);
  M.dwLowDateTime := Cardinal(Modified and $FFFFFFFF);
  M.dwHighDateTime := Cardinal(Modified shr 32);
  A.dwLowDateTime := Cardinal(Accessed and $FFFFFFFF);
  A.dwHighDateTime := Cardinal(Accessed shr 32);
  Handle := CreateFile(PChar(Path), FILE_WRITE_ATTRIBUTES, FILE_SHARE_READ or FILE_SHARE_WRITE or
    FILE_SHARE_DELETE, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if Handle = INVALID_HANDLE_VALUE then RaiseLastOSError;
  try
    if not SetFileTime(Handle, @C, @A, @M) then RaiseLastOSError;
  finally
    CloseHandle(Handle);
  end;
end;

procedure RunFileFilterTests(const Dir: string);
var
  Root, A, B, C, Empty: string;
  Options: TGrepOptions;
  Range, Other: TGrepFilterRange;
  Found: TList<string>;
  D: TDateTime;
  First, Middle, Last: Int64;
  Request: TGrepRequest;
  Stats: TGrepStatistics;
  Sink: IGrepResultSink;

  procedure Enumerate(Expected: Integer; const Name: string);
  begin
    Found.Clear;
    TGrepFileEnumerator.Execute(Options,
      function: Boolean begin Result := False; end,
      procedure(Path: string) begin Found.Add(Path); end,
      procedure(Path, Error: string) begin raise Exception.Create(Path + ': ' + Error); end);
    Check(Found.Count = Expected, Name + ' count');
  end;

begin
  Check(TGrepFileFilters.ParseSize('1.5 MiB') = 1572864, 'fractional binary units');
  Check(TGrepFileFilters.ParseSize('1.25 KB') = 1250, 'decimal units');
  Check(TGrepFileFilters.ParseSize('5GiB') = Int64(5) * 1024 * 1024 * 1024, 'Int64 sizes');
  Check(TGrepFileFilters.ParseSize('9223372036854775807') = High(Int64), 'maximum size');
  ExpectInvalid(procedure begin TGrepFileFilters.ParseSize('9223372036854775808'); end, 'overflow');
  ExpectInvalid(procedure begin TGrepFileFilters.ParseSize('9TiBblah'); end, 'unknown unit');
  ExpectInvalid(procedure begin TGrepFileFilters.ParseSize('0.1B'); end, 'fractional byte');
  ExpectInvalid(procedure begin TGrepFileFilters.ParseSize('-1'); end, 'negative size');
  ExpectInvalid(procedure begin TGrepFileFilters.ParseSizeRange('12..4'); end, 'reversed size');
  Range := TGrepFileFilters.ParseSizeRange('>4');
  Check(not TGrepFileFilters.Contains(Range, 4) and TGrepFileFilters.Contains(Range, 5), 'strict minimum');
  Range := TGrepFileFilters.ParseSizeRange('<=4');
  Check(TGrepFileFilters.Contains(Range, 4) and not TGrepFileFilters.Contains(Range, 5), 'inclusive maximum');
  Range := TGrepFileFilters.ParseSizeRange('=0');
  Check(TGrepFileFilters.Contains(Range, 0) and not TGrepFileFilters.Contains(Range, 1), 'empty files');

  Range := TGrepFileFilters.ParseTimeRange('2026-01-15', '2026-01-15');
  D := EncodeDate(2026, 1, 15);
  Check(Range.Minimum = TGrepFileFilters.UtcTicks(TTimeZone.Local.ToUniversalTime(D)), 'local midnight');
  Check(Range.MaximumExclusive, 'date end exclusive next midnight');
  Check(TGrepFileFilters.Contains(Range, Range.Maximum - 1) and
    not TGrepFileFilters.Contains(Range, Range.Maximum), 'whole day upper boundary');
  Range := TGrepFileFilters.ParseTimeRange('2026-01-15T12:00:00Z', '2026-01-15T12:00:00Z');
  Other := TGrepFileFilters.ParseTimeRange('2026-01-15T13:00:00+01:00', '');
  Check(Range.Minimum = Other.Minimum, 'timezone offset equivalence');
  Other := TGrepFileFilters.ParseTimeRange('2026-01-15T12:00:00.1234567Z', '');
  Check(Other.Minimum = Range.Minimum + 1234567, '100 ns timestamp precision');
  Check(TGrepFileFilters.Contains(Range, Range.Minimum) and
    not TGrepFileFilters.Contains(Range, Range.Minimum + 1), 'exact timestamp boundary');
  Other := TGrepFileFilters.ParseTimeRange('2026-01-15T12:00:00', '');
  Check(Other.Minimum = TGrepFileFilters.UtcTicks(TTimeZone.Local.ToUniversalTime(D + 0.5)), 'local timestamp');
  Range := TGrepFileFilters.ParseTimeRange('now-24h', 'now');
  Check(Abs((Range.Maximum - Range.Minimum) - Int64(86400) * 10000000) < 20000, 'relative 24 hours');
  Range := TGrepFileFilters.ParseTimeRange('today', 'today');
  Check(Range.HasMinimum and Range.HasMaximum and Range.MaximumExclusive, 'today range');
  ExpectInvalid(procedure begin TGrepFileFilters.ParseTimeRange('2026-02-30', ''); end, 'invalid date');
  ExpectInvalid(procedure begin TGrepFileFilters.ParseTimeRange('2026-02-01', '2026-01-01'); end, 'reversed time');
  ExpectInvalid(procedure begin TGrepFileFilters.ParseTimeRange('now-7x', ''); end, 'relative unit');
  ExpectInvalid(procedure begin TGrepFileFilters.ParseTimeRange('2026-01-15T12:00:00.12345678Z', ''); end, 'excess timestamp precision');

  Root := IncludeTrailingPathDelimiter(Dir) + 'filters';
  ForceDirectories(Root + '\nested');
  A := Root + '\a.txt';
  B := Root + '\b.txt';
  C := Root + '\nested\c.txt';
  Empty := Root + '\empty.txt';
  TFile.WriteAllBytes(A, TEncoding.ASCII.GetBytes('TODO'));
  TFile.WriteAllBytes(B, TEncoding.ASCII.GetBytes('TODOxxxx'));
  TFile.WriteAllBytes(C, TEncoding.ASCII.GetBytes('TODOxxxxxxxx'));
  TFile.WriteAllBytes(Empty, nil);
  First := TGrepFileFilters.UtcTicks(EncodeDate(2026, 1, 10));
  Middle := TGrepFileFilters.UtcTicks(EncodeDate(2026, 1, 15));
  Last := TGrepFileFilters.UtcTicks(EncodeDate(2026, 1, 20));
  StampFile(A, First, Middle, Last);
  StampFile(B, Middle, Last, First);
  StampFile(C, Last, First, Middle);
  StampFile(Empty, First, First, First);
  Options := Default(TGrepOptions);
  Options.Roots := [Root];
  Options.Recursive := True;
  Found := TList<string>.Create;
  try
    Enumerate(4, 'unfiltered');
    Options.FileSizeFilter := TGrepFileFilters.ParseSizeRange('4..8');
    Enumerate(2, 'inclusive size range');
    Check(Found.Contains(A) and Found.Contains(B), 'size range members');
    Options.FileSizeFilter := TGrepFileFilters.ParseSizeRange('<8');
    Enumerate(2, 'smaller than');
    Options.FileSizeFilter := TGrepFileFilters.ParseSizeRange('>8');
    Enumerate(1, 'larger than recursive');
    Check(Found[0] = C, 'recursive size member');
    Options.Recursive := False;
    Enumerate(0, 'no recursive descent');
    Options.Recursive := True;
    Options.FileSizeFilter := TGrepFileFilters.ParseSizeRange('=0');
    Enumerate(1, 'only empty file');
    Check(Found[0] = Empty, 'empty member');
    Options.FileSizeFilter := Default(TGrepFilterRange);
    Options.MaxFileSize := 4;
    Enumerate(2, 'legacy maximum');
    Options.FileSizeFilter := TGrepFileFilters.ParseSizeRange('>=8');
    ExpectInvalid(procedure begin TGrepFileFilters.Validate(Options); end, 'conflicting legacy maximum');
    Options.MaxFileSize := 0;
    Options.FileSizeFilter := Default(TGrepFilterRange);
    Range := Default(TGrepFilterRange);
    Range.HasMinimum := True;
    Range.HasMaximum := True;
    Range.Minimum := Middle;
    Range.Maximum := Middle;
    Options.CreatedTimeFilter := Range;
    Enumerate(1, 'created time');
    Check(Found[0] = B, 'created member');
    Options.CreatedTimeFilter := Default(TGrepFilterRange);
    Options.ModifiedTimeFilter := Range;
    Enumerate(1, 'modified time');
    Check(Found[0] = A, 'modified member');
    Options.ModifiedTimeFilter := Default(TGrepFilterRange);
    Options.AccessedTimeFilter := Range;
    Enumerate(1, 'accessed time');
    Check(Found[0] = C, 'accessed member');
    Options.FileSizeFilter := TGrepFileFilters.ParseSizeRange('<=8');
    Enumerate(0, 'time AND size');
    Options.AccessedTimeFilter := Default(TGrepFilterRange);
    Options.Includes := ['*.txt'];
    Options.Excludes := ['empty*'];
    Enumerate(2, 'metadata AND globs');
    Options.Roots := [B];
    Options.ModifiedTimeFilter := Range;
    Enumerate(0, 'explicit file time rejected');
    Options.ModifiedTimeFilter := Default(TGrepFilterRange);
    Enumerate(1, 'explicit file inclusive size accepted');
    Options.FileSizeFilter := TGrepFileFilters.ParseSizeRange('<8');
    Enumerate(0, 'explicit file strict size rejected');
  finally
    Found.Free;
  end;
  Request := Default(TGrepRequest);
  Request.Query.Text := 'TODO';
  Request.Options.Roots := [Root];
  Request.Options.Recursive := True;
  Request.Options.FileSizeFilter := TGrepFileFilters.ParseSizeRange('=8');
  Sink := TFilterSink.Create;
  Request.Options.MaxWorkers := 1;
  Stats := TNativeGrep.Search(Request, Sink);
  Check((Stats.FilesScanned = 1) and (Stats.Matches = 1) and (Stats.BytesScanned = 8), 'engine filters before scanning');
  Request.Options.MaxWorkers := 4;
  Request.Options.SortResults := True;
  Stats := TNativeGrep.Search(Request, Sink);
  Check((Stats.FilesScanned = 1) and (Stats.Matches = 1), 'parallel sorted filtering');
  Request.Options.FileSizeFilter := TGrepFileFilters.ParseSizeRange('>1');
  ExpectInvalid(procedure begin TNativeGrep.SearchBytes(Request, 'bytes', nil, Sink); end, 'metadata on bytes');
end;

end.
