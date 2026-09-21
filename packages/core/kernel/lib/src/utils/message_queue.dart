import 'dart:async';
import 'dart:collection';

/// A generic class to handle message queue processing.
///
/// Example usage:
///
/// ```dart
/// void main() async {
///   // Define a processing function that takes some time to complete.
///   Future<void> processMessage(({String message, int seconds}) params) async {
///     print('Processing message: ${params.message}');
///     await Future.delayed(Duration(seconds: params.seconds));
///     print('Finished processing message: ${params.message}');
///   }
///
///   // Create an instance of MessageQueue without the processing function.
///   final messageQueue = MessageQueue();
///
///   // Set the processing function.
///   messageQueue.setProcessingFunction(processMessage);
///
///   // Enqueue some messages.
///   messageQueue.enqueue((message: 'Message 1', seconds: 1));
///   messageQueue.enqueue((message: 'Message 2', seconds: 0));
///   messageQueue.enqueue((message: 'Message 3', seconds: 3));
///
///   // Optionally, break the current process or all processes.
///   // messageQueue.breakCurrentProcess();
///   // messageQueue.breakAllProcesses();
/// }
class MessageQueue<T> {
  /// The queue to store messages.
  final _queue = Queue<T>();

  /// Flag to indicate if a message is being processed.
  var _isProcessing = false;

  /// Function to process a single message.
  FutureOr<void> Function(T message)? _processMessage;

  /// Constructor to initialize the message queue.
  MessageQueue([this._processMessage]);

  /// Sets the processing function.
  void setProcessingFunction(
    FutureOr<void> Function(T message) processMessage,
  ) {
    _processMessage = processMessage;
  }

  /// Adds a message to the queue and starts processing if not already processing.
  Future<void> enqueue(T message) async {
    _queue.add(message);
    if (!_isProcessing) {
      await _processQueue();
    }
  }

  /// Processes the message queue.
  ///
  /// This function processes messages in the queue one by one. It sets the
  /// `_isProcessing` flag to true while processing and sets it to false
  /// when the queue is empty.
  Future<void> _processQueue() async {
    if (_processMessage == null) {
      throw Exception('Processing function is not set.');
    }

    _isProcessing = true;
    while (_queue.isNotEmpty) {
      final message = _queue.removeFirst();
      await _processMessage!(message);
    }
    _isProcessing = false;
  }

  /// Breaks all processes and clears the queue.
  ///
  /// This method clears the queue and completes the current process completer to stop all processing.
  void breakAllProcesses() {
    _queue.clear();
  }

  /// Disposes the message queue.
  ///
  /// This method clears the queue, completes the current process completer,
  /// and sets the processing function to null to ensure no further processing occurs.
  void dispose() {
    breakAllProcesses();
  }
}
