unit RhythmBreakoutScoreTypes;
// Score系バリエーションの保存幾何型。探索・描画・ファイルI/Oへ依存しない。
interface
uses RhythmBreakoutGeometry;
const
  SCORE_COLUMNS=10;
  SCORE_PITCH=0.041;
  SCORE_BRICK_W=0.126;
  SCORE_BRICK_H=0.028;
  SCORE_MAX_BRICKS=8000;
type
  TScoreKind=(snBlock,snWall,snPaddle,snLaunch,snFinish,snCorner,snCatch,snServe);
  TScoreEvent=record
    Time,Strength:Double;
    Source:Integer;
  end;
  TScoreNode=record
    Time,Speed:Double;
    P:TBreakPoint;
    Kind:TScoreKind;
    Source,Brick,Row,Col:Integer;
  end;
  TScoreBrick=record
    Time,Strength:Double;
    Source,Row,Col:Integer;
  end;
  TScoreKey=record
    Time,Value:Double;
  end;
  TScoreItem=record
    Source:Integer;
    Drop,Take,Finish:Double;
  end;
  TScoreBonus=record
    X,Time:Double;
    Row:Integer;
  end;
  TScoreExtraBall=record
    Launch,Hit,Catch:Double;
    A,B,C:TBreakPoint;
    Target,Item:Integer;
  end;

implementation
end.
