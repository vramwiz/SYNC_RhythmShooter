program MineCartSmoke;
{$APPTYPE CONSOLE}
// 曲全体の接触・走行・連結ボスと保存後の描画を確認する。
uses System.SysUtils,System.Math,System.Types,System.Classes,System.IOUtils,System.Hash,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmAudioCache,RhythmCartPlan,RhythmCartBuild,
  RhythmCartCodec,RhythmStyles,RhythmPlanRef,RhythmSettings,RhythmStyleOps,RhythmStyleRegistry,RhythmScene,
  RhythmFireworksScene;

var Checks:Integer;

procedure Need(Valid:Boolean;const Description:string);
begin
  if not Valid then raise Exception.Create(Description);
  Inc(Checks);
end;

function Fixture(const Source:string):TRhythmAudio;
const Gaps:array[0..7] of Double=(0.44,0.075,0.21,0.042,0.58,0.11,0.31,0.046);
var I,N:Integer; T:Double;
begin
  TFile.WriteAllText(Source,'Mine cart synthetic accents.',TEncoding.UTF8);
  Result:=TRhythmAudio.Create;
  Result.Source:=Source;
  Result.SourceRevision:=AudioSourceStamp(Source);
  Result.Key:=THashSHA2.GetHashStringFromFile(Source);
  Result.Sensitivity:=50;
  Result.Duration:=180;
  Result.SetBossFrequency(100);
  SetLength(Result.Envelope,18000);
  for I:=0 to High(Result.Envelope) do
    Result.Envelope[I]:=0.09+0.089*((I div 950) mod 8)+0.08*Sqr(Sin(I*0.048));
  Result.UpdateSoundBounds;
  SetLength(Result.Hits,10000);
  T:=0.32;
  N:=0;
  while T<179.42 do begin
    Result.Hits[N].Time:=T;
    Result.Hits[N].Strength:=0.24+0.10*(N mod 7);
    Inc(N);
    T:=T+Gaps[Trunc(T/11.25) mod Length(Gaps)]*(0.91+0.044*(N mod 5));
  end;
  SetLength(Result.Hits,N);
end;

procedure VerifyChase(Plan:TCartPlan;Audio:TRhythmAudio);
var I,J,K,Cars,PreviousShots:Integer; B:TCartBoss; M:TCartMove; Shot:TCartBossShot;
  P,Q:TCartPosition; Rider:TPointF;
begin
  for I:=0 to High(Plan.Bosses) do begin
    B:=Plan.Bosses[I];
    Cars:=B.LastMove-B.FirstMove+1;
    Need(Cars=I+2,'Convoy did not grow by one');
    PreviousShots:=0;
    for J:=B.FirstMove to B.LastMove do begin
      M:=Plan.Moves[J];
      Need(M.Kind=cmBossBump,'Legacy stomp used for boss');
      Need(Audio.Hits[Audio.NearestHit(M.Hit)].Time=M.Hit,'Convoy accent moved');
      P:=Plan.Cart(M.Hit);
      Q:=Plan.ChaseCar(I,J,M.Hit);
      Need((Abs(Q.X-P.X-CartChaseContact)<1E-7) and (CartJump(M,M.Hit)=0),'Cart did not ram on the rail');
      Q:=Plan.ChaseCar(I,J,M.Hit-0.45);
      Need(Q.X-Plan.Cart(M.Hit-0.45).X>CartChaseContact,'Convoy did not close in');
      K:=Plan.ChaseShotCount(I,J);
      Need((K>0) and (K>=PreviousShots) and ((PreviousShots>=4) or (K>PreviousShots)),'Boss attacks did not escalate');
      PreviousShots:=K;
      Shot:=Plan.ChaseShot(I,J,K-1);
      Need((Shot.Origin.X>Shot.Target.X) and (Plan.Cart(Shot.CrossTime).Y>Shot.Target.Y+0.5),'Boss shot missed its dodge');
    end;
  end;
  P:=Plan.Track(Plan.Goal);
  Rider:=Plan.FinishRider(Plan.Goal+CartFinishLanding);
  Need((Rider.X>P.X+CartFinishLedge) and (Abs(Rider.Y-(P.Y-CartFinishDrop))<0.00001),'Rider missed goal ground');
  Rider:=Plan.FinishRider(Plan.Goal+0.24);
  Need(Rider.Y>P.Y+0.70,'Rider did not jump from cart');
end;

procedure Verify(Plan:TCartPlan;Audio:TRhythmAudio);
var I,J,AirCoins,ClosePairs:Integer;
  P,Q:TCartPosition;
  Wing,Bomb:TPointF;
  C:TCartCoin;
  M:TCartMove;
  T,Fastest,Slowest,BeforeX:Double;
  Kinds:set of TCartMoveKind;
  Themes:set of 0..4;
begin
  Need(Length(Plan.Coins)=Length(Audio.Hits),'Source accent was dropped');
  AirCoins:=0;
  ClosePairs:=0;
  for I:=0 to High(Plan.Coins) do begin
    C:=Plan.Coins[I];
    Need(C.Time=Audio.Hits[I].Time,'Source accent moved');
    P:=Plan.Cart(C.Time);
    Need((Abs(C.X-P.X-CartCoinAhead)<0.0001) and (Abs(C.Y-P.Y-CartCoinHeight)<0.0001),'Coin misses socket');
    J:=Plan.MoveAt(C.Time);
    if (J>=0) and (CartJump(Plan.Moves[J],C.Time)>0.13) then Inc(AirCoins);
    if (I>0) and (C.Time-Plan.Coins[I-1].Time<0.06) then Inc(ClosePairs);
  end;
  Need((AirCoins>70) and (ClosePairs>60),'Dense and airborne coin coverage');
  Slowest:=1E9;
  Fastest:=0;
  BeforeX:=-1;
  for I:=0 to Floor(Plan.Goal*60) do begin
    T:=I/60;
    P:=Plan.Cart(T);
    Q:=Plan.Rail(T,T);
    Need(P.X>BeforeX,'Cart stopped or moved backward');
    if Plan.GapAt(T) then Need(P.Y-Q.Y>0.20,'Cart crossed a gap without clearance');
    BeforeX:=P.X;
    Slowest:=Min(Slowest,P.Speed);
    Fastest:=Max(Fastest,P.Speed);
  end;
  Need(Fastest>Slowest*1.65,'Slopes do not alter speed enough');
  Kinds:=[];
  for M in Plan.Moves do begin
    Include(Kinds,M.Kind);
    Need(Abs(Plan.Cart(M.Finish).Y-Plan.Rail(M.Finish,M.Finish).Y)<1E-8,'Landing missed rail');
    if M.Kind in [cmStomp,cmBoss] then
      Need(Abs(Plan.Cart(M.Hit).Y-Plan.StompTop(M))<1E-8,'Stomp timing');
    case M.Kind of
      cmStomp:begin
        Wing:=Plan.WingTop(M,M.Hit-0.20);
        Need(Wing.X>Plan.WingTop(M,M.Hit).X,'Wing enemy did not fly in from the right');
        Wing:=Plan.WingTop(M,M.Hit);
        P:=Plan.Cart(M.Hit);
        Need((Abs(Wing.X-P.X)<0.001) and (Abs(Wing.Y-P.Y)<0.001),'Wing contact missed cart');
      end;
      cmRam:begin
        P:=Plan.RamPosition(M,M.Hit-0.20);
        Q:=Plan.RamPosition(M,M.Hit+0.20);
        Need((P.X>Plan.Cart(M.Hit).X) and (Q.X<Plan.Cart(M.Hit).X),'Ram did not cross from right to left');
        Q:=Plan.RamPosition(M,M.Hit);
        Need(Abs(Q.Y-Plan.Rail(M.Hit,M.Hit).Y)<0.001,'Ram is off the shared rail');
      end;
      cmRival:begin
        Bomb:=Plan.ThrowBomb(M,M.Hit-CartThrowLead);
        P:=Plan.Cart(M.Hit-CartThrowLead);
        Need(Bomb.X<P.X-2,'Bomb did not come from the left');
        Bomb:=Plan.ThrowBomb(M,M.Hit);
        P:=Plan.Cart(M.Hit);
        Need((Abs(Bomb.X-P.X)<0.001) and (Bomb.Y>P.Y+1.10),'Bomb missed its timed overhead pass');
      end;
      cmFireJet,cmBlocker,cmRockfall:begin
        P:=Plan.Track(M.Hit);
        Q:=Plan.Cart(M.Hit);
        Need(Q.Y>P.Y+Plan.ObstacleHeight(M,M.Hit)+0.11,'Track obstacle overlaps cart');
        if M.Kind=cmFireJet then begin
          J:=Plan.CoinFrom(M.Start);
          while (J<Length(Plan.Coins)) and (Plan.Coins[J].Time<=M.Finish) do begin
            C:=Plan.Coins[J];
            if Abs(C.X-P.X)<CartObstacleHalfWidth(M.Kind)+0.24 then
              Need(C.Y>P.Y+CartFireHeight+0.32,'Flame overlaps coin');
            Inc(J);
          end;
        end;
        if M.Kind=cmRockfall then
          Need(Plan.ObstacleHeight(M,M.Hit-0.90)>Plan.ObstacleHeight(M,M.Hit)+2.0,'Boulder never falls');
      end;
    end;
  end;
  Need(Kinds=[Low(TCartMoveKind)..High(TCartMoveKind)]-[cmBoss,cmFlame],'Missing gimmick');
  Themes:=[];
  for I:=0 to High(Plan.Knots) do Include(Themes,Plan.Knots[I].Theme);
  Need(Themes=[0..4],'Missing backdrop');
  Need(Length(Plan.Bosses)>=3,'Missing long-course convoys');
  VerifyChase(Plan,Audio);
  WriteLn(Format('%.0fs, %d coins (%d airborne, %d close pairs), %d events, %d convoys, speed %.2f to %.2f',
    [Plan.Duration,Length(Plan.Coins),AirCoins,ClosePairs,Length(Plan.Moves),Length(Plan.Bosses),Slowest,Fastest]));
end;

function FrameHash(Image:TBitmap):string;
var Stream:TMemoryStream; Bytes:TBytes; Hash:THashSHA2;
begin
  Stream:=TMemoryStream.Create;
  try
    Image.SaveToStream(Stream);
    SetLength(Bytes,Stream.Size);
    Stream.Position:=0;
    Stream.ReadBuffer(Bytes[0],Length(Bytes));
    Hash:=THashSHA2.Create;
    Hash.Update(Bytes[0],Length(Bytes));
    Result:=Hash.HashAsString;
  finally
    Stream.Free;
  end;
end;

procedure RenderProof(Plan:TCartPlan;Audio,Cold:TRhythmAudio;const Ref:TRhythmPlanRef;const Folder:string;Short:Boolean=False);
var R:TRhythmRenderer; Image:TBitmap; PNG:TPngImage; M:TCartMove; B:TCartBoss; Seen:set of TCartMoveKind;

  procedure Snapshot(const Name:string;Time:Double);
  var Hash:string;
  begin
    R.Render(Image,Audio,Time,0);
    Hash:=FrameHash(Image);
    PNG.Assign(Image);
    PNG.SaveToFile(TPath.Combine(Folder,Name+'.png'));
    R.Render(Image,Cold,Plan.Goal-Time,0);
    R.Render(Image,Cold,Time+0.25,0,'',1,0,0,0.25);
    Need(FrameHash(Image)=Hash,'Cold restore or seek changed pixels');
  end;

begin
  R:=TRhythmRenderer.Create;
  Image:=TBitmap.Create;
  PNG:=TPngImage.Create;
  try
    R.ConfigureStyle(rsMineCart,Ref,Audio.BossFrequency);
    Image.PixelFormat:=pf32bit;
    Image.SetSize(960,540);
    if not Short then begin
      Snapshot('start',0.6);
      Seen:=[];
      for M in Plan.Moves do
        if not (M.Kind in Seen) then begin
          Snapshot('event-'+IntToStr(Ord(M.Kind)),M.Hit-0.10);
          if M.Kind=cmRockfall then Snapshot('falling-rock',M.Hit-0.64);
          Include(Seen,M.Kind);
        end;
    end;
    B:=Plan.Bosses[High(Plan.Bosses)];
    M:=Plan.Moves[B.FirstMove];
    Snapshot('convoy-entry',M.Start-0.24);
    Snapshot('boss-dodge',M.Start+0.42);
    Snapshot('boss-bomb-blast',Plan.ChaseShot(High(Plan.Bosses),B.FirstMove,0).CrossTime+0.15);
    Snapshot('boss-first-ram',M.Hit+0.065);
    M:=Plan.Moves[B.LastMove];
    Snapshot('boss-final-dodge',M.Start+0.37);
    Snapshot('boss-finish',M.Hit+0.28);
    Snapshot('goal-jump',Plan.Goal+0.30);
    Snapshot('goal-landing',Plan.Goal+CartFinishLanding-0.002);
    Snapshot('goal-fireworks',Plan.Goal+CartFinishLanding+0.62);
  finally
    PNG.Free;
    Image.Free;
    R.Free;
  end;
end;

procedure VerifyShort(const Folder:string);
var Audio,Cold:TRhythmAudio; Plan:TCartPlan; I:Integer; Source:string; Ref:TRhythmPlanRef;
begin
  Audio:=TRhythmAudio.Create;
  try
    Audio.Duration:=0.18;
    Audio.SoundEnd:=0;
    Plan:=BuildCartPlan(Audio,nil);
    try
      Need((Length(Plan.Moves)=0) and (Length(Plan.Coins)=0) and (Plan.Cart(0.18).X>0),'Short silent route');
    finally
      Plan.Free;
    end;
    Source:=TPath.Combine(Folder,'short.identity');
    TFile.WriteAllText(Source,'Short mine cart rhythm',TEncoding.UTF8);
    Audio.Source:=Source;
    Audio.SourceRevision:=AudioSourceStamp(Source);
    Audio.Key:=THashSHA2.GetHashStringFromFile(Source);
    Audio.Sensitivity:=50;
    Audio.Duration:=6.4;
    Audio.SoundEnd:=6.4;
    SetLength(Audio.Hits,27);
    for I:=0 to High(Audio.Hits) do begin
      Audio.Hits[I].Time:=0.23*(I+1);
      Audio.Hits[I].Strength:=0.70;
    end;
    Need(Audio.BossCount=0,'Fixture should exercise short-song fallback');
    Plan:=BuildCartPlan(Audio,nil);
    try
      Need(Length(Plan.Bosses)=1,'Short song has no convoy');
      VerifyChase(Plan,Audio);
      Ref:=NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsMineCart,StyleVariant(rsMineCart,50,100));
      Ref.SourceRevision:=Audio.SourceRevision;
      SaveCartPlan(Plan,Audio,Ref);
      Cold:=LoadCartAudio(Ref,Source,0);
      try
        RenderProof(Plan,Audio,Cold,Ref,Folder,True);
      finally
        Cold.Free;
      end;
    finally
      Plan.Free;
    end;
    Audio.SetBossFrequency(0);
    Plan:=BuildCartPlan(Audio,nil);
    try
      Need(Length(Plan.Bosses)=0,'Boss-off setting was ignored');
    finally
      Plan.Free;
    end;
  finally
    Audio.Free;
  end;
end;

var Audio,Cold:TRhythmAudio; Plan,Again:TCartPlan; Ops:TStyleOperations; Context:TStylePrepareContext;
  Ref,Other:TRhythmPlanRef; Settings,Loaded:TRhythmSettings; Folder,Source,Summary:string; Span:Double;
begin
  Audio:=nil;
  Cold:=nil;
  Plan:=nil;
  Again:=nil;
  try
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');
    ForceDirectories(Folder);
    ForceDirectories(TPath.Combine(Folder,'Short'));
    VerifyShort(TPath.Combine(Folder,'Short'));
    Source:=TPath.Combine(Folder,'source.identity');
    Audio:=Fixture(Source);
    Ref:=NewPlanRef(Audio.Key,Audio.Sensitivity,0,rsMineCart,StyleVariant(rsMineCart,50,100));
    Ops:=StyleOperations(rsMineCart);
    Context:=Default(TStylePrepareContext);
    Context.Audio:=Audio;
    Context.Variant:=Ref.Variant;
    Ops.Prepare(Context,Ref,Span,Summary);
    Settings:=TRhythmSettings.Defaults;
    Settings.Style:=rsMineCart;
    Settings.Music:=Source;
    Settings.BossFrequency:=100;
    Settings.Plan:=Ref;
    Need(TRhythmSettings.TryJSON(Settings.ToJSON,Loaded) and (Loaded.Plan.Digest=Ref.Digest),'Settings restore');
    Cold:=Ops.LoadAudio(Loaded.Plan,Source,0);
    Need(Length(Cold.PCM)=0,'Cold restore decoded PCM');
    Plan:=LoadCartPlan(Loaded.Plan,Cold,0);
    Need(Span>=Plan.Goal+CartFinishLanding+GoalFireworksDuration,'Preview cuts off ending fireworks');
    Again:=BuildCartPlan(Audio,nil);
    Other:=Ref;
    SaveCartPlan(Again,Audio,Other);
    Need(Other.Digest=Ref.Digest,'Same source produced a different plan');
    Verify(Plan,Audio);
    RenderProof(Plan,Audio,Cold,Ref,Folder);
    WriteLn('Mine cart PASS checks=',Checks);
  except
    on E:Exception do begin
      WriteLn(E.ClassName,': ',E.Message);
      ExitCode:=1;
    end;
  end;
  Again.Free;
  Plan.Free;
  Cold.Free;
  Audio.Free;
end.
