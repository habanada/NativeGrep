program NativeGrepGUI;

{$APPTYPE GUI}

uses
  System.Classes,
  Vcl.Forms,
  NimbusForms.Controls.TabControl,
  NativeGrep.GUI.Main in 'NativeGrep.GUI.Main.pas' {frmNativeGrep};


begin
  RegisterClass(TThemedTabControl);
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'NativeGrep';
  Application.CreateForm(TfrmNativeGrep, frmNativeGrep);
  Application.Run;
end.
