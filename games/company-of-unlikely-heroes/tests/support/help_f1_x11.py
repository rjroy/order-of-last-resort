"""Send F1 only when X11 focus belongs to this test's game window."""

import ctypes
import sys


def main() -> int:
    allowed = {int(value) for value in sys.argv[1:] if int(value) > 0}
    if not allowed:
        print("No valid game window handles supplied", file=sys.stderr)
        return 1
    x = ctypes.CDLL("libX11.so.6")
    xtest = ctypes.CDLL("libXtst.so.6")
    display = ctypes.c_void_p
    x.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x.XOpenDisplay.restype = display
    x.XGetInputFocus.argtypes = [display, ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_int)]
    x.XKeysymToKeycode.argtypes = [display, ctypes.c_ulong]
    x.XKeysymToKeycode.restype = ctypes.c_ubyte
    x.XGrabServer.argtypes = [display]
    x.XUngrabServer.argtypes = [display]
    x.XSync.argtypes = [display, ctypes.c_int]
    x.XCloseDisplay.argtypes = [display]
    xtest.XTestFakeKeyEvent.argtypes = [display, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
    connection = x.XOpenDisplay(None)
    if not connection:
        print("Cannot open X11 display", file=sys.stderr)
        return 1
    result = 1
    try:
        # Hold the server across the focus check and key injection so another
        # client cannot change focus between the check and the XTEST requests.
        x.XGrabServer(connection)
        focused = ctypes.c_ulong()
        revert = ctypes.c_int()
        x.XGetInputFocus(connection, ctypes.byref(focused), ctypes.byref(revert))
        if focused.value not in allowed:
            print(f"Refusing F1: focused window {focused.value} is not a test window {allowed}", file=sys.stderr)
        else:
            code = x.XKeysymToKeycode(connection, 0xFFBE)
            if code and xtest.XTestFakeKeyEvent(connection, code, 1, 0):
                if xtest.XTestFakeKeyEvent(connection, code, 0, 0):
                    x.XSync(connection, 0)
                    result = 0
    finally:
        x.XUngrabServer(connection)
        x.XCloseDisplay(connection)
    return result


if __name__ == "__main__":
    sys.exit(main())
