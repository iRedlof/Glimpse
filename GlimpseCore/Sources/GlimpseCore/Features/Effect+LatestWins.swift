import ComposableArchitecture

extension Effect {
    /// Latest-wins cancellation that follows the order the reducer started effects.
    ///
    /// `.run { … }.cancellable(id:cancelInFlight: true)` registers and cancels only
    /// once the effect's task reaches the global executor, so effects returned in
    /// the same main-actor turn can register in any order and an older one can
    /// cancel the newest. Publisher effects are subscribed synchronously by the
    /// store, so wrapping first makes cancel-in-flight run in send order: the
    /// newest effect always survives and every superseded one is cancelled at once.
    func cancellableLatestWins(id: some Hashable & Sendable) -> Self {
        Effect.publisher { _EffectPublisher(self) }
            .cancellable(id: id, cancelInFlight: true)
    }
}
