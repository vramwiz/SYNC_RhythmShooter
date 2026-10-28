program DesignImageEdges;
{$APPTYPE CONSOLE}
{$POINTERMATH ON}
uses System.SysUtils,System.IOUtils,System.Types,System.Hash,System.JSON,Vcl.Graphics,
  RhythmPaths,RhythmDesignTypes,RhythmDesignImages;
var Source,Decoded:TBitmap;X,Y,Fringe,Transparent:Integer;P:PByte;Path,Before,ErrorText:string;Design:TRhythmDesign;Root:TJSONObject;
begin
  Source:=nil;Decoded:=nil;Root:=TJSONObject.Create;
  try
    try
      Path:=TPath.Combine(ModuleFolder,'Verification\Design\colorkey-input.bmp');
      Source:=TBitmap.Create;Source.PixelFormat:=pf24bit;Source.SetSize(55,37);Source.Canvas.Brush.Color:=clFuchsia;Source.Canvas.FillRect(Rect(0,0,55,37));
      Source.Canvas.Brush.Color:=clLime;Source.Canvas.FillRect(Rect(12,9,43,28));Source.SaveToFile(Path);Before:=THashSHA2.GetHashStringFromFile(Path);
      Design:=ImportDesignImage(Path,6);Decoded:=ReadDesignBitmap(ResolveDesignImage(Design));Fringe:=0;Transparent:=0;
      for Y:=0 to Decoded.Height-1 do begin P:=Decoded.ScanLine[Y];for X:=0 to Decoded.Width-1 do begin
        if P[3]=0 then Inc(Transparent) else if (P[0]>0) or (P[2]>0) then Inc(Fringe);Inc(P,4);
      end;end;
      Root.AddPair('fringePixels',TJSONNumber.Create(Fringe));Root.AddPair('transparentPixels',TJSONNumber.Create(Transparent));
      if Before<>THashSHA2.GetHashStringFromFile(Path) then raise Exception.Create('BMP source changed');
      if (Fringe<>0) or (Transparent=0) then raise Exception.Create('BMP color key was interpolated into the visible edge');Root.AddPair('result','passed');
    except on E:Exception do begin ErrorText:=E.Message;Root.AddPair('result','failed');Root.AddPair('error',ErrorText);end;end;
    TFile.WriteAllText(TPath.Combine(ModuleFolder,'Verification\Design\image-edges.json'),Root.ToJSON,TEncoding.UTF8);Writeln(Root.ToJSON);
  finally Root.Free;Source.Free;Decoded.Free;end;
  if ErrorText<>'' then Halt(1);
end.
