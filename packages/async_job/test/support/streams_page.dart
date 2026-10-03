// The code of `doc/streams.md`, verbatim: every block of the page is a run
// of lines of this file, and `streams_rakes_test.dart` runs it. A block
// that declares names another block declares too lives in a function of
// its own.
import 'dart:async';

import 'package:async_job/async_job.dart';

import 'children_stubs.dart';

Job<void> eachInABody() => Job<void>((ctx) async {
      // ignore: prefer_expression_function_bodies
      final saving = ctx.each(messages, (childCtx, message) {
        return childCtx.join(() => store.saveBody(message));
      });
      await saving.value;
    });

Future<void> watchTicks() async {
  final job = Job<void>((ctx) async {
    final ticks = ctx.each(
      Stream<int>.periodic(const Duration(seconds: 1), (index) => index + 1),
      (childCtx, tick) => print('Tick $tick'),
    );

    await ctx.pause(const Duration(milliseconds: 2500));
    await ticks.cancel();
    print('Parent continues');
  });

  await job.value;
}

Job<void> savingInSteps() => Job<void>((ctx) async {
      final processing = ctx.each(messages, (childCtx, message) async {
        await store.saveBody(message);
        await store.saveAttachments(message);
      });
      ctx.onDispose(() => stage.trace.add('parent cleanup'));
      await processing.value;
    });

Job<void> savingWithCheckpoints() => Job<void>((ctx) async {
      final processing = ctx.each(messages, (childCtx, message) async {
        await childCtx.join(() => store.saveBody(message));
        await childCtx.join(() => store.saveAttachments(message));
      });
      ctx.onDispose(() => stage.trace.add('parent cleanup'));
      await processing.value;
    });

Job<void> feedLeftToItself() => Job<void>((ctx) async {
      final feed = Feed();
      await ctx.each(feed.messages, (childCtx, message) => save(message)).value;
    });

Job<void> feedClosedByTheJob() => Job<void>((ctx) async {
      final feed = Feed();
      ctx.onDispose(feed.close);
      await ctx.each(feed.messages, (childCtx, message) => save(message)).value;
    });

Job<void> draftsOnTheStackOfTheStream() => Job<void>((ctx) async {
      final processing = ctx.each(messages, (childCtx, message) async {
        final draft = await childCtx.join(
          () => store.openDraft(message),
          dispose: (draft) => draft.close(),
        );
        await childCtx.join(draft.write);
      });
      await processing.value;
    });

Job<void> draftsOnTheStackOfTheirEvent() => Job<void>((ctx) async {
      // ignore: prefer_expression_function_bodies
      final processing = ctx.each(messages, (childCtx, message) {
        return childCtx.run(Job.deferred<void>((eventCtx) async {
          final draft = await eventCtx.join(
            () => store.openDraft(message),
            dispose: (draft) => draft.close(),
          );
          await eventCtx.join(draft.write);
          // ignore: require_trailing_commas
        }));
      });
      await processing.value;
    });

Job<void> awaitForInABody() => Job<void>((ctx) async {
      await for (final message in messages) {
        await ctx.join(() => store.saveBody(message));
      }
    });

Job<void> listenInABody() => Job<void>((ctx) async {
      final subscription = messages.listen((message) async {
        await store.saveBody(message);
      });
      ctx.onCancel(subscription.cancel);
      await ctx.wait(subscription.asFuture<void>);
    });

Future<void> saveAll(
  Stream<String> messages,
  Future<void> Function(String message) save,
) async {
  // ignore: prefer_expression_function_bodies
  final saving = Job.each(messages, (ctx, message) {
    return ctx.join(() => save(message));
  });

  await saving.value;
}
