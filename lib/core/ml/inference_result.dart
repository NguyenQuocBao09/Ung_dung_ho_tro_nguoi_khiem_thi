class InferenceResult<T> {
  final T data;
  final double confidence;
  final int inferenceTimeMs;
  InferenceResult({required this.data, required this.confidence, required this.inferenceTimeMs});
}
