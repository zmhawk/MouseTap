# Mouse Kit

A minimal macOS mouse-button remapper. Add a binding by pressing a middle/extra mouse button or tilting the horizontal wheel, then record a keyboard shortcut to trigger.

Only inputs with a saved binding are intercepted. Unbound inputs pass through, and left/right clicks remain unchanged.

## 中文说明

忍了那个巨大无比的 Logic Option+ 九年，终于决定让 AI 给我写一个轻量版鼠标“驱动“（我也不知道这玩意该叫啥）。

解决了 Logic Option+ 在其他应用抢走输入焦点后概率性无法触发切屏动作的问题。

解决了 Logic Option+ 不支持苹果 Universal Control 的问题。

是的！这玩意支持 Universal Control！我可以在鼠标连 air 的时候顺利的在 mini 上使用我的自定义动作，只需要两台电脑都安装并使用相同的配置。

### 待优化的交互

左上角的 x 是关闭窗口，但不关闭服务。但是首次授权后需要重新启动 app 才能生效，要点“退出并关闭鼠标服务“彻底关闭后再打开。

## Build and run

```sh
./scripts/build-app.sh
open -n "dist/Mouse Kit.app"
```

Run the `.app` bundle for permission prompts to be attributed to Mouse Kit. Do not use `swift run` for normal use: macOS may attribute permissions to the terminal that launched the bare executable.

Allow **Mouse Kit** under **System Settings → Privacy & Security → Input Monitoring**. When recording or triggering a shortcut, macOS may also request permission to synthesize keyboard events; allow **Mouse Kit** there as well.

Bindings are saved in the current user's preferences.

## Background operation

Mouse Kit runs without a Dock icon. Closing its window keeps saved bindings active; opening the app again brings back the same settings window. Use **退出并关闭鼠标服务** to stop it.

Enable **开机自启** to register with macOS Login Items. Login launches run silently without a settings window. If macOS requires approval, use the settings link shown in the app. Keep the app bundle at its registered path, or disable and re-enable login startup after moving it.

The build script packages the icon from `Assets/MouseKit.png`. `--background` starts without a window, and `--enable-login` enables login startup when launching the app.

## Scroll direction

**反转上下滚动** and **反转左右滚动** reverse each wheel axis relative to the macOS setting. Changes apply immediately and persist across background launches. Existing horizontal-wheel shortcut bindings take priority and retain their original mapping. Phased trackpad gestures and momentum pass through unchanged.
