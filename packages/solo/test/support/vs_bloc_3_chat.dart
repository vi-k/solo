// Section 3 of `doc/vs-bloc.md`, "Closing and cancelling in-flight work": what the page leaves out,
// then the code under its `### Solo` heading, verbatim, then what
// `vs_bloc_rakes_test.dart` adds on top of it. Every piece of the page's
// blocks is a run of lines of this file. The bloc side of the section is
// built and run by the bench, `tool/doc_snippets.py`: this package does not
// depend on bloc.
import 'dart:async';

import 'package:solo/solo.dart';

import 'vs_bloc_stubs.dart';

class Api {
  /// Reads reported to the server. The point of the scenario is that a
  /// reply the user never saw must not be one of them.
  int reads = 0;

  /// Messages the server was asked to deliver, and the ones it answered.
  final sent = <String>[];
  final answered = <String>[];

  Future<String> send(String text) async {
    sent.add(text);
    await tick(50);
    answered.add(text);
    return 'reply to $text';
  }

  Future<void> markRead() async {
    reads++;
    await tick(10);
  }
}

class ChatState {
  const ChatState([this.reply]);

  final String? reply;

  ChatState withReply(String reply) => ChatState(reply);

  @override
  String toString() => 'ChatState($reply)';
}

// The code of the page.

final class ChatController extends Solo<ChatState> {
  final Api _api;

  ChatController(this._api) : super(const ChatState());

  Job<void> send(String text) => run<ChatState, void>(
        key: 'send',
        (ctx) async {
          final reply = await ctx.wait(() => _api.send(text));
          ctx.emit(ctx.state.withReply(reply));
          markReplyRead();
        },
      );

  Job<void> markReplyRead() =>
      run<ChatState, void>((ctx) => ctx.wait(_api.markRead));
}

Future<void> onScreenClosed(ChatController chat) async {
  await chat.close();
  chat.send('bye'); // never runs: the job comes back Cancelled(closed)
}

// What the test adds.

/// The `send` of the page with a plain `await` where the page has
/// `ctx.wait`: "With a plain await instead".
final class PlainAwaitChatController extends Solo<ChatState> {
  PlainAwaitChatController(this._api) : super(const ChatState());

  final Api _api;

  /// What the body met after its await: the error `ctx.emit` threw.
  Object? afterAwait;

  Job<void> send(String text) => run<ChatState, void>(
        key: 'send',
        (ctx) async {
          final reply = await _api.send(text);
          try {
            ctx.emit(ctx.state.withReply(reply));
          } on Object catch (error) {
            afterAwait = error;
            rethrow;
          }
        },
      );
}

/// A future started inside a job and left unawaited.
final class LateChatController extends Solo<ChatState> {
  LateChatController(this._api) : super(const ChatState());

  final Api _api;

  Job<void> send(String text) => run<ChatState, void>(
        key: 'send',
        (ctx) async {
          unawaited(
            _api
                .send(text)
                .then((reply) => ctx.emit(ctx.state.withReply(reply))),
          );
        },
      );
}
