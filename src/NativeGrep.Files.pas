unit NativeGrep.Files;

interface

uses
  System.SysUtils, NativeGrep.Types;

type
  TGrepFileEnumerator = class sealed
  private
    class function GlobMatch(const Pattern, FileName: string): Boolean; static;
    class function GlobPathMatch(const Pattern, RelativePath: string): Boolean; static;
    class function Included(const FileName, RelativePath: string; const Options: TGrepOptions): Boolean; static;
  public
    class procedure Execute(const Options: TGrepOptions; const IsCancelled: TFunc<Boolean>; const OnFile: TProc<string>; const OnError: TProc<string, string>); static;
  end;

implementation

uses
  Winapi.Windows, NativeGrep.Paths, NativeGrep.Filters;

class function TGrepFileEnumerator.GlobMatch(const Pattern, FileName: string): Boolean;
var
  P, N, Star, Saved: Integer;
  A, B: string;
begin
  A := UpperCase(Pattern);
  B := UpperCase(FileName);
  P := 1;
  N := 1;
  Star := 0;
  Saved := 0;
  while N <= Length(B) do
  begin
    if (P <= Length(A)) and ((A[P] = '?') or (A[P] = B[N])) then
    begin
      Inc(P);
      Inc(N);
    end
    else if (P <= Length(A)) and (A[P] = '*') then
    begin
      Star := P;
      Inc(P);
      Saved := N;
    end
    else if Star <> 0 then
    begin
      P := Star + 1;
      Inc(Saved);
      N := Saved;
    end
    else
      Exit(False);
  end;
  while (P <= Length(A)) and (A[P] = '*') do Inc(P);
  Result := P > Length(A);
end;

class function TGrepFileEnumerator.GlobPathMatch(const Pattern, RelativePath: string): Boolean;
var
  Mask, Candidate: string;
  Memo: TBytes;
  Width, P, N, NextP, Index: Integer;
  Value: Boolean;
  C: Char;
begin
  Mask := UpperCase(StringReplace(Pattern, '/', '\', [rfReplaceAll]));
  Candidate := UpperCase(StringReplace(RelativePath, '/', '\', [rfReplaceAll]));
  Width := Length(Candidate) + 2;
  if Int64(Length(Mask) + 2) * Width > 16 * 1024 * 1024 then
    raise EArgumentOutOfRangeException.Create('Path glob is too large');
  SetLength(Memo, (Length(Mask) + 2) * Width);
  for N := 1 to Length(Candidate) + 1 do
    if N > Length(Candidate) then Memo[(Length(Mask) + 1) * Width + N] := 1;
  for P := Length(Mask) downto 1 do
  begin
    C := Mask[P];
    for N := Length(Candidate) + 1 downto 1 do
    begin
      Index := P * Width + N;
      if C = '*' then
      begin
        NextP := P + 1;
        if (NextP <= Length(Mask)) and (Mask[NextP] = '*') then
        begin
          Inc(NextP);
          Value := Memo[NextP * Width + N] <> 0;
          if (NextP <= Length(Mask)) and (Mask[NextP] = '\') then
            Value := Value or (Memo[(NextP + 1) * Width + N] <> 0);
          if N <= Length(Candidate) then Value := Value or (Memo[Index + 1] <> 0);
        end
        else
        begin
          Value := Memo[NextP * Width + N] <> 0;
          if (N <= Length(Candidate)) and (Candidate[N] <> '\') then
            Value := Value or (Memo[Index + 1] <> 0);
        end;
      end
      else
        Value := (N <= Length(Candidate)) and
          ((C = Candidate[N]) or ((C = '?') and (Candidate[N] <> '\'))) and
          (Memo[(P + 1) * Width + N + 1] <> 0);
      if Value then Memo[Index] := 1;
    end;
  end;
  Result := Memo[Width + 1] <> 0;
end;

class function TGrepFileEnumerator.Included(const FileName, RelativePath: string; const Options: TGrepOptions): Boolean;
var
  S: string;

  function Matches(const Mask: string): Boolean;
  begin
    if (Pos('\', Mask) > 0) or (Pos('/', Mask) > 0) then Result := GlobPathMatch(Mask, RelativePath)
    else Result := GlobMatch(Mask, FileName);
  end;

begin
  Result := Length(Options.Includes) = 0;
  for S in Options.Includes do
    if Matches(S) then
    begin
      Result := True;
      Break;
    end;
  if not Result then Exit;
  for S in Options.Excludes do
    if Matches(S) then Exit(False);
end;

class procedure TGrepFileEnumerator.Execute(const Options: TGrepOptions; const IsCancelled: TFunc<Boolean>; const OnFile: TProc<string>; const OnError: TProc<string, string>);
var
  Root: string;
  RootData: TWin32FileAttributeData;
  Attr: DWORD;
  Size: Int64;

  function Accepted(const FileSize: Int64; const Created, Modified, Accessed: TFileTime): Boolean;
  begin
    Result := ((Options.MaxFileSize = 0) or (FileSize <= Options.MaxFileSize)) and
      TGrepFileFilters.Contains(Options.FileSizeFilter, FileSize) and
      TGrepFileFilters.Contains(Options.CreatedTimeFilter,
        (Int64(Created.dwHighDateTime) shl 32) or Created.dwLowDateTime) and
      TGrepFileFilters.Contains(Options.ModifiedTimeFilter,
        (Int64(Modified.dwHighDateTime) shl 32) or Modified.dwLowDateTime) and
      TGrepFileFilters.Contains(Options.AccessedTimeFilter,
        (Int64(Accessed.dwHighDateTime) shl 32) or Accessed.dwLowDateTime);
  end;

  procedure Walk(const DirPath, RelativeDir: string; Depth: Integer);
  var
    Data: TWin32FindData;
    Handle: THandle;
    FullPath, Name, RelativePath: string;
    ItemAttr, Code: DWORD;
    ItemSize: Int64;
  begin
    if IsCancelled() then Exit;
    if Depth > 256 then
    begin
      OnError(DirPath, 'Maximum directory depth exceeded');
      Exit;
    end;
    Handle := FindFirstFile(PChar(GrepWindowsPath(IncludeTrailingPathDelimiter(DirPath) + '*')), Data);
    if Handle = INVALID_HANDLE_VALUE then
    begin
      Code := GetLastError;
      if Code <> ERROR_FILE_NOT_FOUND then OnError(DirPath, SysErrorMessage(Code));
      Exit;
    end;
    try
      repeat
        if IsCancelled() then Break;
        Name := Data.cFileName;
        if (Name = '.') or (Name = '..') then Continue;
        ItemAttr := Data.dwFileAttributes;
        if (ItemAttr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then Continue;
        if not Options.IncludeHidden and ((ItemAttr and (FILE_ATTRIBUTE_HIDDEN or FILE_ATTRIBUTE_SYSTEM)) <> 0) then Continue;
        FullPath := IncludeTrailingPathDelimiter(DirPath) + Name;
        if RelativeDir = '' then RelativePath := Name else RelativePath := RelativeDir + '\' + Name;
        if (ItemAttr and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
        begin
          if Options.Recursive then Walk(FullPath, RelativePath, Depth + 1);
        end
        else if Included(Name, RelativePath, Options) then
        begin
          ItemSize := (Int64(Data.nFileSizeHigh) shl 32) + Int64(Data.nFileSizeLow);
          if Accepted(ItemSize, Data.ftCreationTime, Data.ftLastWriteTime, Data.ftLastAccessTime) then OnFile(FullPath);
        end;
      until not FindNextFile(Handle, Data);
      Code := GetLastError;
      if (Code <> ERROR_NO_MORE_FILES) and not IsCancelled() then OnError(DirPath, SysErrorMessage(Code));
    finally
      Winapi.Windows.FindClose(Handle);
    end;
  end;

begin
  TGrepFileFilters.Validate(Options);
  for Root in Options.Roots do
  begin
    if IsCancelled() then Break;
    if not GetFileAttributesEx(PChar(GrepWindowsPath(Root)), GetFileExInfoStandard, @RootData) then
    begin
      OnError(Root, SysErrorMessage(GetLastError));
      Continue;
    end;
    Attr := RootData.dwFileAttributes;
    if (Attr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then Continue;
    if (Attr and FILE_ATTRIBUTE_DIRECTORY) <> 0 then Walk(Root, '', 0)
    else if Included(ExtractFileName(Root), ExtractFileName(Root), Options) then
    begin
      Size := (Int64(RootData.nFileSizeHigh) shl 32) + Int64(RootData.nFileSizeLow);
      if Accepted(Size, RootData.ftCreationTime, RootData.ftLastWriteTime, RootData.ftLastAccessTime) then OnFile(Root);
    end;
  end;
end;

end.
