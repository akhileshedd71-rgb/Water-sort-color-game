#!/usr/bin/env python3
"""Build the offline campaign with a checked, legal solution for every puzzle.

Gentle puzzles start solved and take only steps whose inverse is an actual
*maximal* pour. Advanced puzzles use shuffled layers and a bounded solver;
unsolved candidates are discarded. Every shipped puzzle has a verified proof.
No third-party packages.
"""
from __future__ import annotations

import json
import itertools
import heapq
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def top_run(tube: list[int]) -> int:
    if not tube:
        return 0
    result = 1
    for color in reversed(tube[:-1]):
        if color != tube[-1]:
            break
        result += 1
    return result


def pour(board: list[list[int]], source: int, target: int, capacity: int):
    if source == target or not board[source] or len(board[target]) >= capacity:
        return None
    if board[target] and board[target][-1] != board[source][-1]:
        return None
    amount = min(top_run(board[source]), capacity - len(board[target]))
    result = [tube[:] for tube in board]
    result[target].extend(result[source][-amount:])
    del result[source][-amount:]
    return result


def solved(board: list[list[int]], capacity: int) -> bool:
    return all(not tube or (len(tube) == capacity and len(set(tube)) == 1) for tube in board)


def key(board: list[list[int]]) -> tuple:
    return tuple(tuple(tube) for tube in board)


def reverse_options(board: list[list[int]], capacity: int):
    """Yield (next board, inverse move) using the real forward move as oracle."""
    for donor, tube in enumerate(board):
        if not tube:
            continue
        run = top_run(tube)
        # A partly stripped mixed run must leave the same color exposed.
        max_remove = run if run == len(tube) else run - 1
        for receiver, into in enumerate(board):
            if donor == receiver or len(into) == capacity:
                continue
            for amount in range(1, min(max_remove, capacity - len(into)) + 1):
                result = [entry[:] for entry in board]
                result[receiver].extend(result[donor][-amount:])
                del result[donor][-amount:]
                if pour(result, receiver, donor, capacity) == board:
                    yield result, [receiver, donor]


def transitions(board: list[list[int]]) -> int:
    return sum(sum(a != b for a, b in zip(tube, tube[1:])) for tube in board)


def scramble(colors: int, capacity: int, helpers: int, seed: int, intensity: float):
    rng = random.Random(seed)
    goal = [[color] * capacity for color in range(colors)] + [[] for _ in range(helpers)]
    best_board = goal
    best_path = []
    best_score = -1.0
    # Independent restarts prevent local dead ends; each walk carries a proof.
    for attempt in range(7):
        board = [tube[:] for tube in goal]
        states = [key(board)]
        state_indices = {states[0]: 0}
        path: list[list[int]] = []
        for step in range(85 + colors * 17):
            options = list(reverse_options(board, capacity))
            if not options:
                break
            # Some neutral/reducing steps are essential to redistribute space.
            scored = []
            for candidate, inverse in options:
                mix = transitions(candidate)
                full_or_empty = sum(not tube or len(tube) == capacity for tube in candidate)
                repeat_penalty = 3.5 if key(candidate) in state_indices else 0
                score = mix * (0.75 + intensity) + full_or_empty * 0.19 + rng.random() * 4.2 - repeat_penalty
                scored.append((score, candidate, inverse))
            _, board, inverse = max(scored, key=lambda entry: entry[0])
            board_key = key(board)
            if board_key in state_indices:
                index = state_indices[board_key]
                path = path[:index]
                states = states[:index + 1]
                state_indices = {value: i for i, value in enumerate(states)}
            else:
                path.append(inverse)
                state_indices[board_key] = len(states)
                states.append(board_key)
            # Conventional initial layout: mixed full bottles + empty helpers.
            if not all(not tube or len(tube) == capacity for tube in board):
                continue
            if solved(board, capacity):
                continue
            mix = transitions(board)
            mixed = sum(len(set(tube)) > 1 for tube in board)
            score = mix * 4 + mixed * 2 + min(len(path), colors * 8) * 0.045
            if score > best_score:
                best_board = [tube[:] for tube in board]
                best_path = [move[:] for move in reversed(path)]
                best_score = score
    if not best_path:
        raise RuntimeError(f"No puzzle found for seed {seed}")
    # Remove cycles once more in the forward certificate, then trim solved tail.
    board = [tube[:] for tube in best_board]
    solution = []
    for move in best_path:
        result = pour(board, *move, capacity)
        assert result is not None, (seed, move, board)
        board = result
        solution.append(move)
        if solved(board, capacity):
            break
    assert solved(board, capacity), seed
    return best_board, solution


def normalize(board: list[list[int]], solution: list[list[int]], capacity: int):
    """Put helpers last, and remove moves that merely rename identical bottles."""
    order = sorted(range(len(board)), key=lambda index: not bool(board[index]))
    mapping = {old: new for new, old in enumerate(order)}
    initial = [board[index][:] for index in order]
    current = [tube[:] for tube in initial]
    cleaned = []
    for old_source, old_target in solution:
        source, target = mapping[old_source], mapping[old_target]
        if current[source] and len(set(current[source])) == 1 and not current[target]:
            # The original certificate relocates one homogeneous tube. Keep
            # the liquid still and redirect all subsequent bottle references.
            mapping[old_source], mapping[old_target] = target, source
            continue
        result = pour(current, source, target, capacity)
        assert result is not None
        current = result
        cleaned.append([source, target])
        if solved(current, capacity):
            break
    assert solved(current, capacity)
    return initial, cleaned


def signature(board: list[list[int]], colors: int) -> tuple:
    # Small beginner boards are additionally unique up to color renaming.
    if colors <= 3:
        return min(tuple(sorted(tuple(palette[color] for color in tube) for tube in board))
                   for palette in itertools.permutations(range(colors)))
    return tuple(sorted(tuple(tube) for tube in board))


def solve(start: list[list[int]], capacity: int, max_states: int = 15000):
    """Best-first solver used only at generation time, with symmetry pruning."""
    color_count = len({color for tube in start for color in tube})

    def estimate(board):
        blocks = sum(sum(a != b for a, b in zip(tube, tube[1:])) + bool(tube) for tube in board)
        unfinished = sum(bool(tube) and (len(tube) != capacity or len(set(tube)) != 1) for tube in board)
        return (blocks - color_count) * 5 + unfinished

    initial = key(start)
    heap = [(estimate(initial), 0, initial, [])]
    seen = {tuple(sorted(initial))}
    serial = 0
    while heap and len(seen) < max_states:
        _, _, board, path = heapq.heappop(heap)
        if estimate(board) == 0:
            return path
        for source, tube in enumerate(board):
            if not tube or (len(tube) == capacity and len(set(tube)) == 1):
                continue
            run = top_run(tube)
            visited_empty = False
            for target, into in enumerate(board):
                if source == target or len(into) == capacity or (into and into[-1] != tube[-1]):
                    continue
                if not into:
                    if visited_empty or run == len(tube):
                        continue
                    visited_empty = True
                amount = min(run, capacity - len(into))
                next_board = list(board)
                next_board[source] = tube[:-amount]
                next_board[target] = into + tube[-amount:]
                next_board = tuple(next_board)
                state_key = tuple(sorted(next_board))
                if state_key in seen:
                    continue
                seen.add(state_key)
                serial += 1
                next_path = path + [[source, target]]
                heapq.heappush(heap, (estimate(next_board) + len(next_path) * 0.4, serial, next_board, next_path))
    return None


def complex_scramble(colors: int, capacity: int, helpers: int, seed: int):
    """Choose a tangled solvable board, falling back safely for narrow puzzles."""
    rng = random.Random(seed)
    candidates = []
    for _attempt in range(64 if helpers == 1 else 12):
        layers = list(range(colors)) * capacity
        rng.shuffle(layers)
        board = [layers[i * capacity:(i + 1) * capacity] for i in range(colors)] + [[] for _ in range(helpers)]
        if any(len(set(tube)) == 1 for tube in board if tube):
            continue
        solution = solve(board, capacity)
        if solution:
            candidates.append((transitions(board) + len(solution) * 0.3, board, solution))
            if len(candidates) >= 4:
                break
    if candidates:
        _, board, solution = max(candidates, key=lambda candidate: candidate[0])
        return board, solution
    return scramble(colors, capacity, helpers, seed, 1.5)


CHAPTERS = [
    ("First light", "classic"),
    ("Prism garden", "classic"),
    ("Veiled waters", "mist"),
    ("Deep currents", "tall"),
    ("Narrow passage", "tight"),
    ("Afterglow", "classic"),
]
NAMES = ["Dewdrop", "Ripple", "Crosscurrent", "Refraction", "Daydream", "Undertow", "Cascade", "Color knot", "Echo pool", "Orbit"]


def build_levels() -> list[dict]:
    levels = []
    seen = set()
    for index in range(240):
        chapter, local = divmod(index, 40)
        chapter_name, mode = CHAPTERS[chapter]
        if chapter == 0:
            colors = 2 + min(3, local // 10)
        elif chapter == 1:
            colors = 4 + local // 10
        elif chapter == 2:
            colors = 5 + local // 10
        elif chapter == 3:
            colors = 5 + local // 10
        elif chapter == 4:
            colors = 4 + local // 10
        else:
            colors = 7 + local // 10
            mode = ["classic", "mist", "tall", "tight"][local % 4]
        capacity = 5 if mode == "tall" else 4
        # Short flasks are a deliberate change of rhythm in the final chapter.
        if chapter == 5 and local % 10 == 4:
            capacity = 3
        helpers = 1 if mode == "tight" else 2
        seed = 0xA7E11E + index * 7919
        for retry in range(80):
            if index == 0:
                board = [[0, 0, 0, 1], [1, 1, 1, 0], [], []]
                solution = [[0, 2], [1, 0], [1, 2]]
            else:
                complex_level = (chapter == 1 and (local % 4 == 3 or local >= 30)) or (chapter >= 2 and local >= 5)
                if complex_level:
                    board, solution = complex_scramble(colors, capacity, helpers, seed + retry)
                else:
                    board, solution = scramble(colors, capacity, helpers, seed + retry, 0.3 + index / 240)
            board, solution = normalize(board, solution, capacity)
            board_signature = signature(board, colors)
            if board_signature not in seen:
                seen.add(board_signature)
                break
        else:
            raise RuntimeError(f"Could not generate unique level {index+1}")
        difficulty = "Gentle" if index < 10 else "Flowing" if chapter == 0 else "Thoughtful" if chapter < 3 else "Challenging" if chapter < 5 else "Expert"
        level = {
            "id": index + 1,
            "name": "A little color" if index == 0 else f"{NAMES[local % len(NAMES)]} {local // 10 + 1}",
            "chapter": chapter,
            "chapter_name": chapter_name,
            "mode": mode,
            "capacity": capacity,
            "tubes": board,
            "solution": solution,
            "difficulty": difficulty,
            "seed": seed,
        }
        levels.append(level)
        if (index + 1) % 10 == 0:
            print(f"Generated {index+1}/240 ({colors} colors, {mode}, {len(solution)} certified moves)", flush=True)
    return levels


if __name__ == "__main__":
    output = ROOT / "data" / "levels.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    levels = build_levels()
    output.write_text(json.dumps(levels, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Wrote {len(levels)} certified puzzles to {output}")
