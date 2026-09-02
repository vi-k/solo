part of 'conveyor.dart';

mixin ExternalSetState<BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>>
    on Conveyor<BaseState, Event> {
  @protected
  void externalSetState(BaseState state) => _externalSetState(state);
}
