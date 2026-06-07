#!/usr/bin/env python3
"""Parse app_restrictions.xml and strings.xml to produce JSON + CSV of MDM restrictions."""

import csv
import json
import os
import sys
import xml.etree.ElementTree as ET

NS_ATTR = "{http://schemas.android.com/apk/res/android}"

MAX_NESTING_DEPTH = 7


def parse_strings_xml(strings_path):
    """Parse strings.xml and return a dict mapping string name -> text content."""
    strings = {}
    try:
        tree = ET.parse(strings_path)
        root = tree.getroot()
        for elem in root.findall("string"):
            name = elem.get("name")
            text = (elem.text or "").replace("\n", " ").strip()
            if name:
                strings[name] = text
    except ET.ParseError:
        pass
    return strings


def resolve_string_ref(ref, strings):
    """Resolve a @string/REFERENCE to its actual text."""
    if ref and ref.startswith("@string/"):
        key = ref[len("@string/"):]
        return strings.get(key, ref)
    return ref


def _find_parent_node(nodes, parent_path):
    """Navigate the tree to find the parent node by its full dot-separated path.

    Returns the node dict or None if not found.
    """
    parts = parent_path.split(".")
     # First, find the root-level parent
    for n in nodes:
        if n["key"] == parts[0]:
            current = n
            for part in parts[1:]:
                if "children" in current:
                    for child in current["children"]:
                        if child["key"] == part:
                            current = child
                            break
                    else:
                        return None
                else:
                    return None
            return current
    return None


def _build_tree(restrictions):
    """Build a hierarchical tree from flat list of restriction dicts.

    Returns a list of top-level nodes, each with optional 'children' key
    containing nested restrictions, mirroring the XML tree structure.
    """
     # Index by key for lookup
    by_key = {}
    for r in restrictions:
        node = {
             "key": r["key"],
             "title": r["title"],
             "default_value": r["default_value"],
             "type": r["type"],
             "description": r["description"],
             "level": r["level"],
         }
        by_key[r["key"]] = node

     # Group by parent path
    children_of = {}    # parent_path -> [node, ...]
    top_level = []

    for r in restrictions:
        parent = r["parent"]
        node = by_key[r["key"]]
        if parent:
            if parent not in children_of:
                children_of[parent] = []
            children_of[parent].append(node)
        else:
            top_level.append(node)

     # Link children to their parent nodes by navigating the tree
    for parent_path, children in children_of.items():
        parent_node = _find_parent_node(top_level, parent_path)
        if parent_node is not None:
            parent_node["children"] = children

     # Sort children by key for deterministic output
    def sort_nodes(nodes):
        nodes.sort(key=lambda n: n["key"])
        for n in nodes:
            if "children" in n:
                sort_nodes(n["children"])

    sort_nodes(top_level)
    return top_level


def generate_summary(restrictions, summary_path):
    """Write a summary table of entries per level to a text file (ASCII markdown)."""
    level_counts = {}
    for r in restrictions:
        lvl = r["level"]
        level_counts[lvl] = level_counts.get(lvl, 0) + 1

    max_level = max(level_counts.keys()) if level_counts else 0
    total = sum(level_counts.values())

    lines = []
    lines.append("| Level | Entries |")
    lines.append("|-------|---------|")
    for lvl in range(max_level + 1):
        count = level_counts.get(lvl, 0)
        if lvl == 0:
            label = "0 (top)"
        else:
            label = str(lvl)
        lines.append("| %s | %d |" % (label, count))
    lines.append("|-------|---------|")
    lines.append("| Total | %d |" % total)

    with open(summary_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def _walk_restrictions(elem, parent_chain, level, strings, restrictions):
    """Recursively walk nested <restriction> elements.

    parent_chain: list of ancestor key names (from root down to direct parent)
    level: depth level (0 = top-level children of <restrictions>)
    """
    if level > MAX_NESTING_DEPTH:
        return

    for child in elem.findall("restriction"):
        key = child.get(f"{NS_ATTR}key", "")
        if not key:
            continue

        restriction = {
             "key": key,
             "title": resolve_string_ref(child.get(f"{NS_ATTR}title"), strings),
             "default_value": child.get(f"{NS_ATTR}defaultValue", ""),
             "type": child.get(f"{NS_ATTR}restrictionType", ""),
             "description": resolve_string_ref(child.get(f"{NS_ATTR}description"), strings),
             "parent": ".".join(parent_chain) if parent_chain else "",
             "level": level,
         }
        restrictions.append(restriction)

        # Recurse into nested restrictions
        _walk_restrictions(child, parent_chain + [key], level + 1, strings, restrictions)


def parse_restrictions(xml_path, strings):
    """Parse app_restrictions.xml and return a list of restriction dicts."""
    restrictions = []
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        _walk_restrictions(root, [], 0, strings, restrictions)
    except ET.ParseError:
        print(f"Error: Failed to parse {xml_path}", file=sys.stderr)
        sys.exit(1)
    return restrictions


def main():
    apk_dir = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    xml_path = os.path.join(apk_dir, "app_restrictions.xml")
    strings_path = os.path.join(apk_dir, "strings.xml")
    json_path = os.path.join(apk_dir, "app_restrictions_consolidated.json")
    csv_path = os.path.join(apk_dir, "app_restrictions_consolidated.csv")
    summary_path = os.path.join(apk_dir, "summary.md")

    if not os.path.isfile(xml_path):
        print(f"Error: {xml_path} not found.", file=sys.stderr)
        sys.exit(1)

     # Load string resources (optional - if missing, raw @string/ refs are kept)
    strings = {}
    if os.path.isfile(strings_path):
        strings = parse_strings_xml(strings_path)

     # Parse restrictions
    restrictions = parse_restrictions(xml_path, strings)

     # Write JSON (hierarchical tree mirroring XML structure)
    tree = _build_tree(restrictions)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(tree, f, indent=2, ensure_ascii=False)
    print(f"Written: {json_path} ({len(restrictions)} entries)")

     # Write CSV
    fieldnames = ["parent", "key", "title", "default_value", "type", "description", "level"]
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, quoting=csv.QUOTE_ALL)
        writer.writeheader()
        writer.writerows(restrictions)
    print(f"Written: {csv_path} ({len(restrictions)} entries)")

     # Write summary
    generate_summary(restrictions, summary_path)
    print(f"Written: {summary_path}")


if __name__ == "__main__":
    main()
