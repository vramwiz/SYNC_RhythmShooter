program OrbitStageSmoke;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Math,System.Hash,System.IOUtils,System.JSON,
  Vcl.Graphics,Vcl.Imaging.pngimage,RhythmAudio,RhythmOrbitPlan,RhythmOrbitTypes,RhythmOrbitShow,
  RhythmOrbitScene,RhythmAnimation,RhythmImageBank,RhythmPlanRef,RhythmStyles,RhythmProduct;
var A:TRhythmAudio;P:TOrbitPlan;Ref:TRhythmPlanRef;Scene:TOrbitAnimation;R:TAnimationRenderer;
  Image:TBitmap;PNG:TPngImage;Stamp:TWin32FileAttributeData;Folder,Source,Revision:string;
  C,I,J,K,N,Checks,Frames:Integer;D,T,Prior,Delta:Double;L:TOrbitLeg;Cam,Other:TOrbitCamera;Q:TOrbitPoint;
procedure Need(OK:Boolean;const S:string);
begin if not OK then raise Exception.Create(S);end;
begin A:=nil;P:=nil;R:=nil;Image:=nil;PNG:=nil;Checks:=0;Frames:=0;
  try
    ConfigureRhythmProduct('SYNC_RhythmGame','Orbit stage native',rsRhythmGame);
    Folder:=TPath.Combine(ExtractFileDir(ParamStr(0)),'Evidence');ForceDirectories(Folder);
    Source:=TPath.Combine(Folder,'stage.identity');TFile.WriteAllText(Source,'Stage identity',TEncoding.UTF8);
    Need(GetFileAttributesEx(PChar(Source),GetFileExInfoStandard,@Stamp),'Source stamp');Revision:=IntToHex(Stamp.nFileSizeHigh,8)+IntToHex(Stamp.nFileSizeLow,8)+'-'+IntToHex(Stamp.ftLastWriteTime.dwHighDateTime,8)+IntToHex(Stamp.ftLastWriteTime.dwLowDateTime,8);
    Image:=TBitmap.Create;Image.PixelFormat:=pf32bit;Image.SetSize(960,540);
    for C:=0 to 4 do begin
      D:=96;if C=1 then D:=8;if C=2 then D:=1;if C=3 then D:=0.1;
      A:=TRhythmAudio.Create;A.Duration:=D;A.SoundEnd:=D;A.Source:=Source;A.SourceRevision:=Revision;A.Sensitivity:=50;A.Key:=THashSHA2.GetHashString('stage-'+IntToStr(C));
      N:=Max(1,Floor(D/0.08));SetLength(A.Hits,N);
      for I:=0 to N-1 do begin A.Hits[I].Time:=I*D/N;A.Hits[I].Strength:=0.8;end;
      if C=4 then begin SetLength(A.Hits,3);A.Hits[0].Time:=12;A.Hits[1].Time:=48;A.Hits[2].Time:=92;end;
      P:=TOrbitPlan.Build(A,20);Ref:=NewPlanRef(A.Key,50,0,rsRhythmGame,121);Ref.SourceRevision:=Revision;P.Save(Ref,A);
      Need((P.Stages[0]<P.Stages[1]) and (P.Stages[2]<D) and (P.Stages[3]=P.Stages[2]) and (P.EndTime=D),'Stage order');
      Need(OrbitShipSize(P,P.Stages[2])<0.4,'Departure did not recede');
      for I:=0 to P.LegCount-1 do begin L:=P.Legs[I];
        if I>0 then for J:=0 to 2 do begin D:=16/9;if J=1 then D:=9/16;if J=2 then D:=1;
          Prior:=1E20;
          for K:=3 to 8 do begin T:=Power(10,-K)*Min(1.0,A.Duration);Cam:=P.CameraAt(L.Start-T,D);Other:=P.CameraAt(L.Start+T,D);
            Delta:=Hypot(Cam.Center.X-Other.Center.X,Cam.Center.Y-Other.Center.Y)+Abs(Cam.Span-Other.Span);
            Need(Delta<=Prior*1.01+1E-10,'Camera boundary does not converge');Prior:=Delta;Inc(Checks);
          end;
          Need(Prior<0.0001,'Camera boundary discontinuity');
        end;
      end;
      for I:=0 to 360 do begin T:=A.Duration*I/360;
        for J:=0 to 2 do begin D:=16/9;if J=1 then D:=9/16;if J=2 then D:=1;Cam:=P.CameraAt(T,D);Q:=OrbitProject(P.CursorAt(T),Cam,D);
          Need((Q.X>0.03) and (Q.X<0.97) and (Q.Y>0.03) and (Q.Y<0.97),'Stage lost ship');Inc(Checks);
        end;
      end;
      Scene:=TOrbitAnimation.Create;Scene.Audio:=A;Scene.SetReference(Ref);R:=TAnimationRenderer.Create(Scene,TAnimationImageBank.Create([],0));
      for J:=0 to 1 do begin R.UseD2D:=J=1;
        for K:=0 to 6 do begin
          case K of 0:T:=0;1:T:=P.Stages[0]*0.5;2:T:=P.Stages[0];3:T:=P.Stages[1];
            4:T:=(P.Stages[1]+P.Stages[2])/2;5:T:=P.Stages[2];else T:=A.Duration*0.999;end;
          R.Render(Image,T,0);Need(Scene.Notice='','Stage rendering '+Scene.Notice);PNG:=TPngImage.Create;
          try PNG.Assign(Image);PNG.SaveToFile(TPath.Combine(Folder,Format('case%d-backend%d-stage%d.png',[C,J,K])));finally FreeAndNil(PNG);end;Inc(Frames);
        end;
      end;
      WriteLn('Stage CASE ',C,' intro=',P.Stages[0]:0:6,' depart=',(P.Stages[2]-P.Stages[1]):0:6,' clear=',(A.SoundEnd-P.Stages[2]):0:6);Flush(Output);
      FreeAndNil(R);FreeAndNil(P);FreeAndNil(A);
    end;
    TFile.WriteAllText(TPath.Combine(Folder,'result.json'),Format('{"cases":5,"checks":%d,"frames":%d,"pass":true}',[Checks,Frames]),TEncoding.UTF8);
    WriteLn('Orbit stage PASS checks=',Checks,' frames=',Frames);
  except on E:Exception do begin WriteLn(E.ClassName,': ',E.Message);ExitCode:=1;end;end;
  PNG.Free;R.Free;P.Free;A.Free;Image.Free;
end.
