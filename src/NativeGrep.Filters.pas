unit NativeGrep.Filters;

interface

uses
  System.SysUtils, NativeGrep.Types;

type
  TGrepFileFilters = class sealed
  public
    class function Contains(const Range: TGrepFilterRange; Value: Int64): Boolean; static;
    class procedure Validate(const Options: TGrepOptions); static;
    class function Active(const Options: TGrepOptions): Boolean; static;
    class function ParseSize(const Value: string): Int64; static;
    class function ParseSizeRange(const Value: string): TGrepFilterRange; static;
    class function ParseTimeRange(const FromValue, ToValue: string): TGrepFilterRange; static;
    class function UtcTicks(const Value: TDateTime): Int64; static;
  end;

implementation

uses
  System.DateUtils, Winapi.Windows;

class function TGrepFileFilters.Contains(const Range: TGrepFilterRange; Value: Int64): Boolean;
begin
  Result := (not Range.HasMinimum or (Value > Range.Minimum) or
    ((Value = Range.Minimum) and not Range.MinimumExclusive)) and
    (not Range.HasMaximum or (Value < Range.Maximum) or
    ((Value = Range.Maximum) and not Range.MaximumExclusive));
end;

procedure ValidateRange(const Range: TGrepFilterRange; const Name: string);
begin
  if (Range.HasMinimum and (Range.Minimum < 0)) or
    (Range.HasMaximum and (Range.Maximum < 0)) then
    raise EArgumentException.Create(Name + ': bounds must not be negative');
  if Range.HasMinimum and Range.HasMaximum and
    ((Range.Minimum > Range.Maximum) or
    ((Range.Minimum = Range.Maximum) and (Range.MinimumExclusive or Range.MaximumExclusive))) then
    raise EArgumentException.Create(Name + ': the range is empty or reversed');
end;

class procedure TGrepFileFilters.Validate(const Options: TGrepOptions);
var
  SizeRange: TGrepFilterRange;
begin
  ValidateRange(Options.FileSizeFilter, 'File size');
  ValidateRange(Options.CreatedTimeFilter, 'Created time');
  ValidateRange(Options.ModifiedTimeFilter, 'Modified time');
  ValidateRange(Options.AccessedTimeFilter, 'Accessed time');
  if Options.MaxFileSize < 0 then raise EArgumentException.Create('MaxFileSize must not be negative');
  SizeRange := Options.FileSizeFilter;
  if (Options.MaxFileSize > 0) and
    (not SizeRange.HasMaximum or (Options.MaxFileSize < SizeRange.Maximum)) then
  begin
    SizeRange.HasMaximum := True;
    SizeRange.Maximum := Options.MaxFileSize;
    SizeRange.MaximumExclusive := False;
  end;
  ValidateRange(SizeRange, 'File size');
end;

class function TGrepFileFilters.Active(const Options: TGrepOptions): Boolean;
begin
  Result := (Options.MaxFileSize <> 0) or
    Options.FileSizeFilter.HasMinimum or Options.FileSizeFilter.HasMaximum or
    Options.CreatedTimeFilter.HasMinimum or Options.CreatedTimeFilter.HasMaximum or
    Options.ModifiedTimeFilter.HasMinimum or Options.ModifiedTimeFilter.HasMaximum or
    Options.AccessedTimeFilter.HasMinimum or Options.AccessedTimeFilter.HasMaximum;
end;

class function TGrepFileFilters.ParseSize(const Value: string): Int64;
var
  S, UnitName, Digits: string;
  I: Integer;
  Scale, Whole, Fraction, Divisor, Part: Int64;
begin
  S := Trim(Value);
  I := 1;
  while (I <= Length(S)) and CharInSet(S[I], ['0'..'9', '.']) do Inc(I);
  Digits := Copy(S, 1, I - 1);
  UnitName := UpperCase(Trim(Copy(S, I, MaxInt)));
  if (UnitName = '') or (UnitName = 'B') then Scale := 1
  else if (UnitName = 'KB') then Scale := 1000
  else if (UnitName = 'MB') then Scale := 1000000
  else if (UnitName = 'GB') then Scale := 1000000000
  else if (UnitName = 'TB') then Scale := 1000000000000
  else if (UnitName = 'KIB') or (UnitName = 'K') then Scale := 1024
  else if (UnitName = 'MIB') or (UnitName = 'M') then Scale := 1048576
  else if (UnitName = 'GIB') or (UnitName = 'G') then Scale := 1073741824
  else if (UnitName = 'TIB') or (UnitName = 'T') then Scale := 1099511627776
  else raise EArgumentException.Create('Unknown size unit: ' + Value);
  I := Pos('.', Digits);
  Fraction := 0;
  Divisor := 1;
  if I > 0 then
  begin
    S := Copy(Digits, I + 1, MaxInt);
    if (Length(S) < 1) or (Length(S) > 6) or not TryStrToInt64(S, Fraction) then
      raise EArgumentException.Create('Invalid size: ' + Value);
    for I := 1 to Length(S) do Divisor := Divisor * 10;
    Digits := Copy(Digits, 1, Pos('.', Digits) - 1);
  end;
  if (Digits = '') or not TryStrToInt64(Digits, Whole) or (Whole < 0) or
    (Whole > High(Int64) div Scale) then raise EArgumentException.Create('Invalid or oversized size: ' + Value);
  Part := Fraction * Scale;
  if Part mod Divisor <> 0 then raise EArgumentException.Create('Size must resolve to whole bytes: ' + Value);
  Part := Part div Divisor;
  Result := Whole * Scale;
  if Result > High(Int64) - Part then raise EArgumentException.Create('Size overflow: ' + Value);
  Inc(Result, Part);
end;

class function TGrepFileFilters.ParseSizeRange(const Value: string): TGrepFilterRange;
var
  S: string;
  P: Integer;
begin
  Result := Default(TGrepFilterRange);
  S := Trim(Value);
  P := Pos('..', S);
  if P > 0 then
  begin
    Result.HasMinimum := True;
    Result.HasMaximum := True;
    Result.Minimum := ParseSize(Copy(S, 1, P - 1));
    Result.Maximum := ParseSize(Copy(S, P + 2, MaxInt));
  end
  else if (S <> '') and CharInSet(S[1], ['<', '>']) then
  begin
    Result.HasMinimum := S[1] = '>';
    Result.HasMaximum := not Result.HasMinimum;
    P := 2;
    if (Length(S) >= 2) and (S[2] = '=') then Inc(P)
    else if Result.HasMinimum then Result.MinimumExclusive := True
    else Result.MaximumExclusive := True;
    if Result.HasMinimum then Result.Minimum := ParseSize(Copy(S, P, MaxInt))
    else Result.Maximum := ParseSize(Copy(S, P, MaxInt));
  end
  else
  begin
    if Copy(S, 1, 1) = '=' then Delete(S, 1, 1);
    Result.HasMinimum := True;
    Result.HasMaximum := True;
    Result.Minimum := ParseSize(S);
    Result.Maximum := Result.Minimum;
  end;
  ValidateRange(Result, 'File size');
end;

class function TGrepFileFilters.UtcTicks(const Value: TDateTime): Int64;
var
  ST: TSystemTime;
  FT: TFileTime;
begin
  DateTimeToSystemTime(Value, ST);
  if not SystemTimeToFileTime(ST, FT) then
    raise EArgumentException.Create('Time is outside the supported Windows file time range');
  Result := (Int64(FT.dwHighDateTime) shl 32) or FT.dwLowDateTime;
  if Result < 0 then raise EArgumentException.Create('Time is outside the supported range');
end;

function ParseTime(const Value: string; UpperBound: Boolean; Reference: TDateTime;
  out Exclusive: Boolean): Int64;
var
  S, Tail: string;
  D: TDateTime;
  N, FractionTicks: Int64;
  UnitChar: Char;
  DateOnly, Zoned: Boolean;
  I, FractionStart, FractionLength: Integer;
begin
  S := LowerCase(Trim(Value));
  Exclusive := False;
  DateOnly := False;
  Zoned := False;
  FractionTicks := 0;
  if (S = 'today') or (S = 'yesterday') then
  begin
    D := DateOf(TTimeZone.Local.ToLocalTime(Reference));
    if S = 'yesterday' then D := D - 1;
    DateOnly := True;
  end
  else if Copy(S, 1, 3) = 'now' then
  begin
    D := Reference;
    Zoned := True;
    if S <> 'now' then
    begin
      Tail := Copy(S, 4, MaxInt);
      if (Length(Tail) < 3) or (Tail[1] <> '-') then
        raise EArgumentException.Create('Expected now-Nh, now-Nm or now-Nd: ' + Value);
      UnitChar := Tail[Length(Tail)];
      if not TryStrToInt64(Copy(Tail, 2, Length(Tail) - 2), N) or (N < 0) or (N > 365000) then
        raise EArgumentException.Create('Invalid relative time: ' + Value);
      case UnitChar of
        'm': D := D - N / MinsPerDay;
        'h': D := D - N / HoursPerDay;
        'd': D := D - N;
      else raise EArgumentException.Create('Expected relative time unit m, h or d: ' + Value);
      end;
    end;
  end
  else
  begin
    DateOnly := Length(S) = 10;
    S := StringReplace(S, ' ', 'T', []);
    S := StringReplace(S, 't', 'T', []);
    S := StringReplace(S, 'z', 'Z', []);
    FractionStart := Pos('.', S);
    if FractionStart > 0 then
    begin
      // Parse fractional seconds separately to preserve all seven FILETIME digits.
      if (FractionStart <> 20) or (Length(S) < 21) then
        raise EArgumentException.Create('Expected fractional seconds after HH:MM:SS: ' + Value);
      I := FractionStart + 1;
      while (I <= Length(S)) and CharInSet(S[I], ['0'..'9']) do Inc(I);
      FractionLength := I - FractionStart - 1;
      if (FractionLength < 1) or (FractionLength > 7) then
        raise EArgumentException.Create('Time supports one to seven fractional second digits: ' + Value);
      Tail := Copy(S, FractionStart + 1, FractionLength);
      while Length(Tail) < 7 do Tail := Tail + '0';
      FractionTicks := StrToInt64(Tail);
      Delete(S, FractionStart, FractionLength + 1);
    end;
    Zoned := Pos('Z', S) > 0;
    for I := 11 to Length(S) do
      if CharInSet(S[I], ['+', '-']) then Zoned := True;
    if DateOnly then S := S + 'T00:00:00';
    // Keep unzoned wall time unchanged until the explicit local conversion below.
    if not Zoned then S := S + 'Z';
    if not TryISO8601ToDate(S, D, True) then
      raise EArgumentException.Create('Expected ISO date/time, today, yesterday or now-Nh/Nm/Nd: ' + Value);
  end;
  if DateOnly and UpperBound then
  begin
    D := D + 1;
    Exclusive := True;
  end;
  if not Zoned then D := TTimeZone.Local.ToUniversalTime(D);
  Result := TGrepFileFilters.UtcTicks(D) + FractionTicks;
end;

class function TGrepFileFilters.ParseTimeRange(const FromValue, ToValue: string): TGrepFilterRange;
var
  Reference: TDateTime;
  ST: TSystemTime;
begin
  Result := Default(TGrepFilterRange);
  GetSystemTime(ST);
  Reference := SystemTimeToDateTime(ST);
  Result.HasMinimum := Trim(FromValue) <> '';
  Result.HasMaximum := Trim(ToValue) <> '';
  try
    if Result.HasMinimum then Result.Minimum := ParseTime(FromValue, False, Reference, Result.MinimumExclusive);
    if Result.HasMaximum then Result.Maximum := ParseTime(ToValue, True, Reference, Result.MaximumExclusive);
  except
    on E: EConvertError do raise EArgumentException.Create('Invalid time filter: ' + E.Message);
    on E: ELocalTimeInvalid do raise EArgumentException.Create('Invalid local time filter: ' + E.Message);
  end;
  ValidateRange(Result, 'Time');
end;

end.
