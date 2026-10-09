#!/usr/bin/env python3
"""Independent campaign invariants and solution-certificate verification."""
from collections import Counter
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CampaignTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.levels = json.loads((ROOT / "data/levels.json").read_text())

    def test_campaign_structure_and_diversity(self):
        self.assertEqual(len(self.levels), 240)
        self.assertEqual([level["id"] for level in self.levels], list(range(1, 241)))
        self.assertEqual(Counter(level["chapter"] for level in self.levels), {i: 40 for i in range(6)})
        self.assertEqual({level["mode"] for level in self.levels}, {"classic", "mist", "tall", "tight"})
        self.assertEqual({level["capacity"] for level in self.levels}, {3, 4, 5})
        signatures = {tuple(sorted(tuple(tube) for tube in level["tubes"])) for level in self.levels}
        self.assertEqual(len(signatures), 240, "Campaign contains duplicate boards")

    def test_every_solution_is_a_legal_maximal_pour(self):
        for level in self.levels:
            with self.subTest(level=level["id"]):
                capacity = level["capacity"]
                board = [tube[:] for tube in level["tubes"]]
                inventory = Counter(color for tube in board for color in tube)
                self.assertTrue(all(total == capacity for total in inventory.values()))
                self.assertTrue(all(not tube or len(tube) == capacity for tube in board))
                self.assertEqual(sum(not tube for tube in board), 1 if level["mode"] == "tight" else 2)
                self.assertTrue(any(len(set(tube)) > 1 for tube in board))
                self.assertTrue(level["solution"])
                for step, (source, target) in enumerate(level["solution"]):
                    self.assertNotEqual(source, target, step)
                    self.assertTrue(0 <= source < len(board) and 0 <= target < len(board), step)
                    self.assertTrue(board[source], step)
                    self.assertLess(len(board[target]), capacity, step)
                    color = board[source][-1]
                    self.assertTrue(not board[target] or board[target][-1] == color, step)
                    # Execute one atomic unit at a time until the mandatory pour
                    # has finished, independent of the generator's implementation.
                    while board[source] and board[source][-1] == color and len(board[target]) < capacity:
                        board[target].append(board[source].pop())
                    self.assertEqual(Counter(value for tube in board for value in tube), inventory)
                self.assertTrue(all(not tube or (len(tube) == capacity and len(set(tube)) == 1) for tube in board))


if __name__ == "__main__":
    unittest.main(verbosity=2)
