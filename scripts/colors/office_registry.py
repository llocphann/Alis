"""Minimal lexical editor for LibreOffice's user XCU property overrides.

Expat locates properties; replacements leave all unrelated original bytes intact.
Both nested nodes and flattened, typed set-member paths are supported. No DTD,
external entities, duplicate logical properties or ambiguous value lists.
"""
import re
from xml.parsers import expat
from xml.sax.saxutils import escape, quoteattr

OOR = "http://openoffice.org/2001/registry"
ATTR = OOR + "|"
EMPTY_REGISTRY = ('<?xml version="1.0" encoding="UTF-8"?>\n'
                  '<oor:items xmlns:oor="' + OOR + '">\n</oor:items>\n').encode()


class RegistryError(ValueError):
    pass


def path_parts(path):
    # Managed scheme names contain no slashes. An unrelated quoted set member
    # may contain one; keep that whole component intact while scanning paths.
    parts, piece, quoted, depth = [], "", False, 0
    for char in path.strip("/") + "/":
        if char == "'":
            quoted = not quoted
        if char == "[" and not quoted:
            depth += 1
        if char == "]" and not quoted:
            depth -= 1
        if char == "/" and not quoted and depth == 0:
            match = re.fullmatch(r"[^\[\]]+\['([^']*)'\]", piece)
            parts.append(match[1] if match else piece)
            piece = ""
        else:
            piece += char
    return tuple(parts)


def end_tag(data, start):
    quote = None
    for index in range(start, len(data)):
        char = data[index]
        if quote:
            if char == quote:
                quote = None
        elif char in (34, 39):
            quote = char
        elif char == 62:
            return index + 1
    raise RegistryError("incomplete registry element")


class Registry:
    def __init__(self, data):
        self.data = data if data is not None else EMPTY_REGISTRY
        self.fields = {}
        self.locations = set()
        self.root = None
        self.nodes = []
        stack = []
        parser = expat.ParserCreate(namespace_separator="|")

        def start(tag, attrs):
            begin = parser.CurrentByteIndex
            node = {"tag": tag, "attrs": attrs, "start": begin,
                    "open_end": end_tag(self.data, begin), "children": [],
                    "parent": stack[-1] if stack else None, "text": ""}
            if stack:
                stack[-1]["children"].append(node)
            else:
                self.root = node
            self.nodes.append(node)
            stack.append(node)

        def end(_tag):
            node = stack.pop()
            node["end"] = node["open_end"] if self.data[node["open_end"] - 2:node["open_end"]] == b"/>" else end_tag(self.data, parser.CurrentByteIndex)

        def text(value):
            if stack:
                stack[-1]["text"] += value

        def forbidden(*_args):
            raise RegistryError("DTD/entities are unsupported in an office profile")

        parser.StartElementHandler, parser.EndElementHandler = start, end
        parser.CharacterDataHandler = text
        parser.StartDoctypeDeclHandler = forbidden
        parser.EntityDeclHandler = forbidden
        parser.ExternalEntityRefHandler = forbidden
        try:
            parser.Parse(self.data, True)
        except expat.ExpatError as error:
            raise RegistryError("malformed LibreOffice registry; preserving it") from error
        if not self.root or self.root["tag"] != ATTR + "items":
            raise RegistryError("unsupported LibreOffice registry root")
        self._walk(self.root, ())

    def _walk(self, node, path):
        tag, attrs = node["tag"], node["attrs"]
        if tag == "item":
            path = path_parts(attrs.get(ATTR + "path", ""))
        elif tag == "node":
            path += (attrs.get(ATTR + "name", ""),)
        elif tag == "prop":
            key = path + (attrs.get(ATTR + "name", ""),)
            if key in self.fields:
                raise RegistryError("duplicate logical registry property; preserving it")
            self.fields[key] = node
        if tag in {"item", "node"}:
            self.locations.add(path)
        for child in node["children"]:
            self._walk(child, path)

    def raw(self, key):
        node = self.fields.get(key)
        return None if node is None else self.data[node["start"]:node["end"]]

    def value(self, key):
        node = self.fields.get(key)
        if node is None:
            return None
        values = node["children"]
        if len(values) != 1 or values[0]["tag"] != "value" or values[0]["children"] or values[0]["attrs"]:
            raise RegistryError("unsupported registry property value; preserving it")
        if node["attrs"].get(ATTR + "op", "fuse") != "fuse":
            raise RegistryError("unsupported registry property operation; preserving it")
        return values[0]["text"].strip()

    def changed(self, replacements):
        """Values are complete prop fragments or None (remove an owned prop)."""
        data = self.data
        if data[self.root["open_end"] - 2:self.root["open_end"]] == b"/>" and any(v is not None for v in replacements.values()):
            tag = re.match(rb"<([^\s/>]+)", data[self.root["start"]:])[1]
            end = self.root["open_end"]
            data = data[:end - 2] + b"></" + tag + b">" + data[end:]
        for key, replacement in replacements.items():
            tree = Registry(data)
            node = tree.fields.get(key)
            if node is not None:
                if replacement is None:
                    # Prune generated empty node/item wrappers, retaining any
                    # parent that also contains user properties or comments.
                    while node["parent"] and node["parent"] is not tree.root:
                        parent = node["parent"]
                        if len(parent["children"]) != 1 or b"<!--" in data[parent["start"]:parent["end"]]:
                            break
                        node = parent
                data = data[:node["start"]] + (replacement or b"") + data[node["end"]:]
            elif replacement is not None:
                component, *nodes, _prop = key
                # Item path names only the component; explicit nested nodes
                # avoid inventing the registry's typed set-path spelling.
                item = '<item xmlns:oor=' + quoteattr(OOR) + ' oor:path=' + quoteattr("/" + component) + '>'
                item += "".join('<node oor:name=' + quoteattr(name) + '>' for name in nodes)
                item = item.encode() + replacement + ("</node>" * len(nodes) + "</item>").encode()
                close = data.rfind(b"</", tree.root["open_end"], tree.root["end"])
                if close < 0:
                    raise RegistryError("self-closing registry root is unsupported")
                data = data[:close] + item + data[close:]
        Registry(data)
        return data


def property_xml(name, value):
    return ('<prop xmlns:oor=' + quoteattr(OOR) + ' oor:name=' + quoteattr(name)
            + ' oor:op="fuse"><value>' + escape(value) + '</value></prop>').encode()
