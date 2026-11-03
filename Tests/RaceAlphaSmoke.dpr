program RaceAlphaSmoke;
{$APPTYPE CONSOLE}
// GUI・音声再生なし。背景色が透過形状を通して正しく混ざることを確認する。
uses Winapi.Windows,System.SysUtils,System.Math,System.Types,Vcl.Graphics,RhythmImageBank,RhythmRenderSurface,RhythmRaceImpact;
var Image:TBitmap;Surface:TAnimationRenderSurface;Backend,Kind,I,X,C,Expected,Checks:Integer;A,Previous:Double;Pixel:PByte;
procedure Need(V:Boolean;const S:string);begin if not V then raise Exception.Create(S);end;
// 近接サイズの斜面を、境界外へ塗らず内部に線状の穴を作らずに埋める。
procedure CheckSolidFaces;
var V:array[0..3] of TPointF;Backend,X,Y,J,Next,FaceChecks:Integer;
  Cross,Margin,Length:Double;Inside:Boolean;Pixel:PByte;
begin
 V[0]:=TPointF.Create(80,80);V[1]:=TPointF.Create(380,140);
 V[2]:=TPointF.Create(560,720);V[3]:=TPointF.Create(180,660);FaceChecks:=0;
 Image.SetSize(640,800);
 try
  for Backend:=0 to 1 do begin
   Surface.UseD2D:=Backend=1;Surface.BeginFrame(Image);
   Surface.FillQuad(V[0],V[1],V[2],V[3],RGB(120,180,205));
   Need(Surface.EndFrame,'Solid face frame');GdiFlush;
   if Backend=1 then Need(Surface.LastUsedD2D,'Solid face D2D');
   for Y:=0 to 799 do begin Pixel:=Image.ScanLine[Y];
    for X:=0 to 639 do begin Inside:=True;Margin:=1E30;
     for J:=0 to 3 do begin Next:=(J+1) mod 4;
      Cross:=(V[Next].X-V[J].X)*(Y+0.5-V[J].Y)-(V[Next].Y-V[J].Y)*(X+0.5-V[J].X);
      if Cross<0 then Inside:=False;
      Length:=Hypot(V[Next].X-V[J].X,V[Next].Y-V[J].Y);Margin:=Min(Margin,Abs(Cross)/Length);
     end;
     if Margin>2 then begin
      if Inside then Need((Pixel[2]=120) and (Pixel[1]=180) and (Pixel[0]=205),'Line or gap inside solid face')
      else Need((Pixel[2]=7) and (Pixel[1]=13) and (Pixel[0]=29),'Stroke escaped solid face');
      Inc(FaceChecks);
     end;
     Inc(Pixel,4);
    end;
   end;
  end;
  Writeln('Solid face coverage PASS pixels=',FaceChecks,' backends=GDI,D2D');
 finally Image.SetSize(128,96);end;
end;
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
  CheckSolidFaces;
 except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);ExitCode:=1;end;end;
 Surface.Free;Image.Free;
end.
