unit AviUtl2FilterTypes;

{$ALIGN 8}

interface

uses
  Winapi.Windows;

type
  LPCWSTR = PWideChar;
  OBJECT_HANDLE = Pointer;

  PEDIT_SECTION = ^TEDIT_SECTION;
  TSetObjectItemValueFunc = function(Obj: OBJECT_HANDLE; Effect: LPCWSTR;
    Item: LPCWSTR; Value: PAnsiChar): LongBool; cdecl;
  TGetFocusObjectFunc = function: OBJECT_HANDLE; cdecl;
  TEDIT_SECTION = record
    Info: Pointer;
    CreateObjectFromAlias: Pointer;
    FindObject: Pointer;
    CountObjectEffect: Pointer;
    GetObjectLayerFrame: Pointer;
    GetObjectAlias: Pointer;
    GetObjectItemValue: Pointer;
    SetObjectItemValue: TSetObjectItemValueFunc;
    MoveObject: Pointer;
    DeleteObject: Pointer;
    GetFocusObject: TGetFocusObjectFunc;
  end;

  PFILTER_ITEM_TRACK = ^TFILTER_ITEM_TRACK;
  TFILTER_ITEM_TRACK = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Value: Double;
    S, E: Double;
    Step: Double;
  end;
  PFILTER_ITEM_CHECK = ^TFILTER_ITEM_CHECK;
  TFILTER_ITEM_CHECK = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Value: Byte;
  end;
  PFILTER_ITEM_COLOR = ^TFILTER_ITEM_COLOR;
  TFILTER_ITEM_COLOR = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    B, G, R, X: Byte;
  end;
  PFILTER_ITEM_SELECT = ^TFILTER_ITEM_SELECT;
  TFILTER_ITEM_SELECT_ITEM = record
    Name: LPCWSTR;
    Value: Integer;
  end;
  TFILTER_ITEM_SELECT = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Value: Integer;
    List: ^TFILTER_ITEM_SELECT_ITEM;
  end;
  PFILTER_ITEM_FILE = ^TFILTER_ITEM_FILE;
  TFILTER_ITEM_FILE = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Value: LPCWSTR;
    FileFilter: LPCWSTR;
  end;
  PFILTER_ITEM_DATA = ^TFILTER_ITEM_DATA;
  TFILTER_ITEM_DATA = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Value: Pointer;
    Size: Integer;
    DefaultValue: Pointer;
  end;
  PFILTER_ITEM_GROUP = ^TFILTER_ITEM_GROUP;
  TFILTER_ITEM_GROUP = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    DefaultVisible: Byte;
  end;
  PFILTER_ITEM_STRING = ^TFILTER_ITEM_STRING;
  TFILTER_ITEM_STRING = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Value: LPCWSTR;
  end;
  PFILTER_ITEM_TEXT = ^TFILTER_ITEM_TEXT;
  TFILTER_ITEM_TEXT = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Value: LPCWSTR;
  end;
  PFILTER_ITEM_FOLDER = ^TFILTER_ITEM_FOLDER;
  TFILTER_ITEM_FOLDER = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Value: LPCWSTR;
  end;
  TFILTER_ITEM_BUTTON_CALLBACK = procedure(Edit: PEDIT_SECTION); cdecl;
  PFILTER_ITEM_BUTTON = ^TFILTER_ITEM_BUTTON;
  TFILTER_ITEM_BUTTON = record
    ItemType: LPCWSTR;
    Name: LPCWSTR;
    Callback: TFILTER_ITEM_BUTTON_CALLBACK;
  end;

  PSCENE_INFO = ^TSCENE_INFO;
  TSCENE_INFO = record
    Width, Height: Integer;
    Rate, Scale: Integer;
    SampleRate: Integer;
  end;
  POBJECT_INFO = ^TOBJECT_INFO;
  TOBJECT_INFO = record
    ID: Int64;
    Frame: Integer;
    FrameTotal: Integer;
    Time: Double;
    TimeTotal: Double;
    Width, Height: Integer;
    SampleIndex: Int64;
    SampleTotal: Int64;
    SampleNum: Integer;
    ChannelNum: Integer;
    EffectID: Int64;
    Flag: Integer;
    Layer: Integer;
    Index: Integer;
    Num: Integer;
    FrameS: Integer;
    FrameE: Integer;
    EffectLayer: Integer;
  end;
  POBJECT_IMAGE_PARAM = ^TOBJECT_IMAGE_PARAM;
  TOBJECT_IMAGE_PARAM = record
    X, Y, Z: Single;
    RX, RY, RZ: Single;
    SX, SY, SZ: Single;
    CX, CY, CZ: Single;
    Alpha: Single;
  end;

  PIXEL_RGBA = packed record
    R, G, B, A: Byte;
  end;
  PPIXEL_RGBA = ^PIXEL_RGBA;
  PID3D11Texture2D = Pointer;
  TFILTER_PROC_VIDEO_GET_TEX2D = function: PID3D11Texture2D; cdecl;
  TFILTER_PROC_VIDEO_GET_OUTPUT_IMAGE_PARAM = function(Obj: OBJECT_HANDLE;
    Offset: Double; Param: POBJECT_IMAGE_PARAM; ParamSize: Integer): Byte; cdecl;
  TFILTER_PROC_VIDEO_GET_IMAGE_OBJECT = function(Layer: Integer;
    Offset: Double): OBJECT_HANDLE; cdecl;
  PFILTER_PROC_VIDEO = ^TFILTER_PROC_VIDEO;
  TFILTER_PROC_VIDEO = record
    Scene: PSCENE_INFO;
    Object_: POBJECT_INFO;
    GetImageData: procedure(Buffer: PPIXEL_RGBA); cdecl;
    SetImageData: procedure(Buffer: PPIXEL_RGBA; Width, Height: Integer); cdecl;
    GetImageTexture2D: TFILTER_PROC_VIDEO_GET_TEX2D;
    GetFramebufferTexture2D: TFILTER_PROC_VIDEO_GET_TEX2D;
    Edit: PEDIT_SECTION;
    Param: POBJECT_IMAGE_PARAM;
    GetOutputImageParam: TFILTER_PROC_VIDEO_GET_OUTPUT_IMAGE_PARAM;
    GetImageObject: TFILTER_PROC_VIDEO_GET_IMAGE_OBJECT;
  end;
  PFILTER_PROC_AUDIO = ^TFILTER_PROC_AUDIO;
  TFILTER_PROC_AUDIO = record
    Scene: PSCENE_INFO;
    Object_: POBJECT_INFO;
    GetSampleData: procedure(Buffer: PSingle; Channel: Integer); cdecl;
    SetSampleData: procedure(Buffer: PSingle; Channel: Integer); cdecl;
  end;
  TFuncProcVideo = function(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
  TFuncProcAudio = function(Audio: PFILTER_PROC_AUDIO): Byte; cdecl;
  PFILTER_PLUGIN_TABLE = ^TFILTER_PLUGIN_TABLE;
  TFILTER_PLUGIN_TABLE = record
    Flag: Integer;
    Name: LPCWSTR;
    Label_: LPCWSTR;
    Information: LPCWSTR;
    Items: ^Pointer;
    Func_Proc_Video: TFuncProcVideo;
    Func_Proc_Audio: TFuncProcAudio;
  end;

const
  FILTER_FLAG_VIDEO = 1;
  FILTER_FLAG_AUDIO = 2;
  FILTER_FLAG_INPUT = 4;
  FILTER_FLAG_FILTER = 8;
  OBJECT_FLAG_FILTER_OBJECT = 1;

implementation

end.
