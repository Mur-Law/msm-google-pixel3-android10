# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import sys
import subprocess
import unittest

from absl.testing import absltest

def load_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("script")
    return parser.parse_known_args()


arguments = None


class ExecruleTest(unittest.TestCase):
    def test_no_args(self):
        output = subprocess.check_output([arguments.script], text=True)
        self.assertEqual(output, "script_a\n")


if __name__ == '__main__':
    arguments, unknown = load_arguments()
    sys.argv[1:] = unknown
    absltest.main()
