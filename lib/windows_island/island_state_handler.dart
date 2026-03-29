import 'package:flutter/material.dart';
import 'island_config.dart';

/// Interface for custom island state handlers.
/// Implement this to add new states to the island UI.
abstract class IslandStateHandler {
  /// Unique identifier for this state
  String get stateId;

  /// Map this handler's stateId to IslandStateConfig
  IslandStateConfig get configState;

  /// Build the UI widget for this state
  Widget build(
    BuildContext context,
    Map<String, dynamic>? payload,
    IslandStateContext stateContext,
  );

  /// Called when entering this state
  void onEnter(Map<String, dynamic>? payload) {}

  /// Called when exiting this state
  void onExit() {}

  /// Whether this state can transition to [targetState]
  bool canTransitionTo(String targetState) => true;

  /// Get the target size for this state
  Size getTargetSize(Map<String, dynamic>? payload) {
    return IslandConfig.sizeForState(configState);
  }
}

/// Context provided to state handlers for interaction
class IslandStateContext {
  final void Function(String action, [int? modifiedSecs, String? data])?
      onAction;
  final void Function(IslandStateConfig nextState) transitionTo;
  final void Function(Size targetSize) resizeWithAnimation;
  final Map<String, dynamic>? Function() getCurrentPayload;
  final void Function() startDragging;

  const IslandStateContext({
    required this.onAction,
    required this.transitionTo,
    required this.resizeWithAnimation,
    required this.getCurrentPayload,
    required this.startDragging,
  });
}

/// Registry for island state handlers.
/// Use this to register custom states.
class IslandStateRegistry {
  IslandStateRegistry._();

  static final Map<String, IslandStateHandler> _handlers = {};

  /// Register a custom state handler
  static void register(IslandStateHandler handler) {
    _handlers[handler.stateId] = handler;
  }

  /// Unregister a custom state handler
  static void unregister(String stateId) {
    _handlers.remove(stateId);
  }

  /// Get a handler by state ID
  static IslandStateHandler? getHandler(String stateId) {
    return _handlers[stateId];
  }

  /// Check if a custom handler exists for the state
  static bool hasHandler(String stateId) {
    return _handlers.containsKey(stateId);
  }

  /// Get all registered state IDs
  static Set<String> get registeredStates => _handlers.keys.toSet();

  /// Clear all registered handlers
  static void clear() {
    _handlers.clear();
  }
}

/// Built-in state IDs
class IslandStateId {
  IslandStateId._();

  static const String idle = 'idle';
  static const String focusing = 'focusing';
  static const String hoverWide = 'hoverWide';
  static const String splitAlert = 'splitAlert';
  static const String stackedCard = 'stackedCard';
  static const String finishConfirm = 'finishConfirm';
  static const String abandonConfirm = 'abandonConfirm';
  static const String finishFinal = 'finishFinal';
  static const String reminderPopup = 'reminderPopup';
  static const String reminderSplit = 'reminderSplit';
  static const String reminderCapsule = 'reminderCapsule';
  static const String copiedLink = 'copiedLink';
}

/// Convert state string to IslandStateConfig
IslandStateConfig stateStringToConfig(String stateStr) {
  switch (stateStr) {
    case 'idle':
      return IslandStateConfig.idle;
    case 'focusing':
      return IslandStateConfig.focusing;
    case 'split_alert':
      return IslandStateConfig.splitAlert;
    case 'stacked_card':
      return IslandStateConfig.stackedCard;
    case 'finish_confirm':
      return IslandStateConfig.finishConfirm;
    case 'abandon_confirm':
      return IslandStateConfig.abandonConfirm;
    case 'finish_final':
      return IslandStateConfig.finishFinal;
    case 'reminder_popup':
      return IslandStateConfig.reminderPopup;
    case 'reminder_split':
      return IslandStateConfig.reminderSplit;
    case 'reminder_capsule':
      return IslandStateConfig.reminderCapsule;
    case 'copied_link':
      return IslandStateConfig.copiedLink;
    default:
      return IslandStateConfig.idle;
  }
}

/// Convert IslandStateConfig to state string
String stateConfigToString(IslandStateConfig config) {
  switch (config) {
    case IslandStateConfig.idle:
      return 'idle';
    case IslandStateConfig.focusing:
      return 'focusing';
    case IslandStateConfig.hoverWide:
      return 'hoverWide';
    case IslandStateConfig.splitAlert:
      return 'split_alert';
    case IslandStateConfig.stackedCard:
      return 'stacked_card';
    case IslandStateConfig.finishConfirm:
      return 'finish_confirm';
    case IslandStateConfig.abandonConfirm:
      return 'abandon_confirm';
    case IslandStateConfig.finishFinal:
      return 'finish_final';
    case IslandStateConfig.reminderPopup:
      return 'reminder_popup';
    case IslandStateConfig.reminderSplit:
      return 'reminder_split';
    case IslandStateConfig.reminderCapsule:
      return 'reminder_capsule';
    case IslandStateConfig.copiedLink:
      return 'copied_link';
  }
}
