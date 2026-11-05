abstract class InferenceEngine<TInput, TOutput> {
  Future<void> initialize();
  Future<TOutput> runInference(TInput input);
  void dispose();
}
