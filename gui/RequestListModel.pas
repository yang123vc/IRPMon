Unit RequestListModel;

Interface

Uses
  Windows, Generics.Collections,
  IRPMonDll, ListModel;


Type
  ERequestListModelColumnType = (
    rlmctTime,
    rlmctRequestType,
    rlmctDeviceObject,
    rlmctDeviceName,
    rlmctDriverObject,
    rlmctDriverName,
    rlmctResult,
    rlmctSubType,
    rlmctIRPAddress,
    rlmctFileObject,
    rlmctIRPFlags,
    rlmctArg1,
    rlmctArg2,
    rlmctArg3,
    rlmctArg4,
    rlmctThreadId,
    rlmctProcessId,
    rlmctIRQL,
    rlmctPreviousMode,
    rlmctRequestorMode,
    rlmctIOSBStatus,
    rlmctIOSBInformation);
  PERequestListModelColumnType = ^ERequestListModelColumnType;

  TDriverRequest = Class
  Private
    FDriverName : WideString;
    FDeviceName : WideString;
    FDriverObject : Pointer;
    FDeviceObject : Pointer;
    FRequestType : ERequestType;
    FResultType : ERequestResultType;
    FResultValue : NativeUInt;
    FTime : UInt64;
    FThreadId : THandle;
    FProcessId : THandle;
    FIRQL : Byte;
  Protected
    Function GetColumn(AColumnType:ERequestListModelColumnType; Var AResult:WideString):Boolean; Virtual;
    Procedure SetDriverName(AName:WideString);
    Procedure SetDeviceName(AName:WideString);
  Public
    Constructor Create(Var ARequest:REQUEST_HEADER); Reintroduce;

    Class Function IOCTLToString(AControlCode:Cardinal):WideString;
    Class Function RequestTypeToString(ARequestType:ERequestType):WideString;
    Class Function RequestResultToString(AResult:NativeUInt; AResultType:ERequestResultType):WideString;
    Class Function NTSTATUSToString(AValue:Cardinal):WideString;
    Class Function AccessModeToString(AMode:Byte):WideString;
    Class Function IRQLToString(AValue:Byte):WideString;
    Class Function MajorFunctionToString(AMajor:Byte):WideString;
    Class Function MinorFunctionToString(AMajor:Byte; AMinor:Byte):WideString;

    Property DriverName : WideString Read FDriverName Write SetDriverName;
    Property DeviceName : WideString Read FDeviceName Write SetDeviceName;
    Property DriverObject : Pointer Read FDriverObject;
    Property DeviceObject : Pointer Read FDeviceObject;
    Property RequestType : ERequestType Read FRequestType;
    Property ResultType : ERequestResultType Read FResultType;
    Property ResultValueRaw : NativeUInt Read FResultValue;
    Property TimeRaw : UInt64 Read FTime;
    Property ThreadId : THandle Read FThreadId;
    Property ProcessId : THandle Read FProcessId;
    Property IRQL : Byte Read FIRQL;
  end;

  TDriverUnloadRequest = Class (TDriverRequest)
  Public
    Constructor Create(Var ARequest:REQUEST_UNLOAD); Reintroduce;
  end;

  TAddDeviceRequest = Class (TDriverRequest)
  Public
    Constructor Create(Var ARequest:REQUEST_ADDDEVICE); Reintroduce;
  end;


  TIRPCompleteRequest = Class (TDriverRequest)
  Private
    FIRPAddress : Pointer;
    FIOSBStatus : Cardinal;
    FIOSBInformation : NativeUInt;
    FProcessId : THandle;
    FThreadId : THandle;
  Protected
    Function GetColumn(AColumnType:ERequestListModelColumnType; Var AResult:WideString):Boolean; Override;
  Public
    Constructor Create(Var ARequest:REQUEST_IRP_COMPLETION); Reintroduce;

    Property Address : Pointer Read FIRPAddress;
    Property IOSBStatus : Cardinal Read FIOSBStatus;
    Property IOSBInformation : NativeUInt Read FIOSBInformation;
    Property ProcessId : THandle Read FProcessId;
    Property ThreadId : THandle Read FThreadId;
  end;

  TFastIoRequest = Class (TDriverRequest)
  Public
    Constructor Create(Var ARequest:REQUEST_FASTIO); Reintroduce;
  end;

  TStartIoRequest = Class (TDriverRequest)
  Public
    Constructor Create(Var ARequest:REQUEST_STARTIO); Reintroduce;
  end;

  TRequestListModel = Class (TListModel<TDriverRequest>)
    Private
      FRequests : TList<TDriverRequest>;
      FDriverMap : TDictionary<Pointer, WideString>;
      FDeviceMap : TDictionary<Pointer, WideString>;
    Protected
      Function GetColumn(AItem:TDriverRequest; ATag:NativeUInt):WideString; Override;
      Procedure FreeItem(AItem:TDriverRequest); Override;
      Function _Item(AIndex:Integer):TDriverRequest; Override;
    Public
      Constructor Create; Reintroduce;
      Destructor Destroy; Override;
      Function RefreshMaps:Cardinal;

      Procedure Clear; Override;
      Function RowCount : Cardinal; Override;
      Function Update:Cardinal; Override;
    end;

Implementation

Uses
  SysUtils, NameTables, IRPRequest;

(** TDriverRequest **)

Constructor TDriverRequest.Create(Var ARequest:REQUEST_HEADER);
begin
Inherited Create;
FDriverObject := ARequest.Driver;
FDriverName := '';
FDeviceObject := ARequest.Device;
FDeviceName := '';
FTime := ARequest.Time;
FRequestType := ARequest.RequestType;
FResultType := ARequest.ResultType;
FResultValue := NativeUInt(ARequest.Other);
FProcessId := ARequest.ProcessId;
FThreadId := ARequest.ThreadId;
FIRQL := ARequest.Irql;
end;

Procedure TDriverRequest.SetDriverName(AName:WideString);
begin
FDriverName := AName;
end;

Procedure TDriverRequest.SetDeviceName(AName:WideString);
begin
FDeviceName := AName;
end;

Function TDriverRequest.GetColumn(AColumnType:ERequestListModelColumnType; Var AResult:WideString):Boolean;
Var
  s : SYSTEMTIME;
begin
Result := True;
Case AColumnType Of
  rlmctTime : begin
    FileTimeToSystemTime(FILETIME(FTime), s);
    AResult := DateTimeToStr(SystemTimeToDateTime(s));
    end;
  rlmctRequestType: AResult := RequestTypeToString(FRequestType);
  rlmctDeviceObject: AResult := Format('0x%p', [FDeviceObject]);
  rlmctDeviceName: AResult := FDeviceName;
  rlmctDriverObject: AResult := Format('0x%p', [FDriverObject]);
  rlmctDriverName: AResult := FDriverName;
  rlmctResult: AResult := RequestResultToString(FResultValue, FResultType);
  rlmctProcessId : AResult := Format('%u', [FProcessId]);
  rlmctThreadId :  AResult := Format('%u', [FThreadId]);
  rlmctIRQL : AResult := IRQLToString(FIRQL);
  Else Result := False;
  end;
end;

Class Function TDriverRequest.IOCTLToString(AControlCode:Cardinal):WideString;
begin
Result := TablesIOCTLToString(AControlCode);
end;

Class Function TDriverRequest.MajorFunctionToString(AMajor:Byte):WideString;
begin
Case AMajor Of
  0 : Result := 'Create';
  1 : Result := 'CreateNamedPipe';
  2 : Result := 'Close';
  3 : Result := 'Read';
  4 : Result := 'Write';
  5 : Result := 'Query';
  6 : Result := 'Set';
  7 : Result := 'QueryEA';
  8 : Result := 'SetEA';
  9 : Result := 'Flush';
  10 : Result := 'QueryVolume';
  11 : Result := 'SetVolume';
  12 : Result := 'DirectoryControl';
  13 : Result := 'FSControl';
  14 : Result := 'DeviceControl';
  15 : Result := 'InternalDeviceControl';
  16 : Result := 'Shutdown';
  17 : Result := 'Lock';
  18 : Result := 'Cleanup';
  19 : Result := 'CreateMailslot';
  20 : Result := 'QuerySecurity';
  21 : Result := 'SetSecurity';
  22 : Result := 'Power';
  23 : Result := 'SystemControl';
  24 : Result := 'DeviceChange';
  25 : Result := 'QueryQuota';
  26 : Result := 'SetQuota';
  27 : Result := 'PnP';
  Else Result := Format('0x%x>', [AMajor]);
  end;
end;

Class Function TDriverRequest.MinorFunctionToString(AMajor:Byte; AMinor:Byte):WideString;
begin
Result := '';
If AMajor = 27 Then
  begin
  Case AMinor Of
    0 : Result := 'Start';
    1 : Result := 'QueryRemove';
    2 : Result := 'Remove';
    3 : Result := 'CancelRemove';
    4 : Result := 'Stop';
    5 : Result := 'QueryStop';
    6 : Result := 'CancelStop ';
    7 : Result := 'QueryRelations';
    8 : Result := 'QueryInterface';
    9 : Result := 'QueryCapabilities';
    10 : Result := 'QueryResources';
    11 : Result := 'QueryResourceRequirements';
    12 : Result := 'QueryDeviceText';
    13 : Result := 'FilterResourceRequirements';
    15 : Result := 'ReadConfig';
    16 : Result := 'WriteConfig';
    17 : Result := 'Eject';
    18 : Result := 'SetLock';
    19 : Result := 'QueryId';
    20 : Result := 'QueryState';
    21 : Result := 'QueryBusInfo';
    22 : Result := 'UsageNotifications';
    23 : Result := 'SurpriseRemoval';
    25 : Result := 'Enumerated';
    Else Result := Format('0x%x', [AMinor]);
    end;
  end
Else If AMajor = 22 Then
  begin
  Case AMinor Of
    0 : Result := 'WaitWake';
    1 : Result := 'PowerSequence';
    2 : Result := 'SetPower';
    3 : Result := 'QueryPower';
    end;
  end
Else If AMajor = 23 Then
  begin
  Case AMinor Of
    0 : Result := 'QueryAllData';
    1 : Result := 'QuerySingleInstance';
    2 : Result := 'ChangeSingleInstance';
    3 : Result := 'ChangeSingleItem';
    4 : Result := 'EnableEvents';
    5 : Result := 'DisableEvents';
    6 : Result := 'EnableCollection';
    7 : Result := 'DisableCollection';
    8 : Result := 'RegInfo';
    9 : Result := 'Execute';
    11 : Result := 'RegInfoEx';
    Else Result := Format('0x%x', [AMinor]);
    end;
  end
Else If AMajor = 12 Then
  begin
  Case AMinor Of
    1 : Result := 'QueryDirectory';
    2 : Result := 'ChangeNotify';
    Else Result := Format('0x%x', [AMinor]);
    end;
  end
Else If AMajor = 13 Then
  begin
  Case AMinor Of
    0 : Result := 'UserRequest';
    1 : Result := 'MountVolume';
    2 : Result := 'VerifyVolume';
    3 : Result := 'LoadFS';
    4 : Result := 'KernelCall';
    Else Result := Format('0x%x', [AMinor]);
    end;
  end
Else If AMajor = 17 Then
  begin
  Case AMinor Of
    1 : Result := 'Lock';
    2 : Result := 'UnlockSingle';
    3 : Result := 'UnlockAll';
    4 : Result := 'UnlockAllByKey';
    Else Result := Format('0x%x', [AMinor]);
    end;
  end
Else If AMajor = 9 Then
  begin
  Case AMinor Of
    1 : Result := 'FlushAndPurge';
    2 : Result := 'DataOnly';
    3 : Result := 'NoSync';
    Else Result := Format('0x%x', [AMinor]);
    end;
  end
Else If (AMajor = 3) Or (AMajor = 4) Then
  begin
  If ((AMinor And 1) <> 0) Then
    Result := Result + ',Dpc';

  If ((AMinor And 2) <> 0) Then
    Result := Result + ',Mdl';

  If ((AMinor And 3) <> 0) Then
    Result := Result + ',Complete';

  If ((AMinor And 4) <> 0) Then
    Result := Result + ',Compressed';

  If Result = '' Then
    Result := 'Normal'
  Else Delete(Result, 1, 1);
  end;
end;

Class Function TDriverRequest.RequestTypeToString(ARequestType:ERequestType):WideString;
begin
Case ARequestType Of
  ertIRP: Result := 'IRP';
  ertIRPCompletion: Result := 'IRPComp';
  ertAddDevice: Result := 'AddDevice';
  ertDriverUnload: Result := 'Unload';
  ertFastIo: Result := 'FastIo';
  ertStartIo: Result := 'StartIo';
  Else Result := Format('<unknown> (%u)', [Ord(ARequestType)]);
  end;
end;

Class Function TDriverRequest.RequestResultToString(AResult:NativeUInt; AResultType:ERequestResultType):WideString;
begin
Case AResultType Of
  rrtUndefined: Result := 'None';
  rrtNTSTATUS: Result := Format('%s (0x%x)', [NTSTATUSToString(AResult), AResult]);
  rrtBOOLEAN: begin
    If AResult <> 0 Then
      Result := 'TRUE'
    Else Result := 'FALSE';
    end;
  Else Result := '';
  end;
end;

Class Function TDriverRequest.NTSTATUSToString(AValue:Cardinal):WideString;
begin
Result := TablesNTSTATUSToString(AValue);
end;

Class Function TDriverRequest.IRQLToString(AValue:Byte):WideString;
begin
Result := Format('%u', [AValue]);
Case AValue Of
  0 : Result := 'Passive';
  1 : Result := 'APC';
  2 : Result := 'Dispatch';
{$IFDEF WIN32}
  27 : Result := 'Profile';
  28 : Result := 'Clock';
  29 : Result := 'IPI';
  30 : Result := 'Power';
  31 : Result := 'High';
{$ELSE}
  13 : Result := 'Clock';
  14 : Result := 'Profile, IPI, Power';
  15 : Result := 'High';
{$ENDIF}
 Else Result := 'Interrupt';
  end;
end;

Class Function TDriverRequest.AccessModeToString(AMode:Byte):WideString;
begin
Case AMode Of
  0 : Result := 'KernelMode';
  1 : Result := 'UserMode';
  Else Result := Format('<unknown> (%u)', [AMode]);
  end;
end;


(** TDriverUnloadRequest **)

Constructor TDriverUnloadRequest.Create(Var ARequest:REQUEST_UNLOAD);
begin
Inherited Create(ARequest.Header);
end;

(** TAddDeviceRequest **)

Constructor TAddDeviceRequest.Create(Var ARequest:REQUEST_ADDDEVICE);
begin
Inherited Create(ARequest.Header);
end;


(** TIRPCompleteRequest **)

Constructor TIRPCompleteRequest.Create(Var ARequest:REQUEST_IRP_COMPLETION);
begin
Inherited Create(ARequest.Header);
FIRPAddress := ARequest.IRPAddress;
FIOSBStatus := ARequest.CompletionStatus;
FIOSBInformation := ARequest.CompletionInformation;
end;

Function TIRPCompleteRequest.GetColumn(AColumnType:ERequestListModelColumnType; Var AResult:WideString):Boolean;
begin
Result := True;
Case AColumnType Of
  rlmctIRPAddress: AResult := Format('0x%p', [FIRPAddress]);
  rlmctIOSBStatus : AResult := Format('%s (0x%x)', [NTSTATUSToString(FIOSBStatus), FIOSBStatus]);
  rlmctIOSBInformation : AResult := Format('0x%p', [Pointer(IOSBInformation)]);
  Else Result := Inherited GetColumn(AColumnType, AResult);
  end;
end;

(** TFastIoRequest **)

Constructor TFastIoRequest.Create(Var ARequest:REQUEST_FASTIO);
begin
Inherited Create(ARequest.Header);
end;

(** TStartIoRequest **)

Constructor TStartIoRequest.Create(Var ARequest:REQUEST_STARTIO);
begin
Inherited Create(ARequest.Header);
end;

(** TRequestListModel **)

Function TRequestListModel.GetColumn(AItem:TDriverRequest; ATag:NativeUInt):WideString;
begin
Result := '';
AItem.GetColumn(ERequestListModelColumnType(ATag), Result);
end;

Procedure TRequestListModel.FreeItem(AItem:TDriverRequest);
begin
AItem.Free;
end;

Function TRequestListModel._Item(AIndex:Integer):TDriverRequest;
begin
Result := FRequests[AIndex];
end;

Function TRequestListModel.RowCount : Cardinal;
begin
Result := FRequests.Count;
end;

Function TRequestListModel.Update:Cardinal;
Var
  dr : TDriverRequest;
  rq : REQUEST_GENERAL;
  deviceName : WideString;
  driverName : WideString;
begin
Result := ERROR_SUCCESS;
Repeat
Result := IRPMonDllGetRequest(@rq.Header, SizeOf(rq));
If Result = ERROR_SUCCESS Then
  begin
  Case rq.Header.RequestType Of
    ertUndefined: ;
    ertIRP: dr := TIRPRequest.Build(rq.Irp);
    ertIRPCompletion: dr := TIRPCompleteRequest.Create(rq.IrpComplete);
    ertAddDevice: dr := TAddDeviceRequest.Create(rq.AddDevice);
    ertDriverUnload: dr := TDriverUnloadRequest.Create(rq.DriverUnload);
    ertFastIo: dr := TFastIoRequest.Create(rq.FastIo);
    ertStartIo: dr := TStartIoRequest.Create(rq.StartIo);
    Else dr := TDriverRequest.Create(rq.Header);
    end;

  If FDriverMap.TryGetValue(dr.DriverObject, driverName) Then
    dr.DriverName := driverName;

  If FDeviceMap.TryGetValue(dr.DeviceObject, deviceName) Then
    dr.DeviceName := deviceName;

  FRequests.Add(dr);
  end;

Until Result <> ERROR_SUCCESS;
If Result = ERROR_NO_MORE_ITEMS Then
  begin
  Inherited Update;
  Result := ERROR_SUCCESS;
  end;
end;

Function TRequestListModel.RefreshMaps:Cardinal;
Var
  I, J : Integer;
  count : Cardinal;
  pdri : PPIRPMON_DRIVER_INFO;
  dri : PIRPMON_DRIVER_INFO;
  tmp : PPIRPMON_DRIVER_INFO;
  pdei : PPIRPMON_DEVICE_INFO;
  dei : PIRPMON_DEVICE_INFO;
begin
Result := IRPMonDllSnapshotRetrieve(pdri, count);
If Result = ERROR_SUCCESS Then
  begin
  FDriverMap.Clear;
  FDeviceMap.Clear;
  tmp := pdri;
  For I := 0 To count - 1 Do
    begin
    dri := tmp^;
    FDriverMap.Add(dri.DriverObject, Copy(WideString(dri.DriverName), 1, Length(WideString(dri.DriverName))));
    pdei := dri.Devices;
    For J := 0 To dri.DeviceCount - 1 Do
      begin
      dei := pdei^;
      FDeviceMap.Add(dei.DeviceObject, Copy(WideString(dei.Name), 1, Length(WideString(dei.Name))));
      Inc(pdei);
      end;

    Inc(tmp);
    end;

  IRPMonDllSnapshotFree(pdri, count);
  end;
end;

Procedure TRequestListModel.Clear;
Var
  dr : TDriverRequest;
begin
Inherited Clear;
For dr In FRequests Do
  dr.Free;

FRequests.Clear;
end;


Constructor TRequestListModel.Create;
begin
Inherited Create(Nil);
FRequests := TList<TDriverRequest>.Create;
FDriverMap := TDictionary<Pointer, WideString>.Create;
FDeviceMap := TDictionary<Pointer, WideString>.Create;
RefreshMaps;
end;

Destructor TRequestListModel.Destroy;
begin
FDriverMap.Free;
FDeviceMap.Free;
Clear;
FRequests.Free;
Inherited Destroy;
end;


End.
