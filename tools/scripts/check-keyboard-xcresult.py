#!/usr/bin/env python3
"""Fail closed on one explicitly selected isolated suite's public xcresult summary/tree."""

import argparse
import hashlib
import json
import pathlib
import re


def require(condition, message):
    if not condition:
        raise ValueError(message)


SUPPORTED_SUITES = ("CalendarKeyboardOwnershipTests", "AIDateSearchIntegrationTests",
                    "CalendarAgendaRefreshTests")


def validate(manifest, summary, tests, *, runtime_warnings=None, suite=SUPPORTED_SUITES[0]):
    require(suite in SUPPORTED_SUITES, "Unsupported test suite")
    require(isinstance(manifest, dict) and type(manifest.get("schema_version")) is int
            and manifest["schema_version"] == 1,
            "Invalid method manifest schema")
    expected = manifest.get("methods")
    require(isinstance(expected, dict) and bool(expected), "Empty or invalid method manifest")
    for identifier, count in expected.items():
        require(re.fullmatch(rf"{re.escape(suite)}/[A-Za-z_]\w*\([^/]*\)", identifier)
                and type(count) is int and count > 0, "Invalid required method or case count")
    require(isinstance(summary, dict) and summary.get("result") == "Passed",
            "Summary did not pass")
    for field, count in (("totalTestCount", len(expected)), ("passedTests", len(expected)),
                         ("failedTests", 0), ("skippedTests", 0), ("expectedFailures", 0)):
        require(type(summary.get(field)) is int and summary[field] == count,
                f"Invalid summary {field}")
    require(summary.get("testFailures") == [], "Summary contains failures or invalid failure data")
    configurations = summary.get("devicesAndConfigurations")
    require(isinstance(configurations, list) and len(configurations) == 1,
            "Expected exactly one device/configuration")
    configuration = configurations[0]
    require(isinstance(configuration, dict), "Invalid device/configuration")
    for field, count in (("passedTests", sum(expected.values())), ("failedTests", 0),
                         ("skippedTests", 0), ("expectedFailures", 0)):
        require(type(configuration.get(field)) is int and configuration[field] == count,
                f"Invalid execution {field}")
    require(isinstance(tests, dict) and isinstance(tests.get("testNodes"), list)
            and bool(tests["testNodes"]), "Empty or invalid test tree")
    methods = {}
    prefix = "test://com.apple.xcode/Glimpse/GlimpseTests/"

    def retain_warning(warning, method, parameter=None):
        require(isinstance(warning, dict) and warning.get("nodeType") == "Runtime Warning"
                and set(warning) <= {"nodeType", "name", "sourceLocation", "children"}
                and isinstance(warning.get("name"), str) and bool(warning["name"].strip())
                and isinstance(warning.get("children", []), list)
                and not warning.get("children", []), "Invalid runtime warning")
        if "sourceLocation" in warning:
            location = warning["sourceLocation"]
            require(isinstance(location, dict)
                    and set(location) == {"filePath", "lineNumber"}
                    and isinstance(location["filePath"], str)
                    and bool(location["filePath"].strip())
                    and type(location["lineNumber"]) is int and location["lineNumber"] > 0,
                    "Invalid runtime warning source location")
        if runtime_warnings is not None:
            entry = {"method": method, **warning}
            if parameter is not None:
                entry["parameter"] = parameter
            runtime_warnings.append(entry)

    def visit(node):
        require(isinstance(node, dict) and node.get("result") == "Passed",
                "A test tree node is not Passed")
        children = node.get("children", [])
        require(isinstance(children, list), "Invalid test children")
        kind = node.get("nodeType")
        if kind == "Test Case":
            identifier = node.get("nodeIdentifier")
            require(isinstance(identifier, str) and identifier in expected,
                    "Unexpected or missing method identifier")
            require(identifier not in methods, "Duplicate method execution")
            require(node.get("nodeIdentifierURL") == prefix + identifier, "Invalid method URL")
            urls, names = set(), set()
            for child in children:
                if isinstance(child, dict) and child.get("nodeType") == "Runtime Warning":
                    retain_warning(child, identifier)
                    continue
                require(isinstance(child, dict) and child.get("nodeType") == "Arguments"
                        and child.get("result") == "Passed"
                        and isinstance(child.get("children", []), list),
                        "Invalid or non-Passed parameter case")
                url, name = child.get("nodeIdentifierURL"), child.get("name")
                require(isinstance(url, str) and url.startswith(prefix + identifier + "?args=")
                        and len(url) > len(prefix + identifier + "?args=")
                        and url not in urls, "Missing or duplicate parameter identity")
                require(isinstance(name, str) and bool(name) and name not in names,
                        "Missing or duplicate parameter name")
                for warning in child.get("children", []):
                    retain_warning(warning, identifier, {"name": name, "nodeIdentifierURL": url})
                urls.add(url)
                names.add(name)
            count = len(urls) if urls else 1
            require(count == expected[identifier], "Missing or unexpected parameter execution")
            methods[identifier] = count
        else:
            require(kind in ("Test Plan", "Unit test bundle", "Test Suite") and bool(children),
                    "Invalid or empty test container")
            for child in children:
                visit(child)

    for node in tests["testNodes"]:
        visit(node)
    require(set(methods) == set(expected), "Missing required method execution")
    return methods


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON key")
        result[key] = value
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=SUPPORTED_SUITES, default=SUPPORTED_SUITES[0])
    for name in ("manifest", "summary", "tests", "receipt"):
        parser.add_argument("--" + name, type=pathlib.Path, required=True)
    for name in ("xcodebuild", "summary", "tests", "log"):
        parser.add_argument("--" + name + "-exit", type=int, default=0)
    args = parser.parse_args()
    receipt = {"status": "Failed", "methods": {}, "executed_cases": 0, "errors": [],
               "runtime_warnings": [],
               "command_exits": {"xcodebuild": args.xcodebuild_exit,
                                "summary": args.summary_exit, "tests": args.tests_exit, "log": args.log_exit},
               "sha256": {"checker": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()}}
    try:
        documents = {}
        for name in ("manifest", "summary", "tests"):
            raw = getattr(args, name).read_bytes()
            receipt["sha256"][name] = hashlib.sha256(raw).hexdigest()
            documents[name] = json.loads(raw, object_pairs_hook=unique_object)
        require(all(code == 0 for code in receipt["command_exits"].values()),
                "Build, log retention or xcresult extraction failed")
        receipt["methods"] = validate(**documents, runtime_warnings=receipt["runtime_warnings"], suite=args.suite)
        receipt["executed_cases"] = sum(receipt["methods"].values())
        receipt["status"] = "Passed"
    except (ValueError, TypeError, OSError) as error:
        receipt["errors"].append(str(error))
    args.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
    label = {"CalendarKeyboardOwnershipTests": "Keyboard ownership",
             "AIDateSearchIntegrationTests": "AI date search integration",
             "CalendarAgendaRefreshTests": "Agenda refresh"}[args.suite]
    print(f"{label}: {receipt['status']} ({receipt['executed_cases']} cases)")
    return 0 if receipt["status"] == "Passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
