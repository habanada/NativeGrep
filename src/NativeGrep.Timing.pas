unit NativeGrep.Timing;

interface

function GrepTimestamp: Int64;
function GrepToMicroseconds(Ticks, Frequency: Int64): Int64;

implementation

uses
  Winapi.Windows;

function GrepTimestamp: Int64;
begin
  QueryPerformanceCounter(Result);
end;

function GrepToMicroseconds(Ticks, Frequency: Int64): Int64;
begin
  if (Ticks <= 0) or (Frequency <= 0) then Exit(0);
  Result := Trunc((Ticks * 1000000.0) / Frequency);
end;

end.
