USING: accessors alien alien.c-types alien.strings arrays
assocs byte-arrays combinators continuations game-input
game-input.dinput.keys-array io.encodings.utf16
io.encodings.utf16n kernel locals math math.bitwise
math.rectangles namespaces parser sequences shuffle
struct-arrays ui.backend.windows vectors windows.com
windows.dinput windows.dinput.constants windows.errors
windows.kernel32 windows.messages windows.ole32
windows.user32 ;
IN: game-input.dinput
CONSTANT: MOUSE-BUFFER-SIZE 16

SINGLETON: dinput-game-input-backend

dinput-game-input-backend game-input-backend set-global

SYMBOLS: +dinput+ +keyboard-device+ +keyboard-state+
    +controller-devices+ +controller-guids+
    +device-change-window+ +device-change-handle+
    +mouse-device+ +mouse-state+ +mouse-buffer+ ;

: create-dinput ( -- )
    f GetModuleHandle DIRECTINPUT_VERSION IDirectInput8W-iid
    f <void*> [ f DirectInput8Create ole32-error ] keep *void*
    +dinput+ set-global ;

: delete-dinput ( -- )
    +dinput+ [ com-release f ] change-global ;

: device-for-guid ( guid -- device )
    +dinput+ get swap f <void*>
    [ f IDirectInput8W::CreateDevice ole32-error ] keep *void* ;

: set-coop-level ( device -- )
    +device-change-window+ get DISCL_BACKGROUND DISCL_NONEXCLUSIVE bitor
    IDirectInputDevice8W::SetCooperativeLevel ole32-error ;

: set-data-format ( device format-symbol -- )
    get IDirectInputDevice8W::SetDataFormat ole32-error ;

: <buffer-size-diprop> ( size -- DIPROPDWORD )
    "DIPROPDWORD" <c-object>
        "DIPROPDWORD" heap-size over set-DIPROPHEADER-dwSize
        "DIPROPHEADER" heap-size over set-DIPROPHEADER-dwHeaderSize
        0 over set-DIPROPHEADER-dwObj
        DIPH_DEVICE over set-DIPROPHEADER-dwHow
        swap over set-DIPROPDWORD-dwData ;

: set-buffer-size ( device size -- )
    DIPROP_BUFFERSIZE swap <buffer-size-diprop>
    IDirectInputDevice8W::SetProperty ole32-error ;

: configure-keyboard ( keyboard -- )
    [ c_dfDIKeyboard_HID set-data-format ] [ set-coop-level ] bi ;
: configure-mouse ( mouse -- )
    [ c_dfDIMouse2 set-data-format ]
    [ MOUSE-BUFFER-SIZE set-buffer-size ]
    [ set-coop-level ] tri ;
: configure-controller ( controller -- )
    [ c_dfDIJoystick2 set-data-format ] [ set-coop-level ] bi ;

: find-keyboard ( -- )
    GUID_SysKeyboard device-for-guid
    [ configure-keyboard ]
    [ +keyboard-device+ set-global ] bi
    256 <byte-array> <keys-array> keyboard-state boa
    +keyboard-state+ set-global ;

: find-mouse ( -- )
    GUID_SysMouse device-for-guid
    [ configure-mouse ]
    [ +mouse-device+ set-global ] bi
    0 0 0 0 8 f <array> mouse-state boa
    +mouse-state+ set-global
    MOUSE-BUFFER-SIZE "DIDEVICEOBJECTDATA" <c-array>
    +mouse-buffer+ set-global ;

: device-info ( device -- DIDEVICEIMAGEINFOW )
    "DIDEVICEINSTANCEW" <c-object>
    "DIDEVICEINSTANCEW" heap-size over set-DIDEVICEINSTANCEW-dwSize
    [ IDirectInputDevice8W::GetDeviceInfo ole32-error ] keep ;
: device-caps ( device -- DIDEVCAPS )
    "DIDEVCAPS" <c-object>
    "DIDEVCAPS" heap-size over set-DIDEVCAPS-dwSize
    [ IDirectInputDevice8W::GetCapabilities ole32-error ] keep ;

: <guid> ( memory -- byte-array )
    "GUID" heap-size memory>byte-array ;

: device-guid ( device -- guid )
    device-info DIDEVICEINSTANCEW-guidInstance <guid> ;

: device-attached? ( device -- ? )
    +dinput+ get swap device-guid
    IDirectInput8W::GetDeviceStatus S_OK = ;

: find-device-axes-callback ( -- alien )
    [ ! ( lpddoi pvRef -- BOOL )
        +controller-devices+ get at
        swap DIDEVICEOBJECTINSTANCEW-guidType <guid> {
            { [ dup GUID_XAxis = ] [ drop 0.0 >>x ] }
            { [ dup GUID_YAxis = ] [ drop 0.0 >>y ] }
            { [ dup GUID_ZAxis = ] [ drop 0.0 >>z ] }
            { [ dup GUID_RxAxis = ] [ drop 0.0 >>rx ] }
            { [ dup GUID_RyAxis = ] [ drop 0.0 >>ry ] }
            { [ dup GUID_RzAxis = ] [ drop 0.0 >>rz ] }
            { [ dup GUID_Slider = ] [ drop 0.0 >>slider ] }
            [ drop ]
        } cond drop
        DIENUM_CONTINUE
    ] LPDIENUMDEVICEOBJECTSCALLBACKW ;

: find-device-axes ( device controller-state -- controller-state )
    swap [ +controller-devices+ get set-at ] 2keep
    find-device-axes-callback over DIDFT_AXIS
    IDirectInputDevice8W::EnumObjects ole32-error ;

: controller-state-template ( device -- controller-state )
    controller-state new
    over device-caps
    [ DIDEVCAPS-dwButtons f <array> >>buttons ]
    [ DIDEVCAPS-dwPOVs zero? f pov-neutral ? >>pov ] bi
    find-device-axes ;

: device-known? ( guid -- ? )
    +controller-guids+ get key? ; inline

: (add-controller) ( guid -- )
    device-for-guid {
        [ configure-controller ]
        [ controller-state-template ]
        [ dup device-guid +controller-guids+ get set-at ]
        [ +controller-devices+ get set-at ]
    } cleave ;

: add-controller ( guid -- )
    dup <guid> device-known? [ drop ] [ (add-controller) ] if ;

: remove-controller ( device -- )
    [ +controller-devices+ get delete-at ]
    [ device-guid +controller-guids+ get delete-at ]
    [ com-release ] tri ;

: find-controller-callback ( -- alien )
    [ ! ( lpddi pvRef -- BOOL )
        drop DIDEVICEINSTANCEW-guidInstance add-controller
        DIENUM_CONTINUE
    ] LPDIENUMDEVICESCALLBACKW ;

: find-controllers ( -- )
    +dinput+ get DI8DEVCLASS_GAMECTRL find-controller-callback
    f DIEDFL_ATTACHEDONLY IDirectInput8W::EnumDevices ole32-error ;

: set-up-controllers ( -- )
    4 <vector> +controller-devices+ set-global
    4 <vector> +controller-guids+ set-global
    find-controllers ;

: find-and-remove-detached-devices ( -- )
    +controller-devices+ get keys
    [ device-attached? not ] filter
    [ remove-controller ] each ;

: device-interface? ( dbt-broadcast-hdr -- ? )
    DEV_BROADCAST_HDR-dbch_devicetype DBT_DEVTYP_DEVICEINTERFACE = ;

: device-arrived ( dbt-broadcast-hdr -- )
    device-interface? [ find-controllers ] when ;

: device-removed ( dbt-broadcast-hdr -- )
    device-interface? [ find-and-remove-detached-devices ] when ;

: handle-wm-devicechange ( hWnd uMsg wParam lParam -- )
    [ 2drop ] 2dip swap {
        { [ dup DBT_DEVICEARRIVAL = ]         [ drop <alien> device-arrived ] }
        { [ dup DBT_DEVICEREMOVECOMPLETE = ]  [ drop <alien> device-removed ] }
        [ 2drop ]
    } cond ;

TUPLE: window-rect < rect window-loc ;
: <zero-window-rect> ( -- window-rect )
    window-rect new
    { 0 0 } >>window-loc
    { 0 0 } >>loc
    { 0 0 } >>dim ;

: (device-notification-filter) ( -- DEV_BROADCAST_DEVICEW )
    "DEV_BROADCAST_DEVICEW" <c-object>
    "DEV_BROADCAST_DEVICEW" heap-size over set-DEV_BROADCAST_DEVICEW-dbcc_size
    DBT_DEVTYP_DEVICEINTERFACE over set-DEV_BROADCAST_DEVICEW-dbcc_devicetype ;

: create-device-change-window ( -- )
    <zero-window-rect> WS_OVERLAPPEDWINDOW 0 create-window
    [
        (device-notification-filter)
        DEVICE_NOTIFY_WINDOW_HANDLE DEVICE_NOTIFY_ALL_INTERFACE_CLASSES bitor
        RegisterDeviceNotification
        +device-change-handle+ set-global
    ]
    [ +device-change-window+ set-global ] bi ;

: close-device-change-window ( -- )
    +device-change-handle+ [ UnregisterDeviceNotification drop f ] change-global
    +device-change-window+ [ DestroyWindow win32-error=0/f f ] change-global ;

: add-wm-devicechange ( -- )
    [ 4dup handle-wm-devicechange DefWindowProc ]
    WM_DEVICECHANGE add-wm-handler ;

: remove-wm-devicechange ( -- )
    WM_DEVICECHANGE wm-handlers get-global delete-at ;

: release-controllers ( -- )
    +controller-devices+ [ [ drop com-release ] assoc-each f ] change-global
    f +controller-guids+ set-global ;

: release-keyboard ( -- )
    +keyboard-device+ [ com-release f ] change-global
    f +keyboard-state+ set-global ;

: release-mouse ( -- )
    +mouse-device+ [ com-release f ] change-global
    f +mouse-state+ set-global ;

M: dinput-game-input-backend (open-game-input)
    create-dinput
    create-device-change-window
    find-keyboard
    find-mouse
    set-up-controllers
    add-wm-devicechange ;

M: dinput-game-input-backend (close-game-input)
    remove-wm-devicechange
    release-controllers
    release-mouse
    release-keyboard
    close-device-change-window
    delete-dinput ;

M: dinput-game-input-backend (reset-game-input)
    {
        +dinput+ +keyboard-device+ +keyboard-state+
        +controller-devices+ +controller-guids+
        +device-change-window+ +device-change-handle+
    } [ f swap set-global ] each ;

M: dinput-game-input-backend get-controllers
    +controller-devices+ get
    [ drop controller boa ] { } assoc>map ;

M: dinput-game-input-backend product-string
    handle>> device-info DIDEVICEINSTANCEW-tszProductName
    utf16n alien>string ;

M: dinput-game-input-backend product-id
    handle>> device-info DIDEVICEINSTANCEW-guidProduct <guid> ;
M: dinput-game-input-backend instance-id
    handle>> device-guid ;

:: with-acquisition ( device acquired-quot succeeded-quot failed-quot -- result/f )
    device IDirectInputDevice8W::Acquire succeeded? [
        device acquired-quot call
        succeeded-quot call
    ] failed-quot if ; inline

CONSTANT: pov-values
    {
        pov-up pov-up-right pov-right pov-down-right
        pov-down pov-down-left pov-left pov-up-left
    }

: >axis ( long -- float )
    32767 - 32767.0 /f ;
: >slider ( long -- float )
    65535.0 /f ;
: >pov ( long -- symbol )
    dup HEX: FFFF bitand HEX: FFFF =
    [ drop pov-neutral ]
    [ 2750 + 4500 /i pov-values nth ] if ;
: >buttons ( alien length -- array )
    memory>byte-array <keys-array> ;

: (fill-if) ( controller-state DIJOYSTATE2 ? quot -- )
    [ drop ] compose [ 2drop ] if ; inline

: fill-controller-state ( controller-state DIJOYSTATE2 -- controller-state )
    {
        [ over x>> [ DIJOYSTATE2-lX >axis >>x ] (fill-if) ]
        [ over y>> [ DIJOYSTATE2-lY >axis >>y ] (fill-if) ]
        [ over z>> [ DIJOYSTATE2-lZ >axis >>z ] (fill-if) ]
        [ over rx>> [ DIJOYSTATE2-lRx >axis >>rx ] (fill-if) ]
        [ over ry>> [ DIJOYSTATE2-lRy >axis >>ry ] (fill-if) ]
        [ over rz>> [ DIJOYSTATE2-lRz >axis >>rz ] (fill-if) ]
        [ over slider>> [ DIJOYSTATE2-rglSlider *long >slider >>slider ] (fill-if) ]
        [ over pov>> [ DIJOYSTATE2-rgdwPOV *uint >pov >>pov ] (fill-if) ]
        [ DIJOYSTATE2-rgbButtons over buttons>> length >buttons >>buttons ]
    } 2cleave ;

: read-device-buffer ( device buffer count -- buffer count' )
    [ "DIDEVICEOBJECTDATA" heap-size ] 2dip <uint>
    [ 0 IDirectInputDevice8W::GetDeviceData ole32-error ] 2keep *uint ;

: (fill-mouse-state) ( state DIDEVICEOBJECTDATA -- state )
    [ DIDEVICEOBJECTDATA-dwData 32 >signed ] [ DIDEVICEOBJECTDATA-dwOfs ] bi {
        { DIMOFS_X [ [ + ] curry change-dx ] }
        { DIMOFS_Y [ [ + ] curry change-dy ] }
        { DIMOFS_Z [ [ + ] curry change-scroll-dy ] }
        [ [ c-bool> ] [ DIMOFS_BUTTON0 - ] bi* rot [ buttons>> set-nth ] keep ]
    } case ;

: fill-mouse-state ( buffer count -- state )
    [ +mouse-state+ get ] 2dip swap
    [ "DIDEVICEOBJECTDATA" byte-array>struct-array nth (fill-mouse-state) ] curry each ;

: get-device-state ( device byte-array -- )
    [ dup IDirectInputDevice8W::Poll ole32-error ] dip
    [ length ] keep
    IDirectInputDevice8W::GetDeviceState ole32-error ;

: (read-controller) ( handle template -- state )
    swap [ "DIJOYSTATE2" heap-size <byte-array> [ get-device-state ] keep ]
    [ fill-controller-state ] [ drop f ] with-acquisition ;

M: dinput-game-input-backend read-controller
    handle>> dup +controller-devices+ get at
    [ (read-controller) ] [ drop f ] if* ;

M: dinput-game-input-backend calibrate-controller
    handle>> f 0 IDirectInputDevice8W::RunControlPanel ole32-error ;

M: dinput-game-input-backend read-keyboard
    +keyboard-device+ get
    [ +keyboard-state+ get [ keys>> underlying>> get-device-state ] keep ]
    [ ] [ f ] with-acquisition ;

M: dinput-game-input-backend read-mouse
    +mouse-device+ get [ +mouse-buffer+ get MOUSE-BUFFER-SIZE read-device-buffer ]
    [ fill-mouse-state ] [ f ] with-acquisition ;

M: dinput-game-input-backend reset-mouse
    +mouse-device+ get [ f MOUSE-BUFFER-SIZE read-device-buffer ]
    [ 2drop ] [ ] with-acquisition
    +mouse-state+ get
        0 >>dx
        0 >>dy
        0 >>scroll-dx
        0 >>scroll-dy
        drop ;