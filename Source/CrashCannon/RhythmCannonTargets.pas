unit RhythmCannonTargets;
// 標的ごとの組み立て座標と部品の支持関係。最後の要素は予備の反撃起点。
interface

type
  TCannonTarget=(ctDepot,ctBridge,ctFactory,ctFort,ctTrain,ctTower,ctRobot,ctAirship,ctReactor);
  TCannonShape=(cpCrate,cpBarrel,cpGirder,cpDeck,cpTank,cpPipe,cpGear,cpBrick,cpGate,
    cpCar,cpWheel,cpArmor,cpEngine,cpTurret,cpCore,cpHelmet,cpFlag);
  TCannonPart=record
    Shape:TCannonShape;
    X,Y,W,H:Double; // Xは右向き、Yは地面から上向き
    BreakAt,LandAt,Drift,Spin:Double;
    Attack,Support:Integer;
  end;

function CannonParts(Kind:TCannonTarget):TArray<TCannonPart>;

implementation

function CannonParts(Kind:TCannonTarget):TArray<TCannonPart>;
var Parts:TArray<TCannonPart>;

  procedure Add(Shape:TCannonShape;X,Y,W,H:Double);
  var Index:Integer;
  begin
    Index:=Length(Parts);
    SetLength(Parts,Index+1);
    Parts[Index].Shape:=Shape;
    Parts[Index].Attack:=-1;
    Parts[Index].Support:=-1;
    Parts[Index].X:=X;
    Parts[Index].Y:=Y;
    Parts[Index].W:=W;
    Parts[Index].H:=H;
  end;

begin
  case Kind of
    ctDepot:begin
      Add(cpBarrel,13.1,0.60,0.82,1.20);
      Add(cpCrate,14.4,0.62,1.20,1.24);
      Add(cpBarrel,15.5,0.60,0.82,1.20);
      Add(cpCrate,16.7,1.98,1.42,1.20);
      Add(cpBarrel,19.1,2.01,0.88,1.26);
      Add(cpCrate,20.4,2.02,1.40,1.28);
      Add(cpCrate,18.0,3.25,1.30,1.23);
      Add(cpBarrel,21.6,0.63,0.92,1.26);
      Add(cpCrate,19.4,3.24,1.36,1.16);
      Add(cpGirder,16.7,0.55,0.36,1.11);
      Add(cpGirder,20.4,0.55,0.36,1.11);
      Add(cpDeck,18.7,1.27,5.65,0.34);
      Add(cpBarrel,18.0,2.02,0.87,1.28);
    end;
    ctBridge:begin
      Add(cpGirder,14.3,1.65,0.68,3.30);
      Add(cpDeck,13.5,3.65,2.42,0.65);
      Add(cpGirder,21.7,1.65,0.70,3.30);
      Add(cpDeck,21.75,3.65,2.30,0.65);
      Add(cpGirder,17.3,2.21,0.47,4.40);
      Add(cpGirder,19.4,2.21,0.47,4.40);
      Add(cpDeck,16.0,4.18,2.85,1.90);
      Add(cpDeck,20.6,4.18,2.80,1.90);
      Add(cpBarrel,18.3,5.55,0.97,1.33);
      Add(cpDeck,18.33,4.54,2.68,1.45);
    end;
    ctFactory:begin
      Add(cpTank,14.40,1.55,2.0,3.10);
      Add(cpPipe,15.65,3.18,2.95,0.62);
      Add(cpGear,17.21,3.43,1.76,1.76);
      Add(cpPipe,20.85,4.98,2.70,0.68);
      Add(cpTank,21.82,2.06,1.48,4.12);
      Add(cpGear,19.30,5.11,2.20,2.20);
      Add(cpPipe,16.60,5.42,2.35,0.72);
      Add(cpTank,17.68,1.57,2.20,3.14);
      Add(cpArmor,19.64,1.31,2.58,2.62);
      Add(cpTank,19.66,3.43,2.40,3.16);
    end;
    ctFort:begin
      Add(cpBrick,14.00,2.15,1.55,4.30);
      Add(cpBrick,16.06,1.64,2.58,3.28);
      Add(cpArmor,14.00,4.77,1.96,0.94);
      Add(cpBrick,20.15,1.64,2.44,3.28);
      Add(cpBrick,22.10,2.45,1.60,4.90);
      Add(cpArmor,22.10,5.38,2.00,0.96);
      Add(cpBrick,18.27,4.02,3.18,1.55);
      Add(cpFlag,18.39,5.72,1.32,2.16);
      Add(cpGate,18.22,1.62,1.96,3.24);
      Add(cpBrick,18.24,3.22,2.78,0.89);
    end;
    ctTrain:begin
      Add(cpWheel,13.86,0.43,0.86,0.86);
      Add(cpWheel,15.62,0.43,0.86,0.86);
      Add(cpPipe,16.19,0.83,1.20,0.36);
      Add(cpCar,14.75,1.77,2.95,1.75);
      Add(cpWheel,17.30,0.43,0.86,0.86);
      Add(cpWheel,19.28,0.43,0.86,0.86);
      Add(cpPipe,19.88,0.83,1.16,0.36);
      Add(cpCar,18.24,1.80,3.00,1.80);
      Add(cpWheel,20.95,0.49,0.98,0.98);
      Add(cpWheel,22.43,0.49,0.98,0.98);
      Add(cpTurret,22.03,2.83,1.32,0.99);
      Add(cpEngine,21.68,1.82,2.83,2.03);
    end;
    ctTower:begin
      Add(cpArmor,16.32,3.69,2.02,1.92);
      Add(cpGirder,20.80,1.85,0.84,3.70);
      Add(cpArmor,20.41,6.06,2.56,2.44);
      Add(cpTurret,15.79,6.73,2.90,1.31);
      Add(cpArmor,17.14,7.93,1.52,1.14);
      Add(cpGirder,17.96,1.93,0.89,3.86);
      Add(cpDeck,19.30,3.28,4.68,0.91);
      Add(cpArmor,19.11,7.41,3.10,1.50);
      Add(cpArmor,18.90,5.73,2.82,1.72);
      Add(cpEngine,20.58,4.08,2.16,1.70);
      Add(cpDeck,19.15,8.79,4.25,1.12);
      Add(cpCore,18.39,5.75,2.35,2.35);
    end;
    ctRobot:begin
      Add(cpArmor,15.35,4.65,1.65,2.38);
      Add(cpArmor,21.80,5.25,1.30,2.02);
      Add(cpArmor,17.17,0.50,2.20,1.0);
      Add(cpEngine,17.49,2.34,1.44,2.72);
      Add(cpEngine,20.16,2.43,1.57,2.94);
      Add(cpArmor,20.34,0.54,2.16,1.08);
      Add(cpTurret,15.80,7.06,2.32,1.79);
      Add(cpArmor,21.72,7.22,2.14,1.92);
      Add(cpHelmet,18.86,8.70,2.31,1.74);
      Add(cpArmor,18.87,6.42,3.93,2.42);
      Add(cpEngine,19.01,4.33,3.20,1.60);
      Add(cpCore,18.65,6.23,2.15,2.15);
    end;
    ctAirship:begin
      Add(cpTurret,15.37,5.10,2.52,0.91);
      Add(cpEngine,21.75,4.93,2.16,1.31);
      Add(cpArmor,14.28,6.91,1.91,2.09);
      Add(cpEngine,17.32,4.81,2.54,1.15);
      Add(cpArmor,21.42,7.69,2.63,2.21);
      Add(cpArmor,16.35,7.98,2.98,1.89);
      Add(cpTurret,20.00,8.85,2.45,1.03);
      Add(cpArmor,18.78,8.70,2.12,1.12);
      Add(cpDeck,18.86,5.81,4.24,0.89);
      Add(cpArmor,19.02,7.13,3.68,2.19);
      Add(cpEngine,19.37,4.83,2.00,1.37);
      Add(cpCore,17.73,6.94,2.40,2.40);
    end;
    ctReactor:begin
      Add(cpTank,14.50,1.43,1.61,2.86);
      Add(cpTank,22.12,1.56,1.63,3.12);
      Add(cpPipe,15.57,3.28,2.59,0.65);
      Add(cpPipe,21.58,3.90,2.67,0.75);
      Add(cpTurret,15.99,6.28,2.75,1.10);
      Add(cpArmor,21.11,6.15,2.17,2.70);
      Add(cpArmor,18.57,8.67,2.66,1.48);
      Add(cpGear,18.50,5.27,6.43,6.43);
      Add(cpArmor,18.20,5.32,3.44,2.20);
      Add(cpEngine,19.30,1.04,3.41,2.08);
      Add(cpDeck,18.50,2.30,4.84,0.95);
      Add(cpCore,18.51,5.20,2.82,2.82);
    end;
  end;
  // 上物と支えを結ぶ。支柱や車輪を失うと、次の着弾前から上物が傾く。
  case Kind of
    ctDepot:begin Parts[6].Support:=9; Parts[8].Support:=10; Parts[11].Support:=9; end;
    ctBridge:begin Parts[1].Support:=0; Parts[3].Support:=2; Parts[9].Support:=4; end;
    ctFactory:begin Parts[1].Support:=0; Parts[5].Support:=3; Parts[9].Support:=7; end;
    ctFort:begin Parts[2].Support:=0; Parts[5].Support:=4; Parts[7].Support:=6; end;
    ctTrain:begin Parts[3].Support:=0; Parts[7].Support:=4; Parts[11].Support:=8; end;
  end;
  Result:=Parts;
end;
end.
