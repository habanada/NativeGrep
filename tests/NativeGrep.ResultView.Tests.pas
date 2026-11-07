unit NativeGrep.ResultView.Tests;

interface

procedure RunResultViewTests;

implementation

uses
  System.SysUtils, System.Generics.Collections, NativeGrep.Types, NativeGrep.ResultView;

procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then raise Exception.Create('RESULT VIEW FAIL: ' + Name);
end;

procedure RunResultViewTests;
var
  Matches: TList<TGrepMatch>;
  Excerpts: TList<string>;
  View: TGrepResultView;
  Match: TGrepMatch;
  I: Integer;

  procedure Add(const Path, Text: string; Offset: Int64; Line: Int64 = 1);
  begin
    Match := Default(TGrepMatch);
    Match.SourcePath := Path;
    Match.ByteOffset := Offset;
    Match.Line := Line;
    Match.Column := 3;
    Matches.Add(Match);
    Excerpts.Add(Text);
  end;

begin
  Matches := TList<TGrepMatch>.Create;
  Excerpts := TList<string>.Create;
  View := TGrepResultView.Create;
  try
    Add('C:\z\beta.txt', 'TODO connection failed', 200, 42);
    Add('C:\a\alpha.txt', 'TODO success', 80, 8);
    Add('C:\z\beta.txt', 'TODO timeout', 100, 20);
    Add('C:\a\gamma.txt', 'TODO TIMEOUT', 10, 2);
    Add('c:\Z\BETA.TXT', 'TODO duplicate offset', 100, 20);
    Add('relative.txt', 'relative result', 0);
    View.Rebuild(Matches, Excerpts, '', grgNone);
    Check(View.Count = 6, 'all source rows');
    for I := 0 to 5 do Check(View.SourceIndex(I) = I, 'ungrouped arrival order');
    Check(View.SourceIndex(-1) = -1, 'negative row');
    Check(View.SourceIndex(6) = -1, 'past final row');
    Check(View.RowIndex(99) = -1, 'unknown source');
    View.Rebuild(Matches, Excerpts, '', grgFile);
    Check(View.SourceIndex(0) = 1, 'files sorted by path');
    Check(View.SourceIndex(2) = 2, 'within-file offset order');
    Check(View.SourceIndex(3) = 4, 'equal offsets retain stable identity');
    Check(View.GroupText(2) = View.GroupText(4), 'case-insensitive canonical group');
    Check(Pos('(3 matches)', View.GroupText(2)) > 0, 'file group total');
    for I := 0 to 5 do Check(View.RowIndex(View.SourceIndex(I)) = I, 'bidirectional row mapping');
    Check(Matches[0].ByteOffset = 200, 'original matches stay in arrival order');
    View.Rebuild(Matches, Excerpts, 'timeout', grgFile);
    Check(View.Count = 2, 'case-insensitive excerpt filter');
    Check(View.SourceIndex(0) = 3, 'filtered source identity');
    Check(View.RowIndex(2) = 1, 'filtered selection identity');
    Check(View.RowIndex(0) = -1, 'hidden source cannot be selected');
    Check(Pos('(1 match)', View.GroupText(1)) > 0, 'group count uses visible matches');
    View.Rebuild(Matches, Excerpts, 'C:\A', grgFolder);
    Check(View.Count = 2, 'case-insensitive path filter');
    Check(View.GroupText(0) = View.GroupText(1), 'folder groups contain different files');
    Check(Pos('(2 matches)', View.GroupText(0)) > 0, 'folder group count');
    View.Rebuild(Matches, Excerpts, '42:3', grgNone);
    Check((View.Count = 1) and (View.SourceIndex(0) = 0), 'line and column filter');
    View.Rebuild(Matches, Excerpts, '0xC8', grgNone);
    Check((View.Count = 1) and (View.SourceIndex(0) = 0), 'hexadecimal offset filter');
    View.Rebuild(Matches, Excerpts, 'relative result', grgFolder);
    Check(Pos('. (1 match)', View.GroupText(0)) = 1, 'relative filename folder');
    View.Rebuild(Matches, Excerpts, 'absent value', grgFile);
    Check((View.Count = 0) and (View.GroupText(0) = ''), 'empty filtered view');
    View.Rebuild(Matches, Excerpts, ' ', grgNone);
    Check(View.Count = 6, 'clearing the filter restores all results');
    View.Clear;
    Check((View.Count = 0) and (View.RowIndex(0) = -1), 'clear removes stale mappings');
  finally
    View.Free;
    Excerpts.Free;
    Matches.Free;
  end;
end;

end.
