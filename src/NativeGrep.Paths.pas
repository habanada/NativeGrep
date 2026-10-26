unit NativeGrep.Paths;

interface

function GrepWindowsPath(const Path: string): string;

implementation

uses
  System.SysUtils;

function GrepWindowsPath(const Path: string): string;
var
  FullPath: string;
begin
  if (Length(Path) < 248) or (Copy(Path, 1, 4) = '\\?\') then Exit(Path);
  FullPath := ExpandFileName(Path);
  if Copy(FullPath, 1, 2) = '\\' then Result := '\\?\UNC\' + Copy(FullPath, 3, MaxInt)
  else Result := '\\?\' + FullPath;
end;

end.
