# Mouse Kit

A minimal macOS mouse-button remapper. Add a binding by pressing a middle/extra mouse button or tilting the horizontal wheel, then record a keyboard shortcut to trigger.

Only inputs with a saved binding are intercepted. Unbound inputs pass through, and left/right clicks remain unchanged.

## Build and run

```sh
./scripts/build-app.sh
open -n "dist/Mouse Kit.app"
```

Run the `.app` bundle for permission prompts to be attributed to Mouse Kit. Do not use `swift run` for normal use: macOS may attribute permissions to the terminal that launched the bare executable.

Allow **Mouse Kit** under **System Settings → Privacy & Security → Input Monitoring**. When recording or triggering a shortcut, macOS may also request permission to synthesize keyboard events; allow **Mouse Kit** there as well.

Bindings are saved in the current user's preferences.

## Background operation

Mouse Kit runs without a Dock icon. Closing its window keeps saved bindings active; opening the app again brings back the same settings window. Use **退出 Mouse Kit** to stop it.

Enable **开机自启** to register with macOS Login Items. Login launches run silently without a settings window. If macOS requires approval, use the settings link shown in the app. Keep the app bundle at its registered path, or disable and re-enable login startup after moving it.

The build script packages the icon from `Assets/MouseKit.png`. `--background` starts without a window, and `--enable-login` enables login startup when launching the app.

## Scroll direction

**反转上下滚动** and **反转左右滚动** reverse each wheel axis relative to the macOS setting. Changes apply immediately and persist across background launches. Existing horizontal-wheel shortcut bindings take priority and retain their original mapping. Phased trackpad gestures and momentum pass through unchanged.
