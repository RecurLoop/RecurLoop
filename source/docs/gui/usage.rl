// Extended usage documentation. The catalog and index are generated from these objects.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Gui" }
    section = phrase { payload = "API" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "Gui provides windows, layout, controls and event callbacks.

## Object lifetimes

Create a window or widget, attach it to the intended parent and connect callbacks while their captured state remains valid. Release owned GUI resources using the corresponding destroy functions.

## Events

Signals represent user interaction, timer events and shortcuts. Keep callback work bounded so the event loop can continue processing input."
    }
]

