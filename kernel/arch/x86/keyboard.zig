pub const Scancode = enum(u8) {
    // Unknown  = 0x00

    // Escape
    EscPressed = 0x01,

    // Digits
    OnePressed = 0x02,
    TwoPressed = 0x03,
    ThreePressed = 0x04,
    FourPressed = 0x05,
    FivePressed = 0x06,
    SixPressed = 0x07,
    SevenPressed = 0x08,
    EightPressed = 0x09,
    NinePressed = 0x0a,
    ZeroPressed = 0x0b,

    // Unknown 0x0c

    EqualsPressed = 0x0d,
    BackspacePressed = 0x0e,
    TabPressed = 0x0f,

    // First row
    QPressed = 0x10,
    WPressed = 0x11,
    EPressed = 0x12,
    RPressed = 0x13,
    TPressed = 0x14,
    YPressed = 0x15,
    UPressed = 0x16,
    IPressed = 0x17,
    OPressed = 0x18,
    PPressed = 0x19,
    LBracePressed = 0x1a,
    RBracePressed = 0x1b,

    EnterPressed = 0x1c,
    LControlPressed = 0x1d,

    // Second row
    APressed = 0x1e,
    SPressed = 0x1f,
    DPressed = 0x20,
    FPressed = 0x21,
    GPressed = 0x22,
    HPressed = 0x23,
    JPressed = 0x24,
    KPressed = 0x25,
    LPressed = 0x26,
    SemicolonPressed = 0x27,
    SinglequotePressed = 0x28,
    BacktickPressed = 0x29,

    // Third row
    LShiftPressed = 0x2a,
    BackslashPressed = 0x2b,
    ZPressed = 0x2c,
    XPressed = 0x2d,
    CPressed = 0x2e,
    VPressed = 0x2f,
    BPressed = 0x30,
    NPressed = 0x31,
    MPressed = 0x32,
    CommaPressed = 0x33,
    DotPressed = 0x34,
    SlashPressed = 0x35,

    RShiftPressed = 0x36,
    KeypadMulPressed = 0x37,
    LAltPressed = 0x38,
    SpacePressed = 0x39,
    CapsLockPressed = 0x3a,

    // Function keys

    F1Pressed = 0x3b,
    F2Pressed = 0x3c,
    F3Pressed = 0x3d,
    F4Pressed = 0x3e,
    F5Pressed = 0x3f,
    F6Pressed = 0x40,
    F7Pressed = 0x41,
    F8Pressed = 0x42,
    F9Pressed = 0x43,
    F10Pressed = 0x44,

    // Keypad

    NumLockPressed = 0x45,
    ScrollLockPressed = 0x46,

    Keypad7Pressed = 0x47,
    Keypad8Pressed = 0x48,
    Keypad9Pressed = 0x49,

    KeypadMinusPressed = 0x4a,

    Keypad4Pressed = 0x4b,
    Keypad5Pressed = 0x4c,
    Keypad6Pressed = 0x4d,

    KeypadPlusPressed = 0x4e,

    Keypad1Pressed = 0x4f,
    Keypad2Pressed = 0x50,
    Keypad3Pressed = 0x51,
    Keypad0Pressed = 0x52,
    KeypadDotPressed = 0x53,

    // Unknown 0x54..0x56

    F11Pressed = 0x57,
    F12Pressed = 0x58,

    _,

    pub fn to_ascii(self: @This()) ?u8 {
        return switch (self) {
            // Digits
            .OnePressed => '1',
            .TwoPressed => '2',
            .ThreePressed => '3',
            .FourPressed => '4',
            .FivePressed => '5',
            .SixPressed => '6',
            .SevenPressed => '7',
            .EightPressed => '8',
            .NinePressed => '9',
            .ZeroPressed => '0',

            // Letters
            .APressed => 'a',
            .BPressed => 'b',
            .CPressed => 'c',
            .DPressed => 'd',
            .EPressed => 'e',
            .FPressed => 'f',
            .GPressed => 'g',
            .HPressed => 'h',
            .IPressed => 'i',
            .JPressed => 'j',
            .KPressed => 'k',
            .LPressed => 'l',
            .MPressed => 'm',
            .NPressed => 'n',
            .OPressed => 'o',
            .PPressed => 'p',
            .QPressed => 'q',
            .RPressed => 'r',
            .SPressed => 's',
            .TPressed => 't',
            .UPressed => 'u',
            .VPressed => 'v',
            .WPressed => 'w',
            .XPressed => 'x',
            .YPressed => 'y',
            .ZPressed => 'z',

            .SpacePressed => ' ',
            .EnterPressed => '\n',

            else => null,
        };
    }
};
