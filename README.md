# Mouse Kit

A minimal macOS mouse-button remapper. Add a binding by pressing a middle/extra mouse button or tilting the horizontal wheel, then record a keyboard shortcut to trigger.

Only inputs with a saved binding are intercepted. Unbound inputs pass through, and left/right clicks remain unchanged.

## Run

```sh
swift run mouse-event-probe
```

If macOS refuses to create the event tap or post shortcuts, allow the app under **System Settings → Privacy & Security** → **Accessibility** and, if requested by macOS, **Input Monitoring**.

Bindings are saved in the current user's preferences.
