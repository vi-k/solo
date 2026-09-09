/// A plain delay, for bodies that need time to pass.
Future<void> delay(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));
