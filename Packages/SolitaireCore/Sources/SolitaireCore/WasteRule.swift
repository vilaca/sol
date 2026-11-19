/// What Golf and TriPeaks share: a card from the layout goes to the waste when it is one rank above or below
/// the waste's top card, and a game is won when the layout is empty.
enum WasteRule {
    /// Whether `card` can go onto `top`. With `wraps`, an ace and a king are neighbours.
    static func fits(_ card: Card, on top: Card, wraps: Bool) -> Bool {
        let distance = abs(card.rank - top.rank)
        return distance == 1 || (wraps && distance == 12)
    }

    /// The most cards that playing from the layout alone (no draws) can still clear, found by depth-first search.
    /// `next` lists the positions one play away. The search stops after `budget` positions and returns the best
    /// chain found so far, so a hint is always quick.
    static func longestChain<State>(from state: State, budget: Int = 3000, next: (State) -> [State]) -> Int {
        var visited = 0
        func search(_ state: State) -> Int {
            var best = 0
            for following in next(state) {
                visited += 1
                if visited > budget { return best }
                best = max(best, 1 + search(following))
            }
            return best
        }
        return search(state)
    }
}
