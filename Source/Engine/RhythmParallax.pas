unit RhythmParallax;
interface
uses Vcl.Graphics,RhythmImageBank,RhythmD2D;
procedure DrawParallax(Canvas:TCanvas;Images:TAnimationImageBank;FD2D:TRhythmD2D;FD2DActive:Boolean;
  Time:Double;Width,Height,Direction:Integer;OnlyLayer:Integer=-1;
  ForceStandard:Boolean=False;ClearTarget:Boolean=True);
implementation
uses System.Types,System.Math,Winapi.Windows;
procedure DrawParallax(Canvas:TCanvas;Images:TAnimationImageBank;FD2D:TRhythmD2D;FD2DActive:Boolean;
  Time:Double;Width,Height,Direction,OnlyLayer:Integer;ForceStandard,ClearTarget:Boolean);
const Speeds:array[0..2] of Double=(30,110,260);
  Density:array[0..2] of Double=(0.00013,0.000075,0.000020);
  Sizes:array[0..2] of Double=(0.65,1.8,3.4);
  Trails:array[0..2] of Double=(0,6,18);
var Layer,I,Count,Index,Tile,Offset,TX,TY:Integer;Seed:UInt64;Across,Along,Period,Span,Position,X,Y,Radius,Scale,Trail:Double;
  function RandomUnit:Double;
  begin Seed:=(Seed*48271) mod 2147483647;Result:=Seed/2147483647;end;
begin
  if ClearTarget and not FD2DActive then begin Canvas.Brush.Color:=RGB(7,13,29);Canvas.FillRect(Rect(0,0,Width,Height));end;
  // A long torus has no small repeated tile or per-cell regularity. Each layer
  // has its own fixed seed, density, point size, brightness and travel speed.
  if Direction=0 then begin Span:=Width;Period:=Max(Height,1080)*5;end
  else begin Span:=Height;Period:=Max(Width,1920)*5;end;
  Scale:=Min(Width,Height)/720;
  for Layer:=0 to 2 do
  begin
    if (OnlyLayer>=0) and (Layer<>OnlyLayer) then Continue;
    Index:=Direction*3+Layer;
    if not ForceStandard and Images.IsCustom[Index] then begin
      Tile:=Max(1,Round(1024*Scale));Offset:=Round(Time*Speeds[Layer]*Scale) mod Tile;
      if Direction=0 then begin TY:=Offset-Tile;while TY<Height do begin TX:=0;while TX<Width do begin
        if FD2DActive then FD2D.DrawAsset(Index,Rect(TX,TY,TX+Tile,TY+Tile)) else Canvas.StretchDraw(Rect(TX,TY,TX+Tile,TY+Tile),Images.Image[Index]);Inc(TX,Tile);
      end;Inc(TY,Tile);end;end
      else begin TX:=-Offset;while TX<Width do begin TY:=0;while TY<Height do begin
        if FD2DActive then FD2D.DrawAsset(Index,Rect(TX,TY,TX+Tile,TY+Tile)) else Canvas.StretchDraw(Rect(TX,TY,TX+Tile,TY+Tile),Images.Image[Index]);Inc(TY,Tile);
      end;Inc(TX,Tile);end;end;Continue;
    end;
    Seed:=7919+Layer*104729;Count:=Round(Span*Period*Density[Layer]);
    Radius:=Sizes[Layer]*Max(0.8,Scale);Trail:=Trails[Layer]*Scale;
    if not FD2DActive then begin Canvas.Pen.Style:=psClear;Canvas.Brush.Color:=RGB(42+Layer*25,62+Layer*35,88+Layer*44);end;
    for I:=0 to Count-1 do
    begin
      Across:=RandomUnit*Span;Along:=RandomUnit*Period;
      Position:=Along+Time*Speeds[Layer]*Scale;Position:=Position-Floor(Position/Period)*Period;
      if Direction=0 then begin X:=Across;Y:=Position;end else begin X:=Width-Position;Y:=Across;end;
      if (X< -Radius) or (X>Width+Radius) or (Y< -Radius) or (Y>Height+Radius) then Continue;
      if FD2DActive then FD2D.Star(X,Y,Radius,Trail,Layer,Direction)
      else begin
        if Trail>0 then begin
          Canvas.Pen.Style:=psSolid;Canvas.Pen.Color:=RGB(30,50,77);Canvas.Pen.Width:=Max(1,Round(Radius*0.48));Canvas.MoveTo(Round(X),Round(Y));
          if Direction=0 then Canvas.LineTo(Round(X),Round(Y-Trail)) else Canvas.LineTo(Round(X+Trail),Round(Y));
          Canvas.Pen.Width:=1;Canvas.Pen.Style:=psClear;
        end;
        Canvas.Ellipse(Floor(X-Radius),Floor(Y-Radius),Ceil(X+Radius),Ceil(Y+Radius));
      end;
    end;
  end;
  if not FD2DActive then Canvas.Pen.Style:=psSolid;
end;
end.
