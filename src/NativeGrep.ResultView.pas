unit NativeGrep.ResultView;

interface

uses
  System.SysUtils, System.Generics.Collections, NativeGrep.Types;

type
  TGrepResultGrouping = (grgNone, grgFile, grgFolder);

  // View rows refer to stable source indices; source matches are never reordered.
  TGrepResultView = class
  private
    FRows: TList<Integer>;
    FSourceRows: TDictionary<Integer, Integer>;
    FGroupKeys: TArray<string>;
    FGroupCounts: TDictionary<string, Integer>;
    FGroupNames: TDictionary<string, string>;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure Rebuild(const Matches: TList<TGrepMatch>; const Excerpts: TList<string>;
      const Filter: string; Grouping: TGrepResultGrouping);
    function SourceIndex(Row: Integer): Integer;
    function RowIndex(Source: Integer): Integer;
    function GroupText(Row: Integer): string;
    property Count: Integer read GetCount;
  end;

implementation

uses
  System.StrUtils, System.Generics.Defaults;

constructor TGrepResultView.Create;
begin
  inherited Create;
  FRows := TList<Integer>.Create;
  FSourceRows := TDictionary<Integer, Integer>.Create;
  FGroupCounts := TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  FGroupNames := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
end;

destructor TGrepResultView.Destroy;
begin
  FGroupCounts.Free;
  FGroupNames.Free;
  FSourceRows.Free;
  FRows.Free;
  inherited;
end;

procedure TGrepResultView.Clear;
begin
  FRows.Clear;
  FSourceRows.Clear;
  FGroupCounts.Clear;
  FGroupNames.Clear;
  FGroupKeys := nil;
end;

function TGrepResultView.GetCount: Integer;
begin
  Result := FRows.Count;
end;

function TGrepResultView.SourceIndex(Row: Integer): Integer;
begin
  if (Row < 0) or (Row >= FRows.Count) then Exit(-1);
  Result := FRows[Row];
end;

function TGrepResultView.RowIndex(Source: Integer): Integer;
begin
  if not FSourceRows.TryGetValue(Source, Result) then Result := -1;
end;

function TGrepResultView.GroupText(Row: Integer): string;
var
  Index, N: Integer;
  Key: string;
begin
  Result := '';
  Index := SourceIndex(Row);
  if (Index < 0) or (Index >= Length(FGroupKeys)) then Exit;
  Key := FGroupKeys[Index];
  if (Key <> '') and FGroupCounts.TryGetValue(Key, N) then
    if N = 1 then Result := Key + ' (1 match)'
    else Result := Format('%s (%d matches)', [Key, N]);
end;

procedure TGrepResultView.Rebuild(const Matches: TList<TGrepMatch>; const Excerpts: TList<string>;
  const Filter: string; Grouping: TGrepResultGrouping);
var
  I, N: Integer;
  Query, Text, Canonical: string;
  Match: TGrepMatch;
  Comparer: IComparer<Integer>;
  PathComparer: IComparer<string>;
begin
  if Matches.Count <> Excerpts.Count then
    raise EArgumentException.Create('Every source match must have an excerpt');
  Clear;
  SetLength(FGroupKeys, Matches.Count);
  Query := Trim(Filter);
  for I := 0 to Matches.Count - 1 do
  begin
    Match := Matches[I];
    if Query <> '' then
    begin
      Text := Match.SourcePath + #10 + Excerpts[I] + #10 +
        IntToStr(Match.Line) + ':' + IntToStr(Match.Column) + #10 +
        IntToStr(Match.ByteOffset) + #10 + '0x' + IntToHex(Match.ByteOffset, 1) +
        #10 + '$' + IntToHex(Match.ByteOffset, 1);
      if not ContainsText(Text, Query) then Continue;
    end;
    case Grouping of
      grgFile: FGroupKeys[I] := Match.SourcePath;
      grgFolder: FGroupKeys[I] := ExcludeTrailingPathDelimiter(ExtractFilePath(Match.SourcePath));
    end;
    if (Grouping = grgFolder) and (FGroupKeys[I] = '') then FGroupKeys[I] := '.';
    FRows.Add(I);
    if Grouping <> grgNone then
    begin
      if FGroupNames.TryGetValue(FGroupKeys[I], Canonical) then FGroupKeys[I] := Canonical
      else FGroupNames.Add(FGroupKeys[I], FGroupKeys[I]);
      if not FGroupCounts.TryGetValue(FGroupKeys[I], N) then N := 0;
      FGroupCounts.AddOrSetValue(FGroupKeys[I], N + 1);
    end;
  end;
  if Grouping <> grgNone then
  begin
    PathComparer := TIStringComparer.Ordinal;
    Comparer := TComparer<Integer>.Construct(
      function(const Left, Right: Integer): Integer
      begin
        Result := PathComparer.Compare(FGroupKeys[Left], FGroupKeys[Right]);
        if Result <> 0 then Exit;
        Result := PathComparer.Compare(Matches[Left].SourcePath, Matches[Right].SourcePath);
        if Result <> 0 then Exit;
        if Matches[Left].ByteOffset < Matches[Right].ByteOffset then Exit(-1);
        if Matches[Left].ByteOffset > Matches[Right].ByteOffset then Exit(1);
        if Left < Right then Result := -1 else if Left > Right then Result := 1;
      end);
    FRows.Sort(Comparer);
  end;
  for I := 0 to FRows.Count - 1 do FSourceRows.Add(FRows[I], I);
end;

end.
