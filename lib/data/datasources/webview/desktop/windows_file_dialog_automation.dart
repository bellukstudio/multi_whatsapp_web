import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Completes WhatsApp's real Attach -> Document file selection.
///
/// The native dialog is intentional: selecting the file through the browser's
/// own file input is the trusted path WhatsApp accepts reliably.
class WindowsFileDialogAutomation {
  static Future<bool> selectFiles({
    required String folderPath,
    required List<String> fileNames,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final hwnd = await _waitForDialog(timeout);
    if (hwnd == 0) return false;

    final foreground = GetForegroundWindow();
    final currentThread = GetCurrentThreadId();
    final foregroundThread = GetWindowThreadProcessId(foreground, nullptr);
    final attached = foregroundThread != 0 &&
        foregroundThread != currentThread &&
        AttachThreadInput(currentThread, foregroundThread, 1) != 0;
    ShowWindow(hwnd, SW_RESTORE);
    BringWindowToTop(hwnd);
    SetForegroundWindow(hwnd);
    if (attached) AttachThreadInput(currentThread, foregroundThread, 0);

    await Future<void>.delayed(const Duration(milliseconds: 250));
    // In the modern common file dialog, `cmb13` (0x47c) is the filename
    // combobox, while its editable text field is `edt1` (0x480). Writing only
    // to the combobox can leave the visible filename empty, so Open simply
    // keeps Explorer open and the caller eventually times out.
    final fileNameEdit = GetDlgItem(hwnd, 0x480); // edt1
    final fileNameCombo = GetDlgItem(hwnd, 0x47c); // cmb13
    final openButton = GetDlgItem(hwnd, 1); // IDOK
    final fullPaths = fileNames.map((name) => '"$folderPath\\$name"').join(' ');
    if (openButton != 0 && (fileNameEdit != 0 || fileNameCombo != 0)) {
      final text = fullPaths.toNativeUtf16();
      try {
        // Prefer the actual editable control; set the combobox too for older
        // dialog layouts where it owns the edit field internally.
        if (fileNameEdit != 0) SetWindowText(fileNameEdit, text);
        if (fileNameCombo != 0) SetWindowText(fileNameCombo, text);
        SendMessage(openButton, 0x00f5 /* BM_CLICK */, 0, 0);
      } finally {
        calloc.free(text);
      }
    } else {
      // Older common-dialog implementations may not expose the standard
      // control IDs; retain the keyboard path for those dialogs.
      _sendChord(VK_MENU, 0x44);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      _typeText(folderPath);
      _sendKey(VK_RETURN);
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      _sendChord(VK_MENU, 0x4E);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      _sendChord(VK_CONTROL, 0x41);
      _typeText(fileNames.map((name) => '"$name"').join(' '));
      _sendKey(VK_RETURN);
    }
    final closeDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(closeDeadline)) {
      if (IsWindow(hwnd) == 0 || IsWindowVisible(hwnd) == 0) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  static Future<int> _waitForDialog(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final hwnd = FindWindow(TEXT('#32770'), nullptr);
      if (hwnd != 0 && IsWindowVisible(hwnd) != 0) return hwnd;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return 0;
  }

  static void _sendKey(int key) => _sendInput([key]);

  static void _sendChord(int modifier, int key) =>
      _sendInput([modifier, key], releaseReverse: true);

  static void _sendInput(
    List<int> keys, {
    bool releaseReverse = false,
  }) {
    final inputs = calloc<INPUT>(keys.length * 2);
    try {
      for (var i = 0; i < keys.length; i++) {
        inputs[i].type = INPUT_KEYBOARD;
        inputs[i].ki.wVk = keys[i];
        final releaseIndex =
            releaseReverse ? keys.length * 2 - i - 1 : keys.length + i;
        inputs[releaseIndex].type = INPUT_KEYBOARD;
        inputs[releaseIndex].ki.wVk = keys[i];
        inputs[releaseIndex].ki.dwFlags = KEYEVENTF_KEYUP;
      }
      SendInput(keys.length * 2, inputs, sizeOf<INPUT>());
    } finally {
      calloc.free(inputs);
    }
  }

  static void _typeText(String value) {
    for (final rune in value.runes) {
      final inputs = calloc<INPUT>(2);
      try {
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].ki.wScan = rune;
        inputs[0].ki.dwFlags = KEYEVENTF_UNICODE;
        inputs[1].type = INPUT_KEYBOARD;
        inputs[1].ki.wScan = rune;
        inputs[1].ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
        SendInput(2, inputs, sizeOf<INPUT>());
      } finally {
        calloc.free(inputs);
      }
    }
  }
}
