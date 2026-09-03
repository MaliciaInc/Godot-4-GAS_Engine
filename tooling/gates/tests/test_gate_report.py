from __future__ import annotations

import dataclasses
import sys
import unittest
from pathlib import Path

# Imported as part of its package: the shared library uses relative imports, so
# a file-location load would break on the first one.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib import gate_report  # noqa: E402


class GateReportTests(unittest.TestCase):
    """What a rendered report may and may not contain.

    These reports are committed as release evidence, so a report is a file that
    has to be identical for an identical run in any checkout. It was not: the
    header rendered the resolved project root, which put an absolute path - and
    a username - into every `.md` this renderer produced. Sanitising them
    afterwards is not the fix; a generated artefact has to come out clean.
    """

    def _rendered(self) -> str:
        report = gate_report.Report(
            title="Probe Gate",
            blocking=(),
            scan_issues=(),
            files_scanned=3,
        )
        return gate_report.render_report(report)

    def test_the_header_names_the_repository_and_not_a_place_on_a_disk(self) -> None:
        rendered = self._rendered()

        self.assertIn("- Project: `<repo>`", rendered)

    def test_nothing_rendered_looks_like_an_absolute_path(self) -> None:
        # The shapes a machine path takes on the three platforms this could be
        # run from. None of them belongs in a committed report.
        rendered = self._rendered()

        for shape in (":\\", ":/", "/home/", "/Users/", "\\Users\\"):
            with self.subTest(shape=shape):
                self.assertNotIn(shape, rendered)

    def test_a_report_cannot_be_given_a_root_to_render(self) -> None:
        # The field is gone rather than merely unread. An unread field on a
        # dataclass every gate fills in is an invitation to print it again, and
        # the next person to add a row to this header would have had no way of
        # knowing why they should not.
        self.assertNotIn(
            "root", {field.name for field in dataclasses.fields(gate_report.Report)}
        )


if __name__ == "__main__":
    unittest.main()
