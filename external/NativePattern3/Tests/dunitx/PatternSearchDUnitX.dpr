program PatternSearchDUnitX;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  NativePattern.Tests in 'NativePattern.Tests.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
  Logger: ITestLogger;
  NUnitLogger: ITestLogger;
  OutputFile, OutputDir: string;
begin
  ReportMemoryLeaksOnShutdown := True;
  try
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := True;
    Logger := TDUnitXConsoleLogger.Create(False);
    Runner.AddLogger(Logger);
    OutputFile := GetEnvironmentVariable('NATIVEPE_DUNITX_XML');
    if OutputFile = '' then
      OutputFile := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'PatternSearchDUnitX-results.xml';
    OutputDir := ExtractFileDir(OutputFile);
    if OutputDir <> '' then
      ForceDirectories(OutputDir);
    NUnitLogger := TDUnitXXMLNUnitFileLogger.Create(OutputFile);
    Runner.AddLogger(NUnitLogger);
    Results := Runner.Execute;
    if not Results.AllPassed then
      System.ExitCode := EXIT_ERRORS;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      System.ExitCode := EXIT_ERRORS;
    end;
  end;
end.
