"""Answers the `ACTION <name>` lines of the phone probes from the host.

Usage, from the app's folder, next to the run whose output goes to LOG:
  python3 integration_test/support/answer_actions.py android SERIAL LOG
  python3 integration_test/support/answer_actions.py ios UDID LOG
Options: --host-log FILE (what was done, default stdout), --lifetime S
(default 900), --allow (Android: press "allow" on any permission dialog,
since `flutter test` reinstalls the app and drops the grants), --shots DIR
(Android screenshots, default the current folder).

A test prints to the host, not to the device log, so the script follows
the output of the run: `flutter test integration_test/attempts_test.dart
-d SERIAL > LOG` on Android, `flutter run -d UDID -t
integration_test/attempts_test.dart > LOG` on an iPhone. It stops at the
end line of the run or after the lifetime.

Actions:
  home           the launcher (Android) or Settings (iOS) to the front,
                 the app back after a few seconds;
  home-and-back  the same, the app back at once;
  other-camera   the system camera to the front, the app back after 5 s;
                 Android stops the system camera before the app is back;
  deny           Android: press "deny" on the dialogs of one request,
                 the camera's and the microphone's;
  forget-denials Android: clear the flags a denial leaves on the camera
                 and the microphone, so the next request shows the dialog
                 as the first one did;
  screenshot     Android: a screenshot into --shots; iOS: skipped.
"""
import argparse
import os
import re
import subprocess
import sys
import time

ANDROID_PACKAGE = 'dev.yet_another.flutter_solo_camera_example'
IOS_BUNDLE = 'dev.yetanother.flutterSoloCameraExample'
STILL_IMAGE_CAMERA = 'android.media.action.STILL_IMAGE_CAMERA'


class Android:
    def __init__(self, serial, shots):
        self.serial = serial
        self.shots = shots

    def adb(self, *args):
        return subprocess.run(['adb', '-s', self.serial, *args],
                              capture_output=True, text=True,
                              timeout=60).stdout

    def camera_app(self):
        """The package that answers `STILL_IMAGE_CAMERA`, or None."""
        found = self.adb('shell', 'cmd', 'package', 'resolve-activity',
                         '--brief', '-a', STILL_IMAGE_CAMERA)
        lines = [line for line in found.split('\n') if '/' in line]
        return lines[-1].split('/')[0].strip() if lines else None

    def front(self):
        self.adb('shell', 'am', 'start', '-n',
                 f'{ANDROID_PACKAGE}/.MainActivity')

    def buttons(self):
        """The buttons of a permission dialog on the screen, if any."""
        self.adb('shell', 'uiautomator', 'dump', '/sdcard/probe-ui.xml')
        xml = self.adb('shell', 'cat', '/sdcard/probe-ui.xml')
        found = []
        for node in re.findall(r'<node [^>]*>', xml):
            rid = re.search(r'resource-id="([^"]*)"', node)
            if not rid or 'permission_' not in rid.group(1):
                continue
            text = re.search(r' text="([^"]*)"', node)
            b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
            if not b:
                continue
            x = (int(b.group(1)) + int(b.group(3))) // 2
            y = (int(b.group(2)) + int(b.group(4))) // 2
            found.append((rid.group(1), text.group(1) if text else '', x, y))
        return found

    def tap(self, x, y):
        self.adb('shell', 'input', 'tap', str(x), str(y))

    def allow(self, note):
        for rid, text, x, y in self.buttons():
            if 'allow_foreground' in rid or rid.endswith(
                    'permission_allow_button'):
                self.tap(x, y)
                note(f'allowed {rid} "{text}"')
                return

    def deny(self, note):
        # Camera and microphone come as two dialogs of one request; deny
        # each that shows, and no more than these two: the dialog of the
        # next request is the next action's.
        for _ in range(40):
            found = [f for f in self.buttons() if 'deny' in f[0]]
            if found:
                rid, text, x, y = found[0]
                self.tap(x, y)
                note(f'tapped {rid} "{text}"')
                break
            time.sleep(0.5)
        else:
            note('no deny button in 20 s')
            return
        for _ in range(3):
            time.sleep(1)
            found = [f for f in self.buttons() if 'deny' in f[0]]
            if found:
                rid, text, x, y = found[0]
                self.tap(x, y)
                note(f'tapped {rid} "{text}"')
                return

    def answer(self, action, note):
        if action in ('home', 'home-and-back'):
            self.adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
            time.sleep(3 if action == 'home' else 0.3)
            self.front()
        elif action == 'other-camera':
            self.adb('shell', 'am', 'start', '-a', STILL_IMAGE_CAMERA)
            time.sleep(5)
            # Left in the background, the system camera of a Galaxy A55
            # kept the camera and slowed the phone down for later runs.
            camera = self.camera_app()
            if camera:
                self.adb('shell', 'am', 'force-stop', camera)
                note(f'stopped {camera}')
            self.front()
        elif action == 'deny':
            self.deny(note)
        elif action == 'forget-denials':
            for permission in ('CAMERA', 'RECORD_AUDIO'):
                self.adb('shell', 'pm', 'clear-permission-flags',
                         ANDROID_PACKAGE, f'android.permission.{permission}',
                         'user-set', 'user-fixed')
            note('denials forgotten')
        elif action == 'screenshot':
            name = os.path.join(self.shots,
                                f'shot-{time.strftime("%H%M%S")}.png')
            with open(name, 'wb') as f:
                f.write(subprocess.run(
                    ['adb', '-s', self.serial, 'exec-out', 'screencap',
                     '-p'], capture_output=True).stdout)
            note(f'screenshot {name}')
        else:
            note(f'unknown action {action}')


class Ios:
    def __init__(self, udid):
        self.udid = udid

    def launch(self, bundle, note):
        result = subprocess.run(
            ['xcrun', 'devicectl', 'device', 'process', 'launch',
             '--device', self.udid, bundle], capture_output=True, text=True)
        note(f'launch {bundle} rc={result.returncode}')

    def allow(self, note):
        pass

    def answer(self, action, note):
        if action == 'home':
            self.launch('com.apple.Preferences', note)
            time.sleep(5)
            self.launch(IOS_BUNDLE, note)
        elif action == 'home-and-back':
            self.launch('com.apple.Preferences', note)
            self.launch(IOS_BUNDLE, note)
        elif action == 'other-camera':
            self.launch('com.apple.camera', note)
            time.sleep(5)
            self.launch(IOS_BUNDLE, note)
        else:
            note(f'skip {action}')


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('platform', choices=['android', 'ios'])
    parser.add_argument('device')
    parser.add_argument('log')
    parser.add_argument('--host-log')
    parser.add_argument('--lifetime', type=float, default=900)
    parser.add_argument('--allow', action='store_true')
    parser.add_argument('--shots', default='.')
    args = parser.parse_args()

    out = open(args.host_log, 'a', buffering=1) if args.host_log else (
        sys.stdout)

    def note(text):
        out.write(f'{time.strftime("%H:%M:%S")} {text}\n')
        out.flush()

    phone = (Android(args.device, args.shots) if args.platform == 'android'
             else Ios(args.device))
    end = time.time() + args.lifetime
    last_allow = 0.0
    while not os.path.exists(args.log):
        time.sleep(0.5)
    with open(args.log) as source:
        while time.time() < end:
            line = source.readline()
            if not line:
                if args.allow and time.time() - last_allow > 2:
                    last_allow = time.time()
                    phone.allow(note)
                time.sleep(0.2)
                continue
            if 'All tests passed' in line or 'Some tests failed' in line:
                note('run over')
                return
            m = re.search(r'PROBE .*ACTION (\S+)', line)
            if m:
                note(f'action {m.group(1)}')
                phone.answer(m.group(1), note)
                note(f'done {m.group(1)}')
    note('lifetime over')


if __name__ == '__main__':
    main()
