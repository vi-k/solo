part of 'conveyor.dart';

/// Only for testing!
@visibleForTesting
mixin TestSetState<BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>>
    on Conveyor<BaseState, Event> {
  @visibleForTesting
  @protected
  void testSetState(BaseState state) => _setState(state);
}
