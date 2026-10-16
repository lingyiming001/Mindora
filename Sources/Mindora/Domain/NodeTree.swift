import Foundation

struct NodeLocation: Equatable {
    var parentID: UUID
    var index: Int
}

extension MindMapNode {
    func flattened(visibleOnly: Bool = false) -> [MindMapNode] {
        [self] + ((visibleOnly && isCollapsed) ? [] : children.flatMap { $0.flattened(visibleOnly: visibleOnly) })
    }
    func find(_ target: UUID) -> MindMapNode? {
        if id == target { return self }
        for child in children { if let found = child.find(target) { return found } }
        return nil
    }
    func location(of target: UUID) -> NodeLocation? {
        if let index = children.firstIndex(where: { $0.id == target }) { return NodeLocation(parentID: id, index: index) }
        for child in children { if let result = child.location(of: target) { return result } }
        return nil
    }
    func ancestors(of target: UUID) -> [UUID]? {
        if id == target { return [] }
        for child in children {
            if let path = child.ancestors(of: target) { return [id] + path }
        }
        return nil
    }
    @discardableResult mutating func update(_ target: UUID, _ body: (inout MindMapNode) -> Void) -> Bool {
        if id == target { body(&self); return true }
        for index in children.indices {
            if children[index].update(target, body) { return true }
        }
        return false
    }
    @discardableResult mutating func insert(_ node: MindMapNode, at location: NodeLocation) -> Bool {
        update(location.parentID) { parent in
            parent.children.insert(node, at: min(max(location.index, 0), parent.children.count))
        }
    }
    mutating func remove(_ target: UUID) -> MindMapNode? {
        if let index = children.firstIndex(where: { $0.id == target }) { return children.remove(at: index) }
        for index in children.indices { if let result = children[index].remove(target) { return result } }
        return nil
    }
    func cloned() -> MindMapNode {
        var copy = self
        copy.id = UUID()
        copy.children = children.map { $0.cloned() }
        return copy
    }
}
