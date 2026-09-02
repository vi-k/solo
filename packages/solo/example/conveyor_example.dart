// import 'dart:async';

// import 'package:conveyor/conveyor.dart';

// sealed class State {
//   const State();
// }

// final class State1 extends State {
//   final int a;
//   final int b;

//   State1({
//     required this.a,
//     required this.b,
//   });

//   State1 copyWith({
//     int? a,
//     int? b,
//   }) {
//     print('* copyWith');
//     return State1(
//       a: a ?? this.a,
//       b: b ?? this.b,
//     );
//   }

//   @override
//   String toString() => 'State1(a: $a, b: $b)';
// }

// final class State2 extends State {
//   final int c;

//   State2({
//     required this.c,
//   });

//   State2 copyWith({
//     int? c,
//   }) {
//     print('* copyWith');
//     return State2(
//       c: c ?? this.c,
//     );
//   }

//   @override
//   String toString() => 'State2(c: $c)';
// }

// State _state = State1(a: 0, b: 0);
// final StreamController<State> _stateController =
//     StreamController.broadcast(sync: true);
// // StreamController.broadcast();

// T state<T extends State>([bool Function(T state)? test]) {
//   if (_state is! T) {
//     throw Cancelled(CancelReason.stateTypeChanged);
//   }

//   final state = _state as T;
//   if (test != null && !test(state)) {
//     throw Cancelled(CancelReason.stateDoesNotMeetCondition);
//   }

//   return state;
// }

// void checkState<T extends State>([bool Function(T state)? test]) {
//   state<T>(test);
// }

// void _externalSetState(State state) {
//   print('* externalSetState');
//   _stateController.add(state);
// }

// Future<void> main() async {
//   _stateController.stream.listen((state) {
//     print('state: $state');
//     _state = state;
//   });

//   // Future(() {
//   //   _externalSetState(_state.copyWith(b: 1));
//   // });

//   Future.microtask(() {
//     _externalSetState(State1(a: 0, b: 10));
//   });

//   final sub = f().listen(
//     (state) => _stateController.add(state),
//     onError: (Object error, StackTrace stackTrace) {
//       if (error is Cancelled) {
//         print('* cancelled by reason ${error.reason}');
//       } else {
//         Error.throwWithStackTrace(error, stackTrace);
//       }
//     },
//     cancelOnError: true,
//   );

//   // sub.cancel();

//   // Future.microtask(() {
//   //   // sub.cancel();
//   //   _externalSetState(State2(c: 2));
//   // });

//   await Future<void>.delayed(const Duration(milliseconds: 2000));
//   _stateController.close();
// }

// Stream<State> f() async* {
//   try {
//     print('* start f');

//     yield state<State1>().copyWith(a: 1);
//     // yield state().copyWith(a: 1);

//     // await Future(() {});
//     //

//     print('* after yield 1 state=$_state');

//     checkState<State2>();

//     yield state<State1>((state) => state.b < 10).copyWith(a: 2);
//     print('* after yield 2 state=$_state');

//     yield state<State1>().copyWith(a: 3);
//     print('* after yield 3 state=$_state');
//   } finally {
//     print('* finish f');
//   }
// }
