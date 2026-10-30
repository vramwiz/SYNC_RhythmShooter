program BuildAssets;
{$APPTYPE CONSOLE}
uses System.SysUtils, RhythmAssets in '..\Source\Shooting\RhythmAssets.pas';
begin
  try
    if ParamCount<>1 then raise Exception.Create('Pass the asset output directory.');
    BuildStandardAssets(ParamStr(1));
    Writeln('Original geometric assets created: ',ParamStr(1));
  except on E:Exception do begin Writeln(E.ClassName,': ',E.Message);Halt(1);end;end;
end.
