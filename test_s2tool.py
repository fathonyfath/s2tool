#!/usr/bin/env python3
# SPDX-License-Identifier: 0BSD
"""Tests for s2tool's pure helpers. No Wine or image needed: python3 test_s2tool.py"""
import unittest

import s2tool

OK_LOG = r"""
Failed loading resource "materials/error.vmat_c" (ERROR_FILEOPEN: File not found)
- dota_addons\s2tool\panorama\styles\hud\hud_reborn.css

-----------------------------------------------------------------
 OK: 1 compiled, 0 failed, 0 skipped, 0m:00s
-----------------------------------------------------------------
"""

ERROR_LOG = r"""
- dota_addons\s2tool\panorama\styles\bad.css
Z:\opt\rescomp\content\dota_addons\s2tool\panorama\styles\bad.css(4,2): RESOURCE COMPILE ERROR: Unexpected '}' found; expecting root-level declaration.

                                                                      [FAIL]
 Look for "RESOURCE COMPILE ERROR:" in the log above.
  Unexpected '}' found; expecting root-level declaration.

-----------------------------------------------------------------
 ERROR: 0 compiled, 1 failed, 0 skipped, 0m:00s
-----------------------------------------------------------------
"""


class ParseLog(unittest.TestCase):
    def test_success(self):
        self.assertEqual(s2tool.parse_log(OK_LOG), (1, 0, []))

    def test_error_maps_path_to_in(self):
        ok, failed, errors = s2tool.parse_log(ERROR_LOG)
        self.assertEqual((ok, failed), (0, 1))
        self.assertEqual(errors, ["/in/panorama/styles/bad.css(4,2): "
                                  "Unexpected '}' found; expecting root-level declaration."])

    def test_crash_has_no_summary(self):
        self.assertEqual(s2tool.parse_log("Encountered accessviolation.\n"), (None, None, []))


class DecompiledPath(unittest.TestCase):
    def test_extensions(self):
        self.assertEqual(s2tool.decompiled_path("panorama/styles/hud/hud_reborn.vcss_c"),
                         "panorama/styles/hud/hud_reborn.css")
        self.assertEqual(s2tool.decompiled_path("panorama/images/hud/reborn/bg_minimap_psd.vtex_c"),
                         "panorama/images/hud/reborn/bg_minimap_psd.png")
        self.assertEqual(s2tool.decompiled_path("panorama/layout/hud/hud.vxml_c"), "panorama/layout/hud/hud.xml")


if __name__ == "__main__":
    unittest.main()
