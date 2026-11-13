unit RhythmGArt;
// Type.Gの絶対時刻フレーム合成。共通の舞台装飾と短い切替だけを担当し、ゲームは4群へ委譲する。
interface
uses RhythmRenderSurface, RhythmGPlan, RhythmAnimation;
procedure DrawTypeG(Surface: TAnimationRenderSurface; Plan: TGPlan; const Frame: TAnimationFrame);
implementation
uses System.Math, System.Types, Vcl.Graphics, RhythmGDraw, RhythmGDaily, RhythmGAnimals, RhythmGSports, RhythmGWhimsy;
const
  Backgrounds: array[0..31] of Cardinal = (
    $FFEDD1,$C5EEFF,$E9D8F8,$FFF0CD,$FDE3DC,$E5EFCC,$D4E9FF,$FFE4EF,
    $C4EFFF,$CFEEDA,$FFE4B9,$FAD8EB,$D0F0F2,$DDF3C8,$BADDF6,$E8F4C8,
    $DAE7FC,$FFEDC4,$FADBCF,$F8DDF0,$D5EFFF,$DBEFCE,$FFDECF,$D6F2F3,
    $D1EBF0,$E5D8FF,$EBDDF7,$E1D6FA,$FCE0ED,$F9E6BF,$D4ECFD,$F7E7CB);
  Accents: array[0..31] of Cardinal = (
    $F1757C,$F6A861,$B385D3,$EE9855,$EF827E,$EBB951,$F09181,$F48CB0,
    $F4AC50,$E9AB76,$EBA471,$E685AD,$F18D71,$F6BD53,$A98CDB,$ECAD58,
    $EA8C7D,$EE907E,$F18079,$DB81B6,$EFA46B,$E38D8B,$EB927A,$ECBD66,
    $F4BE5F,$B1D780,$ECB466,$EBAE71,$F19AB9,$ECAF5C,$EE9A75,$EEAA65);
  Seconds: array[0..7] of Cardinal = ($65BDB5,$76B3DB,$8BA5D5,$80BFA0,$8D9DD4,$A494D1,$75BEAF,$A797D4);

procedure Backdrop(var D: TGDraw; const Frame: TAnimationFrame);
var I,J: Integer; X,Y,R: Double;
begin
  D.Surface.FillRect(0,0,Frame.Width,Frame.Height,D.Paper);
  // 図案の動きは拍だけに同期させ、導入・無音区間でも舞台に呼吸を残す。
  case D.Game mod 5 of
    0:for I:=-3 to 12 do begin
      X:=I*120+Frac(D.T/D.Beat*0.08)*120;
      D.Quad(X-100,-500,X-65,-500,X+450,1200,X+415,1200,clWhite);
    end;
    1:for I:=0 to 8 do for J:=0 to 5 do
      D.Disc(60+I*120,50+J*125,8+D.Pulse*3,clWhite,False);
    2:for I:=0 to 10 do begin
      X:=70+I*90; Y:=110+Sin(D.T/D.Beat*Pi+I)*17;
      D.Star(X,Y,13+D.Pulse*4,D.T*0.15,D.Secondary);
    end;
    3:for I:=0 to 6 do begin
      X:=100+I*140; Y:=110+I mod 2*80;
      D.Cloud(X,Y,28+D.Pulse*2,clWhite);
    end;
    4:for I:=0 to 9 do begin
      X:=I*130-60; Y:=120;
      D.Quad(X,Y,X+65,Y+140,X+130,Y,X,Y,D.Secondary);
    end;
  end;
  // 構図の端の細い枠。主役と衝突しない領域に置く。
  D.Rect(55,655,890,4,D.Secondary,False);
  if D.Local<D.Beat*2 then begin
    R:=Frac(D.Local/D.Beat); for I:=0 to 3 do begin
      X:=440+I*40; D.Disc(X,635,7+Ord(I=Trunc(D.Local/D.Beat) mod 4)*(1-R)*6,D.Accent,False);
    end;
  end;
end;

procedure Transition(var D: TGDraw; P: TGPlan; const S: TGScene; const Frame: TAnimationFrame);
var U,R,A,X,Y: Double; I: Integer;
begin
  if not P.Transitions or (S.Start=0) then Exit;
  U:=GSmooth(D.Local/Min(0.32,D.Beat*0.65)); if U>=1 then Exit;
  case S.Transition of
    0:Exit;
    1: D.Surface.FillRect(Frame.Width*U,0,Frame.Width,Frame.Height,D.Accent);
    2: D.Surface.Circle(Frame.Width/2,Frame.Height/2,Hypot(Frame.Width,Frame.Height)*(1-U),D.Secondary,True);
    3: D.Surface.FillRect(0,0,Frame.Width,Frame.Height,clWhite,1-U);
    4:begin
      D.Surface.FillRect(0,0,Frame.Width,Frame.Height*(1-U)/2,D.Accent);
      D.Surface.FillRect(0,Frame.Height*(1+U)/2,Frame.Width,Frame.Height,D.Secondary);
    end;
    5:begin
      R:=Hypot(Frame.Width,Frame.Height)*(1-U)*1.2; A:=U*Pi/2;
      for I:=0 to 3 do begin
        X:=Frame.Width/2; Y:=Frame.Height/2;
        D.Surface.FillQuad(PointF(X,Y),PointF(X+Cos(A+I*Pi/2)*R,Y+Sin(A+I*Pi/2)*R),
          PointF(X+Cos(A+(I+1)*Pi/2)*R,Y+Sin(A+(I+1)*Pi/2)*R),PointF(X,Y),D.Accent);
      end;
    end;
  end;
end;

procedure DrawTypeG(Surface: TAnimationRenderSurface; Plan: TGPlan; const Frame: TAnimationFrame);
var D: TGDraw; S: TGScene; C: TGCue; I,J: Integer; Time: Double;
begin
  if (Plan=nil) or (Length(Plan.Scenes)=0) then Exit;
  Time:=EnsureRange(Frame.Time,0.0,Plan.Duration); I:=Plan.SceneAt(Time); S:=Plan.Scenes[I];
  D:=Default(TGDraw); D.Surface:=Surface; D.K:=Min(Frame.Width/1000,Frame.Height/700);
  D.OX:=(Frame.Width-D.K*1000)/2; D.OY:=(Frame.Height-D.K*700)/2;
  D.T:=Time; D.Local:=Time-S.Start; D.Beat:=Plan.Beat; D.Game:=S.Game; D.CueIndex:=-1;
  D.Sway:=Sin((Time-Plan.Origin)/Plan.Beat*Pi*2);
  D.Pulse:=(1+Cos((Time-Plan.Origin)/Plan.Beat*Pi*2))/2;
  D.Progress:=(Time-S.Start)/(S.Finish-S.Start); D.Ending:=GSmooth((Time-S.ActionEnd)/(S.Finish-S.ActionEnd));
  D.Ink:=GColor($25344D); D.Paper:=GColor(Backgrounds[S.Game]); D.Accent:=GColor(Accents[S.Game]);
  D.Secondary:=GColor(Seconds[(S.Game*3+S.Game div 8) mod 8]); D.BackgroundOnly:=Frame.BackgroundOnly;
  J:=Plan.CueAt(Time);
  if (J<High(Plan.Cues)) and (Plan.Cues[J+1].Scene=I) and
    (Time>=Plan.Cues[J+1].Time-Plan.Cues[J+1].Lead) then Inc(J);
  if (J>=0) and (J<Length(Plan.Cues)) then begin
    C:=Plan.Cues[J];
    if (C.Scene=I) and (Time>=C.Time-C.Lead) and (Time<=C.Time+C.Recover) then begin
      D.HasCue:=True; D.Active:=True; D.CueIndex:=J; D.Age:=Time-C.Time; D.Action:=C.Action;
      D.Wind:=GSmooth((Time-C.Time+C.Lead)/C.Lead);
      D.Resolved:=Time>=C.Time; D.After:=EnsureRange((Time-C.Time)/C.Recover,0.0,1.0);
      if D.Resolved then D.Hit:=Sqr(1-D.After);
    end;
  end;
  Backdrop(D,Frame);
  if not Frame.BackgroundOnly then begin
    case S.Game div 8 of
      0: DrawGDaily(D); 1: DrawGAnimals(D); 2: DrawGSports(D); 3: DrawGWhimsy(D);
    end;
    if Surface.Images.ImageCount>=32 then Surface.DrawAsset(S.Game,
      Point(Round(D.OX+500*D.K),Round(D.OY+49*D.K)),Round(620*D.K),Round(65*D.K));
  end;
  Transition(D,Plan,S,Frame);
end;
end.
