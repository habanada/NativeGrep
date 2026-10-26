{
   NativePattern Library  |  © 2026 Selahattin Erkoc
   Licensed under MIT License  |  https://opensource.org/licenses/MIT
}
unit NativePattern.Avx2;

{$POINTERMATH ON}

interface

uses
  System.SysUtils,
  NativePattern.Core;

type
  TAvx2Searcher = class(TSinglePatternSearcher)
  private
    class function CpuSupported: Boolean; static;
  protected
    function DoFindFirst(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch; override;
  public
    constructor Create(const Pattern: TBytes); overload;
    constructor Create(const Pattern: string); overload;
    class function Available: Boolean; static;
  end;

implementation

{$IF Defined(MSWINDOWS)}
uses
  Winapi.Windows;
{$ENDIF}

{$IF Defined(MSWINDOWS) and Defined(CPUX64)}
function FindByteAvx2(Buffer: PByte; Count: NativeUInt; Value: Byte): NativeInt; assembler;
asm
  .NOFRAME
  test rdx, rdx
  jz @NotFound
  mov r9, rcx
  cmp rdx, 32
  jb @Tail
  movd xmm0, r8d
  vpbroadcastb ymm0, xmm0
@VectorLoop:
  cmp rdx, 32
  jb @VectorTail
  vmovdqu ymm1, yword ptr [rcx]
  vpcmpeqb ymm1, ymm1, ymm0
  vpmovmskb eax, ymm1
  test eax, eax
  jnz @VectorFound
  add rcx, 32
  sub rdx, 32
  jmp @VectorLoop
@VectorFound:
  bsf eax, eax
  mov r10, rcx
  sub r10, r9
  add rax, r10
  vzeroupper
  ret
@VectorTail:
  vzeroupper
@Tail:
  test rdx, rdx
  jz @NotFound
@TailLoop:
  cmp byte ptr [rcx], r8b
  je @TailFound
  inc rcx
  dec rdx
  jnz @TailLoop
@NotFound:
  mov rax, -1
  ret
@TailFound:
  mov rax, rcx
  sub rax, r9
end;
{$ENDIF}

constructor TAvx2Searcher.Create(const Pattern: TBytes);
begin
  if not Available then
    raise ENotSupportedException.Create('AVX2 is not available on this platform or processor');
  inherited Create(Pattern);
end;

constructor TAvx2Searcher.Create(const Pattern: string);
begin
  if not Available then
    raise ENotSupportedException.Create('AVX2 is not available on this platform or processor');
  inherited Create(Pattern);
end;

class function TAvx2Searcher.CpuSupported: Boolean;
const
  PF_AVX2_INSTRUCTIONS_AVAILABLE = 40;
begin
{$IF Defined(MSWINDOWS) and Defined(CPUX64)}
  Result := IsProcessorFeaturePresent(PF_AVX2_INSTRUCTIONS_AVAILABLE);
{$ELSE}
  Result := False;
{$ENDIF}
end;

class function TAvx2Searcher.Available: Boolean;
begin
  Result := CpuSupported;
end;

function TAvx2Searcher.DoFindFirst(Buffer: PByte; BufferSize, StartOffset: NativeUInt): TPatternMatch;
var
  CandidateCount, PatternLength, Position: NativeUInt;
  Relative: NativeInt;
begin
  Result := TPatternMatch.NotFound;
  PatternLength := Length(PatternBytes);
  if (Buffer = nil) or (PatternLength = 0) or (StartOffset > BufferSize) or (PatternLength > BufferSize - StartOffset) then
    Exit;
  Position := StartOffset;
  while Position <= BufferSize - PatternLength do
  begin
    CandidateCount := BufferSize - PatternLength - Position + 1;
{$IF Defined(MSWINDOWS) and Defined(CPUX64)}
    Relative := FindByteAvx2(Buffer + Position, CandidateCount, PatternBytes[0]);
{$ELSE}
    Relative := -1;
{$ENDIF}
    if Relative < 0 then
      Exit;
    Inc(Position, NativeUInt(Relative));
    if (PatternLength = 1) or CompareMem(Buffer + Position, @PatternBytes[0], PatternLength) then
    begin
      Result.Offset := Position;
      Result.MatchLength := PatternLength;
      Result.PatternIndex := 0;
      Result.Distance := 0;
      Result.MatchUnit := muByte;
      Exit;
    end;
    Inc(Position);
  end;
end;

end.
