program RaceAlphaSmoke;
{$APPTYPE CONSOLE}
// GUI・音声再生なし。背景色が透過形状を通して正しく混ざることを確認する。
uses Winapi.Windows,System.SysUtils,System.Math,Vcl.Graphics,RhythmImageBank,RhythmRenderSurface,RhythmRaceImpact;
var Image:TBitmap;Surface:TAnimationRenderSurface;Backend,Kind,I,X,C,Expected,Checks:Integer;A,Previous:Double;Pixel:PByte;
procedure Need(V:Boolean;const S:string);begin if not V then raise Exception.Create(S);end;
begin
 Image:=nil;Surface:=nil;Checks:=0;
 try
  Previous:=1;
  for I:=0 to 650 do begin A:=RaceImpactOpacity(I/1000,0.65,0.018);Need((A>=0) and (A<=Previous),'Alpha must decrease');Previous:=A;Inc(Checks);end;
  Need(RaceImpactOpacity(0,0.65,0.018)=1,'Peak must match contact');Need(RaceImpactOpacity(-0.001,0.65,0.018)=0,'Pre-contact effect');Need(RaceImpactOpacity(0.65,0.65,0.018)=0,'Effect tail');
  Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(128,96);
  Surface:=TAnimationRenderSurface.Create(TAnimationImageBank.Create([],0));
  for Backend:=0 to 1 do begin Surface.UseD2D:=Backend=1;
   for Kind:=0 to 3 do for I:=0 to 4 do begin
    A:=I/4;Surface.BeginFrame(Image);
    Surface.FillRect(0,0,64,96,RGB(20,60,120));Surface.FillRect(64,0,128,96,RGB(100,30,60));
    case Kind of
     0:Surface.FillRect(32,24,96,72,RGB(240,180,80),A);
     1:Surface.Circle(64,48,32,RGB(240,180,80),True,1,A);
     2:Surface.Line(32,48,96,48,RGB(240,180,80),12,A);
     3:Surface.Circle(64,48,22,RGB(240,180,80),False,10,A);
    end;
    Need(Surface.EndFrame,'Surface frame');GdiFlush;
    if Backend=1 then Need(Surface.LastUsedD2D,'D2D unavailable');
    for X in [43,85] do begin Pixel:=Image.ScanLine[48];Inc(Pixel,X*4);
     C:=20;if X>64 then C:=100;Expected:=Round(C*(1-A)+240*A);Need(Abs(Pixel[2]-Expected)<=3,'True red alpha blend');
     C:=60;if X>64 then C:=30;Expected:=Round(C*(1-A)+180*A);Need(Abs(Pixel[1]-Expected)<=3,'True green alpha blend');
     C:=120;if X>64 then C:=60;Expected:=Round(C*(1-A)+80*A);Need(Abs(Pixel[0]-Expected)<=3,'True blue alpha blend');Inc(Checks);
    end;
   end;
  end;
  Writeln('Race true alpha PASS checks=',Checks,' backends=GDI,D2D peak=1 tail=0');
 except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
 Surface.Free;Image.Free;
end.
