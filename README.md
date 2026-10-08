# MouseTap

A minimal macOS mouse-button remapper. Add a binding by pressing a middle/extra mouse button or tilting the horizontal wheel, then record a keyboard shortcut to trigger.

Only inputs with a saved binding are intercepted. Unbound inputs pass through, and left/right clicks remain unchanged.

## 中文说明

忍了那个巨大无比的 Logi Options+ 九年，终于决定让 AI 给我写一个轻量版鼠标“驱动“（我也不知道这玩意该叫啥）。

解决了 Logi Options+ 在其他应用抢走输入焦点后概率性无法触发切屏动作的问题。

解决了 Logi Options+ 不支持苹果 Universal Control 的问题。

是的！这玩意支持 Universal Control！我可以在鼠标连 air 的时候顺利的在 mini 上使用我的自定义动作，只需要两台电脑都安装并使用相同的配置。

### 待优化的交互

左上角的 x 是关闭窗口，但不关闭服务。但是首次授权后需要重新启动 app 才能生效，要点“退出并关闭鼠标服务“彻底关闭后再打开。

先把核心功能分享出来，细节再慢慢优化吧。

## Build and run

```sh
./scripts/build-app.sh
open -n "dist/MouseTap.app"
```

Run the `.app` bundle for permission prompts to be attributed to MouseTap. Do not use `swift run` for normal use: macOS may attribute permissions to the terminal that launched the bare executable.

Allow **MouseTap** under **System Settings → Privacy & Security → Input Monitoring**. When recording or triggering a shortcut, macOS may also request permission to synthesize keyboard events; allow **MouseTap** there as well.

Bindings are saved in the current user's preferences.

## Background operation

MouseTap runs without a Dock icon. Closing its window keeps saved bindings active; opening the app again brings back the same settings window. Use **退出并关闭鼠标服务** to stop it.

Enable **开机自启** to register with macOS Login Items. Login launches run silently without a settings window. If macOS requires approval, use the settings link shown in the app. Keep the app bundle at its registered path, or disable and re-enable login startup after moving it.

The build script packages the icon from `Assets/MouseTap.png`. `--background` starts without a window, and `--enable-login` enables login startup when launching the app.

## Scroll direction

**反转上下滚动** and **反转左右滚动** reverse each wheel axis relative to the macOS setting. Changes apply immediately and persist across background launches. Existing horizontal-wheel shortcut bindings take priority and retain their original mapping. Phased trackpad gestures and momentum pass through unchanged.

## Horizontal-wheel repeat limiting

Bound horizontal-wheel shortcuts start at least 180 ms apart. Repeated events replace a single pending request, so long presses cannot create an unbounded shortcut queue. Changing direction replaces the pending direction. Requests older than 200 ms are dropped; entering capture/learning, stopping the monitor, or changing bindings clears pending wheel requests. An in-progress shortcut always finishes its key releases. Mouse-button clicks and unbound scrolling keep their normal handling.

## Editable configuration files

Use **导出配置…** to save the current mouse bindings and wheel directions as a readable TOML file. Edit it in a text editor and use **加载配置…** to apply it. Loading replaces all current bindings and wheel-direction settings, saves them to preferences, and cancels pending wheel shortcuts. Invalid files leave the existing settings intact. Files do not reload automatically on save. macOS launch-at-login registration and permissions remain local to each computer.

See `Examples/mousetap.toml` for a complete example. TOML supports `#` comments. Quote input IDs in table headers, e.g. `[bindings."button.2"]`, so the dot stays part of the ID.

- `version`: currently `1`.
- `scroll.reverseVertical` / `scroll.reverseHorizontal`: `true` or `false`.
- `bindings`: maps `button.2` (middle), `button.3` through `button.31`, `scroll.left`, or `scroll.right` to a shortcut. Remove an entry to unbind that input; an empty `[bindings]` table clears all bindings.
- `keyCode`: macOS virtual key code, used for the actual key press. Common values: A = 0, Return = 36, Space = 49, Escape = 53, Left = 123, Right = 124, Down = 125, Up = 126. Record an unfamiliar key in the app and export to get its code.
- `keyName`: display label only; changing it does not change the actual key.
- `control`, `option`, `shift`, `command`, `function`: boolean modifier flags. `function` is Fn; omitted `function` defaults to false for compatibility. Other listed fields are required.

Unknown field names, unsupported versions, invalid input IDs or key codes, malformed TOML, and files larger than 1 MB are rejected. File reads and writes run off the event-monitor thread.

## Migration from Mouse Kit

MouseTap uses bundle identifier `com.zmhawk.mousetap`. On its first launch it copies saved mouse bindings and scroll-direction settings from the previous `com.yujianbo.mousekit` preferences without overwriting existing MouseTap settings. TOML configuration files keep the same version-1 structure and can still be imported.

macOS treats the new bundle ID as a new app: grant MouseTap Input Monitoring and keyboard-synthesis/accessibility permissions. Disable the old Mouse Kit login item and quit the old app before using MouseTap, then enable launch-at-login in MouseTap. Do not run both remappers simultaneously.

## Continuous integration

GitHub Actions tests and builds on Apple Silicon and Intel macOS runners for pushes to `main`, pull requests, manual runs, and version tags. Each successful job uploads a zipped, ad-hoc-signed `MouseTap.app` for its architecture. These builds are not notarized; Developer ID signing/notarization is a separate setup.

To publish a release, tag the desired commit with `vMAJOR.MINOR.PATCH` (for example, `v1.0.0`) and push that tag to `origin`. Both architectures must pass tests and build successfully before Actions publishes a GitHub Release with generated release notes and `MouseTap-arm64.zip` / `MouseTap-x86_64.zip`. The tag version is embedded in the app. Other tag formats fail validation; branch pushes, pull requests, and manual runs only produce CI artifacts.

Run the checks locally with `swift test` and `./scripts/build-app.sh`. The app supports macOS 13 and later.

For local CI-signature checks, use `CODESIGN_IDENTITY=- APP_BUNDLE_PATH=/tmp/MouseTap-CI.app ./scripts/build-app.sh` so the ad-hoc build does not replace the locally authorized development-signed app. Changing signing identity may require removing and re-adding MouseTap in macOS privacy settings.

The event tap runs on a dedicated thread. If macOS disables it, MouseTap pauses the service instead of automatically re-enabling the tap; quit and reopen the app to resume. Ordinary monitoring does not subscribe to keyboard events; keyboard capture is enabled when recording a shortcut. Repeated bound mouse buttons and wheels share a bounded shortcut scheduler (180 ms minimum interval, one pending event, 200 ms expiry).

## License

MouseTap is distributed under the MIT License; see `LICENSE`. Bundled dependency license notices are in `THIRD_PARTY_NOTICES.txt` and included in the app.
