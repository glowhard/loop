import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Loop's own palette, so the phone and the PC look like one product.
class C {
  static const well = Color(0xFF0E161D);
  static const chrome = Color(0xFF141E27);
  static const panel = Color(0xFF19252F);
  static const raised = Color(0xFF22313F);
  static const raised2 = Color(0xFF2B3D4E);
  static const line = Color(0xFF273645);
  static const lineStrong = Color(0xFF35485A);
  static const text = Color(0xFFDCE5EC);
  static const text2 = Color(0xFF93A6B5);
  static const text3 = Color(0xFF647A8C);
  static const accent = Color(0xFF7CC4F0);
  static const accentInk = Color(0xFF0C1820);
  static const busy = Color(0xFFF0B24A);
  static const idle = Color(0xFF57C98A);
  static const shell = Color(0xFFB79CF2);
  static const off = Color(0xFF4A5E70);
  static const danger = Color(0xFFEE7B6C);
  // chat only
  static const bubble = Color(0xFF263B4B);
  static const codeWell = Color(0xFF0B1218);
  static const accentDim = Color(0x667CC4F0);

  static Color lamp(String name) => switch (name) {
    'idle' => idle,
    'busy' => busy,
    'shell' => shell,
    'exited' => off,
    _ => off,
  };
}

ThemeData loopTheme() {
  const scheme = ColorScheme.dark(
    primary: C.accent,
    onPrimary: C.accentInk,
    secondary: C.shell,
    surface: C.chrome,
    onSurface: C.text,
    error: C.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.chrome,
    canvasColor: C.chrome,
    fontFamily: 'Roboto',
    dividerColor: C.line,
    dividerTheme: const DividerThemeData(color: C.line, thickness: 1, space: 1),
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: C.chrome,
      surfaceTintColor: Colors.transparent,
      foregroundColor: C.text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: C.text,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.panel,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 62,
      labelTextStyle: WidgetStatePropertyAll(
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 22,
          color: s.contains(WidgetState.selected) ? C.accent : C.text3,
        ),
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.panel,
      modalBackgroundColor: C.panel,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Color(0x99000000),
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: C.lineStrong,
      dragHandleSize: Size(36, 4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: C.panel,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: C.text2,
      textColor: C.text,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: C.raised2,
      contentTextStyle: TextStyle(color: C.text),
      behavior: SnackBarBehavior.floating,
      // Clear of the message box and the tabs: a note that covers the send
      // button turns a tap meant for it into a tap on the note.
      insetPadding: EdgeInsets.fromLTRB(12, 0, 12, 84),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.well,
      hintStyle: const TextStyle(color: C.text3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: C.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: C.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: C.accent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.accent,
        foregroundColor: C.accentInk,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.text,
        side: const BorderSide(color: C.lineStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}

/// The terminal colours Loop uses, so a session looks the same on both screens.
const loopTerminalTheme = TerminalTheme(
  cursor: Color(0xFFF0B24A),
  selection: Color(0x662F4A61),
  foreground: Color(0xFFD5DEE6),
  background: Color(0xFF0E161D),
  black: Color(0xFF1B2731),
  red: Color(0xFFEE7B6C),
  green: Color(0xFF57C98A),
  yellow: Color(0xFFF0B24A),
  blue: Color(0xFF7CC4F0),
  magenta: Color(0xFFB79CF2),
  cyan: Color(0xFF5FD0C5),
  white: Color(0xFFC9D4DC),
  brightBlack: Color(0xFF647A8C),
  brightRed: Color(0xFFF59A8E),
  brightGreen: Color(0xFF7DDBA6),
  brightYellow: Color(0xFFF6C878),
  brightBlue: Color(0xFFA3D7F6),
  brightMagenta: Color(0xFFCDBAF7),
  brightCyan: Color(0xFF8BE0D8),
  brightWhite: Color(0xFFF2F6F9),
  searchHitBackground: Color(0xFFF0B24A),
  searchHitBackgroundCurrent: Color(0xFF7CC4F0),
  searchHitForeground: Color(0xFF0E161D),
);

/// Every sheet in the app opens the same way: dark to the edge, one handle,
/// and a soft ease rather than a snap.
Future<T?> showLoopSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? backgroundColor,
}) => showModalBottomSheet<T>(
  context: context,
  builder: builder,
  isScrollControlled: isScrollControlled,
  useSafeArea: true,
  backgroundColor: backgroundColor ?? C.panel,
  sheetAnimationStyle: const AnimationStyle(
    duration: Duration(milliseconds: 320),
    reverseDuration: Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  ),
);

/// The round close button used at the top of sheets.
class CloseCircle extends StatelessWidget {
  const CloseCircle({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: C.raised,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: const SizedBox(
        width: 36,
        height: 36,
        child: Icon(Icons.close_rounded, size: 20, color: C.text),
      ),
    ),
  );
}
