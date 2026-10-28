program MockCodex;
{$APPTYPE CONSOLE}
uses Winapi.Windows,System.SysUtils,System.Classes,System.JSON,System.IOUtils,System.NetEncoding;
var Line,Mode,ImagePath,Method:string;Message,Params:TJSONObject;Input:THandle;B:Byte;ReadCount:DWORD;
function TextOf(O:TJSONObject;const Key:string):string;
begin Result:='';if (O<>nil) and (O.GetValue(Key)<>nil) then Result:=O.GetValue(Key).Value;end;
procedure Emit(const Text:string);
var Bytes:TBytes;Offset,Count,Written:DWORD;
begin
  Bytes:=TEncoding.UTF8.GetBytes(Text+#10);Offset:=0;
  while Offset<DWORD(Length(Bytes)) do begin Count:=Length(Bytes)-Offset;if Mode='fragmented' then if Count>7 then Count:=7;
    if not WriteFile(GetStdHandle(STD_OUTPUT_HANDLE),Bytes[Offset],Count,Written,nil) then Halt(2);Inc(Offset,Written);if Mode='fragmented' then Sleep(1);
  end;
end;
procedure ResultOf(Request:TJSONObject;ResultValue:TJSONObject);
var Reply:TJSONObject;
begin Reply:=TJSONObject.Create.AddPair('id',Request.GetValue('id').Clone as TJSONValue).AddPair('result',ResultValue);try Emit(Reply.ToJSON);finally Reply.Free;end;end;
procedure Image(const ThreadId,TurnId:string);
var Item,Reply:TJSONObject;
begin
  Item:=TJSONObject.Create.AddPair('id','image1').AddPair('type','imageGeneration').AddPair('status','completed');
  if Mode='base64' then Item.AddPair('result','data:image/png;base64,'+TNetEncoding.Base64.EncodeBytesToString(TFile.ReadAllBytes(ImagePath)))
  else if Mode='missing-image' then Item.AddPair('savedPath',ImagePath+'.missing') else Item.AddPair('savedPath',ImagePath);
  Reply:=TJSONObject.Create.AddPair('method','item/completed').AddPair('params',TJSONObject.Create.AddPair('threadId',ThreadId).AddPair('turnId',TurnId).AddPair('item',Item));
  try Emit(Reply.ToJSON);finally Reply.Free;end;
end;
procedure Complete(const Status:string);
begin Emit('{"method":"turn/completed","params":{"threadId":"thread1","turn":{"id":"turn1","status":"'+Status+'"}}}');end;
begin
  Mode:=GetEnvironmentVariable('RHYTHM_MOCK_CASE');ImagePath:=GetEnvironmentVariable('RHYTHM_MOCK_IMAGE');Input:=GetStdHandle(STD_INPUT_HANDLE);
  while True do begin
    Line:='';repeat if not ReadFile(Input,B,1,ReadCount,nil) or (ReadCount=0) then Halt(0);if B<>10 then Line:=Line+Char(B);until B=10;
    Message:=TJSONObject.ParseJSONValue(Line) as TJSONObject;if Message=nil then Halt(3);
    try
      Method:=TextOf(Message,'method');Params:=nil;if Message.GetValue('params') is TJSONObject then Params:=TJSONObject(Message.GetValue('params'));
      if Method='initialize' then ResultOf(Message,TJSONObject.Create)
      else if Method='thread/start' then begin
        if (TextOf(Params,'approvalPolicy')<>'never') or (TextOf(Params,'sandbox')<>'read-only') then Halt(4);
        ResultOf(Message,TJSONObject.Create.AddPair('thread',TJSONObject.Create.AddPair('id','thread1')));
      end else if Method='turn/start' then begin
        TFile.WriteAllText(TPath.Combine(GetCurrentDir,'mock-request.json'),Params.ToJSON,TEncoding.UTF8);
        if Mode='early' then begin Image('thread1','old-turn');Image('thread1','turn1');end;
        ResultOf(Message,TJSONObject.Create.AddPair('turn',TJSONObject.Create.AddPair('id','turn1')));
        if Mode='cancel' then begin Sleep(20000);Halt(0);end;
        if Mode='bad-json' then begin Emit('{broken');Continue;end;
        if Mode='failed' then begin Complete('failed');Continue;end;
        Image('wrong-thread','turn1');Image('thread1','wrong-turn');
        if Mode<>'early' then Image('thread1','turn1');
        if Mode='duplicate' then Image('thread1','turn1');
        Emit('{"method":"item/completed","params":{"threadId":"thread1","turnId":"turn1","item":{"type":"agentMessage","phase":"final_answer","text":"画像を受信"}}}');
        Complete('completed');
      end;
    finally Message.Free;end;
  end;
end.
