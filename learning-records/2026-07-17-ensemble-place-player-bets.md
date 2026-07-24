# Ensemble Session — Place Player Bets against PlayerAccount

**Date:** 2026-07-17
**Repo:** [`tedyoung/blackjack-ensemble-blue`](https://github.com/tedyoung/blackjack-ensemble-blue) (branch [`mob-session`](https://github.com/tedyoung/blackjack-ensemble-blue/tree/mob-session))
**Format:** Mob/ensemble via `mob.sh` + Zoom
**Participants (from commits):** Ted M. Young, Lada Kesseler, CodeItQuick, Daniel Ranner, Tom Spencer

---

## Goal of the session

Turn the deliberately-failing WIP test
`GameServiceTest.placeBetsForPlayerAccountWithInsufficientBalanceThrowsException`
green **for the right reason**, and start wiring `GameService.placePlayerBets(...)`
to the event-sourced `PlayerAccount` — the money/wallet side of placing a bet.

---

## What we changed (from the git diff, not the "mob next" messages)

### 1. `GameService.placePlayerBets(...)` — implemented (smallest step)
```java
public void placePlayerBets(List<PlayerBet> bets) {
    PlayerBet firstPlayerBet = bets.getFirst();
    Optional<PlayerAccount> playerAccount =
            playerAccountRepository.find(firstPlayerBet.playerId());
    playerAccount.ifPresent(account -> {
        account.bet(firstPlayerBet.bet().amount());   // throws InsufficientBalance if too low
        playerAccountRepository.save(account);
    });
    currentGame.placePlayerBets(bets);
}
```
- Uses `find(...).ifPresent(...)` so tests with **no account** simply skip (they stay green) —
  only a *found* account with too little balance throws.
- Deliberately handles **only the first bet** (`getFirst()`) — a fake-it/smallest-step to get to
  green before generalising to all players.

### 2. `GameService.createForTest(...)` — signature shielding, and one `null` removed
- `createForTest(Shuffler)` now passes **`new PlayerAccountRepository()`** instead of `null`.
- Added a shielded factory `createForTest(GameMonitor, Shuffler)` so tests stop calling the
  raw 4-arg constructor.

### 3. `GameServiceTest.placeBetsForPlayerAccountWithInsufficientBalanceThrowsException`
- **IDs aligned** so the account is actually found (killed the false-green):
  `withNextId(74)` + `PlayerId.of(9)` → `withNextId(111)` + `PlayerId.of(111)`.
- **Assertion made more expressive** — `assertThatIllegalStateException()` →
  `assertThatExceptionOfType(InsufficientBalance.class)`. We let the *meaningful domain
  exception* win instead of forcing a generic one.

### 4. `GameServiceTest.placeBetsReducesPlayerAccountBalance` — un-`@Disabled` and implemented
```java
var repo = PlayerAccountRepository.withNextId(7);
var account = PlayerAccount.register("enough money");
account.deposit(30);
repo.save(account);                                   // account seeded via the aggregate
...
gameService.placePlayerBets(List.of(new PlayerBet(PlayerId.of(7), Bet.of(13))));
assertThat(repo.find(PlayerId.of(7))).get()
        .extracting(PlayerAccount::balance).isEqualTo(30 - 13);   // 17
```
Replaced the `fail("Start here")` placeholder with a real behaviour assertion.

### 5. `MultiPlayerGameMonitorTest` — moved onto the shield
- `new GameService(spy, DUMMY_GAME_REPOSITORY, new StubShuffler(), null)`
  → `GameService.createForTest(gameMonitorSpy, new StubShuffler())`.

---

## The domain behaviour behind it

`PlayerAccount` is an **event-sourced aggregate**:
- `register` / `deposit` / `bet` don't mutate fields — they **enqueue events**
  (`MoneyDeposited`, `MoneyBet`, `PlayerWonGame`).
- `apply(event)` folds each event into `balance` (`+= amount`, `-= amount`, …).
- `PlayerAccountRepository.save()` appends the fresh events; `find()` **replays** them
  (`reconstitute`) to rebuild the account.

So "placing a bet" = look up the account, append a `MoneyBet` event (which `bet()` refuses if
the balance is too low), and save — then a later `find()` sees the reduced balance.

---

## Best practices we followed

- **Don't introduce `null` when changing a signature.** Replace it with a real cheap object
  (`new PlayerAccountRepository()`) or a no-op dummy (`game -> {}`), or shield it.
- **Signature shielding.** Route tests through a `createForTest(...)` creation method so a
  constructor change is one edit, not many. (The tests still on the raw constructor were exactly
  the ones that broke earlier — proof the shield works.)
- **Smallest change to green, then improve.** `getFirst()` before looping all bets.
- **Read the red.** The failing test showed `InsufficientBalance` where it expected
  `IllegalStateException`. The "unexpected" exception was the *more correct* one — so we asserted
  it, rather than dumbing the code down to a generic exception.
- **Seed test state through the aggregate**, not by poking fields — `register` → `deposit` → `save`.
- **Enable the next disabled test** as the next red step (TDD triangulation).

## Key lessons

1. **`null` is a hidden landmine.** It's harmless until the first code path *uses* the dependency,
   then it's an NPE at every construction site. Shield or supply a real/dummy value instead.
2. **A failing test with an unexpected-but-correct result is a design cue**, not a mechanical fix —
   let the more expressive domain exception drive the code.
3. **Parallel change & signature shielding both use deliberate, temporary duplication as a
   stepping stone**: expand (duplicate) → migrate callers one-by-one (stay green) → contract
   (delete the old). Safe only if you finish by removing the duplication.
4. **Break large refactors into small safe steps** — green before and after each step, so a
   red bar names its own culprit. (See the Mikado Method / TCR for drilling this.)

---

## Deep dive: the techniques in full

### Signature shielding

**In one sentence:** route tests through a single creation method or builder instead of calling a
production constructor/method directly, so that when its signature changes you fix it in *one place*
rather than across every test.

The live example is `createForTest`:

```java
public static GameService createForTest(Shuffler shuffler) {
    return new GameService(game -> {}, game -> {}, shuffler, new PlayerAccountRepository());
}
```

- Most tests do `GameService.createForTest(new StubShuffler())` and **never touch the raw 4-arg
  constructor**. So when the constructor grew a `PlayerAccountRepository` parameter, only
  `createForTest` changed — the ~13 tests through it kept compiling.
- The shield **failed where it wasn't used**: tests that called
  `new GameService(dummyGameMonitor, repositorySpy, new StubShuffler(), null)` directly were exactly
  the ones that broke and had to be edited by hand. Shielded tests survived; unshielded ones didn't.
- Bonus: the factory **hides irrelevant parameters** by passing no-op lambdas (`game -> {}`) for the
  monitor the test doesn't care about — keeping tests about behaviour, not construction plumbing.

**Goal to aim for:** when the ensemble adds a parameter, *one edit to the creation method, zero edits
to the tests using it.*

### `null` vs a real-or-dummy value

Never introduce `null` when you change a signature. A `null` argument is a hidden landmine —
harmless until the first code path actually *uses* the dependency, then it's an NPE at every call
site. Supply the cheapest **honest** value instead:

- **Real cheap instance** when the test needs it to behave — `new PlayerAccountRepository()`.
- **No-op dummy** when the test doesn't care — a lambda like `GameMonitor game -> {}`.

Both are honest and safe; `null` is neither.

### Small safe steps

A step is **safe** when tests are green before *and* after it. A step is **small** when a red bar
names its own culprit, because you only changed one thing. Together: *never be more than one
`git revert` away from a working system.*

The cautionary tale was ours — implementing `placePlayerBets` in one leap turned ~20 tests red at
once (a mix of NPEs and "no account" errors) and we had to reverse-engineer which change caused
which failure. The same destination in small steps stays green the whole way.

Named moves to reach for:

- **Parallel change (expand → migrate → contract)** — add the new form beside the old (both work),
  migrate callers one at a time (green after each), then delete the old. The `createForTest`
  overloads are exactly this.
- **Branch by abstraction** — introduce an interface over the thing you're replacing, move everyone
  onto it (green), swap the implementation, delete the old. How you'd safely turn a concrete
  `PlayerAccountRepository` into a port.
- **Preparatory refactoring** — "make the change easy (this may be hard), then make the easy change."
- **Lean on the compiler** — make the breaking change deliberately, use the compile errors as a
  worklist you can't miss a spot on.
- **Prefer automated refactorings** (Rename, Extract Method, Change Signature) — behaviour-preserving
  by construction, so always a safe step.

For large refactors, the **Mikado Method** plans it: attempt the goal naively, and when it breaks
*don't fix forward* — note the prerequisites, revert to green, do those first (recursively), and
execute the resulting dependency graph leaves-first. To drill the habit, **TCR**
(`test && commit || revert`) is the most brutal teacher — you can't stay red, so steps stay tiny.

### Duplication as a stepping stone

Parallel change and signature shielding are two instances of **duplicate → migrate → converge**. You
stand up the new form beside the old (that coexistence *is* the duplication), migrate callers one by
one staying green, then delete the old form so the duplication disappears.

This is not the "bad" DRY-violating duplication — it's **intentional, temporary, green-keeping**.
Duplication is a smell at rest but a technique in motion; the distinction is whether it's on its way
out. The one discipline that makes it safe: you **must** take the contract step — a shield or
overload you introduce and then leave stops being a scaffold and becomes real debt.

### Event-sourced aggregate (the domain machinery)

`PlayerAccount` combines two DDD ideas:

- **Aggregate** — a cluster of objects with one consistency boundary, reached through a root that
  guards invariants. Nobody edits `balance` directly; they call `bet()` / `deposit()`.
- **Event sourcing** — store the *sequence of events* (`deposited 10`, `bet 5`), not the current
  state, and derive state by replaying them. Events are the source of truth; state is a fold over
  them.

Commands don't mutate state — they **emit events**:

```java
public void bet(int amount) {
    if (balance < amount) throw new InsufficientBalance(...);
    enqueue(new MoneyBet(amount));      // record the fact
}
```

- `apply(event)` is the **only** place state changes — it folds each event into `balance`
  (`MoneyDeposited` → `+= amount`, `MoneyBet` → `-= amount`, `PlayerWonGame` → `+= payout`).
- `reconstitute(playerId, events)` rebuilds an aggregate by replaying its whole event list.
- The repository stores **events, not state** — `save()` appends the fresh events, `find()` reads and
  replays them.

**One-liner:** an event-sourced aggregate treats state as a left-fold over an append-only list of
events — `bet()`/`deposit()` append facts, `apply()` folds them into the balance, and
`reconstitute()` replays the whole list to rebuild the object. This is also *why* we seed test state
through the aggregate (`register` → `deposit` → `save`) — you set up state by supplying past events,
not by poking fields.

---

## Follow-ups / not yet done

- `placePlayerBets` only handles **the first bet** — generalise to loop all `bets` (multi-player).
- Clean up leftovers in `GameService`: the commented-out `if (playerAccountRepository != null)`
  and the new `createForTest(GameMonitor, Shuffler)` factory that still passes `null` internally
  (contract step — remove the stepping-stone `null`).
- Wire the **win/payout** side (`execute()` game-over path still has `// repository.save(...)`
  comments and a `PlayerWonGame` event waiting to be used).
