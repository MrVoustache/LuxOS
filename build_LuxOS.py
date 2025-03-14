from dataclasses import dataclass, field
from pathlib import Path
from textwrap import indent


LUX_FOLDER = (Path(__file__).parent / "LuxOS").absolute()

@dataclass
class DirNode:
    name : str
    children : dict[str, "DirNode | FileNode"] = field(default_factory=dict)

@dataclass
class FileNode:
    name : str
    id : int

def escape_lua_multiline_strings(text : str) -> str:
    import re

    pattern = re.compile(r"\[\[|\]\]")

    def replace_match(sub : re.Match) -> str:
        match sub.group(0):
            case "[[":
                return ']].."[["..[['
            case "]]":
                return ']].."]]"..[['
            case s:
                raise ValueError(f"Unexpected match: '{s}'")

    translated_text = re.sub(pattern, replace_match, text)
    return translated_text

contents : list[str] = []
def package_node(file : Path, parent : DirNode | None = None) -> DirNode:
    if file.is_file():
        if not parent:
            raise RuntimeError("Cannot package a single file.")
        print(f"Packaging file '{file}'...")
        content = escape_lua_multiline_strings(file.read_text())
        contents.append(content)
        id = len(contents)
        parent.children[file.name] = FileNode(file.name, id)
        return parent
    else:
        node = DirNode(file.name)
        if parent:
            parent.children[file.name] = node
        for file in file.iterdir():
            package_node(file, node)
        if parent:
            return parent
        return node

def dump_package(node : DirNode | FileNode) -> str:
    if isinstance(node, DirNode):
        return "{\n" + indent(f"name = \"{node.name}\",\n"
                               "type = DIRECTORY,\n"
                               "children = " + "{\n"
                               + indent(",\n".join(dump_package(child) for child in node.children.values()), "\t") +
                               "\n}\n", "\t") + "}"
    else:
        return "{\n" + indent(f"name = \"{node.name}\",\n"
                                "type = FILE,\n"
                                f"code = {node.id}\n"
                              , "\t") + "}"

package_root = package_node(LUX_FOLDER)

lua_installer = """local DIRECTORY = 1
local FILE = 2
local ENTRY_POINT = "LuxOS/main.lua"

local package = {package_dump}

local raw_package = {raw_package_content}

local function install(node, parent_path)
    if node.type == DIRECTORY then
        if not fs.exists(parent_path..node.name) then
            fs.makeDir(parent_path..node.name)
        end
        for _, child in ipairs(node.children) do
            install(child, parent_path..node.name.."/")
        end
    elseif node.type == FILE then
        local path = parent_path..node.name
        if not fs.exists(path) then
            local content = raw_package[node.code]
            print("Installing file '"..path.."'...")
            local file = fs.open(path, "w")
            file.write(content)
            file.close()
        end
    end
end

install(package, "")

print("Installation is finished. Press any key to boot LuxOS.")
while true do
    local event = coroutine.yield()
    if event == "key" then
        break
    end
end

dofile(ENTRY_POINT)""".format(
    package_dump = dump_package(package_root),
    raw_package_content = "{\n" + ",\n".join(f"[[{content}]]" for content in contents) + "\n}"
    )

with open("install.lua", "w") as f:
    f.write(lua_installer)