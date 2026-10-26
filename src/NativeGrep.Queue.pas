unit NativeGrep.Queue;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TBoundedQueue<T> = class
  private
    FQueue: TQueue<T>;
    FCapacity: Integer;
    FClosed: Boolean;
  public
    constructor Create(Capacity: Integer);
    destructor Destroy; override;
    function Enqueue(const Item: T; const IsCancelled: TFunc<Boolean>): Boolean;
    function Dequeue(out Item: T; const IsCancelled: TFunc<Boolean>): Boolean;
    procedure Close;
  end;

implementation

constructor TBoundedQueue<T>.Create(Capacity: Integer);
begin
  inherited Create;
  if Capacity < 1 then
    raise EArgumentOutOfRangeException.Create('Queue capacity must be positive');
  FCapacity := Capacity;
  FQueue := TQueue<T>.Create;
end;

destructor TBoundedQueue<T>.Destroy;
begin
  FQueue.Free;
  inherited;
end;

function TBoundedQueue<T>.Enqueue(const Item: T; const IsCancelled: TFunc<Boolean>): Boolean;
begin
  Result := False;
  TMonitor.Enter(Self);
  try
    while not FClosed and (FQueue.Count >= FCapacity) and not IsCancelled() do
      TMonitor.Wait(Self, 50);
    if FClosed or IsCancelled() then Exit;
    FQueue.Enqueue(Item);
    Result := True;
    TMonitor.PulseAll(Self);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TBoundedQueue<T>.Dequeue(out Item: T; const IsCancelled: TFunc<Boolean>): Boolean;
begin
  Result := False;
  Item := Default(T);
  TMonitor.Enter(Self);
  try
    while (FQueue.Count = 0) and not FClosed and not IsCancelled() do
      TMonitor.Wait(Self, 50);
    if IsCancelled() or (FQueue.Count = 0) then Exit;
    Item := FQueue.Dequeue;
    Result := True;
    TMonitor.PulseAll(Self);
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TBoundedQueue<T>.Close;
begin
  TMonitor.Enter(Self);
  try
    FClosed := True;
    TMonitor.PulseAll(Self);
  finally
    TMonitor.Exit(Self);
  end;
end;

end.
