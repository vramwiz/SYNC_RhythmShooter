unit MimiChildProcess;

interface

uses System.SysUtils;

type
  TProcessCancel = reference to function: Boolean;
  EAudioToolTimeout = class(Exception);

procedure RunAudioTool(const Exe: string; const Args: array of string;
  const Output, Log: string; const Cancel: TProcessCancel;
  RunTimeoutMs: Cardinal = 1800000; CancelGraceMs: Cardinal = 2000);

implementation

uses Winapi.Windows, System.IOUtils, System.Classes;

function QuoteArg(const S: string): string;
var C: Char; Slashes: Integer;
begin
  Result := '"'; Slashes := 0;
  for C in S do
    if C = '\' then Inc(Slashes)
    else
    begin
      if C = '"' then Result := Result + StringOfChar('\', Slashes * 2 + 1)
      else Result := Result + StringOfChar('\', Slashes);
      Slashes := 0;
      Result := Result + C;
    end;
  Result := Result + StringOfChar('\', Slashes * 2) + '"';
end;

procedure RunAudioTool(const Exe: string; const Args: array of string;
  const Output, Log: string; const Cancel: TProcessCancel;
  RunTimeoutMs, CancelGraceMs: Cardinal);
var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  PI: TProcessInformation;
  Limits: TJobObjectExtendedLimitInformation;
  InputRead, InputWrite, OutHandle, ErrHandle, Job: THandle;
  Command, Arg: string;
  Code, Written, WaitResult: DWORD;
  Started, Requested: UInt64;
  WasCancelled, TimedOut, Forced, Launched, Exited: Boolean;
  Q: AnsiString;
begin
  if Assigned(Cancel) and Cancel() then raise EAbort.Create('Operation cancelled');
  if not TFile.Exists(Exe) then raise Exception.Create('FFmpeg tool is missing: ' + Exe);
  InputRead := 0; InputWrite := 0; Job := 0;
  OutHandle := INVALID_HANDLE_VALUE; ErrHandle := INVALID_HANDLE_VALUE;
  Launched := False; Exited := False;
  ZeroMemory(@PI, SizeOf(PI));
  SA.nLength := SizeOf(SA); SA.lpSecurityDescriptor := nil; SA.bInheritHandle := True;
  try
    Job := CreateJobObject(nil, nil);
    if Job = 0 then RaiseLastOSError;
    ZeroMemory(@Limits, SizeOf(Limits));
    Limits.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if not SetInformationJobObject(Job, JobObjectExtendedLimitInformation, @Limits, SizeOf(Limits)) then RaiseLastOSError;
    if not CreatePipe(InputRead, InputWrite, @SA, 0) then RaiseLastOSError;
    if not SetHandleInformation(InputWrite, HANDLE_FLAG_INHERIT, 0) then RaiseLastOSError;
    OutHandle := CreateFile(PChar(Output), GENERIC_WRITE, FILE_SHARE_READ, @SA, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
    if OutHandle = INVALID_HANDLE_VALUE then RaiseLastOSError;
    ErrHandle := CreateFile(PChar(Log), GENERIC_WRITE, FILE_SHARE_READ, @SA, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
    if ErrHandle = INVALID_HANDLE_VALUE then RaiseLastOSError;
    ZeroMemory(@SI, SizeOf(SI)); SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW; SI.wShowWindow := SW_HIDE;
    SI.hStdInput := InputRead; SI.hStdOutput := OutHandle; SI.hStdError := ErrHandle;
    Command := QuoteArg(Exe);
    for Arg in Args do Command := Command + ' ' + QuoteArg(Arg);
    UniqueString(Command);
    if not CreateProcess(PChar(Exe), PChar(Command), nil, nil, True,
      CREATE_NO_WINDOW or CREATE_SUSPENDED, nil, nil, SI, PI) then RaiseLastOSError;
    Launched := True;
    // Start only after the private unnamed job owns this newly created child.
    // No PID lookup, process-name search, or user-owned process is involved.
    if not AssignProcessToJobObject(Job, PI.hProcess) then RaiseLastOSError;
    if ResumeThread(PI.hThread) = DWORD(-1) then RaiseLastOSError;
    CloseHandle(PI.hThread); PI.hThread := 0;
    Started := GetTickCount64; Requested := 0;
    WasCancelled := False; TimedOut := False; Forced := False;
    repeat
      WaitResult := WaitForSingleObject(PI.hProcess, 50);
      if WaitResult = WAIT_OBJECT_0 then begin Exited := True; Break; end;
      if WaitResult = WAIT_FAILED then RaiseLastOSError;
      if Assigned(Cancel) and Cancel() then WasCancelled := True;
      if GetTickCount64 - Started >= RunTimeoutMs then TimedOut := True;
      if (WasCancelled or TimedOut) and (Requested = 0) then
      begin
        Q := 'q' + #10;
        WriteFile(InputWrite, Q[1], Length(Q), Written, nil);
        Requested := GetTickCount64;
      end;
      if (Requested <> 0) and (GetTickCount64 - Requested >= CancelGraceMs) then
      begin
        if not TerminateJobObject(Job, ERROR_CANCELLED) then RaiseLastOSError;
        Forced := True;
        Exited := WaitForSingleObject(PI.hProcess, 5000) = WAIT_OBJECT_0;
        if not Exited then raise Exception.Create('Own audio child exit is unconfirmed; temporary work is preserved.');
        Break;
      end;
    until False;
    if WasCancelled or (Assigned(Cancel) and Cancel()) then
    begin
      if Forced then raise EAbort.Create('Operation cancelled; unresponsive own child job stopped after deadline');
      raise EAbort.Create('Operation cancelled; own child exited normally');
    end;
    if TimedOut then raise EAudioToolTimeout.Create('Audio tool exceeded its execution deadline; own child stopped. Retry the operation.');
    if not GetExitCodeProcess(PI.hProcess, Code) then RaiseLastOSError;
    if Code <> 0 then raise Exception.CreateFmt('%s failed (exit %d). Details: %s', [ExtractFileName(Exe), Code, Log]);
  finally
    if Launched and not Exited then
    begin
      // This exact handle was returned by our CreateProcess, possibly still
      // suspended if job assignment failed. Never leave an unowned running child.
      TerminateProcess(PI.hProcess, ERROR_CANCELLED);
      Exited := WaitForSingleObject(PI.hProcess, 5000) = WAIT_OBJECT_0;
      if not Exited then
        try TFile.WriteAllText(TPath.Combine(ExtractFileDir(Log), 'process-exit-unconfirmed.txt'),
          'Preserve this session: own child exit could not be confirmed.', TEncoding.UTF8); except end;
    end;
    if PI.hThread <> 0 then CloseHandle(PI.hThread);
    if PI.hProcess <> 0 then CloseHandle(PI.hProcess);
    if Job <> 0 then CloseHandle(Job);
    if InputRead <> 0 then CloseHandle(InputRead);
    if InputWrite <> 0 then CloseHandle(InputWrite);
    if OutHandle <> INVALID_HANDLE_VALUE then CloseHandle(OutHandle);
    if ErrHandle <> INVALID_HANDLE_VALUE then CloseHandle(ErrHandle);
  end;
end;

end.
