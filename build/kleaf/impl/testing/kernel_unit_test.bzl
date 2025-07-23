# Copyright (C) 2024 The Android Open Source Project
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
"""
Tests for kernel unit testing.
"""

load("@rules_python//python:defs.bzl", "py_test")

visibility("//build/kernel/kleaf/...")

def kunit_test(
        name,
        test_name,
        modules,
        deps,
        **kwargs):
    """A kunit test.

    Args:
        name: name of the test
        test_name: name of the kunit test suite
        modules: list of modules to be installed for kunit test
        deps: dependencies for kunit test runner
        **kwargs: additional arguments for py_test
    """
    test_args = ["--name", test_name, "--modules"] + [
        "$(rootpaths {})".format(m)
        for m in modules
    ]
    py_test(
        name = name,
        main = Label("kunit_test.py"),
        srcs = [Label("kunit_test.py")],
        data = modules,
        args = test_args,
        size = "small",
        deps = deps,
        **kwargs
    )
