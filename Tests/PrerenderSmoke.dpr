program PrerenderSmoke;
{$APPTYPE CONSOLE}
// 標準描画の変更前後を画素ハッシュで照合し、準備済み画像と任意時刻描画の再利用を調べる。
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  Vcl.Graphics, RhythmImageBank, RhythmShootingAssets, RhythmAudio, RhythmScene,
  RhythmSettings, RhythmStyles, RhythmPlanRef;

const
  AcceptedPixels: array[0..71, 0..1] of string = (
    ('image-6', '507548be7b406381fbfc7d02cf4705c2de77d24f97ab4ca5f4e27efc66b0fb1c'),
    ('image-7', '222c792b54cdef135ea2b87e5f788ae5ab261d0f2f152d8de503f302dd6d5846'),
    ('image-8', 'd7de0fa54e0654d97cd624db729f2b1df661e494a9db0796aed5d8656f64f1a7'),
    ('alpha-8', 'bc998a0ca095ad08f39c683e959d463f3d865567a37bedb482697627c6b40c50'),
    ('image-9', 'dd18c1fb181af6f37f0f4154ac107476b7d5e26125c8eb3c3dc4c7eb6a42cd0d'),
    ('image-10', '709520474de45f763e279cc6940890cb41cd7e263550c707a229f553f3af0f08'),
    ('image-11', '7495dec8ff45d031fedc6994e7d2fa7ba2117f43ce926a42b3d73d8bcc340d4d'),
    ('alpha-11', '7495dec8ff45d031fedc6994e7d2fa7ba2117f43ce926a42b3d73d8bcc340d4d'),
    ('image-12', 'bf6d638f9d64f9e9c4ff1c04272fd9c07c21746cec52e342466695a780672c0b'),
    ('alpha-12', 'bf6d638f9d64f9e9c4ff1c04272fd9c07c21746cec52e342466695a780672c0b'),
    ('image-13', '3c224fa49f169e101d34c3bdc386b711857732dfa17fc5d45810a3f7ef32bfc3'),
    ('alpha-13', 'fa2b07e9856eece2d8174ea271f6e4093c4e7d306e8bb4a057db33e47332583f'),
    ('image-14', 'a5f00cbc0690a7b9c9ac5d35cdc3f5e2219f62ba7bbda1e6c58577b98a79ba82'),
    ('alpha-14', '3ae71ad78765be18ecffb62bcd0e895ba7c41295ec714f0299b0a048331f7d86'),
    ('image-15', 'f70e7720fe0b0ba6d17e3edb12af43c37c88c1ae487c1aab2d216e3f5eb76e02'),
    ('alpha-15', 'c2ff54eaaa15cb494b2b25d2395caec64b1d105380b9f3e849848471d90ebddb'),
    ('image-16', '779b189bbd55c538c7911a9fdaacd55de64e9fcf3ac600293976c0beac8a9fce'),
    ('image-17', '1c7077f61de236a38d374b51e0c127bd53df9b8aec19d0b5a62c4ee8a92fe2e8'),
    ('image-18', '298564db4bd9442debef37afc9645535994bf738aec0ae073895803af77a82c5'),
    ('alpha-18', '298564db4bd9442debef37afc9645535994bf738aec0ae073895803af77a82c5'),
    ('image-19', '37485f8bee906516219d2839edd0976d37b782f62c9a5f298a7cceba5ece6dbf'),
    ('alpha-19', '26b89749d8635e1c4e424895022c7a2c594037f2ec8ac1aa9ef54d36c3e545ef'),
    ('image-20', '2de6c8e619e91ec1bf44516447a5772a255f86d2c014fce0217a3cec4789ac78'),
    ('alpha-20', '0d4fd9a5ad6660aa993e134118816f6e74a6157c3e78768edd0645f3b24837cb'),
    ('image-21', 'ed345fbce01c25478b5699792e5dde0c63a17c1a821260d9fa81b8669adbcfb8'),
    ('alpha-21', '53a86d907e0195718be4c340e0d00f26d23104cb8feac17d3ce18d6e99415941'),
    ('image-22', 'fe6fe72d3563cf201018715090746255114cae9df5a6814ec1ea4c2c052d2f4f'),
    ('alpha-22', 'b15a4d9e7ec98d24777ac96e79c04939cfcf9d4d157394a59c8e3f365584bb8c'),
    ('image-23', 'c0e836b65c4895f65f62fc14146031b51e298fd0a0f676f26f769d69536dd212'),
    ('alpha-23', 'd4c6e71bd67643f9df25d1acf185ca6d891101bc33f0ec465a911156bc161bef'),
    ('image-24', '4157fc3f77abfb549eb417a06127ec5ff6f2ba68a8ee61612d987cf0129eb6be'),
    ('alpha-24', '4157fc3f77abfb549eb417a06127ec5ff6f2ba68a8ee61612d987cf0129eb6be'),
    ('image-25', '2f765d1fa6e21296aa4c508dc0375df2257cb4f7c4124034913e85dc92934287'),
    ('alpha-25', '2f765d1fa6e21296aa4c508dc0375df2257cb4f7c4124034913e85dc92934287'),
    ('image-26', '308bafe906a8615d861f3d0fa7ca56f4452bfba3fd7c45366cc721345aff4af7'),
    ('alpha-26', '308bafe906a8615d861f3d0fa7ca56f4452bfba3fd7c45366cc721345aff4af7'),
    ('image-27', '30dc123bded7e76138ccfc57185085374794f27a48f8e52478d45a7b29bf8249'),
    ('alpha-27', '30dc123bded7e76138ccfc57185085374794f27a48f8e52478d45a7b29bf8249'),
    ('image-28', 'd9cf94aa64b78a402e74779fd3c38e1857bb4c202a7e848e66d0411cb7787d3c'),
    ('alpha-28', 'd9cf94aa64b78a402e74779fd3c38e1857bb4c202a7e848e66d0411cb7787d3c'),
    ('image-29', '0cadd808ca5f6632447b3fc3b54d25bf3f2c42f3fe17aac5edb2493c63007e54'),
    ('alpha-29', '0cadd808ca5f6632447b3fc3b54d25bf3f2c42f3fe17aac5edb2493c63007e54'),
    ('image-30', '2a2217866940b08e06d14aafad4d84a5c83b6ec5c9a8f79ca3e771751b268a65'),
    ('alpha-30', '2a2217866940b08e06d14aafad4d84a5c83b6ec5c9a8f79ca3e771751b268a65'),
    ('image-31', '1995304219e60927445ccf9053245125f1ccb359787930006590cfa8b99604c6'),
    ('alpha-31', '1995304219e60927445ccf9053245125f1ccb359787930006590cfa8b99604c6'),
    ('image-32', 'e909f9b4305bf0d0c45b8b0d7129eaaf0e3ab9fe44601cc21deba40465699124'),
    ('alpha-32', 'e909f9b4305bf0d0c45b8b0d7129eaaf0e3ab9fe44601cc21deba40465699124'),
    ('frame-0-0-0', '40b48defd4561ab4820138de79f45b1cef486be826510152c108caa8cc73b868'),
    ('frame-0-0-1', 'ffdc4231f8a5ebb06282462a749e309f40a9b3724ddbfc48d6232b981f3d88ca'),
    ('frame-0-0-2', 'ee3309b3ed9d81a8cc6bd7f76a789bb46be0551e32d0ca17f56641f87c21755f'),
    ('frame-0-0-3', '25a32657b3c1a033c0562e59708471b595b336a08ce79b9d64f05ea1d910b063'),
    ('frame-0-0-4', '185fee400f8a002f7acae5c25e13cd539e9b14eacad673b83acb4279424bf024'),
    ('frame-0-0-5', '87d1f4d6f5e38b3c7f448e01a2886def9b8ff065b253d2e426ed2bc71ce10383'),
    ('frame-0-1-0', '368b1f389c175af3a0a801d0dcc0b3085e4abb381961ce4dcb56355da7b66191'),
    ('frame-0-1-1', 'c1b9a037b8ada58fc37104655453fffacee2d089d3af93f628cf84e40a3cbe5e'),
    ('frame-0-1-2', 'd34f55d28305a255f3f0ba4c97613ec502f379832cd5e51b92659ea0ec06c38c'),
    ('frame-0-1-3', '7bfbcc71b6dc5aa9fd9e85c07467199354de20cd6f9a258b2fcdad1372308d8c'),
    ('frame-0-1-4', 'c25d27f87431bea0a8cddd2879f0b9772a59be5fd5b0da570eecc3bc97905965'),
    ('frame-0-1-5', '4fa323ca38caf54f9310fcc6c2c4a77693334e69b5beebcf9f2d523d640e5b33'),
    ('frame-1-0-0', '5fdaed0465a84479dfd6f40daca207b1f51dfa0f60bee14bf25933ba4fb11b1c'),
    ('frame-1-0-1', 'd10bf872529a22c8390f7c8f58f5e92a91819744df5ea64074482d2e6a3b2983'),
    ('frame-1-0-2', '9d9e1e9fa291165fe357aefff30a3973fee6c2f728651215947658d9a9e35e06'),
    ('frame-1-0-3', 'a672b9150f7f0a0857b3d0f283b47f3f2ef37c204789b706eb017d6be9ca5744'),
    ('frame-1-0-4', 'ae6f4ea2ff59b9cbc04ee41a7cfbbe4d5153476bda7d8c382ca82f5edbe7e709'),
    ('frame-1-0-5', '4947336e97861e84418509e71de22aab76909e1575a2c7f5ad3691f2d2759dca'),
    ('frame-1-1-0', '7ffbfb901b89e71e2b01b185b02cd0963b14314d8aa4ef74186b122426605131'),
    ('frame-1-1-1', '50b50447ce6d21141d000c5513e868ab699920a3f6a3c0c2418245b132e68697'),
    ('frame-1-1-2', '33ffcc524998a148d42878c56f812052e1c2eee71695b803c5e88ea6384d08ec'),
    ('frame-1-1-3', 'e752e241a8d9994f24f7756f14032c39e7836050e5e5623f12e712d6e542f401'),
    ('frame-1-1-4', '450d94e47573018c4172d9e3019fda6c3aeee7538ae84e5a201e914f17f6f773'),
    ('frame-1-1-5', '71aebf8f446e5ae7fa129d1ac165a386c78d222269f511555bb4cc327685ba8e'));

function PixelHash(Bitmap: TBitmap): string;
var CopyImage: TBitmap; Hash: THashSHA2; Y: Integer;
begin
  CopyImage := TBitmap.Create;
  try
    CopyImage.Assign(Bitmap);
    CopyImage.PixelFormat := pf32bit;
    Hash := THashSHA2.Create;
    for Y := 0 to CopyImage.Height - 1 do Hash.Update(CopyImage.ScanLine[Y]^, CopyImage.Width * 4);
    Result := Hash.HashAsString;
  finally
    CopyImage.Free;
  end;
end;

procedure Need(Value: Boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

var Bank: TShootingImageBank; Image: TBitmap; Renderer: TRhythmRenderer; Audio: TRhythmAudio;
  Expected: TJSONObject; Key, Value: string;
  I, Direction, Backend, Checks, FilesBefore: Integer; T: Double;
  State: TRhythmSettings; Ref: TRhythmPlanRef;

procedure Compare(const Name, Hash: string);
begin
  Inc(Checks);
  Need(Expected.GetValue<string>(Name, '') = Hash, 'Standard pixels changed: ' + Name);
end;

begin
  Bank := nil; Image := nil; Renderer := nil; Audio := nil; Expected := nil;
  try
    Expected := TJSONObject.Create;
    for I := 0 to High(AcceptedPixels) do Expected.AddPair(AcceptedPixels[I, 0], AcceptedPixels[I, 1]);
    FilesBefore := Length(TDirectory.GetFiles(ExtractFileDir(ParamStr(0)), '*', TSearchOption.soAllDirectories));
    Bank := TShootingImageBank.Create;
    Bank.EnsurePrepared;
    Need(Bank.ImageCount = 27, 'Standard image cache count');
    for I := 6 to SHOOT_EMBER do
    begin
      Need(not Bank.Image[I].Empty, 'Empty standard sprite ' + IntToStr(I));
      Compare('image-' + IntToStr(I), PixelHash(Bank.Image[I]));
      if not Bank.AlphaImage[I].Empty then Compare('alpha-' + IntToStr(I), PixelHash(Bank.AlphaImage[I]));
    end;
    Value := PixelHash(Bank.Image[8]);
    Bank.EnsurePrepared;
    Need(PixelHash(Bank.Image[8]) = Value, 'Preparation changes an already prepared image');
    Audio := TRhythmAudio.Create;
    Audio.Duration := 100;
    Audio.SoundEnd := 98;
    Audio.Key := StringOfChar('a', 64);
    Audio.Sensitivity := 50;
    SetLength(Audio.Hits, 180);
    SetLength(Audio.Envelope, 10000);
    for I := 0 to High(Audio.Hits) do
    begin
      Audio.Hits[I].Time := 0.5 + I * 0.54;
      Audio.Hits[I].Strength := 0.3 + (I mod 7) * 0.1;
      Audio.Hits[I].Lane := 0.2 + (I mod 13) * 0.05;
      Audio.Hits[I].Flight := 0.4;
    end;
    for I := 0 to High(Audio.Envelope) do Audio.Envelope[I] := 0.35;
    Image := TBitmap.Create;
    Image.PixelFormat := pf32bit;
    Image.SetSize(640, 360);
    Renderer := TRhythmRenderer.Create;
    Ref := NewPlanRef(Audio.Key, 50, 0, rsShooting);
    Renderer.ConfigureStyle(rsShooting, Ref, 100, 0);
    for Backend := 0 to 1 do
    begin
      Renderer.UseD2D := Backend = 1;
      for Direction := 0 to 1 do
        for I := 0 to 5 do
        begin
          T := 0.35 + I * 17.13;
          Renderer.Render(Image, Audio, T, Direction);
          Key := Format('frame-%d-%d-%d', [Backend, Direction, I]);
          Value := PixelHash(Image);
          Compare(Key, Value);
          Renderer.Render(Image, Audio, 99 - T, Direction);
          Renderer.Render(Image, Audio, T, Direction);
          Need(PixelHash(Image) = Value, 'Frame depends on render history');
        end;
    end;
    Need(TRhythmSettings.TryJSON('{"schema":1,"style":"shooting","music":"old.mp3",' +
      '"sensitivity":73,"offsetSeconds":0.17,"designs":[{"id":"enemy","path":"missing.png","memo":"old"}]}', State),
      'Old custom settings cannot migrate');
    Need((State.Music = 'old.mp3') and (State.Sensitivity = 73) and
      (Abs(State.OffsetSeconds - 0.17) < 1E-9) and not State.ToJSON.Contains('designs'), 'Legacy settings migration');
    Need(Length(TDirectory.GetFiles(ExtractFileDir(ParamStr(0)), '*', TSearchOption.soAllDirectories)) = FilesBefore,
      'Rendering wrote files beside the executable');
    WriteLn('PRERENDER_PASS ', Checks, ' exact image/frame comparisons, two directions/backends.');
  except
    on E: Exception do begin WriteLn(E.ClassName, ': ', E.Message); ExitCode := 1; end;
  end;
  Expected.Free; Renderer.Free; Image.Free; Audio.Free; Bank.Free;
end.
