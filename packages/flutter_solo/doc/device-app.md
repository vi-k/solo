# A device app

A camera app with two screens. The home screen shows the last picture or video.
The camera screen has a preview and buttons for a picture, a video, the flash
and a switch between the cameras. The camera is the `camera` plugin, and the
screen owns it through `CameraSession`, a `Solo<CameraState>`. Every command
takes time on the phone, the phone can take the camera away, and a camera has
to be let go before the next screen opens it.

The sections on the situations of the app open with a first attempt: the
version the plugin's README and its example lead to. A section shows what that
code does on a phone and ends on the app's code.

The app is
[`camera_example`](https://github.com/vi-k/solo/blob/main/packages/flutter_solo/camera_example)
in the repository of this package, and it runs on Android and iOS:

```sh
git clone https://github.com/vi-k/solo.git
cd solo/packages/flutter_solo/camera_example
flutter run
```

The code on this page is the app's code. A trace is what the app does to the
camera under `flutter test`, where a fake camera platform stands in for the
phone. A call on the camera is a line, or two for a call that takes time, where
it starts and where it ends; a change of the state is a line too. Opening the
camera:

```text
state Opening
create back #1
initialize #1 start
initialize #1 end
state Ready
```
