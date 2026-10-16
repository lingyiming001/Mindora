import Foundation

indirect enum EditCommand {
    case update(UUID, before: NodeProperties, after: NodeProperties)
    case insert(MindMapNode, NodeLocation)
    case remove(MindMapNode, NodeLocation)
    case move(UUID, from: NodeLocation, to: NodeLocation)
    case layout(MindMapLayout, MindMapLayout)
    case theme(MapTheme, MapTheme)
    case pageStyle(NodeStyle?, NodeStyle?)
    case batch([EditCommand])
    case replace(MindMapDocument, MindMapDocument)

    func merged(with next: EditCommand) -> EditCommand? {
        switch (self, next) {
        case let (.update(id, before, _), .update(nextID, _, after)) where id == nextID:
            return .update(id, before: before, after: after)
        case let (.pageStyle(before, _), .pageStyle(_, after)): return .pageStyle(before, after)
        case let (.batch(previous), .batch(following)) where previous.count == following.count:
            var merged: [EditCommand] = []
            for (a, b) in zip(previous, following) {
                guard let command = a.merged(with: b) else { return nil }
                merged.append(command)
            }
            return .batch(merged)
        default: return nil
        }
    }
    var inverse: EditCommand {
        switch self {
        case let .update(id, before, after): .update(id, before: after, after: before)
        case let .insert(node, location): .remove(node, location)
        case let .remove(node, location): .insert(node, location)
        case let .move(id, from, to): .move(id, from: to, to: from)
        case let .layout(before, after): .layout(after, before)
        case let .theme(before, after): .theme(after, before)
        case let .pageStyle(before, after): .pageStyle(after, before)
        case let .batch(commands): .batch(commands.reversed().map(\.inverse))
        case let .replace(before, after): .replace(after, before)
        }
    }
    func apply(to document: inout MindMapDocument) throws {
        switch self {
        case let .update(id, _, after):
            guard document.nodes[0].update(id, { after.apply(to: &$0) }) else { throw DocumentError.invalidTree }
        case let .insert(node, location):
            guard document.nodes[0].insert(node, at: location) else { throw DocumentError.invalidTree }
        case let .remove(node, _):
            guard document.nodes[0].remove(node.id) != nil else { throw DocumentError.invalidTree }
        case let .move(id, _, to):
            guard id != document.root.id, let source = document.root.find(id), source.find(to.parentID) == nil,
                  let moving = document.nodes[0].remove(id), document.nodes[0].insert(moving, at: to) else { throw DocumentError.invalidMove }
        case let .layout(_, after): document.layout = after
        case let .theme(_, after): document.theme = after
        case let .pageStyle(_, after): document.defaultNodeStyle = after
        case let .batch(commands): for command in commands { try command.apply(to: &document) }
        case let .replace(_, after): document = after
        }
    }
}
