// Section 8 of `doc/vs-bloc.md`, "Awaiting a particular request": what the page leaves out,
// then the code under its `### Solo` heading, verbatim, then what
// `vs_bloc_rakes_test.dart` adds on top of it. Every piece of the page's
// blocks is a run of lines of this file. The bloc side of the section is
// built and run by the bench, `tool/doc_snippets.py`: this package does not
// depend on bloc.
import 'package:solo/solo.dart';

import 'vs_bloc_stubs.dart';

class Order {
  const Order(this.id);

  final String id;
}

class Receipt {
  const Receipt(this.orderId);

  final String orderId;

  String get id => 'R-$orderId';

  @override
  String toString() => 'Receipt(for $orderId)';
}

class Api {
  Api({this.declines = false});

  /// The bank refuses every charge.
  final bool declines;
  int calls = 0;

  Future<Receipt> pay(Order order) async {
    calls++;
    await tick(30);
    if (declines) {
      throw StateError('card declined');
    }
    return Receipt(order.id);
  }
}

sealed class CheckoutState {
  const CheckoutState();
}

/// What the page's width argument is about: a state the checkout can be
/// put in from outside while a charge is on its way, and the states it is
/// in otherwise.
final class Suspended extends CheckoutState {
  const Suspended();

  @override
  String toString() => 'Suspended';
}

sealed class Open extends CheckoutState {
  const Open();
}

final class Idle extends Open {
  const Idle();

  @override
  String toString() => 'Idle';
}

final class Paying extends Open {
  const Paying(this.orderId);

  final String orderId;

  @override
  String toString() => 'Paying($orderId)';
}

final class Paid extends Open {
  const Paid(this.receipt);

  final Receipt receipt;

  @override
  String toString() => 'Paid($receipt)';
}

// The code of the page.

final class CheckoutController extends Solo<CheckoutState> {
  final Api _api;

  CheckoutController(this._api) : super(const Idle());

  Job<Receipt> pay(Order order) => run<CheckoutState, Receipt>(
        key: ('pay', order.id),
        policy: Policy.droppable,
        cancellable: false,
        (ctx) async {
          ctx.emit(Paying(order.id));
          final receipt = await _api.pay(order);
          ctx.emit(Paid(receipt));
          return receipt;
        },
      );
}

Future<Map<String, Object?>> handlePayRequest(
  CheckoutController checkout,
  Order order,
) async {
  switch (await checkout.pay(order).done) {
    case Done(:final value):
      return {'paid': true, 'receipt': value.id};
    case Cancelled(:final reason):
      return {'paid': false, 'cancelled': reason.name};
    case Failed(:final error):
      return {'paid': false, 'error': '$error'};
  }
}

// What the test adds.

/// What the test reaches of the protected members of the page's controller.
extension Reach on CheckoutController {
  // ignore: invalid_use_of_protected_member
  void clearQueue({bool force = false}) => queue.clear(force: force);

  // ignore: invalid_use_of_protected_member
  void suspend() => externalSetState(const Suspended());
}

/// The payment of the page under a narrower working type: "a narrower type
/// would allow cancellation after a charge was sent but before it was
/// recorded".
final class NarrowCheckoutController extends Solo<CheckoutState> {
  NarrowCheckoutController(this._api) : super(const Idle());

  final Api _api;

  Job<Receipt> pay(Order order) => run<Open, Receipt>(
        key: ('pay', order.id),
        policy: Policy.droppable,
        cancellable: false,
        (ctx) async {
          ctx.emit(Paying(order.id));
          final receipt = await _api.pay(order);
          ctx.emit(Paid(receipt));
          return receipt;
        },
      );

  void suspend() => externalSetState(const Suspended());
}

/// One cancellable job per waiting member, to tell the three apart: what
/// each does with a cancellation that arrives during the call.
final class WaitingCheckoutController extends Solo<CheckoutState> {
  WaitingCheckoutController(this._api) : super(const Idle());

  final Api _api;

  /// Where each body was when it ended: the receipt it got or what it met.
  final met = <String>[];

  Job<void> viaWait(Order order) => run<CheckoutState, void>((ctx) async {
        try {
          met.add('wait got ${await ctx.wait(() => _api.pay(order))}');
        } on Cancelled {
          met.add('wait threw Cancelled');
          rethrow;
        }
      });

  Job<void> viaJoin(Order order) => run<CheckoutState, void>((ctx) async {
        try {
          met.add('join got ${await ctx.join(() => _api.pay(order))}');
        } on Cancelled {
          met.add('join threw Cancelled');
          rethrow;
        }
      });

  Job<void> viaUncancellable(Order order) =>
      run<CheckoutState, void>((ctx) async {
        final receipt = await ctx.uncancellable(() => _api.pay(order));
        met.add('uncancellable got $receipt');
        try {
          ctx.check();
          met.add('the body went on');
        } on Cancelled {
          met.add('the next checkpoint threw Cancelled');
          rethrow;
        }
      });
}
