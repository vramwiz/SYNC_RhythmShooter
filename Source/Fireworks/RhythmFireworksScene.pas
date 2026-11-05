unit RhythmFireworksScene;
// ゴール時刻からの経過秒だけで再現できる共通の花火演出。
interface
uses RhythmRenderSurface;
const GoalFireworksDuration=1.48;
procedure DrawGoalFireworks(Surface:TAnimationRenderSurface;Width,Height:Integer;Age:Double);
implementation
uses System.Math,Vcl.Graphics;

procedure DrawGoalFireworks(Surface:TAnimationRenderSurface;Width,Height:Integer;Age:Double);
const
  Colors:array[0..4] of TColor=($006BCFFF,$00F1D46E,$00BF88FF,$008FF9BC,$00ABAAFF);
  CentersX:array[0..4] of Double=(0.27,0.73,0.50,0.17,0.84);
  CentersY:array[0..4] of Double=(0.27,0.29,0.17,0.38,0.38);
var I,J:Integer; S,T,U,R,LastR,A,V,X,Y,PX,PY,Alpha:Double;
begin
  if (Age<0) or (Age>=GoalFireworksDuration) then Exit;
  S:=Min(Width,Height);
  for I:=0 to High(Colors) do begin
    T:=Age-I*0.13;
    if (T<0) or (T>=0.96) then Continue;
    X:=Width*CentersX[I];
    Y:=Height*CentersY[I];
    R:=S*(0.10+0.013*(I mod 3))*(1-Exp(-4.3*T));
    U:=Max(0.0,T-0.085);
    LastR:=S*(0.10+0.013*(I mod 3))*(1-Exp(-4.3*U));
    Alpha:=Sqr(1-T/0.96);
    for J:=0 to 27 do begin
      A:=2*Pi*J/28+I*0.63;
      V:=0.78+0.22*Frac(J*0.618034+I*0.37);
      PX:=Cos(A)*V;
      PY:=Sin(A)*V;
      Surface.Line(X+LastR*PX,Y+LastR*PY+S*0.055*Sqr(U),
        X+R*PX,Y+R*PY+S*0.055*Sqr(T),Colors[I],Max(1.0,S*0.0035),Alpha);
      Surface.Circle(X+R*PX,Y+R*PY+S*0.055*Sqr(T),Max(1.0,S*0.0022),clWhite,True,1,Alpha*0.85);
    end;
    if T<0.16 then Surface.Circle(X,Y,Max(1.0,S*0.009*(1-T/0.16)),Colors[I],True,1,1-T/0.16);
  end;
end;
end.
